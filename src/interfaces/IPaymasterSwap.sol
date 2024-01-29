// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title The interface for the AAERC20 Paymaster Swap.
 */
interface IPaymasterSwap {
    /**
     * @dev Initialize the swap
     * @param token The address of token to swap
     */
    function initialize(address token) external;

    /**
     * @dev Swap the token
     * @param amount The amount of token to swap
     * @return amountOut The amount of token swapped
     */
    function swap(uint128 amount) external returns (uint256 amountOut);
}
