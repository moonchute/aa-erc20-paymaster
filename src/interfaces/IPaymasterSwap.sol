// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title The interface for the AAERC20 Paymaster Swap.
 */
interface IPaymasterSwap {
    /**
     * @dev Initialize the swap
     * @param data The data of initialization
     */
    function initialize(bytes calldata data) external;

    /**
     * @dev Swap the token
     * @param amount The amount of token to swap
     * @return amountOut The amount of token swapped
     */
    function swap(uint128 amount) external returns (uint256 amountOut);
}
