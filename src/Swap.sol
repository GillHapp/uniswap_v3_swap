// SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract SimpleSwap is IERC721Receiver {
    event PoolCreated(address indexed tokenA, address indexed tokenB, uint24 indexed fee, address pool);
    event PoolInitialized(address indexed pool, uint160 sqrtPriceX96);

    ISwapRouter public immutable swapRouter = ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
    uint24 public constant feeTier = 3000;
    address public immutable token0;
    address public immutable token1;

    IUniswapV3Factory public immutable iUniswapV3Factory = IUniswapV3Factory(0x0227628f3F023bb0B980b67D528571c95c6DaC1c);
    INonfungiblePositionManager public immutable nonfungiblePositionManager =
        INonfungiblePositionManager(0x1238536071E1c677A632429e3655c799b22cDA52);

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    mapping(uint256 => Deposit) public deposits;

    constructor(address _token0, address _token1) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
        token0 = _token0;
        token1 = _token1;
    }

    // Create pool and initialize it if it doesn't exist
    function createAndInitializePoolIfNecessary(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96)
        external
        returns (address pool)
    {
        pool = iUniswapV3Factory.getPool(tokenA, tokenB, fee);

        if (pool == address(0)) {
            pool = iUniswapV3Factory.createPool(tokenA, tokenB, fee);
            emit PoolCreated(tokenA, tokenB, fee, pool);
        }

        // Check if pool needs initialization
        (uint160 currentSqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        if (currentSqrtPriceX96 == 0) {
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            emit PoolInitialized(pool, sqrtPriceX96);
        }

        require(pool != address(0), "Pool creation failed");
        return pool;
    }

    // Helper function to calculate sqrtPriceX96 for a 1:10 ratio (1 token0 = 10 token1)
    function getSqrtPriceX96For1to10Ratio() public pure returns (uint160) {
        // For a 1:10 ratio, price = 10
        // sqrtPrice = sqrt(10) ≈ 3.16227766
        // sqrtPriceX96 = sqrtPrice * 2^96
        return 250541448375047931186413801569; // This represents sqrt(10) * 2^96
    }

    // Helper function to get current tick from pool
    function getCurrentTick() external view returns (int24) {
        address poolAddress = iUniswapV3Factory.getPool(token0, token1, feeTier);
        require(poolAddress != address(0), "Pool does not exist");

        (, int24 tick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        return tick;
    }

    // Helper function to calculate tick range around current price
    function getTickRangeAroundCurrent(int24 tickDistance) external view returns (int24 lowerTick, int24 upperTick) {
        int24 currentTick = this.getCurrentTick();
        int24 tickSpacing = 60; // For 0.3% fee tier

        lowerTick = ((currentTick - tickDistance) / tickSpacing) * tickSpacing;
        upperTick = ((currentTick + tickDistance) / tickSpacing) * tickSpacing;
    }

    // create pool if it does not exist (keeping original function for compatibility)
    function createPoolIfNotExists(address tokenA, address tokenB, uint24 fee) external returns (address) {
        address pool = iUniswapV3Factory.createPool(tokenA, tokenB, fee);
        require(pool != address(0), "Pool creation failed");
        emit PoolCreated(tokenA, tokenB, fee, pool);
        return pool;
    }

    // get the pool address for a given pair of tokens and fee
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        address pool = iUniswapV3Factory.getPool(tokenA, tokenB, fee);
        require(pool != address(0), "Pool does not exist");
        return pool;
    }

    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        // get position information
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (,, address posToken0, address posToken1,,,, uint128 liquidity,,,,) =
            nonfungiblePositionManager.positions(tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: posToken0, token1: posToken1});
    }

    // add liquidity
    function mintNewPosition(int24 _lowerTick, int24 _upperTick)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // Check if pool exists and is initialized
        address poolAddress = iUniswapV3Factory.getPool(token0, token1, feeTier);
        require(poolAddress != address(0), "Pool does not exist");

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        require(sqrtPriceX96 > 0, "Pool not initialized");

        uint256 amount0ToMint = 100 * 10 ** 18;
        uint256 amount1ToMint = 1000 * 10 ** 18;

        // Approve the position manager
        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: feeTier,
            tickLower: _lowerTick,
            tickUpper: _upperTick,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param tokenId The id of the erc721 token
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
    function increaseLiquidityCurrentRange(uint256 tokenId, uint256 amountAdd0, uint256 amountAdd1)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amountAdd0,
            amount1Desired: amountAdd1,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
    }

    /// @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseLiquidityInHalf(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // caller must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, "Not the owner");
        // get liquidity data for tokenId
        uint128 liquidity = deposits[tokenId].liquidity;
        uint128 halfLiquidity = liquidity / 2;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: halfLiquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        nonfungiblePositionManager.decreaseLiquidity(params);

        (amount0, amount1) = nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        //send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToOwner(uint256 tokenId, uint256 amount0, uint256 amount1) internal {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address tokenA = deposits[tokenId].token0;
        address tokenB = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(tokenA, owner, amount0);
        TransferHelper.safeTransfer(tokenB, owner, amount1);
    }

    /// @notice swapExactInputSingle swaps a fixed amount of DAI for a maximum possible amount of WETH9
    /// using the DAI/WETH9 0.3% pool by calling `exactInputSingle` in the swap router.
    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its DAI for this function to succeed.
    /// @param amountIn The exact amount of DAI that will be swapped for WETH9.
    /// @return amountOut The amount of WETH9 received.
    function swapExactInputSingle(uint256 amountIn) external returns (uint256 amountOut) {
        // msg.sender must approve this contract

        // Transfer the specified amount of DAI to this contract.
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountIn);

        // Approve the router to spend DAI.
        TransferHelper.safeApprove(token0, address(swapRouter), amountIn);
        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: token0,
            tokenOut: token1,
            fee: feeTier,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    /// @notice swapExactOutputSingle swaps a minimum possible amount of DAI for a fixed amount of WETH.
    /// @dev The calling address must approve this contract to spend its DAI for this function to succeed. As the amount of input DAI is variable,
    /// the calling address will need to approve for a slightly higher amount, anticipating some variance.
    /// @param amountOut The exact amount of WETH9 to receive from the swap.
    /// @param amountInMaximum The amount of DAI we are willing to spend to receive the specified amount of WETH9.
    /// @return amountIn The amount of DAI actually spent in the swap.
    function swapExactOutputSingle(uint256 amountOut, uint256 amountInMaximum) external returns (uint256 amountIn) {
        // Transfer the specified amount of DAI to this contract.
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountInMaximum);

        // Approve the router to spend the specified `amountInMaximum` of DAI.
        // In production, you should choose the maximum amount to spend based on oracles or other data sources to achieve a better swap.
        TransferHelper.safeApprove(token0, address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: token0,
            tokenOut: token1,
            fee: feeTier,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = swapRouter.exactOutputSingle(params);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(token0, address(swapRouter), 0);
            TransferHelper.safeTransfer(token0, msg.sender, amountInMaximum - amountIn);
        }
    }
}
