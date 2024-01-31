// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {IPaymasterOracle} from "./IPaymasterOracle.sol";
import {IPaymasterSwap} from "./IPaymasterSwap.sol";
import {IWETH} from "./IWETH.sol";

/**
 * @title The interface for the AAERC20 Paymaster.
 */
interface IAAERC20Paymaster is IAccount {

    /**
     * @dev Get the factory address
     * @return factory The address of the factory
     */
    function factory() external view returns (address);

    /**
     * @dev Get the current price
     * @return price The current price
     */
    function currentPrice() external view returns (uint256 price);
    /**
     * @dev Get the address of native token
     * @return nativeToken The address of native token
     */
    function nativeToken() external view returns (IWETH nativeToken);

    /**
     * @dev Get the address of oracle
     * @return oracle The address of oracle
     */
    function oracle() external view returns (IPaymasterOracle oracle);

    /**
     * @dev Get the address of swap
     * @return swap The address of swap
     */
    function swap() external view returns (IPaymasterSwap swap);

    /**
     * @dev Get the accumulated amount sponsored at the fee price
     * @param feePrice The fee price
     * @return fee The accumulated amount
     */
    function accumulatedFee(uint256 feePrice) external view returns (uint256 fee);

    /**
     * @dev Get the accumulated fee owned by liquidator
     * @param liquidator The address of liquidator
     * @return fee The accumulated fee owned by liquidator
     */
    function accumulatedLiquidateFee(address liquidator) external view returns (uint256 fee);

    /**
     * @dev Transfer with fee paid with token
     * @param from The address of the sender
     * @param to The address of the recipient
     * @param amount The amount to transfer
     * @return isSuccessful True if successful
     */
    function transferWithFee(address from, address to, uint256 amount) external returns (bool isSuccessful);

    /**
     * @dev Burn with fee paid with token
     * @param from The address of the sender
     * @param to The address of the recipient
     * @param amount The amount to transfer
     */
    function burnWithFee(address from, address to, uint256 amount) external;

    /**
     * @dev Liquidate if the acculuated fee is insolvent or the deposit amount in entrypoint is insufficient
     * @param feePrice The fee price to liquidate
     */
    function liquidate(uint256 feePrice) external payable;

    /**
     * @dev Withdraw the liquidator fee
     * @param to The address of the recipient
     */
    function withdrawLiquidatorFee(address to) external;

    /**
     * @dev Check if the liquidate is allowed
     * @param feePrice The fee price to liquidate
     * @return isAllowed True if allowed
     */
    function isLiquidateAllowed(uint256 feePrice) external returns (bool isAllowed);
}
