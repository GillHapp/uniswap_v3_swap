// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Swap.sol";

contract SimpleSwapTest is Test {
    SimpleSwap public simpleSwap;

    address public token0; // USDC
    address public token1; // WETH
    address public user;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("https://sepolia.infura.io/v3/2de477c3b1b74816ae5475da6d289208");

        token0 = 0x55C173e35d6E69F628cE1E612A5eDeA7E6a0D492;
        token1 = 0xd492389905D6D1dAF45Ae1839cdB6f23d80C9067;

        simpleSwap = new SimpleSwap(token0, token1);

        user = address(this);
    }

    function testCreatePool() public {
        address pool = simpleSwap.createPoolIfNotExists(token0, token1, 3000);
        assertTrue(pool != address(0), "Pool should be created");
    }

    function testGetPool() public view {
        address pool = simpleSwap.getPool(token0, token1, 3000);
        assertTrue(pool != address(0), "Pool should exist");
    }

    function testSwapExactInputSingle() public {
        uint256 swapAmount = 100 * 10 ** 6; // 100 USDC

        deal(token0, user, swapAmount);
        IERC20(token0).approve(address(simpleSwap), swapAmount);

        uint256 output = simpleSwap.swapExactInputSingle(swapAmount);
        console.log("WETH received: ", output);
        assertTrue(output > 0, "Should receive some token1");
    }

    function testSwapExactOutputSingle() public {
        uint256 amountOut = 0.01 ether;
        uint256 amountInMax = 200 * 10 ** 6; // 200 USDC

        deal(token0, user, amountInMax);
        IERC20(token0).approve(address(simpleSwap), amountInMax);

        uint256 amountIn = simpleSwap.swapExactOutputSingle(amountOut, amountInMax);
        console.log("USDC spent: ", amountIn);
        assertTrue(amountIn > 0 && amountIn <= amountInMax, "Should swap within limit");
    }

    // function testMintNewPosition() public {
    //     uint256 usdcAmount = 500 * 10 ** 6;
    //     uint256 wethAmount = 1 ether;

    //     deal(token0, user, usdcAmount);
    //     deal(token1, user, wethAmount);

    //     IERC20(token0).approve(address(simpleSwap), usdcAmount);
    //     IERC20(token1).approve(address(simpleSwap), wethAmount);

    //     // uint256 tokenId = simpleSwap.mintNewPosition();
    //     // console.log("LP token minted with ID: ", tokenId);
    //     // assertTrue(tokenId > 0, "LP Token should be minted");
    // }

    // function testIncreaseLiquidity() public {
    //     testMintNewPosition();

    //     uint256 usdcAmount = 300 * 10 ** 6;
    //     uint256 wethAmount = 0.5 ether;

    //     deal(token0, user, usdcAmount);
    //     deal(token1, user, wethAmount);

    //     IERC20(token0).approve(address(simpleSwap), usdcAmount);
    //     IERC20(token1).approve(address(simpleSwap), wethAmount);

    //     simpleSwap.increaseLiquidityCurrentRange();
    // }

    // function testDecreaseLiquidity() public {
    //     testMintNewPosition();

    //     // Should reduce liquidity and collect some tokens back
    //     simpleSwap.decreaseLiquidityInHalf();
    // }

    // function testGetLiquidityInfo() public {
    //     testMintNewPosition();

    //     uint256 liquidity = simpleSwap.getPoolLiquidity();
    //     int24 tick = simpleSwap.getCurrentTick();
    //     uint256 ratio = simpleSwap.getPriceRatio();

    //     console.log("Liquidity: ", liquidity);
    //     console.log("Current Tick: ", tick);
    //     console.log("Price Ratio: ", ratio);

    //     assertTrue(liquidity > 0, "Liquidity should exist");
    // }
}
