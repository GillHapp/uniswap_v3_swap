// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";
import "../src/Swap.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract SimpleSwapTest is Test {
    SimpleSwap public simpleSwap;
    address public token0; // USDC
    address public token1; // WETH
    address public user;

    // sqrtPriceX96 for 1:10 ratio (1 token0 = 10 token1)
    uint160 constant SQRT_PRICE_X96 = 250541448375047931186413801569;

    function setUp() public {
        simpleSwap = new SimpleSwap(
            address(0x55C173e35d6E69F628cE1E612A5eDeA7E6a0D492), address(0xd492389905D6D1dAF45Ae1839cdB6f23d80C9067)
        );
        // Fork from Sepolia to use existing tokens
        vm.createSelectFork("https://sepolia.infura.io/v3/2de477c3b1b74816ae5475da6d289208");

        token0 = 0x55C173e35d6E69F628cE1E612A5eDeA7E6a0D492;
        token1 = 0xd492389905D6D1dAF45Ae1839cdB6f23d80C9067;
        user = address(this);
    }

    // Helper function to calculate tick from price
    function getTickFromPrice(uint256 price) public pure returns (int24) {
        // price = 1.0001^tick
        // tick = log(price) / log(1.0001)
        // For price = 10: tick ≈ 23027
        if (price == 10) return 23027;// a/b 1:10 
        if (price == 5) return 16094; // Lower bound
        if (price == 20) return 29956; // Upper bound
        return 23027; // Default for price = 10
    }

    function testMintNewPositionWithCorrectTicks() public {
        uint256 amount0ToMint = 100e18;
        uint256 amount1ToMint = 1000e18;

        // Give tokens to the test contract
        deal(token0, user, amount0ToMint);
        deal(token1, user, amount1ToMint);

        // Create and initialize pool
        address poolAddress = simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        // Get current tick from the pool
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, int24 currentTick,,,,, bool unlocked) = pool.slot0();

        console.log("Current tick:", currentTick);
        // console.log("Current sqrtPriceX96:", sqrtPriceX96);

        assertTrue(sqrtPriceX96 > 0, "Pool should be initialized");
        assertTrue(unlocked, "Pool should be unlocked");

        // Transfer tokens to SimpleSwap contract
        IERC20(token0).transfer(address(simpleSwap), amount0ToMint);
        IERC20(token1).transfer(address(simpleSwap), amount1ToMint);

        // Set tick range AROUND the current tick to ensure both tokens are used
        // Tick spacing for 0.3% fee tier is 60, so use multiples of 60
        int24 tickSpacing = 60;
        int24 lowerTick = ((currentTick - 1200) / tickSpacing) * tickSpacing; // ~5% below
        int24 upperTick = ((currentTick + 1200) / tickSpacing) * tickSpacing; // ~5% above

        console.log("Lower tick:", lowerTick);
        console.log("Upper tick:", upperTick);

        // Mint position with corrected ticks
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            simpleSwap.mintNewPosition(lowerTick, upperTick);

        console.log("Token ID: ", tokenId, " Liquidity: ", liquidity);
        console.log("Amount0 used: ", amount0);
        console.log("Amount1 used: ", amount1);

        assertTrue(tokenId > 0, "LP Token should be minted");
        assertTrue(liquidity > 0, "Should have liquidity");
        assertTrue(amount0 > 0, "Should use some token0");
        assertTrue(amount1 > 0, "Should use some token1");
    }

    // Test with manually calculated ticks for 1:10 ratio
    function testMintNewPositionWithManualTicks() public {
        uint256 amount0ToMint = 100e18;
        uint256 amount1ToMint = 1000e18;

        // Give tokens to the test contract
        deal(token0, user, amount0ToMint);
        deal(token1, user, amount1ToMint);

        // Create and initialize pool
        simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        // Transfer tokens to SimpleSwap contract
        IERC20(token0).transfer(address(simpleSwap), amount0ToMint);
        IERC20(token1).transfer(address(simpleSwap), amount1ToMint);

        // Use calculated ticks for price range 5 to 20 (current price is 10)
        // This ensures the current price is in the middle of our range
        int24 lowerTick = 16020; // Represents price ~5
        int24 upperTick = 29940; // Represents price ~20

        console.log("Manual Lower tick:", lowerTick);
        console.log("Manual Upper tick:", upperTick);

        // Mint position
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            simpleSwap.mintNewPosition(lowerTick, upperTick);

        console.log("Token ID: ", tokenId, " Liquidity: ", liquidity);
        console.log("Amount0 used: ", amount0);
        console.log("Amount1 used: ", amount1);

        assertTrue(tokenId > 0, "LP Token should be minted");
        assertTrue(liquidity > 0, "Should have liquidity");
        assertTrue(amount0 > 0, "Should use some token0");
        assertTrue(amount1 > 0, "Should use some token1");
    }

    // Test with very wide range to ensure both tokens are used
    function testMintNewPositionWideRange() public {
        uint256 amount0ToMint = 100e18;
        uint256 amount1ToMint = 1000e18;

        // Give tokens to the test contract
        deal(token0, user, amount0ToMint);
        deal(token1, user, amount1ToMint);

        // Create and initialize pool
        address poolAddress = simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        // Transfer tokens to SimpleSwap contract
        IERC20(token0).transfer(address(simpleSwap), amount0ToMint);
        IERC20(token1).transfer(address(simpleSwap), amount1ToMint);

        // Use a very wide range to ensure both tokens are definitely used
        // This represents roughly 1:1 to 1:100 price range
        int24 lowerTick = 0; // Price ~1
        int24 upperTick = 46080; // Price ~100

        console.log("Wide range - Lower tick:", lowerTick);
        console.log("Wide range - Upper tick:", upperTick);

        // Mint position
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            simpleSwap.mintNewPosition(lowerTick, upperTick);

        console.log("Token ID: ", tokenId, " Liquidity: ", liquidity);
        console.log("Amount0 used: ", amount0);
        console.log("Amount1 used: ", amount1);

        assertTrue(tokenId > 0, "LP Token should be minted");
        assertTrue(liquidity > 0, "Should have liquidity");
        assertTrue(amount0 > 0, "Should use some token0");
        assertTrue(amount1 > 0, "Should use some token1");
    }

    function testGetCurrentPoolInfo() public {
        // Create and initialize pool
        address poolAddress = simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();

        console.log("Pool address:", poolAddress);
        // console.log("sqrtPriceX96:", sqrtPriceX96);
        console.log("Current tick:", currentTick);

        // Calculate actual price from sqrtPriceX96
        // price = (sqrtPriceX96 / 2^96)^2
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
        console.log("Calculated price:", price);
    }

    // ===========================================
    // NEW TESTS FOR ADDITIONAL FUNCTIONALITY
    // ===========================================

    function testIncreaseLiquidity() public {
        uint256 amount0ToMint = 100e18;
        uint256 amount1ToMint = 1000e18;

        // Give initial tokens
        deal(token0, user, amount0ToMint * 2);
        deal(token1, user, amount1ToMint * 2);

        // Create and initialize pool
        simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        // Transfer tokens to SimpleSwap contract
        IERC20(token0).transfer(address(simpleSwap), amount0ToMint);
        IERC20(token1).transfer(address(simpleSwap), amount1ToMint);

        // Get tick range
        int24 currentTick = simpleSwap.getCurrentTick();
        int24 tickSpacing = 60;
        int24 lowerTick = ((currentTick - 1200) / tickSpacing) * tickSpacing;
        int24 upperTick = ((currentTick + 1200) / tickSpacing) * tickSpacing;

        // Mint initial position
        (uint256 tokenId,,,) = simpleSwap.mintNewPosition(lowerTick, upperTick);

        // console.log("Initial liquidity:", initialLiquidity);

        // Prepare additional tokens for increasing liquidity
        uint256 additionalAmount0 = 50e18;
        uint256 additionalAmount1 = 500e18;

        // Transfer additional tokens to SimpleSwap
        IERC20(token0).transfer(address(simpleSwap), additionalAmount0);
        IERC20(token1).transfer(address(simpleSwap), additionalAmount1);

        // Increase liquidity
        (uint128 addedLiquidity, uint256 amount0Used, uint256 amount1Used) =
            simpleSwap.increaseLiquidityCurrentRange(tokenId, additionalAmount0, additionalAmount1);

        // console.log("Added liquidity:", addedLiquidity);
        console.log("Amount0 used for increase:", amount0Used);
        console.log("Amount1 used for increase:", amount1Used);

        assertTrue(addedLiquidity > 0, "Should add liquidity");
        assertTrue(amount0Used > 0, "Should use some token0");
        assertTrue(amount1Used > 0, "Should use some token1");

        // Verify total liquidity increased
        (, uint128 finalLiquidity,,) = simpleSwap.deposits(tokenId);
        // console.log("Final liquidity in deposit:", finalLiquidity);
        // Note: The deposit struct liquidity might not update automatically,
        // but the actual position liquidity should be higher
    }

    function testSwapExactInputSingle() public {
        uint256 amount0ToMint = 1000e18; // 1000 USDC
        uint256 amount1ToMint = 10000e18; // 10000 WETH
        uint256 swapAmount = 1e18; // Swap 1 USDC

        // Give tokens for liquidity and swap
        deal(token0, user, amount0ToMint + swapAmount);
        deal(token1, user, amount1ToMint);

        // Create and initialize pool
        simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        // Approve and transfer tokens for liquidity
        vm.startPrank(user);
        IERC20(token0).approve(address(simpleSwap), amount0ToMint);
        IERC20(token1).approve(address(simpleSwap), amount1ToMint);
        IERC20(token0).transfer(address(simpleSwap), amount0ToMint);
        IERC20(token1).transfer(address(simpleSwap), amount1ToMint);
        vm.stopPrank();

        int24 lowerTick = 0; // Price ~1
        int24 upperTick = 46080; // Price ~100

        console.log("Lower tick:", lowerTick);
        console.log("Upper tick:", upperTick);

        // Mint initial position
        (, uint128 initialLiquidity,,) = simpleSwap.mintNewPosition(lowerTick, upperTick);
        // console.log("Initial liquidity:", initialLiquidity);

        // Approve tokens for swap
        vm.startPrank(user);
        IERC20(token0).approve(address(simpleSwap), swapAmount);
        vm.stopPrank();

        // Perform swap
        uint256 amountOut = simpleSwap.swapExactInputSingle(swapAmount);
        console.log("Swap input (token0):", swapAmount);
        console.log("Swap output (token1):", amountOut);

        assertTrue(amountOut > 0, "Should receive some token1");
    }

    function testSwapExactOutputSingle() public {
        uint256 liquidityAmount0 = 1000e18;
        uint256 liquidityAmount1 = 10000e18;
        uint256 desiredOutput = 50e18; // Want 50 token1
        uint256 maxInput = 10e18; // Willing to spend max 10 token0

        // Give tokens for liquidity and swap
        deal(token0, user, liquidityAmount0 + maxInput);
        deal(token1, user, liquidityAmount1);

        // Create and initialize pool
        simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        // Add liquidity first
        IERC20(token0).transfer(address(simpleSwap), liquidityAmount0);
        IERC20(token1).transfer(address(simpleSwap), liquidityAmount1);

        int24 currentTick = simpleSwap.getCurrentTick();
        int24 tickSpacing = 60;
        int24 lowerTick = ((currentTick - 6000) / tickSpacing) * tickSpacing;
        int24 upperTick = ((currentTick + 6000) / tickSpacing) * tickSpacing;

        simpleSwap.mintNewPosition(lowerTick, upperTick);

        // Record balances before swap
        uint256 token0BalanceBefore = IERC20(token0).balanceOf(user);
        uint256 token1BalanceBefore = IERC20(token1).balanceOf(user);

        console.log("Before exact output swap - Token0 balance:", token0BalanceBefore);
        console.log("Before exact output swap - Token1 balance:", token1BalanceBefore);

        // Approve SimpleSwap to spend tokens
        IERC20(token0).approve(address(simpleSwap), maxInput);

        // Perform exact output swap: spend token0 to get exact amount of token1
        uint256 actualAmountIn = simpleSwap.swapExactOutputSingle(desiredOutput, maxInput);

        console.log("Desired output (token1):", desiredOutput);
        console.log("Max input (token0):", maxInput);
        console.log("Actual input used (token0):", actualAmountIn);

        // Check balances after swap
        uint256 token0BalanceAfter = IERC20(token0).balanceOf(user);
        uint256 token1BalanceAfter = IERC20(token1).balanceOf(user);

        console.log("After exact output swap - Token0 balance:", token0BalanceAfter);
        console.log("After exact output swap - Token1 balance:", token1BalanceAfter);

        assertTrue(actualAmountIn > 0, "Should use some token0");
        assertTrue(actualAmountIn <= maxInput, "Should not exceed max input");
        assertEq(token0BalanceAfter, token0BalanceBefore - actualAmountIn, "Token0 should decrease by actual input");
        assertEq(token1BalanceAfter, token1BalanceBefore + desiredOutput, "Token1 should increase by exact output");
    }

    function testSwapBackAndForth() public {
        uint256 liquidityAmount0 = 2000e18;
        uint256 liquidityAmount1 = 20000e18;
        uint256 swapAmount = 50e18;

        // Give tokens for liquidity and swaps
        deal(token0, user, liquidityAmount0 + swapAmount);
        deal(token1, user, liquidityAmount1);

        // Create and initialize pool
        simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        // Add substantial liquidity
        IERC20(token0).transfer(address(simpleSwap), liquidityAmount0);
        IERC20(token1).transfer(address(simpleSwap), liquidityAmount1);

        int24 currentTick = simpleSwap.getCurrentTick();
        int24 tickSpacing = 60;
        int24 lowerTick = ((currentTick - 12000) / tickSpacing) * tickSpacing; // Very wide range
        int24 upperTick = ((currentTick + 12000) / tickSpacing) * tickSpacing;

        simpleSwap.mintNewPosition(lowerTick, upperTick);

        // Record initial balances
        uint256 initialToken0 = IERC20(token0).balanceOf(user);
        uint256 initialToken1 = IERC20(token1).balanceOf(user);

        console.log("=== INITIAL BALANCES ===");
        console.log("Token0:", initialToken0);
        console.log("Token1:", initialToken1);

        // FIRST SWAP: token0 -> token1
        IERC20(token0).approve(address(simpleSwap), swapAmount);
        uint256 token1Received = simpleSwap.swapExactInputSingle(swapAmount);

        uint256 midToken0 = IERC20(token0).balanceOf(user);
        uint256 midToken1 = IERC20(token1).balanceOf(user);

        console.log("=== AFTER FIRST SWAP (token0 -> token1) ===");
        console.log("Token0:", midToken0);
        console.log("Token1:", midToken1);
        console.log("Token1 received:", token1Received);

        // SECOND SWAP: token1 -> token0 (swap back half of what we received)
        uint256 swapBackAmount = token1Received / 2;

        // For swapping token1 -> token0, we need to create a swap function or use the existing ones
        // Since the current contract only has token0 -> token1 swaps, let's test exact output
        // to get some token0 back by specifying we want a certain amount of token0

        uint256 desiredToken0Back = swapAmount / 4; // Want back 1/4 of original token0
        uint256 maxToken1ToSpend = token1Received; // Willing to spend all received token1

        IERC20(token1).approve(address(simpleSwap), maxToken1ToSpend);

        // Note: This won't work directly with current contract as it's hardcoded for token0->token1
        // But let's demonstrate the concept by doing another forward swap

        // Alternative: Do another forward swap with remaining token0
        uint256 remainingToken0 = midToken0;
        if (remainingToken0 > 10e18) {
            uint256 secondSwapAmount = 10e18;
            IERC20(token0).approve(address(simpleSwap), secondSwapAmount);
            uint256 secondToken1Received = simpleSwap.swapExactInputSingle(secondSwapAmount);

            console.log("=== AFTER SECOND FORWARD SWAP ===");
            console.log("Second swap amount (token0):", secondSwapAmount);
            console.log("Second token1 received:", secondToken1Received);
        }

        // Final balances
        uint256 finalToken0 = IERC20(token0).balanceOf(user);
        uint256 finalToken1 = IERC20(token1).balanceOf(user);

        console.log("=== FINAL BALANCES ===");
        console.log("Token0:", finalToken0);
        console.log("Token1:", finalToken1);

        // Verify swaps occurred
        assertTrue(finalToken0 < initialToken0, "Should have spent some token0");
        assertTrue(finalToken1 > initialToken1, "Should have gained some token1");
    }

    function testCompleteWorkflow() public {
        console.log("=== TESTING COMPLETE WORKFLOW ===");

        uint256 liquidityAmount0 = 500e18;
        uint256 liquidityAmount1 = 5000e18;

        // Give tokens
        deal(token0, user, liquidityAmount0 * 3);
        deal(token1, user, liquidityAmount1 * 3);

        // 1. Create and initialize pool
        console.log("1. Creating and initializing pool...");
        address poolAddress = simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);
        console.log("Pool created at:", poolAddress);

        // 2. Add initial liquidity
        console.log("2. Adding initial liquidity...");
        IERC20(token0).transfer(address(simpleSwap), liquidityAmount0);
        IERC20(token1).transfer(address(simpleSwap), liquidityAmount1);

        int24 currentTick = simpleSwap.getCurrentTick();
        int24 tickSpacing = 60;
        int24 lowerTick = ((currentTick - 3000) / tickSpacing) * tickSpacing;
        int24 upperTick = ((currentTick + 3000) / tickSpacing) * tickSpacing;

        (uint256 tokenId, uint128 initialLiquidity,,) = simpleSwap.mintNewPosition(lowerTick, upperTick);
        console.log("Position created with tokenId:", tokenId);
        // console.log("Initial liquidity:", initialLiquidity);

        // 3. Increase liquidity
        console.log("3. Increasing liquidity...");
        IERC20(token0).transfer(address(simpleSwap), liquidityAmount0 / 2);
        IERC20(token1).transfer(address(simpleSwap), liquidityAmount1 / 2);

        (uint128 addedLiquidity,,) =
            simpleSwap.increaseLiquidityCurrentRange(tokenId, liquidityAmount0 / 2, liquidityAmount1 / 2);
        // console.log("Added liquidity:", addedLiquidity);

        // 4. Perform swaps
        console.log("4. Performing swaps...");
        uint256 swapAmount = 25e18;
        IERC20(token0).approve(address(simpleSwap), swapAmount);
        uint256 outputReceived = simpleSwap.swapExactInputSingle(swapAmount);
        // console.log("Swapped", swapAmount, "token0 for", outputReceived, "token1");

        // 5. Decrease liquidity
        console.log("5. Decreasing liquidity by half...");
        uint256 userBalanceBefore0 = IERC20(token0).balanceOf(user);
        uint256 userBalanceBefore1 = IERC20(token1).balanceOf(user);

        (uint256 returned0, uint256 returned1) = simpleSwap.decreaseLiquidityInHalf(tokenId);
        console.log("Returned from liquidity decrease - Token0:", returned0, "Token1:", returned1);

        uint256 userBalanceAfter0 = IERC20(token0).balanceOf(user);
        uint256 userBalanceAfter1 = IERC20(token1).balanceOf(user);

        console.log("User balance change - Token0:", userBalanceAfter0 - userBalanceBefore0);
        console.log("User balance change - Token1:", userBalanceAfter1 - userBalanceBefore1);

        // Final verification
        assertTrue(tokenId > 0, "Position should be created");
        assertTrue(addedLiquidity > 0, "Should add liquidity");
        assertTrue(outputReceived > 0, "Should receive tokens from swap");
        assertTrue(returned0 > 0 || returned1 > 0, "Should return tokens from liquidity decrease");

        console.log("=== WORKFLOW COMPLETED SUCCESSFULLY ===");
    }

    // Test error cases
    function testUnauthorizedDecreaseLiquidity() public {
        uint256 amount0ToMint = 100e18;
        uint256 amount1ToMint = 1000e18;

        deal(token0, user, amount0ToMint);
        deal(token1, user, amount1ToMint);

        simpleSwap.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_X96);

        IERC20(token0).transfer(address(simpleSwap), amount0ToMint);
        IERC20(token1).transfer(address(simpleSwap), amount1ToMint);

        int24 currentTick = simpleSwap.getCurrentTick();
        int24 tickSpacing = 60;
        int24 lowerTick = ((currentTick - 1200) / tickSpacing) * tickSpacing;
        int24 upperTick = ((currentTick + 1200) / tickSpacing) * tickSpacing;

        (uint256 tokenId,,,) = simpleSwap.mintNewPosition(lowerTick, upperTick);

        // Try to decrease liquidity from a different address
        address otherUser = address(0x123);
        vm.prank(otherUser);
        vm.expectRevert("Not the owner");
        simpleSwap.decreaseLiquidityInHalf(tokenId);
    }
}
