// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import {ChainlinkPaymasterOracle} from "src/oracle/ChainlinkPaymasterOracle.sol";
import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract UniswapPaymasterOracleTest is Test {
    ChainlinkPaymasterOracle public paymasterOracle;
    address public maticOracle;
    address public usdcOracle;

    function setUp() public {
        string memory rpcId = vm.envString("POLYGON_RPC_URL");
        uint256 forkId = vm.createFork(rpcId);
        vm.selectFork(forkId);
        // Chainlink MATIC/USD
        maticOracle = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
        // Chainlink USDC/USD
        usdcOracle = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;

        paymasterOracle = new ChainlinkPaymasterOracle(maticOracle);
        paymasterOracle.initialize(abi.encodePacked(usdcOracle, uint8(6)));
    }

    function testCanGetPrice() public {        
        uint128 amount = 1 ether;
        vm.expectCall(maticOracle, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector));
        vm.expectCall(usdcOracle, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector));

        uint256 amountOut = paymasterOracle.getPrice(address(this), amount);
        console.log("amountOut", amountOut);
        assertNotEq(amountOut, 0);
    }
}
