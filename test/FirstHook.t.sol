// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import "forge-std/Test.sol";
import {CountingHook} from "../src/FirstHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

contract CountingHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    CountingHook public hook;
    // The two currencies (tokens) from the pool
    Currency token0;
    Currency token1;

    PoolKey pool_key;
    PoolId pool_id;

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy our TOKEN contract
        (token0, token1) = deployMintAndApprove2Currencies();

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        address hookAddress = address(flags);
        // Deploy our hook
        deployCodeTo("FirstHook.sol", abi.encode(manager), hookAddress);
        hook = CountingHook(hookAddress);

        // Approve our hook address to spend these tokens as well
        MockERC20(Currency.unwrap(token0)).approve(address(hook), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), type(uint256).max);

        // Initialize a pool
        (pool_key, pool_id) = initPool(
            token0, // Currency 0 = ETH
            token1, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1, // Initial Sqrt(P) value = 1
            ZERO_BYTES // No additional `initData`
        );

        // Add some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            pool_key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_swap() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true, //true: from token 0 to token 1
            amountSpecified: 0.1 ether,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        assertEq(hook.afterSwapCount(pool_id), 0);

        // After swap transaction, our hook will be triggered
        swapRouter.swap(pool_key, params, testSettings, "");
        assertEq(hook.afterSwapCount(pool_id), 1);
    }
}
