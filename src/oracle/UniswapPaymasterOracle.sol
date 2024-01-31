// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";
import {IPaymasterOracle} from "src/interfaces/IPaymasterOracle.sol";

contract UniswapPaymasterOracle is IPaymasterOracle {
    address public immutable factory;
    address public immutable nativeToken;
    uint24 public immutable fee;
    mapping(address => address) public pools;

    constructor(address _factory, address _nativeToken, uint24 _fee) {
        factory = _factory;
        nativeToken = _nativeToken;
        fee = _fee;
    }

    /// @inheritdoc IPaymasterOracle
    function initialize(address token0) public override {
        address pool = IUniswapV3Factory(factory).getPool(token0, nativeToken, fee);
        pools[msg.sender] = pool;
    }

    /// @inheritdoc IPaymasterOracle
    function getPrice(address from, uint128 amount) public view override returns (uint256) {
        address pool = pools[from];
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        address erc20Token = nativeToken == token0 ? token1 : token0;

        (, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();

        uint256 feeAmount =
            OracleLibrary.getQuoteAtTick(tick, amount, nativeToken, erc20Token);

        return feeAmount;
    }
}
