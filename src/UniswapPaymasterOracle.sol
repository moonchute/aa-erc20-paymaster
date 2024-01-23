// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";
import {IPaymasterOracle} from "src/interfaces/IPaymasterOracle.sol";
import "forge-std/console.sol";

contract UniswapPaymasterOracle is IPaymasterOracle { 
  address immutable public factory;
  address immutable public nativeToken;
  uint24 immutable public fee;
  mapping(address => address) public pools;
  
  constructor (address _factory, address _nativeToken, uint24 _fee) {
    factory = _factory;
    nativeToken = _nativeToken;
    fee = _fee;
  }

  event EnableOracle(address indexed sender, address indexed pool);
  event DisableOracle(address indexed sender);

  function enable(bytes calldata data) public override {
    (address token0) = abi.decode(data, (address));
    address pool = IUniswapV3Factory(factory).getPool(token0, nativeToken, fee);
    console.log("pool:", pool);
    pools[msg.sender] = pool;
    emit EnableOracle(msg.sender, pool);
  }

  function disable() public override {
    delete pools[msg.sender];
    emit DisableOracle(msg.sender);
  }

  function getTick(address from) public override view returns (int24) {
    address pool = pools[from];
    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = 0;
    secondsAgos[1] = 108;
    (,int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();  

    return tick;
  }

  function getPrice(address from, uint128 amount) public override view returns (uint256, int24) {
    address pool = pools[from];
    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = 0;
    secondsAgos[1] = 108;
    (,int24 tick,,,,,) = IUniswapV3Pool(pool).slot0(); 

    uint256 feeAmount = OracleLibrary.getQuoteAtTick(
      tick, 
      amount, 
      IUniswapV3Pool(pool).token0(), 
      IUniswapV3Pool(pool).token1()
    );
    console.log("feeAmount:", feeAmount);

    return (
      feeAmount,
      tick
    );
  }  
}
