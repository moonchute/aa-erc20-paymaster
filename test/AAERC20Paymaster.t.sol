// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import "account-abstraction/core/EntryPoint.sol";
import "account-abstraction/interfaces/IEntryPoint.sol";

import {SimpleAccount} from "account-abstraction/samples/SimpleAccount.sol";
import {SimpleAccountFactory} from "account-abstraction/samples/SimpleAccountFactory.sol";

import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ECDSA} from "solady/utils/ECDSA.sol";

import {AAERC20Paymaster} from "../src/AAERC20Paymaster.sol";
import {IPaymasterOracle} from "../src/interfaces/IPaymasterOracle.sol";
import {IPaymasterSwap} from "../src/interfaces/IPaymasterSwap.sol";
import {TestERC20} from "../src/test/TestERC20.sol";
import {TestSimpleAccount} from "../src/test/TestSimpleAccount.sol";
import {UniswapPaymasterSwap} from "../src/swap/UniswapPaymasterSwap.sol";
import "forge-std/console2.sol";

contract AAERC20PaymasterTest is Test {
    AAERC20Paymaster public aaERC20Paymaster;
    EntryPoint public entryPoint;
    TestERC20 public erc20;
    address owner;
    address alice;
    address bob;
    uint256 aliceKey;
    uint256 bobKey;
    address liquidator;
    IPaymasterOracle oracle;

    error FailedOp(uint256 opIndex, string reason);

    function setUp() public {
        string memory rpcId = vm.envString("POLYGON_RPC_URL");
        uint256 forkId = vm.createFork(rpcId);
        vm.selectFork(forkId);

        owner = makeAddr("owner");
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        liquidator = makeAddr("liquidator");
        entryPoint = new EntryPoint();
        erc20 = new TestERC20();

        // mock oracle and swap
        oracle = IPaymasterOracle(address(bytes20(keccak256("paymasterOracle"))));
        vm.mockCall(
            address(oracle), 
            abi.encodeWithSelector(IPaymasterOracle.enable.selector),
            abi.encode(address(0))
        );
        vm.mockCall(
            address(oracle), 
            abi.encodeWithSelector(IPaymasterOracle.getPrice.selector),
            abi.encode(uint256(1_000), int24(100))
        );
        vm.mockCall(
            address(oracle), 
            abi.encodeWithSelector(IPaymasterOracle.getTick.selector),
            abi.encode(int24(100))
        );

        // Uniswap V3 Factory
        address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        // Uniswap SwapRouter
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

        // WMATIC
        address token0 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        // USDC
        erc20 = TestERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        uint24 fee = 100;
        IPaymasterSwap swap = new UniswapPaymasterSwap(
            router, 
            factory,
            token0,
            fee
        );
        vm.stopPrank();
        
        vm.startPrank(owner);
        aaERC20Paymaster =
            new AAERC20Paymaster(
                entryPoint, 
                token0, 
                IERC20Metadata(address(erc20)), 
                oracle, 
                swap, 
                owner
            );

        // deposit paymaster
        deal(owner, 100 ether);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();
        // // erc20 token
        vm.startPrank(alice);
        deal(address(erc20), alice, 100_000);
        // erc20.mint(alice, 1000);
        erc20.approve(address(aaERC20Paymaster), 10_000);
        aaERC20Paymaster.mint(alice, 10_000);
        vm.stopPrank();
    }

    function testBeforeMint() public {
        assertEq(erc20.balanceOf(alice), 90_000);
        assertEq(erc20.balanceOf(address(aaERC20Paymaster)), 10_000);
        assertEq(aaERC20Paymaster.balanceOf(alice), 10_000);
    }

    function testTransferAAERC20() public {
        vm.prank(alice);
        aaERC20Paymaster.transfer(bob, 1_000);
        assertEq(aaERC20Paymaster.balanceOf(alice), 9_000 );
        assertEq(aaERC20Paymaster.balanceOf(bob), 1_000);
    }

    function testTransferAAERC20UserOp() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        assertEq(aaERC20Paymaster.balanceOf(bob), 10);
        assertEq(aaERC20Paymaster.balanceOf(alice), 8990);
        assertEq(aaERC20Paymaster.balanceOf(address(aaERC20Paymaster)), 1000);
    }

    function testTransferAAERC20UserOpFromSmartAccount() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 5_000);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, account, bob, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        assertEq(aaERC20Paymaster.balanceOf(bob), 10);
        assertEq(aaERC20Paymaster.balanceOf(account), 3990);
        assertEq(aaERC20Paymaster.balanceOf(address(aaERC20Paymaster)), 1000);
    }

    function testBurnAAERC20UserOp() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.burnWithFee.selector, alice, bob, 10);
        uint256 beforeErc20 = erc20.balanceOf(bob);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        assertEq(afterErc20 - beforeErc20, 10);
        assertEq(aaERC20Paymaster.balanceOf(alice), 8990);
        assertEq(aaERC20Paymaster.balanceOf(address(aaERC20Paymaster)), 1000);
    }

    function testBurnAAERC20UserOpFromSmartAccount() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 5_000);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.burnWithFee.selector, account, bob, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        assertEq(erc20.balanceOf(bob), 10);
        assertEq(aaERC20Paymaster.balanceOf(account), 3990);
        assertEq(aaERC20Paymaster.balanceOf(address(aaERC20Paymaster)), 1000);
    }

    function testInvalidSignature() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        vm.expectRevert(abi.encodeWithSelector(FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testWrongSender() public {
        address simpleAccount = address(new SimpleAccount(entryPoint));
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 10);

        userOps[0] = UserOperation({
            sender: simpleAccount,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        vm.expectRevert(abi.encodeWithSelector(FailedOp.selector, 0, "AA33 reverted: AA-ERC20 : insufficient balance"));
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testWrongCalldataSelector() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(aaERC20Paymaster.transferFrom.selector, alice, bob, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        vm.expectRevert(abi.encodeWithSelector(FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testInsufficientAAERC20() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(aaERC20Paymaster.transferWithFee.selector, bob, alice, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        vm.expectRevert(abi.encodeWithSelector(FailedOp.selector, 0, "AA33 reverted: AA-ERC20 : insufficient balance"));
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testInsufficientFee() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 100);

        uint256 beforeBalanceAlice = erc20.balanceOf(alice);
        uint256 beforeBalanceBob = erc20.balanceOf(bob);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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
        uint256 afterBalanceAlice = erc20.balanceOf(alice);
        uint256 afterBalanceBob = erc20.balanceOf(bob);
        assertEq(beforeBalanceAlice - afterBalanceAlice, 0);
        assertEq(afterBalanceBob - beforeBalanceBob, 0);
    }

    function testSmartAccountInvalidSignature() public {
        vm.startPrank(alice);
        // SimpleAccountFactory factory = new SimpleAccountFactory(entryPoint);
        // address account = address(factory.createAccount(owner, 0));
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));

        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 5000);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, account, bob, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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

        vm.expectRevert(abi.encodeWithSelector(FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(userOps, payable(owner));
    }

    function testERC20Paymaster() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        erc20.transfer(account, 5_000);
        aaERC20Paymaster.transfer(account, 5_000);
        
        vm.stopPrank();
        uint256 beforeBalanceAccount = erc20.balanceOf(account);
        uint256 beforeBalanceBob = erc20.balanceOf(bob);

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory transferCallData = abi.encodeWithSelector(IERC20.transfer.selector, bob, 10);
        bytes memory callData = abi.encodeWithSelector(SimpleAccount.execute.selector, address(erc20), 0, transferCallData);

        userOps[0] = UserOperation({
            sender: account,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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
        uint256 afterBalanceAccount = erc20.balanceOf(account);
        uint256 afterBalanceBob = erc20.balanceOf(bob);

        assertEq(beforeBalanceAccount - afterBalanceAccount, 10);
        assertEq(afterBalanceBob - beforeBalanceBob, 10);
    }

    function testLiquidateAddDeposit() external {
        aaERC20Utils();
        address protocolReceiver = aaERC20Paymaster.owner();
        uint256 beforeAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 beforeProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 beforeLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);

        uint256 beforeTickAmount = aaERC20Paymaster.accumulatedFee(3020);
        
        vm.startPrank(liquidator);
        aaERC20Paymaster.liquidate(3020);
        vm.stopPrank();

        uint256 afterAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 afterProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 afterLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);
        uint256 afterTickAmount = aaERC20Paymaster.accumulatedFee(3020);
        
        assertEq(beforeAmount - afterAmount, 985);
        assertEq(afterProtocolAmount - beforeProtocolAmount, 10);
        assertEq(afterLiquidatorAmount - beforeLiquidatorAmount, 5);
        assertEq(beforeTickAmount - afterTickAmount, 1000);
    }

    function testLiquidateSwapTick() external {
        aaERC20Utils();
        vm.startPrank(owner);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();
        vm.mockCall(
            address(oracle), 
            abi.encodeWithSelector(IPaymasterOracle.getPrice.selector),
            abi.encode(uint256(4000), int24(150))
        );

        address protocolReceiver = aaERC20Paymaster.owner();
        uint256 beforeAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 beforeProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 beforeLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);
        uint256 beforeTickAmount = aaERC20Paymaster.accumulatedFee(3020);
        
        vm.startPrank(liquidator);
        aaERC20Paymaster.liquidate(3020);
        vm.stopPrank();

        uint256 afterAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 afterProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 afterLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);
        uint256 afterTickAmount = aaERC20Paymaster.accumulatedFee(3020);
        
        assertEq(beforeAmount - afterAmount, 985);
        assertEq(afterProtocolAmount - beforeProtocolAmount, 10);
        assertEq(afterLiquidatorAmount - beforeLiquidatorAmount, 5);
        assertEq(beforeTickAmount - afterTickAmount, 1000);
    }

    function testLiquidateNotAllowed() external {
        aaERC20Utils();
        vm.startPrank(owner);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();
        
        vm.expectRevert("AA-ERC20 : not liquidatable");
        aaERC20Paymaster.liquidate(3020);
    }

    function testLiquidateInsufficientAmount() external {
        aaERC20Utils();
        vm.startPrank(owner);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();
        
        vm.expectRevert("AA-ERC20 : insufficient liquidate amount");
        aaERC20Paymaster.liquidate(3001);
    }
    
    function aaERC20Utils() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new TestSimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 5000);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, account, bob, 10);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 500000,
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
    }
}
