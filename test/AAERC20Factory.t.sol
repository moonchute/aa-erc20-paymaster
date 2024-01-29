// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AAERC20Factory} from "../src/AAERC20Factory.sol";
import {IPaymasterOracle} from "../src/interfaces/IPaymasterOracle.sol";
import {IPaymasterSwap} from "../src/interfaces/IPaymasterSwap.sol";
import {IAAERC20Paymaster} from "../src/interfaces/IAAERC20Paymaster.sol";

contract AAERC20FactoryTest is Test {
    AAERC20Factory public factory;
    address public owner;
    address public nativeToken;
    address public token;
    address public oracle;
    address public swap;
    address public entryPoint;

    function setUp() public {
        owner = makeAddr("owner");
        oracle = makeAddr("oracle");
        swap = makeAddr("swap");
        entryPoint = makeAddr("entryPoint");
        nativeToken = address(new ERC20("native", "NT"));
        token = address(new ERC20("test", "TEST"));

        vm.mockCall(
            address(oracle), abi.encodeWithSelector(IPaymasterOracle.initialize.selector), abi.encode(address(0))
        );
        vm.mockCall(address(swap), abi.encodeWithSelector(IPaymasterSwap.initialize.selector), abi.encode(address(0)));

        vm.startPrank(owner);
        factory = new AAERC20Factory(nativeToken);
        vm.stopPrank();
    }

    function testCreatePaymaster() public {
        factory.createAAERC20(entryPoint, token, oracle, swap, owner);
        IAAERC20Paymaster paymaster = IAAERC20Paymaster(factory.getAAErc20(token, oracle, swap, entryPoint));
        assertNotEq(address(paymaster), address(0));
        assertEq(address(paymaster.nativeToken()), nativeToken);
        assertEq(address(paymaster.oracle()), oracle);
        assertEq(address(paymaster.swap()), swap);
    }

    function testCreateDuplicatePaymaster() public {
        factory.createAAERC20(entryPoint, token, oracle, swap, owner);

        vm.expectRevert("AAERC20Factory: already created");
        factory.createAAERC20(entryPoint, token, oracle, swap, owner);
    }

    function testSetOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        factory.setOwner(newOwner);
        assertEq(factory.owner(), newOwner);
    }

    function testSetOwnerNotOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.expectRevert("AAERC20Factory: not owner");
        factory.setOwner(newOwner);
    }
}
