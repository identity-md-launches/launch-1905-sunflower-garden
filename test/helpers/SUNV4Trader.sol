// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SUNToken} from "../../src/SUNToken.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

interface SUNV4Asset {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address holder) external view returns (uint256);
}

/// @dev Test-only funded trader. All sync/transfer/settle/take calls happen inside a single unlock.
/// This deliberately small router measures net output instead of assuming a taxed take delivers gross.
contract SUNV4Trader is IUnlockCallback {
    IPoolManager public immutable manager;
    SUNToken public immutable sun;

    struct Request {
        PoolKey key;
        bool zeroForOne;
        int256 amountSpecified;
        address recipient;
        bool forwardOutput;
        uint256 minimumReceived;
        bool underpaySun;
    }

    error MinimumOutputNotMet(uint256 received, uint256 minimum);

    constructor(IPoolManager manager_, SUNToken sun_) {
        manager = manager_;
        sun = sun_;
    }

    function swap(Request calldata request) external returns (BalanceDelta) {
        return abi.decode(manager.unlock(abi.encode(request)), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "test trader: only manager");
        Request memory request = abi.decode(data, (Request));
        Currency output = request.zeroForOne ? request.key.currency1 : request.key.currency0;
        uint256 beforeOutput = SUNV4Asset(Currency.unwrap(output)).balanceOf(request.recipient);
        BalanceDelta delta = manager.swap(
            request.key,
            SwapParams(
                request.zeroForOne,
                request.amountSpecified,
                request.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            ""
        );
        _settle(request.key.currency0, delta.amount0(), request);
        _settle(request.key.currency1, delta.amount1(), request);
        uint256 received = SUNV4Asset(Currency.unwrap(output)).balanceOf(request.recipient) - beforeOutput;
        if (received < request.minimumReceived) revert MinimumOutputNotMet(received, request.minimumReceived);

        // Inspect transient deltas while still in the callback. Reading after swap() returns would
        // be vacuous on Forge 1.8, which clears transient storage between top-level transactions.
        // In the negative case, leave the deliberately unpaid unit for PoolManager to reject.
        if (!request.underpaySun) {
            _assertNoDebt(request.key.currency0);
            _assertNoDebt(request.key.currency1);
        }
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta, Request memory request) private {
        SUNV4Asset asset = SUNV4Asset(Currency.unwrap(currency));
        if (delta < 0) {
            uint256 debt = uint256(-int256(delta));
            uint256 paid = request.underpaySun && Currency.unwrap(currency) == address(sun) ? debt - 1 : debt;
            manager.sync(currency);
            require(asset.transfer(address(manager), paid), "test trader: payment failed");
            require(manager.settle() == paid, "test trader: settlement shortfall");
        } else if (delta > 0) {
            if (request.forwardOutput) {
                uint256 beforeTake = asset.balanceOf(address(this));
                manager.take(currency, address(this), uint128(delta));
                uint256 received = asset.balanceOf(address(this)) - beforeTake;
                require(asset.transfer(request.recipient, received), "test trader: forwarding failed");
            } else {
                manager.take(currency, request.recipient, uint128(delta));
            }
        }
    }

    function _assertNoDebt(Currency currency) private view {
        bytes32 slot = keccak256(abi.encode(address(this), Currency.unwrap(currency)));
        require(manager.exttload(slot) == bytes32(0), "test trader: unsettled currency");
    }
}
