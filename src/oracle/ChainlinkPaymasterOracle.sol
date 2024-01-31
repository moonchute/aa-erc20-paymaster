// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPaymasterOracle} from "src/interfaces/IPaymasterOracle.sol";
import {AggregatorV2V3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

contract ChainlinkPaymasterOracle is IPaymasterOracle {
  struct OracleData {
    address oracle;
    uint8 oracleDecimal;
    uint8 tokenDecimal;
  }
  
  address public immutable nativeOracle;
  uint8 public immutable nativeDecimal;
  mapping(address => OracleData) public oracles;

  constructor(address _nativeOracle) {
    uint8 decimal = AggregatorV2V3Interface(_nativeOracle).decimals();
    nativeOracle = _nativeOracle;
    nativeDecimal = decimal;
  }

  /// @inheritdoc IPaymasterOracle
  function initialize(bytes calldata data) public override {
    address tokenOracle = address(bytes20(data[0:20]));
    uint8 tokenDecimal = uint8(bytes1(data[20:21]));
    uint8 oracleDecimal = AggregatorV2V3Interface(tokenOracle).decimals();

    oracles[msg.sender] = OracleData ({
      oracle: tokenOracle,
      oracleDecimal: oracleDecimal,
      tokenDecimal: tokenDecimal
    });
  }

  /// @inheritdoc IPaymasterOracle
  function getPrice(address from, uint128 amount) public view override returns (uint256) {
    OracleData memory tokenOracle = oracles[from];

    (, int256 nativeAnswer,,,) = AggregatorV2V3Interface(nativeOracle).latestRoundData();
    (, int256 tokenAnswer,,,) = AggregatorV2V3Interface(tokenOracle.oracle).latestRoundData();
    
    uint256 amountOut = (uint256(amount) * uint256(nativeAnswer)) / uint256(tokenAnswer);
    int8 decimalDiff = int8(tokenOracle.oracleDecimal) - int8(nativeDecimal) - int8(18 - tokenOracle.tokenDecimal);
    if (decimalDiff > 0) {
      amountOut = amountOut * (10 ** uint8(decimalDiff));
    } else {
      amountOut = amountOut / (10 ** uint8(-decimalDiff));
    }

    return amountOut;
  }
}