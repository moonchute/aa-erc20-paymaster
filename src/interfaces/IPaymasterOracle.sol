// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IPaymasterOracle {

  function enable(bytes calldata data) external;

  function disable() external;

  function getTick(address from) external view returns (int24);

  function getPrice(address from, uint128 amount) external returns (uint256, int24);
}
