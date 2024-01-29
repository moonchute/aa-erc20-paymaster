// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPaymasterSwap} from "src/interfaces/IPaymasterSwap.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IERC20Minimal} from "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "forge-std/console.sol";

contract UniswapPaymasterSwap is IPaymasterSwap {

  struct Pool {
    address token0;
    address token1;
    uint24 fee;
  }

  address public immutable uniswapFactory;
  address public swapRouter;
  address immutable public nativeToken;
  uint24 immutable public fee;
  mapping (address => Pool) public pools;

  event EnableSwap(address indexed sender, address indexed token0, address indexed token1, uint24 fee);
  event DisableSwap(address indexed sender);  

  constructor(address _router, address _factory, address _nativeToken, uint24 _fee) {
    swapRouter = _router;
    uniswapFactory = _factory;
    nativeToken = _nativeToken;
    fee = _fee;
  }

  function enable(address token0) public override {
    if (IERC20Minimal(token0).allowance(address(this), swapRouter) == 0) {
      IERC20Minimal(token0).approve(swapRouter, type(uint256).max);
    }
    if (IERC20Minimal(nativeToken).allowance(address(this), swapRouter) == 0) {
      IERC20Minimal(nativeToken).approve(swapRouter, type(uint256).max);
    }

    pools[msg.sender] = Pool(token0, nativeToken, fee);
    emit EnableSwap(msg.sender, token0, nativeToken, fee);
  }

  function disable() public override {
    delete pools[msg.sender];
    emit DisableSwap(msg.sender);
  }

  function swap(uint128 amount) public override returns (uint256) {
    Pool memory pool = pools[msg.sender];
    uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(
      ISwapRouter.ExactInputSingleParams({
        tokenIn: pool.token0,
        tokenOut: pool.token1,
        fee: pool.fee,
        recipient: msg.sender,
        deadline: block.timestamp + 10000,
        amountIn: amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );
    return amountOut;
  }
}
