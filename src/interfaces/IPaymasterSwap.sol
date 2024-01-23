// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IPaymasterSwap {
  function enable(bytes calldata data) external;

  function disable() external;

  function swap(uint128 amount) external returns (uint256);
}