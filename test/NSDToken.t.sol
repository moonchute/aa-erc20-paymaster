// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {NSDToken} from "../src/NSDToken.sol";

contract NSDTokenTest is Test {
    NSDToken public nsdToken;
    EntryPoint public entryPoint;
    ERC20 public erc20;

    function setUp() public {
        entryPoint = new EntryPoint();
        erc20 = new ERC20("ERC20", "erc20");
        // nsdToken = new NSDToken();
    }

    function test_name() public {
      
    }
}