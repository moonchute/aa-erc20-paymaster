// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPaymasterSwap} from "src/interfaces/IPaymasterSwap.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IERC20Minimal} from "v3-core/contracts/interfaces/IERC20Minimal.sol";

contract UniswapPaymasterSwap is IPaymasterSwap {
    struct Pool {
        address token0;
        address token1;
        uint24 fee;
    }

    address public swapRouter;
    address public immutable nativeToken;
    uint24 public immutable fee;
    mapping(address => Pool) public pools;

    constructor(address _router, address _nativeToken, uint24 _fee) {
        swapRouter = _router;
        nativeToken = _nativeToken;
        fee = _fee;
    }

    /// @inheritdoc IPaymasterSwap
    function initialize(bytes calldata data) public override {
        address token0 = address(bytes20(data[0:20]));
        if (IERC20Minimal(token0).allowance(address(this), swapRouter) == 0) {
            IERC20Minimal(token0).approve(swapRouter, type(uint256).max);
        }
        if (IERC20Minimal(nativeToken).allowance(address(this), swapRouter) == 0) {
            IERC20Minimal(nativeToken).approve(swapRouter, type(uint256).max);
        }
        pools[msg.sender] = Pool(token0, nativeToken, fee);
    }

    /// @inheritdoc IPaymasterSwap
    function swap(uint128 amount) public override returns (uint256 amountOut) {
        Pool memory pool = pools[msg.sender];

        amountOut = ISwapRouter(swapRouter).exactInputSingle(
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
    }
}
