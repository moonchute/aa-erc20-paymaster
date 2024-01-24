// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IPaymasterSwap {
  function enable(address) external;

  function disable() external;

  function swap(uint128) external returns (uint256);
}