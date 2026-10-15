// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SUNToken} from "../src/SUNToken.sol";
import {Vm} from "./SUNToken.t.sol";

/// @dev Closed actor set: every possible recipient, including the tax wallet, is accounted for.
/// The model uses the specified 1/200 fee, independent of the token's constant getters.
contract SUNTokenHandler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1e27;
    address private constant POOL = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address private constant CREATOR = 0xEeaF04a41aC45A605E30dc6a41A44E6F75Ddf8b6;
    SUNToken public immutable token;
    address[6] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SUNToken token_, address[6] memory actors_) {
        token = token_;
        actors = actors_;
        // Match the explicit setup allocation, not the token's observed balances.
        expectedBalance[actors[0]] = SUPPLY / 10;
        expectedBalance[actors[1]] = SUPPLY * 45 / 100;
        expectedBalance[actors[2]] = SUPPLY * 5 / 100;
        expectedBalance[actors[3]] = SUPPLY / 10;
        expectedBalance[actors[4]] = SUPPLY / 5;
        expectedBalance[actors[5]] = SUPPLY / 10;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 raw) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(raw, expectedBalance[from]);
        vm.prank(from);
        require(token.transfer(to, amount), "transfer returned false");
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 raw, uint8 mode) external {
        // Include overwrites, revocations and unlimited approvals in arbitrary order.
        uint256 amount = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : raw % (SUPPLY + 1);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 raw) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = expectedBalance[from];
        uint256 approved = expectedAllowance[from][spender];
        if (approved < limit) limit = approved;
        _spend(from, to, spender, _amount(raw, limit));
    }

    function buy(uint256 toSeed, uint256 spenderSeed, uint256 raw, bool delegated, bool unlimited) external {
        address to = _actor(toSeed);
        uint256 amount = _amount(raw, expectedBalance[POOL]);
        if (delegated) {
            address spender = _actor(spenderSeed);
            _approve(POOL, spender, unlimited ? type(uint256).max : amount);
            _spend(POOL, to, spender, amount);
        } else {
            vm.prank(POOL);
            require(token.transfer(to, amount), "buy returned false");
            _move(POOL, to, amount);
        }
    }

    function sell(uint256 fromSeed, uint256 raw) external {
        address from = _actor(fromSeed);
        uint256 amount = _amount(raw, expectedBalance[from]);
        vm.prank(from);
        require(token.transfer(POOL, amount), "sell returned false");
        _move(from, POOL, amount);
    }

    function rejectOverdraw(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 raw, bool delegated)
        external
    {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        address spender = _actor(spenderSeed);
        uint256 held = expectedBalance[from];
        uint256 amount = held + 1 + raw % (SUPPLY - held + 1);
        if (delegated) _approve(from, spender, amount);
        vm.prank(delegated ? spender : from);
        (bool ok, bytes memory reason) = address(token)
            .call(
                delegated
                    ? abi.encodeCall(token.transferFrom, (from, to, amount))
                    : abi.encodeCall(token.transfer, (to, amount))
            );
        _requireRevert(
            ok, reason, abi.encodeWithSelector(SUNToken.ERC20InsufficientBalance.selector, from, held, amount)
        );
        // The model remains untouched, including any finite allowance spent before _transfer reverted.
    }

    function rejectUnapprovedSpend(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 raw) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = 1 + raw % SUPPLY;
        _approve(from, spender, amount - 1);
        vm.prank(spender);
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, _actor(toSeed), amount)));
        _requireRevert(
            ok,
            reason,
            abi.encodeWithSelector(SUNToken.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
        );
    }

    function rejectZeroRecipient(uint256 fromSeed, uint256 spenderSeed, uint256 raw, bool unlimited) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(raw, expectedBalance[from]);
        _approve(from, spender, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, address(0), amount)));
        _requireRevert(ok, reason, abi.encodeWithSelector(SUNToken.ERC20InvalidReceiver.selector, address(0)));
    }

    function _spend(address from, address to, address spender, uint256 amount) private {
        vm.prank(spender);
        require(token.transferFrom(from, to, amount), "transferFrom returned false");
        if (expectedAllowance[from][spender] != type(uint256).max) expectedAllowance[from][spender] -= amount;
        _move(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        require(token.approve(spender, amount), "approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) private {
        uint256 fee = from == POOL && to != POOL ? amount / 200 : 0;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount - fee;
        expectedBalance[CREATOR] += fee;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _amount(uint256 raw, uint256 limit) private pure returns (uint256) {
        // Frequently reach zero, one unit, the tax rounding boundary, and a full-balance transfer.
        uint256 mode = raw % 6;
        if (mode == 0) return 0;
        if (mode == 1) return limit;
        if (mode == 2) return limit < 1 ? limit : 1;
        if (mode == 3) return limit < 199 ? limit : 199;
        if (mode == 4) return limit < 200 ? limit : 200;
        return raw % (limit + 1);
    }

    function _requireRevert(bool ok, bytes memory actual, bytes memory expected) private pure {
        require(!ok, "invalid operation unexpectedly succeeded");
        require(keccak256(actual) == keccak256(expected), "invalid operation returned wrong error");
    }
}

contract SUNTokenInvariantTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1e27;
    address private constant FACTORY = address(0xFAC7);
    address private constant POOL = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address private constant CREATOR = 0xEeaF04a41aC45A605E30dc6a41A44E6F75Ddf8b6;
    SUNToken private token;
    SUNTokenHandler private handler;

    // Foundry's invariant targeting ABI, kept local so this suite needs no additional dependency.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        vm.prank(FACTORY);
        token = new SUNToken();
        address[6] memory actors = [FACTORY, POOL, CREATOR, address(0xD157), address(0xA11CE), address(0xB0B)];
        vm.startPrank(FACTORY);
        token.transfer(POOL, SUPPLY * 45 / 100);
        token.transfer(CREATOR, SUPPLY * 5 / 100);
        token.transfer(actors[3], SUPPLY / 10);
        token.transfer(actors[4], SUPPLY / 5);
        token.transfer(actors[5], SUPPLY / 10);
        vm.stopPrank();
        handler = new SUNTokenHandler(token, actors);
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() external view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = SUNTokenHandler.transfer.selector;
        selectors[1] = SUNTokenHandler.approve.selector;
        selectors[2] = SUNTokenHandler.transferFrom.selector;
        selectors[3] = SUNTokenHandler.buy.selector;
        selectors[4] = SUNTokenHandler.sell.selector;
        selectors[5] = SUNTokenHandler.rejectOverdraw.selector;
        selectors[6] = SUNTokenHandler.rejectUnapprovedSpend.selector;
        selectors[7] = SUNTokenHandler.rejectZeroRecipient.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 48
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyBalancesAllowancesAndParameters() public view {
        uint256 sum;
        for (uint256 i; i < 6; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            require(balance == handler.expectedBalance(actor), "balance diverged from transfer/tax model");
            sum += balance;
            for (uint256 j; j < 6; ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(actor, spender) == handler.expectedAllowance(actor, spender),
                    "allowance diverged from authorization model"
                );
            }
        }
        require(sum == SUPPLY && token.totalSupply() == SUPPLY, "fixed supply conservation");
        require(token.balanceOf(address(0)) == 0 && token.balanceOf(address(token)) == 0, "unaccounted tokens");
        require(token.CREATOR_TAX_BPS() == 50 && token.BPS_DENOMINATOR() == 10_000, "fee changed");
        require(token.CREATOR_WALLET() == CREATOR && token.POOL_MANAGER() == POOL, "fixed address changed");
    }
}
