// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IPaymasterOracle {

  function enable(address) external;

  function disable() external;

  function getTick(address) external view returns (int24);

  function getPrice(address, uint128) external returns (uint256, int24);
}
