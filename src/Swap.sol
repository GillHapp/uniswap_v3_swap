// SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract SimpleSwap is IERC721Receiver {
    event PoolCreated(address indexed tokenA, address indexed tokenB, uint24 indexed fee, address pool);

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

    // create pool if it does not exist
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

    
}
