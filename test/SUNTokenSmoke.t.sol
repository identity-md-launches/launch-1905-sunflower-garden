// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SUNToken} from "../src/SUNToken.sol";
import {Vm} from "./SUNToken.t.sol";

/// @notice Smoke tests, one per numbered check in the launch brief. Each is a short, independent
/// scenario: deploy, supply, one transfer of each kind, and the absence of any admin surface.
/// The deeper fuzz and real-PoolManager suites live in SUNToken.t.sol and UniswapV4.t.sol.
contract SUNTokenSmokeTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant FACTORY = address(0xFAC7);
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant BUYER = address(0xB0B1);
    address internal constant SELLER = address(0x5E11);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant CREATOR = 0xEeaF04a41aC45A605E30dc6a41A44E6F75Ddf8b6;

    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant SWARM_SHARE = 100_000_000 ether;
    uint256 internal constant POOL_SHARE = 900_000_000 ether;

    SUNToken internal token;

    /// @dev Deploy from a distinct "factory" address so the mint-to-msg.sender rule is visible.
    function setUp() public {
        vm.prank(FACTORY);
        token = new SUNToken();
    }

    // Brief test 4: total supply is exactly 1,000,000,000 tokens with 18 decimals.
    function test_SupplyIsOneBillionWithEighteenDecimals() public view {
        require(token.decimals() == 18, "decimals");
        require(token.totalSupply() == SUPPLY, "total supply");
        require(token.totalSupply() == 1e27, "minor units");
        require(keccak256(bytes(token.name())) == keccak256("Sunflower Garden"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("SUN"), "symbol");
    }

    // Brief test 5: the deployer holds the full supply and the factory splits it 10% / 90%.
    function test_DeployerHoldsFullSupplyAndFactorySplitsIt() public {
        require(token.balanceOf(FACTORY) == SUPPLY, "deployer must hold the whole supply");
        require(token.balanceOf(CREATOR) == 0, "nothing goes to the creator at mint");

        vm.prank(FACTORY);
        require(token.transfer(DISTRIBUTOR, SWARM_SHARE), "swarm transfer returned false");
        vm.prank(FACTORY);
        require(token.transfer(POOL_MANAGER, POOL_SHARE), "pool seed returned false");

        require(token.balanceOf(DISTRIBUTOR) == SWARM_SHARE, "swarm share arrived short");
        require(token.balanceOf(POOL_MANAGER) == POOL_SHARE, "pool seed arrived short");
        require(token.balanceOf(FACTORY) == 0, "no remainder is left behind");
        require(token.balanceOf(CREATOR) == 0, "the seed must not be taxed");
    }

    // Brief test 1: a transfer FROM the PoolManager loses 0.5% to the creator wallet.
    function test_BuyFromPoolManagerPaysHalfPercentToCreator() public {
        vm.prank(FACTORY);
        token.transfer(POOL_MANAGER, 1_000 ether);

        vm.prank(POOL_MANAGER);
        require(token.transfer(BUYER, 1_000 ether), "buy returned false");

        require(token.balanceOf(BUYER) == 995 ether, "buyer receives amount net of 0.5%");
        require(token.balanceOf(CREATOR) == 5 ether, "creator receives exactly 0.5%");
        require(token.balanceOf(POOL_MANAGER) == 0, "the pool manager is debited the full amount");
        require(token.totalSupply() == SUPPLY, "supply unchanged");
    }

    // Brief test 2: a transfer TO the PoolManager carries no tax.
    function test_SellToPoolManagerIsUntaxed() public {
        vm.prank(FACTORY);
        token.transfer(SELLER, 1_000 ether);

        vm.prank(SELLER);
        require(token.transfer(POOL_MANAGER, 1_000 ether), "sell returned false");

        require(token.balanceOf(POOL_MANAGER) == 1_000 ether, "pool manager receives the full amount");
        require(token.balanceOf(SELLER) == 0, "seller fully debited");
        require(token.balanceOf(CREATOR) == 0, "no creator tax on a sell");
    }

    // Brief test 3: plain wallet-to-wallet transfers carry no fee.
    function test_WalletToWalletTransferIsFree() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 500 ether);

        vm.prank(ALICE);
        require(token.transfer(BOB, 200 ether), "transfer returned false");

        require(token.balanceOf(ALICE) == 300 ether, "sender debited exactly");
        require(token.balanceOf(BOB) == 200 ether, "receiver credited exactly");
        require(token.balanceOf(CREATOR) == 0, "no creator tax between wallets");
    }

    // Brief test 7: the full pool round trip in miniature. Seed in (untaxed), buy out (taxed),
    // sell back in (untaxed). Every unit is accounted for, so v4 settlement can always balance.
    function test_PoolRoundTripBalances() public {
        vm.prank(FACTORY);
        token.transfer(POOL_MANAGER, POOL_SHARE);
        uint256 poolBefore = token.balanceOf(POOL_MANAGER);

        uint256 bought = 10_000 ether;
        vm.prank(POOL_MANAGER);
        token.transfer(BUYER, bought);
        uint256 tax = bought / 200;
        uint256 net = token.balanceOf(BUYER);
        require(net == bought - tax, "buyer net of tax");
        require(token.balanceOf(CREATOR) == tax, "creator tax");

        vm.prank(BUYER);
        token.transfer(POOL_MANAGER, net);
        require(token.balanceOf(POOL_MANAGER) == poolBefore - tax, "pool receives the sale in full");
        require(token.balanceOf(BUYER) == 0, "buyer fully debited on sell");
        require(token.balanceOf(CREATOR) == tax, "sell adds no tax");
        require(
            token.balanceOf(FACTORY) + token.balanceOf(POOL_MANAGER) + token.balanceOf(CREATOR) == SUPPLY,
            "conservation"
        );
    }

    // Brief test 6: no function can change the rate or the recipient after deployment.
    function test_FeeRateAndRecipientAreCompileTimeConstants() public {
        require(token.CREATOR_TAX_BPS() == 50, "rate is 50 bps");
        require(token.BPS_DENOMINATOR() == 10_000, "denominator");
        require(token.CREATOR_WALLET() == CREATOR, "recipient");
        require(token.POOL_MANAGER() == POOL_MANAGER, "pool manager");

        string[6] memory setters = [
            "setFee(uint256)",
            "setTaxRate(uint256)",
            "setCreatorTaxBps(uint256)",
            "setCreatorWallet(address)",
            "setFeeRecipient(address)",
            "setPoolManager(address)"
        ];
        for (uint256 i; i < setters.length; ++i) {
            vm.prank(FACTORY);
            (bool ok,) = address(token).call(abi.encodeWithSignature(setters[i], ALICE, 0));
            require(!ok, setters[i]);
        }
        require(token.CREATOR_TAX_BPS() == 50 && token.CREATOR_WALLET() == CREATOR, "parameters moved");
    }

    // Brief test 8: no owner, no admin powers, no way to grow the supply.
    function test_NoOwnerOrAdminPowers() public {
        string[8] memory calls = [
            "owner()",
            "renounceOwnership()",
            "transferOwnership(address)",
            "mint(address,uint256)",
            "burn(uint256)",
            "pause()",
            "blacklist(address)",
            "upgradeTo(address)"
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(FACTORY);
            (bool ok,) = address(token).call(abi.encodeWithSignature(calls[i], ALICE, 1));
            require(!ok, calls[i]);
        }
        require(token.totalSupply() == SUPPLY, "supply must not grow");
        require(token.balanceOf(FACTORY) == SUPPLY, "nothing moved");
    }

    // Failure paths: over-spending and unapproved spending revert with the ERC-20 errors.
    function test_RevertsOnInsufficientBalance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 10 ether);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InsufficientBalance.selector, ALICE, 10 ether, 11 ether));
        token.transfer(BOB, 11 ether);
        require(token.balanceOf(ALICE) == 10 ether, "failed transfer must not move funds");
    }

    function test_RevertsOnInsufficientAllowance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 10 ether);

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InsufficientAllowance.selector, BOB, 0, 1 ether));
        token.transferFrom(ALICE, BOB, 1 ether);
    }

    function test_RevertsOnZeroAddressReceiver() public {
        vm.prank(FACTORY);
        vm.expectRevert(abi.encodeWithSelector(SUNToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // A buy routed through transferFrom cannot bypass the tax.
    function test_TransferFromOutOfPoolManagerIsAlsoTaxed() public {
        vm.prank(FACTORY);
        token.transfer(POOL_MANAGER, 1_000 ether);
        vm.prank(POOL_MANAGER);
        token.approve(BUYER, 1_000 ether);

        vm.prank(BUYER);
        require(token.transferFrom(POOL_MANAGER, BUYER, 1_000 ether), "transferFrom returned false");

        require(token.balanceOf(BUYER) == 995 ether, "delegated buy net of tax");
        require(token.balanceOf(CREATOR) == 5 ether, "delegated buy pays the creator");
        require(token.allowance(POOL_MANAGER, BUYER) == 0, "gross allowance consumed");
    }
}
