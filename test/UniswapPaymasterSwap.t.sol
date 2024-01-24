// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {UniswapPaymasterSwap} from "src/UniswapPaymasterSwap.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Minimal} from "v3-core/contracts/interfaces/IERC20Minimal.sol";

contract UniswapPaymasterSwapTest is Test {
  UniswapPaymasterSwap paymasterSwap;
  address owner;
  
  function setUp() public {
    string memory rpcId = vm.envString("POLYGON_RPC_URL");
    uint256 forkId = vm.createFork(rpcId);
    vm.selectFork(forkId);
    owner = makeAddr("owner");
    // Uniswap V3 Factory
    address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    // Uniswap SwapRouter
    address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // WMATIC
    address token0 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    // USDC
    address token1 = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    uint24 fee = 100;

    paymasterSwap = new UniswapPaymasterSwap(
      router, 
      factory,
      token0,
      fee
    );
    paymasterSwap.enable(token1);

    deal(token1, owner, 1 ether);
    deal(token1, address(paymasterSwap), 1 ether);
    console.log("balance:", IERC20Minimal(token1).balanceOf(owner));
  }

  function testCanSwap() public {
    uint128 amount = 10;
    console.log("paymasterSwap:", address(paymasterSwap));
    paymasterSwap.swap(amount);
    console.log("balance after swap:", IERC20Minimal(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270).balanceOf(address(this)));
  }
}