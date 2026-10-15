// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SUNToken} from "../src/SUNToken.sol";
import {Vm} from "./SUNToken.t.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

interface Transferable {
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

// Test-only stand-in for IMD; no production application contract is deployed.
contract PairForTest {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

abstract contract UniswapV4Test is IUnlockCallback {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant POOL = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant PAIR = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address constant SWARM = address(0xD157);
    SUNToken token;
    IPoolManager manager;
    PoolKey key;
    int24 lower;
    int24 upper;

    function preferSunFirst() internal pure virtual returns (bool);

    function setUp() public {
        bytes32 codeHash = keccak256(type(SUNToken).creationCode);
        for (uint256 i; i < 1000; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
            if ((predicted < PAIR) == preferSunFirst()) {
                token = new SUNToken{salt: salt}();
                break;
            }
        }
        require(address(token) != address(0), "currency order deployment");
        // Execute the actual v4 constructor at the fixed address so NoDelegateCall's
        // original-address immutable matches the manager used by the token.
        vm.etch(POOL, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = POOL.call("");
        require(ok && runtime.length > 0, "manager construction");
        vm.etch(POOL, runtime);
        manager = IPoolManager(POOL);
        vm.etch(PAIR, address(new PairForTest()).code);
        PairForTest(PAIR).mint(address(this), 10_000 ether);
        token.transfer(SWARM, 100_000_000 ether);
        bool sunFirst = address(token) < PAIR;
        key = PoolKey(
            Currency.wrap(sunFirst ? address(token) : PAIR),
            Currency.wrap(sunFirst ? PAIR : address(token)),
            12500,
            60,
            IHooks(address(0))
        );
        // Opening quote is 2500 IMD / 1e9 SUN = 0.0000025 IMD per SUN.
        uint160 price = sunFirst ? uint160(125270724187523965593206900) : uint160(50108289675009586237282760313921);
        int24 tick = manager.initialize(key, price);
        int24 aligned = (tick / 60) * 60;
        if (sunFirst) {
            lower = aligned + 60;
            upper = lower + 1200;
        } else {
            upper = aligned - 60;
            lower = upper - 1200;
        }
    }

    function test_ActualV4SingleSidedSeedBuyAndSell() public {
        uint256 beforeSeed = token.balanceOf(address(this));
        manager.unlock(abi.encode(uint8(0), int256(1e24)));
        uint256 seeded = beforeSeed - token.balanceOf(address(this));
        require(seeded > 0 && seeded <= 900_000_000 ether, "single-sided seed size");
        require(token.balanceOf(POOL) == seeded, "seed settlement tax");
        require(token.balanceOf(token.CREATOR_WALLET()) == 0, "creator taxed seed");
        uint256 beforeBuy = token.balanceOf(address(this));
        uint256 poolBefore = token.balanceOf(POOL);
        manager.unlock(abi.encode(uint8(1), -int256(1 ether)));
        uint256 gross = poolBefore - token.balanceOf(POOL);
        uint256 net = token.balanceOf(address(this)) - beforeBuy;
        require(gross > 0 && net == gross - gross / 200, "buy net tax");
        require(token.balanceOf(token.CREATOR_WALLET()) == gross / 200, "creator payment");
        uint256 feeBefore = token.balanceOf(token.CREATOR_WALLET());
        poolBefore = token.balanceOf(POOL);
        uint256 pairedBefore = PairForTest(PAIR).balanceOf(address(this));
        manager.unlock(abi.encode(uint8(2), -int256(net)));
        require(token.balanceOf(address(this)) == beforeBuy, "sold entire net amount");
        require(token.balanceOf(POOL) == poolBefore + net, "sell settles full debt");
        require(PairForTest(PAIR).balanceOf(address(this)) > pairedBefore, "no paired output");
        require(token.balanceOf(token.CREATOR_WALLET()) == feeBefore, "sell taxed");
        require(token.totalSupply() == 1e27, "supply changed");
        require(token.balanceOf(SWARM) == 100_000_000 ether, "swarm touched");
    }

    function test_ActualV4WithdrawalIsAlsoTaxedOnPoolOutflow() public {
        manager.unlock(abi.encode(uint8(0), int256(1e24)));
        uint256 before = token.balanceOf(address(this));
        uint256 managerBefore = token.balanceOf(POOL);
        manager.unlock(abi.encode(uint8(3), -int256(1e24)));
        uint256 gross = managerBefore - token.balanceOf(POOL);
        require(gross > 0, "no withdrawn liquidity");
        require(token.balanceOf(address(this)) - before == gross - gross / 200, "withdrawal tax");
        require(token.balanceOf(token.CREATOR_WALLET()) == gross / 200, "withdrawal recipient");
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == POOL, "only manager");
        (uint8 operation, int256 amount) = abi.decode(data, (uint8, int256));
        BalanceDelta delta;
        if (operation == 0 || operation == 3) {
            (delta,) = manager.modifyLiquidity(key, ModifyLiquidityParams(lower, upper, amount, bytes32(0)), "");
        } else {
            bool sunFirst = address(token) < PAIR;
            bool zeroForOne = operation == 1 ? !sunFirst : sunFirst;
            delta = manager.swap(
                key,
                SwapParams(zeroForOne, amount, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
                ""
            );
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta) private {
        if (delta < 0) {
            uint256 amount = uint256(-int256(delta));
            manager.sync(currency);
            Transferable(Currency.unwrap(currency)).transfer(POOL, amount);
            require(manager.settle() == amount, "settlement shortfall");
        } else if (delta > 0) {
            manager.take(currency, address(this), uint128(delta));
        }
    }
}

contract SUNAsCurrencyZeroTest is UniswapV4Test {
    function preferSunFirst() internal pure override returns (bool) {
        return true;
    }
}

contract SUNAsCurrencyOneTest is UniswapV4Test {
    function preferSunFirst() internal pure override returns (bool) {
        return false;
    }
}
