// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {NSDToken} from "../src/NSDToken.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IOracle} from "../src/interface/IOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NSDTokenScript is Script {
    // function setUp() public {}

    function run() public {
        IEntryPoint ENTRY_POINT = IEntryPoint(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        IERC20Metadata USDC = IERC20Metadata(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        IOracle USDC_ORACLE = IOracle(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7);
        IOracle NATIVE_ORACLE = IOracle(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0);
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.envAddress("DEPLOYER_ADDRESS");
        vm.startBroadcast(key);

        NSDToken nsd = new NSDToken(
            ENTRY_POINT,
            USDC,
            USDC_ORACLE,
            NATIVE_ORACLE,
            owner
        );
        IERC20(address(USDC)).approve(address(nsd), 1e7);
        nsd.mint(owner, 1e7);
        nsd.updatePrice();
        ENTRY_POINT.depositTo{value: 1e18}(address(nsd));
        vm.stopBroadcast();
    }
}
