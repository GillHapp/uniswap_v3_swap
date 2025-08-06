//SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;
pragma abicoder v2;

// Importing the necessary interfaces and libraries
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract Swap is IERC721Receiver {
    uint24 public constant poolFee = 3000;
    INonfungiblePositionManager public immutable nonfungiblePositionManager =
        INonfungiblePositionManager(0x1238536071E1c677A632429e3655c799b22cDA52);

    ISwapRouter public immutable swapRouter = ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
    address public immutable tokenA;
    address public immutable tokenB;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    mapping(uint256 => Deposit) public deposits;

    constructor(address _tokenA, address _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    // Helper function to handle mint parameters
    function _getMintParams(address _tokenA, address _tokenB, uint256 _amountA, uint256 _amountB)
        internal
        view
        returns (INonfungiblePositionManager.MintParams memory)
    {
        return INonfungiblePositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            fee: poolFee,
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            amount0Desired: _amountA,
            amount1Desired: _amountB,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 15 minutes
        });
    }

    // Helper function to handle refunds
    function _handleRefunds(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB,
        uint256 amount0,
        uint256 amount1
    ) internal {
        if (amount0 < _amountA) {
            TransferHelper.safeApprove(_tokenA, address(nonfungiblePositionManager), 0);
            TransferHelper.safeTransfer(_tokenA, msg.sender, _amountA - amount0);
        }

        if (amount1 < _amountB) {
            TransferHelper.safeApprove(_tokenB, address(nonfungiblePositionManager), 0);
            TransferHelper.safeTransfer(_tokenB, msg.sender, _amountB - amount1);
        }
    }

    // add liquidity to the Uniswap V3 pool
    function addLiquidity(address _tokenA, address _tokenB, uint256 _amountA, uint256 _amountB)
        public
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // Transfer tokens from user
        TransferHelper.safeTransferFrom(_tokenA, msg.sender, address(this), _amountA);
        TransferHelper.safeTransferFrom(_tokenB, msg.sender, address(this), _amountB);

        // Approve tokens
        TransferHelper.safeApprove(_tokenA, address(nonfungiblePositionManager), _amountA);
        TransferHelper.safeApprove(_tokenB, address(nonfungiblePositionManager), _amountB);

        // Get mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            fee: poolFee,
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            amount0Desired: _amountA,
            amount1Desired: _amountB,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Note that the pool defined by DAI/USDC and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create deposit record
        _createDeposit(msg.sender, tokenId);

        // Handle refunds
        _handleRefunds(_tokenA, _tokenB, _amountA, _amountB, amount0, amount1);

        return (tokenId, liquidity, amount0, amount1);
    }

    // collect the fee from the Uniswap V3 pool
    function collectAllFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // Transfer NFT to this contract
        nonfungiblePositionManager.safeTransferFrom(msg.sender, address(this), tokenId);

        // Create collect parameters
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        // Send collected fees back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice Transfers funds to owner of NFT
    function _sendToOwner(uint256 tokenId, uint256 amount0, uint256 amount1) internal {
        Deposit memory deposit = deposits[tokenId];

        // Send collected fees to owner
        TransferHelper.safeTransfer(deposit.token0, deposit.owner, amount0);
        TransferHelper.safeTransfer(deposit.token1, deposit.owner, amount1);
    }

    /// @notice Increases liquidity in the current range
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

        return nonfungiblePositionManager.increaseLiquidity(params);
    }

    /// @notice Decreases liquidity by half
    function decreaseLiquidityInHalf(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == deposits[tokenId].owner, "Not the owner");

        uint128 liquidity = deposits[tokenId].liquidity;
        uint128 halfLiquidity = liquidity / 2;

        // Decrease liquidity parameters
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: halfLiquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        nonfungiblePositionManager.decreaseLiquidity(decreaseParams);

        // Collect parameters
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(collectParams);

        // Send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice Swaps exact input single
    function swapExactInputSingle(address _tokenA, address _tokenB, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        // Transfer tokens from sender
        TransferHelper.safeTransferFrom(_tokenA, msg.sender, address(this), amountIn);
        // Approve router
        TransferHelper.safeApprove(_tokenA, address(swapRouter), amountIn);

        // Create swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp + 2 minutes,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }

    /// @notice Swaps exact output single
    function swapExactOutputSingle(address _tokenA, address _tokenB, uint256 amountOut, uint256 amountInMaximum)
        external
        returns (uint256 amountIn)
    {
        // Transfer maximum amount from sender
        TransferHelper.safeTransferFrom(_tokenA, msg.sender, address(this), amountInMaximum);
        // Approve router
        TransferHelper.safeApprove(_tokenA, address(swapRouter), amountInMaximum);

        // Create swap parameters
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        amountIn = swapRouter.exactOutputSingle(params);

        // Refund excess tokens
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(_tokenA, address(swapRouter), 0);
            TransferHelper.safeTransfer(_tokenA, msg.sender, amountInMaximum - amountIn);
        }

        return amountIn;
    }

    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        // (,, address token0, address token1,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);
        (address token0, address token1, uint128 liquidity) = nonfungiblePositionManager.positions1(tokenId);
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    }
}
