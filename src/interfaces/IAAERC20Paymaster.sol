// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {IPaymasterOracle} from "./IPaymasterOracle.sol";
import {IPaymasterSwap} from "./IPaymasterSwap.sol";

interface IAAERC20Paymaster is IAccount  {

    function oracle() external view returns (IPaymasterOracle);

    function swap() external view returns (IPaymasterSwap);

    function accumulatedFees(int24) external view returns (uint256);
    
    function transferWithFee(address, address, uint256) external returns (bool);
    
    function burnWithFee(address, address, uint256) external;

    function liquidate(int24) external payable;
}