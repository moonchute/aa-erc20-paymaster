// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import "account-abstraction/core/EntryPoint.sol";
import "account-abstraction/interfaces/IEntryPoint.sol";

import {SimpleAccount} from "account-abstraction/samples/SimpleAccount.sol";
import {SimpleAccountFactory} from "account-abstraction/samples/SimpleAccountFactory.sol";

import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ECDSA} from "solady/utils/ECDSA.sol";

import {NSDToken} from "../src/NSDToken.sol";
import {IOracle} from "../src/interface/IOracle.sol";
import {TestERC20} from "../src/test/TestERC20.sol";
import {TestSimpleAccount} from "../src/test/TestSimpleAccount.sol";
import "forge-std/console2.sol";

contract NSDTokenTest is Test {
    NSDToken public nsdToken;
    EntryPoint public entryPoint;
    TestERC20 public erc20;
    address owner;
    address alice;
    address bob;
    uint256 aliceKey;
    uint256 bobKey;

    error FailedOp(uint256 opIndex, string reason);

    function setUp() public {
        owner = makeAddr("owner");
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        entryPoint = new EntryPoint();
        erc20 = new TestERC20();
        IOracle tokenOracle = IOracle(address(bytes20(keccak256("tokenOracle"))));
        IOracle nativeOracle = IOracle(address(bytes20(keccak256("nativeOracle"))));
        vm.startPrank(owner);
        nsdToken = new NSDToken(entryPoint, IERC20Metadata(address(erc20)), tokenOracle, nativeOracle, owner);
        
        // update Oracle price 
        vm.store(address(nsdToken), bytes32(uint256(4)), bytes32(uint256(10)));

        // deposit paymaster
        deal(owner, 100 ether);
        nsdToken.deposit{value: 10 ether}();
        vm.stopPrank();
        // erc20 token
        vm.startPrank(alice);
        erc20.mint(alice, 1000);
        erc20.approve(address(nsdToken), 100);
        nsdToken.mint(alice, 100);
        vm.stopPrank();
    }

    function testBeforeMint() public {
        assertEq(erc20.balanceOf(alice), 900);
        assertEq(erc20.balanceOf(address(nsdToken)), 100);
        assertEq(nsdToken.balanceOf(alice), 100);
    }

    function testTransferNSD() public {
        vm.prank(alice);
        nsdToken.transfer(bob, 10);
        assertEq(nsdToken.balanceOf(alice), 90);
        assertEq(nsdToken.balanceOf(bob), 10);
    }

    function testTransferNSDUserOp() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.transferWithFee.selector,
            alice,
            bob,
            10
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        entryPoint.handleOps(userOps, payable(owner));

        assertEq(nsdToken.balanceOf(bob), 10);
        assertEq(nsdToken.balanceOf(alice), 89);
        assertEq(nsdToken.balanceOf(address(nsdToken)), 1);
    }

    function testTransferNSDUserOpFromSmartAccount() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));
        address account = address(new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice)));
        nsdToken.transfer(account, 20);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.transferWithFee.selector,
            account,
            bob,
            10
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        entryPoint.handleOps(userOps, payable(owner));

        assertEq(nsdToken.balanceOf(bob), 10);
        assertEq(nsdToken.balanceOf(account), 9);
        assertEq(nsdToken.balanceOf(address(nsdToken)), 1);
    }

    function testBurnNSDUserOp() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.burnWithFee.selector,
            alice,
            bob,
            10
        );
        uint256 beforeErc20 = erc20.balanceOf(bob);

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        entryPoint.handleOps(userOps, payable(owner));
        uint256 afterErc20 = erc20.balanceOf(bob);

        assertEq(nsdToken.balanceOf(alice), 89);
        assertEq(nsdToken.balanceOf(address(nsdToken)), 1);
        assertEq(afterErc20 - beforeErc20, 10);
    }

    function testBurnNSDUserOpFromSmartAccount() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));
        address account = address(new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice)));
        nsdToken.transfer(account, 20);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.burnWithFee.selector,
            account,
            bob,
            10
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        entryPoint.handleOps(userOps, payable(owner));

        assertEq(nsdToken.balanceOf(account), 9);
        assertEq(nsdToken.balanceOf(address(nsdToken)), 1);
        assertEq(erc20.balanceOf(bob), 10);
    }

    function testInvalidSignature() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.transferWithFee.selector,
            alice,
            bob,
            10
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        vm.expectRevert(
            abi.encodeWithSelector(
                FailedOp.selector, 
                0, 
                "AA24 signature error"
            )
        );
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testWrongSender() public {
        address simpleAccount = address(new SimpleAccount(entryPoint));
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.transferWithFee.selector,
            alice,
            bob,
            10
        );

        userOps[0] = UserOperation({
            sender: simpleAccount,
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        vm.expectRevert(
            abi.encodeWithSelector(
                FailedOp.selector, 
                0, 
                "AA33 reverted: NSDToken: only NSDToken can call paymaster"
            )
        );
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testWrongCalldataSelector() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            nsdToken.transferFrom.selector,
            alice,
            bob,
            10
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        vm.expectRevert(
            abi.encodeWithSelector(
                FailedOp.selector, 
                0, 
                "AA24 signature error"
            )
        );
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testInsufficientNSDToken() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            nsdToken.transferWithFee.selector,
            bob,
            alice,
            10
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        vm.expectRevert(
            abi.encodeWithSelector(
                FailedOp.selector, 
                0, 
                "AA33 reverted: NSDToken : insufficient balance"
            )
        );
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testInsufficientFee() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.transferWithFee.selector,
            alice,
            bob,
            100
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        vm.expectRevert(
            abi.encodeWithSelector(
                FailedOp.selector, 
                0, 
                "AA33 reverted: NSDToken : insufficient balance"
            )
        );
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testSmartAccountInvalidSignature() public {
        vm.startPrank(alice);
        // SimpleAccountFactory factory = new SimpleAccountFactory(entryPoint);
        // address account = address(factory.createAccount(owner, 0));
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));
        console2.log("simpleAccountImpl", simpleAccountImpl);

        address account = address(new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice)));
        nsdToken.transfer(account, 20);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(nsdToken));
        bytes memory callData = abi.encodeWithSelector(
            NSDToken.transferWithFee.selector,
            account,
            bob,
            10
        );

        userOps[0] = UserOperation({
            sender: address(nsdToken),
            nonce: uint256(0),
            initCode: '',
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 100000,
            maxFeePerGas: 172676895612,
            maxPriorityFeePerGas: 46047172163,
            paymasterAndData: paymasterAndData,
            signature: "0x"
        });
        // sign
        bytes32 userOpHash = entryPoint.getUserOpHash(userOps[0]);
        bytes32 signMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, signMessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOps[0].signature = signature;

        vm.expectRevert(
            abi.encodeWithSelector(
                FailedOp.selector, 
                0, 
                "AA24 signature error"
            )
        );
        entryPoint.handleOps(userOps, payable(owner));
    }
}