// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;
pragma abicoder v2;

import "forge-std/Test.sol";
import {UniswapPaymasterOracle} from "src/oracle/UniswapPaymasterOracle.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "forge-std/console.sol";

contract UniswapPaymasterOracleTest is Test {
    UniswapPaymasterOracle public paymasterOracle;

    function setUp() public {
        string memory rpcId = vm.envString("POLYGON_RPC_URL");
        uint256 forkId = vm.createFork(rpcId);
        vm.selectFork(forkId);
        // Uniswap V3 Factory
        address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        // WMATIC
        address token0 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        // USDC
        address token1 = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

        uint24 fee = 100;
        paymasterOracle = new UniswapPaymasterOracle(factory, token0, fee);
        paymasterOracle.initialize(abi.encodePacked(token1));
    }

    function testCanGetPrice() public {
        // WMATIC/USDC 1% pool
        address pool = 0x0a6c4588b7D8Bd22cF120283B1FFf953420c45F3;

        uint128 amount = 1 ether;
        vm.expectCall(pool, abi.encodeWithSelector(bytes4(keccak256("slot0()"))));
        uint256 amountOut = paymasterOracle.getPrice(address(this), amount);
        assertNotEq(amountOut, 0);
    }
}
