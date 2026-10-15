// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SUNToken} from "../src/SUNToken.sol";
import {Vm} from "./SUNToken.t.sol";

interface SUNEventVm is Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

/// @dev A contract deployer distinguishes msg.sender from the externally calling launch user.
contract SUNDeploymentProbe {
    function deploy() external returns (SUNToken) {
        return new SUNToken();
    }
}

contract SUNTokenEdgesTest {
    SUNEventVm internal constant vm = SUNEventVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant POOL = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant CREATOR = 0xEeaF04a41aC45A605E30dc6a41A44E6F75Ddf8b6;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    uint256 internal constant SUPPLY = 1e27;
    SUNToken internal token;

    function setUp() public {
        token = new SUNToken();
    }

    function test_ContractDeployerGetsSingleMintAndLaunchCallerGetsNothing() public {
        SUNDeploymentProbe factory = new SUNDeploymentProbe();
        vm.recordLogs();
        vm.prank(ALICE);
        SUNToken launched = factory.deploy();
        SUNEventVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1, "constructor must only mint once");
        _assertTransfer(logs[0], address(launched), address(0), address(factory), SUPPLY);
        require(launched.balanceOf(address(factory)) == SUPPLY, "factory must own all supply");
        require(launched.balanceOf(ALICE) == 0, "launch caller must not receive the mint");
        require(launched.balanceOf(POOL) == 0 && launched.balanceOf(CREATOR) == 0, "premature distribution");
        require(launched.balanceOf(address(launched)) == 0, "token retained a reserve");
    }

    function testFuzz_NetAllowanceCannotAuthorizeGrossBuy(uint256 raw) public {
        uint256 gross = 200 + raw % (SUPPLY - 199);
        uint256 net = gross - gross / 200;
        token.transfer(POOL, gross);
        vm.prank(POOL);
        token.approve(SPENDER, net);

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InsufficientAllowance.selector, SPENDER, net, gross));
        token.transferFrom(POOL, ALICE, gross);
        _assertFailedBuy(gross, net);

        // The same gross amount becomes spendable only after the full amount is authorized.
        vm.prank(POOL);
        token.approve(SPENDER, gross);
        vm.prank(SPENDER);
        require(token.transferFrom(POOL, ALICE, gross), "authorized buy failed");
        require(token.balanceOf(ALICE) == net && token.balanceOf(CREATOR) == gross / 200, "buy credits");
        require(token.allowance(POOL, SPENDER) == 0, "gross allowance not consumed");
    }

    function testFuzz_NetBalanceCannotFundGrossBuyAndAllowanceRollsBack(uint256 raw) public {
        uint256 gross = 200 + raw % (SUPPLY - 199);
        uint256 available = gross - gross / 200;
        token.transfer(POOL, available);
        vm.prank(POOL);
        token.approve(SPENDER, gross);

        bytes memory errorData =
            abi.encodeWithSelector(SUNToken.ERC20InsufficientBalance.selector, POOL, available, gross);
        vm.prank(POOL);
        vm.expectRevert(errorData);
        token.transfer(ALICE, gross);
        _assertFailedBuy(available, gross);

        vm.prank(SPENDER);
        vm.expectRevert(errorData);
        token.transferFrom(POOL, ALICE, gross);
        _assertFailedBuy(available, gross);
    }

    function test_MaximumAmountRevertsWithBalanceErrorBeforeTaxArithmetic() public {
        token.transfer(POOL, SUPPLY);
        vm.prank(POOL);
        token.approve(SPENDER, type(uint256).max);
        bytes memory errorData =
            abi.encodeWithSelector(SUNToken.ERC20InsufficientBalance.selector, POOL, SUPPLY, type(uint256).max);
        vm.prank(POOL);
        vm.expectRevert(errorData);
        token.transfer(ALICE, type(uint256).max);
        vm.prank(SPENDER);
        vm.expectRevert(errorData);
        token.transferFrom(POOL, ALICE, type(uint256).max);
        _assertFailedBuy(SUPPLY, type(uint256).max);
    }

    function test_InvalidBuyRecipientRollsBackFiniteAndInfiniteAllowance() public {
        uint256 gross = 200 ether;
        token.transfer(POOL, gross);
        for (uint256 i; i < 2; ++i) {
            uint256 approved = i == 0 ? gross : type(uint256).max;
            vm.prank(POOL);
            token.approve(SPENDER, approved);
            vm.prank(SPENDER);
            vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InvalidReceiver.selector, address(0)));
            token.transferFrom(POOL, address(0), gross);
            _assertFailedBuy(gross, approved);
        }
    }

    function testFuzz_TaxUsesTokenSenderNotApprovedSpender(uint256 raw) public {
        uint256 amount = raw % (SUPPLY / 2 + 1);
        token.transfer(ALICE, amount);
        token.transfer(POOL, amount);

        vm.prank(ALICE);
        token.approve(POOL, amount);
        vm.prank(POOL);
        require(token.transferFrom(ALICE, BOB, amount), "manager spending wallet funds failed");
        require(token.balanceOf(BOB) == amount && token.balanceOf(CREATOR) == 0, "caller incorrectly triggers tax");

        vm.prank(POOL);
        token.approve(CREATOR, amount);
        vm.prank(CREATOR);
        require(token.transferFrom(POOL, ALICE, amount), "creator spending pool funds failed");
        require(token.balanceOf(ALICE) == amount - amount / 200, "creator caller incorrectly exempted");
        require(token.balanceOf(CREATOR) == amount / 200, "creator fee missing");
    }

    function testFuzz_DelegatedSelfTransfersConsumeAllowanceWithoutMovingBalances(uint256 raw) public {
        uint256 amount = raw % (SUPPLY / 3 + 1);
        address[3] memory holders = [ALICE, POOL, CREATOR];
        for (uint256 i; i < holders.length; ++i) {
            token.transfer(holders[i], amount);
            vm.prank(holders[i]);
            token.approve(SPENDER, amount);
            vm.prank(SPENDER);
            require(token.transferFrom(holders[i], holders[i], amount), "self transfer failed");
            require(token.balanceOf(holders[i]) == amount, "self transfer changed balance");
            require(token.allowance(holders[i], SPENDER) == 0, "self transfer did not spend allowance");
        }
        require(token.balanceOf(CREATOR) == amount, "pool self transfer charged tax");
        require(token.totalSupply() == SUPPLY, "self transfer changed supply");
    }

    function test_CreatorCanSpendAllCollectedFeesWithoutAnotherTax() public {
        token.transfer(POOL, 200 ether);
        vm.prank(POOL);
        token.transfer(ALICE, 200 ether);
        vm.prank(CREATOR);
        token.transfer(BOB, 0.4 ether);
        vm.prank(CREATOR);
        token.transfer(POOL, 0.6 ether);
        require(token.balanceOf(CREATOR) == 0, "creator fees locked or taxed");
        require(token.balanceOf(BOB) == 0.4 ether && token.balanceOf(POOL) == 0.6 ether, "creator outflow short");
    }

    function test_ZeroAmountsStillRejectZeroAddresses() public {
        vm.prank(POOL);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(POOL, address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        require(token.totalSupply() == SUPPLY && token.balanceOf(address(0)) == 0, "invalid call changed supply");
    }

    function test_ZeroAndDustBuysEmitOnlyActualCredit() public {
        token.transfer(POOL, 199);
        uint256[3] memory amounts = [uint256(0), uint256(1), uint256(198)];
        for (uint256 i; i < amounts.length; ++i) {
            vm.recordLogs();
            vm.prank(POOL);
            require(token.transfer(ALICE, amounts[i]), "dust transfer failed");
            SUNEventVm.Log[] memory logs = vm.getRecordedLogs();
            require(logs.length == 1, "zero fee must not create a tax leg");
            _assertTransfer(logs[0], address(token), POOL, ALICE, amounts[i]);
        }
        require(token.balanceOf(ALICE) == 199 && token.balanceOf(CREATOR) == 0, "dust fee");
    }

    function test_CreatorAsBuyRecipientHasBothCreditsInEvents() public {
        token.transfer(POOL, 400);
        vm.recordLogs();
        vm.prank(POOL);
        token.transfer(CREATOR, 400);
        SUNEventVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 2, "taxed buy must have two transfer legs");
        _assertTransfer(logs[0], address(token), POOL, CREATOR, 2);
        _assertTransfer(logs[1], address(token), POOL, CREATOR, 398);
        require(token.balanceOf(CREATOR) == 400 && token.balanceOf(POOL) == 0, "aliased credits lost");
    }

    function _assertFailedBuy(uint256 poolBalance, uint256 approved) private view {
        require(token.balanceOf(POOL) == poolBalance, "reverted buy debited pool");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(CREATOR) == 0, "reverted buy credited recipient");
        require(token.allowance(POOL, SPENDER) == approved, "reverted buy consumed allowance");
        require(token.totalSupply() == SUPPLY && token.balanceOf(address(0)) == 0, "reverted buy changed supply");
    }

    function _assertTransfer(SUNEventVm.Log memory log, address emitter, address from, address to, uint256 amount)
        private
        pure
    {
        require(log.emitter == emitter && log.topics.length == 3, "incorrect transfer emitter/topics");
        require(log.topics[0] == keccak256("Transfer(address,address,uint256)"), "incorrect event");
        require(log.topics[1] == bytes32(uint256(uint160(from))), "incorrect event sender");
        require(log.topics[2] == bytes32(uint256(uint160(to))), "incorrect event recipient");
        require(abi.decode(log.data, (uint256)) == amount, "incorrect event amount");
    }
}
