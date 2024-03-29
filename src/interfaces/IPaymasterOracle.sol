// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

/**
 * @title The interface for the AAERC20 Paymaster Oracle.
 */
interface IPaymasterOracle {
    /**
     * @dev Initialize the oracle
     * @param data The data of initialization
     */
    function initialize(bytes calldata data) external;

    /**
     * @dev Get the price
     * @param from The address of the token0
     * @param amount The amount of native token
     * @return feeAmount The fee amount
     */
    function getPrice(address from, uint128 amount) external returns (uint256 feeAmount);
}
