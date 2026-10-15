// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SUNToken} from "../src/SUNToken.sol";

interface Vm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes calldata) external;
    function expectEmit(bool, bool, bool, bool) external;
    function etch(address, bytes calldata) external;
}

contract SUNTokenTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SUNToken internal token;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant CREATOR = 0xEeaF04a41aC45A605E30dc6a41A44E6F75Ddf8b6;
    uint256 internal constant SUPPLY = 1e27;
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new SUNToken();
    }

    function test_FactoryReceivesEverythingAndDistributesExactly() public {
        require(token.totalSupply() == SUPPLY && token.decimals() == 18, "supply units");
        require(token.balanceOf(address(this)) == SUPPLY, "constructor must not reserve swarm tokens");
        token.transfer(DISTRIBUTOR, 100_000_000 ether);
        token.transfer(POOL, 900_000_000 ether);
        require(token.balanceOf(address(this)) == 0, "remainder");
        require(token.balanceOf(POOL) == 900_000_000 ether, "pool seed short");
        require(token.balanceOf(CREATOR) == 0, "seed taxed");
        vm.prank(DISTRIBUTOR);
        token.transfer(ALICE, 100_000_000 ether);
        require(token.balanceOf(ALICE) == 100_000_000 ether, "swarm claim short");
        require(token.balanceOf(DISTRIBUTOR) == 0, "distributor residue");
    }

    function test_BuyEventsDescribeActualCredits() public {
        token.transfer(POOL, 200 ether);
        vm.expectEmit(true, true, false, true);
        emit Transfer(POOL, CREATOR, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit Transfer(POOL, ALICE, 199 ether);
        vm.prank(POOL);
        token.transfer(ALICE, 200 ether);
        require(token.balanceOf(ALICE) == 199 ether, "buyer net");
        require(token.balanceOf(CREATOR) == 1 ether, "creator credit");
    }

    function testFuzz_BuySellAndWalletConservation(uint256 raw) public {
        uint256 amount = raw % (SUPPLY + 1);
        token.transfer(POOL, amount);
        vm.prank(POOL);
        token.transfer(ALICE, amount);
        // Independent rational bound: floor(amount / 200), with the remainder staying with buyer.
        uint256 tax = amount / 200;
        require(token.balanceOf(CREATOR) == tax, "tax rounding");
        uint256 received = token.balanceOf(ALICE);
        require(received + tax == amount, "buy conservation");
        vm.prank(ALICE);
        token.transfer(BOB, received);
        require(token.balanceOf(BOB) == received, "wallet fee");
        vm.prank(BOB);
        token.transfer(POOL, received);
        require(token.balanceOf(POOL) == received, "sell settlement short");
        require(token.balanceOf(BOB) == 0 && token.balanceOf(ALICE) == 0, "residue");
        require(
            token.balanceOf(address(this)) + token.balanceOf(POOL) + token.balanceOf(CREATOR) == SUPPLY,
            "supply conservation"
        );
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_RoundingAtSmallestTaxUnit() public {
        token.transfer(POOL, 400);
        vm.prank(POOL);
        token.transfer(ALICE, 199);
        require(token.balanceOf(CREATOR) == 0, "dust taxed");
        vm.prank(POOL);
        token.transfer(BOB, 200);
        require(token.balanceOf(CREATOR) == 1 && token.balanceOf(BOB) == 199, "one minor-unit tax");
    }

    function test_TransferFromChargesGrossAllowanceAndCannotBypassTax() public {
        token.transfer(POOL, 200 ether);
        vm.prank(POOL);
        token.approve(SPENDER, 200 ether);
        vm.prank(SPENDER);
        token.transferFrom(POOL, ALICE, 200 ether);
        require(token.allowance(POOL, SPENDER) == 0, "gross allowance");
        require(token.balanceOf(ALICE) == 199 ether && token.balanceOf(CREATOR) == 1 ether, "tax bypassed");
        vm.prank(ALICE);
        token.approve(SPENDER, 199 ether);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, POOL, 199 ether);
        require(token.balanceOf(POOL) == 199 ether, "delegated sell short");
    }

    function test_UnlimitedAllowanceAndOverwrite() public {
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 20 ether);
        require(token.allowance(ALICE, SPENDER) == type(uint256).max, "infinite allowance spent");
        vm.prank(ALICE);
        token.approve(SPENDER, 0);
        vm.prank(SPENDER);
        vm.expectRevert();
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_SelfTransfersZeroTransfersAndCreatorAsBuyer() public {
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        token.transfer(ALICE, 100);
        require(token.balanceOf(ALICE) == 100, "wallet self transfer");
        token.transfer(POOL, 200 ether);
        vm.prank(POOL);
        token.transfer(POOL, 200 ether);
        require(token.balanceOf(POOL) == 200 ether && token.balanceOf(CREATOR) == 0, "pool destination precedence");
        vm.prank(POOL);
        token.transfer(CREATOR, 200 ether);
        require(token.balanceOf(CREATOR) == 200 ether, "creator receives both legs");
        vm.prank(BOB);
        token.transfer(ALICE, 0);
        require(token.balanceOf(ALICE) == 100, "zero transfer changed balance");
    }

    function test_InvalidCallsRevertAtomically() public {
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        vm.expectRevert();
        token.transferFrom(ALICE, address(0), 100);
        require(token.balanceOf(ALICE) == 100 && token.allowance(ALICE, SPENDER) == 100, "revert not atomic");
        vm.expectRevert();
        token.transfer(BOB, type(uint256).max);
        vm.expectRevert();
        token.transferFrom(address(0), BOB, 0);
        vm.expectRevert();
        token.approve(address(0), 1);
        vm.prank(BOB);
        vm.expectRevert();
        token.transferFrom(ALICE, BOB, 1);
        vm.prank(ALICE);
        vm.expectRevert();
        token.transfer(BOB, 101);
    }

    function test_NoAdminMintBurnUpgradeOrFeeMutation() public {
        token.transfer(ALICE, 10 ether);
        // Use valid ABI arguments and plausible values. Passing an address as a fee or boolean
        // could make an existing privileged setter revert on validation and hide the privilege.
        bytes[24] memory calls = [
            abi.encodeWithSignature("owner()"),
            abi.encodeWithSignature("mint(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("mint(uint256)", 1),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("transferOwnership(address)", BOB),
            abi.encodeWithSignature("renounceOwnership()"),
            abi.encodeWithSignature("setFee(uint256)", 0),
            abi.encodeWithSignature("setTaxRate(uint256)", 0),
            abi.encodeWithSignature("setCreatorTaxBps(uint256)", 0),
            abi.encodeWithSignature("setFeeBps(uint256)", 0),
            abi.encodeWithSignature("setCreatorWallet(address)", BOB),
            abi.encodeWithSignature("setFeeRecipient(address)", BOB),
            abi.encodeWithSignature("setPoolManager(address)", BOB),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true),
            abi.encodeWithSignature("freeze(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("setMinter(address)", BOB),
            abi.encodeWithSignature("setOwner(address)", BOB)
        ];
        address[5] memory callers = [address(this), ALICE, BOB, CREATOR, POOL];
        for (uint256 i; i < calls.length; ++i) {
            for (uint256 j; j < callers.length; ++j) {
                vm.prank(callers[j]);
                (bool ok,) = address(token).call(calls[i]);
                require(!ok, "unexpected owner/admin/mint/burn function");
            }
        }
        require(token.CREATOR_TAX_BPS() == 50 && token.CREATOR_WALLET() == CREATOR, "mutable fees");
        require(token.BPS_DENOMINATOR() == 10_000 && token.POOL_MANAGER() == POOL, "mutable tax parameters");
        require(token.totalSupply() == SUPPLY && token.balanceOf(ALICE) == 10 ether, "privileged balance change");
        vm.prank(ALICE);
        token.transfer(BOB, 10 ether);
        require(token.balanceOf(BOB) == 10 ether, "holder frozen");
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            require(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
        require(code.length < 24_576, "runtime size");
    }

    function testFuzz_StatefulSupplyConservation(bytes32 seed) public {
        address[6] memory actors = [address(this), ALICE, BOB, POOL, CREATOR, DISTRIBUTOR];
        for (uint256 i; i < 40; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            address from = actors[entropy % actors.length];
            address to = actors[(entropy >> 32) % actors.length];
            uint256 amount = (entropy >> 64) % (token.balanceOf(from) + 1);
            vm.prank(from);
            token.transfer(to, amount);
            uint256 sum;
            for (uint256 j; j < actors.length; ++j) {
                sum += token.balanceOf(actors[j]);
            }
            require(sum == SUPPLY && token.totalSupply() == SUPPLY, "stateful conservation violated");
        }
    }
}
