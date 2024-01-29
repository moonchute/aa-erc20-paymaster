// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import "account-abstraction/core/EntryPoint.sol";
import "account-abstraction/interfaces/IEntryPoint.sol";
import {SimpleAccount} from "account-abstraction/samples/SimpleAccount.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

import {AAERC20Paymaster} from "../src/AAERC20Paymaster.sol";
import {IPaymasterOracle} from "../src/interfaces/IPaymasterOracle.sol";
import {IPaymasterSwap} from "../src/interfaces/IPaymasterSwap.sol";
import {UniswapPaymasterSwap} from "../src/swap/UniswapPaymasterSwap.sol";

contract AAERC20PaymasterTest is Test {
    AAERC20Paymaster public aaERC20Paymaster;
    EntryPoint public entryPoint;
    IERC20 public erc20;
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

        // mock oracle and swap
        oracle = IPaymasterOracle(address(bytes20(keccak256("paymasterOracle"))));
        vm.mockCall(
            address(oracle), abi.encodeWithSelector(IPaymasterOracle.initialize.selector), abi.encode(address(0))
        );
        vm.mockCall(
            address(oracle), abi.encodeWithSelector(IPaymasterOracle.getPrice.selector), abi.encode(uint256(100_000))
        );

        // Uniswap SwapRouter
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

        // WMATIC
        address token0 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        // USDC
        erc20 = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        uint24 fee = 100;
        IPaymasterSwap swap = new UniswapPaymasterSwap(router, token0, fee);
        vm.stopPrank();

        vm.startPrank(owner);
        aaERC20Paymaster = new AAERC20Paymaster(entryPoint, token0, IERC20Metadata(address(erc20)), oracle, swap, owner);

        // deposit paymaster
        deal(owner, 100 ether);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();
        // // erc20 token
        vm.startPrank(alice);
        deal(address(erc20), alice, 1 ether);
        erc20.approve(address(aaERC20Paymaster), 0.1 ether);
        aaERC20Paymaster.mint(alice, 0.1 ether);
        vm.stopPrank();
    }

    function testBeforeMint() public {
        assertEq(erc20.balanceOf(alice), 0.9 ether);
        assertEq(erc20.balanceOf(address(aaERC20Paymaster)), 0.1 ether);
        assertEq(aaERC20Paymaster.balanceOf(alice), 0.1 ether);
    }

    function testTransferAAERC20() public {
        vm.prank(alice);
        aaERC20Paymaster.transfer(bob, 0.01 ether);
        assertEq(aaERC20Paymaster.balanceOf(alice), 0.09 ether);
        assertEq(aaERC20Paymaster.balanceOf(bob), 0.01 ether);
    }

    function testTransferAAERC20UserOp() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData =
            abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 0.01 ether);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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

        uint256 afterAliceBalance = aaERC20Paymaster.balanceOf(alice);
        uint256 afterPmBalance = aaERC20Paymaster.balanceOf(address(aaERC20Paymaster));
        assertEq(aaERC20Paymaster.balanceOf(bob), 0.01 ether);
        assertEq(afterAliceBalance + afterPmBalance, 0.09 ether);
        // _postOp refund
        assertTrue(afterAliceBalance > 0.089 ether);
        assertTrue(afterPmBalance < 0.001 ether);
    }

    function testTransferAAERC20UserOpFromSmartAccount() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new SimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 0.05 ether);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(aaERC20Paymaster),
            0,
            abi.encodeWithSelector(aaERC20Paymaster.transfer.selector, bob, 0.01 ether)
        );

        userOps[0] = UserOperation({
            sender: account,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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

        uint256 afterAccountBalance = aaERC20Paymaster.balanceOf(account);
        uint256 afterPmBalance = aaERC20Paymaster.balanceOf(address(aaERC20Paymaster));
        assertEq(aaERC20Paymaster.balanceOf(bob), 0.01 ether);
        assertEq(afterAccountBalance + afterPmBalance, 0.04 ether);
        // _postOp refund
        assertTrue(afterAccountBalance > 0.039 ether);
        assertTrue(afterPmBalance < 0.001 ether);
    }

    function testBurnAAERC20UserOp() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(AAERC20Paymaster.burnWithFee.selector, alice, bob, 0.01 ether);
        uint256 beforeErc20 = erc20.balanceOf(bob);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        uint256 afterAliceBalance = aaERC20Paymaster.balanceOf(alice);
        uint256 afterPmBalance = aaERC20Paymaster.balanceOf(address(aaERC20Paymaster));

        assertEq(afterErc20 - beforeErc20, 0.01 ether);
        assertEq(afterAliceBalance + afterPmBalance, 0.09 ether);
        // _postOp refund
        assertTrue(afterAliceBalance > 0.089 ether);
        assertTrue(afterPmBalance < 0.001 ether);
    }

    function testBurnAAERC20UserOpFromSmartAccount() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new SimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 0.05 ether);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(aaERC20Paymaster),
            0,
            abi.encodeWithSelector(aaERC20Paymaster.burn.selector, bob, 0.01 ether)
        );

        userOps[0] = UserOperation({
            sender: account,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        uint256 afterAccountBalance = aaERC20Paymaster.balanceOf(account);
        uint256 afterPmBalance = aaERC20Paymaster.balanceOf(address(aaERC20Paymaster));

        assertEq(erc20.balanceOf(bob), 0.01 ether);
        assertEq(afterAccountBalance + afterPmBalance, 0.04 ether);
        // _postOp refund
        assertTrue(afterAccountBalance > 0.039 ether);
        assertTrue(afterPmBalance < 0.001 ether);
    }

    function testInvalidSignature() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData =
            abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 0.01 ether);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        bytes memory callData =
            abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 0.01 ether);

        userOps[0] = UserOperation({
            sender: simpleAccount,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        bytes memory callData = abi.encodeWithSelector(aaERC20Paymaster.transferFrom.selector, alice, bob, 0.01 ether);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        bytes memory callData =
            abi.encodeWithSelector(aaERC20Paymaster.transferWithFee.selector, bob, alice, 0.01 ether);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        bytes memory callData =
            abi.encodeWithSelector(AAERC20Paymaster.transferWithFee.selector, alice, bob, 0.01 ether);

        uint256 beforeBalanceAlice = erc20.balanceOf(alice);
        uint256 beforeBalanceBob = erc20.balanceOf(bob);

        userOps[0] = UserOperation({
            sender: address(aaERC20Paymaster),
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        address simpleAccountImpl = address(new SimpleAccount(entryPoint));

        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 0.05 ether);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(aaERC20Paymaster.transfer.selector, account, bob, 0.01 ether);

        userOps[0] = UserOperation({
            sender: account,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        address simpleAccountImpl = address(new SimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        erc20.transfer(account, 0.05 ether);
        aaERC20Paymaster.transfer(account, 0.05 ether);

        vm.stopPrank();
        uint256 beforeBalanceAccount = erc20.balanceOf(account);
        uint256 beforeBalanceBob = erc20.balanceOf(bob);

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory transferCallData = abi.encodeWithSelector(IERC20.transfer.selector, bob, 0.01 ether);
        bytes memory callData =
            abi.encodeWithSelector(SimpleAccount.execute.selector, address(erc20), 0, transferCallData);

        userOps[0] = UserOperation({
            sender: account,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
        
        assertEq(beforeBalanceAccount - afterBalanceAccount, 0.01 ether);
        assertEq(afterBalanceBob - beforeBalanceBob, 0.01 ether);
    }

    function testLiquidateAddDeposit() external {
        aaERC20Utils();
        address protocolReceiver = aaERC20Paymaster.owner();
        uint256 beforeAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 beforeProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 beforeLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);

        uint256 beforeAccAmount = aaERC20Paymaster.accumulatedFee(625850);
        uint256 beforeDeposit = aaERC20Paymaster.getDeposit();

        vm.startPrank(liquidator);
        aaERC20Paymaster.liquidate(625850);
        vm.stopPrank();

        uint256 afterAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 afterProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 afterLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);
        uint256 afterAccAmount = aaERC20Paymaster.accumulatedFee(625850);
        uint256 afterDeposit = aaERC20Paymaster.getDeposit();

        uint256 diffPm = beforeAmount - afterAmount;
        uint256 diffProtocol = afterProtocolAmount - beforeProtocolAmount;
        uint256 diffLiquidator = afterLiquidatorAmount - beforeLiquidatorAmount;
        uint256 diffAcc = beforeAccAmount - afterAccAmount;
        assertEq(diffAcc, diffPm + diffProtocol + diffLiquidator);
        assertEq(diffProtocol / 2, diffLiquidator);
        assertTrue(afterDeposit > beforeDeposit);
    }

    function testLiquidateSwapTick() external {
        aaERC20Utils();
        vm.startPrank(owner);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();
        vm.mockCall(
            address(oracle), abi.encodeWithSelector(IPaymasterOracle.getPrice.selector), abi.encode(uint256(800_000))
        );

        address protocolReceiver = aaERC20Paymaster.owner();
        uint256 beforeAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 beforeProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 beforeLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);
        uint256 beforeAccAmount = aaERC20Paymaster.accumulatedFee(625850);
        uint256 beforeDeposit = aaERC20Paymaster.getDeposit();

        vm.startPrank(liquidator);
        aaERC20Paymaster.liquidate(625850);
        vm.stopPrank();

        uint256 afterAmount = erc20.balanceOf(address(aaERC20Paymaster));
        uint256 afterProtocolAmount = aaERC20Paymaster.accumulatedLiquidateFee(protocolReceiver);
        uint256 afterLiquidatorAmount = aaERC20Paymaster.accumulatedLiquidateFee(liquidator);
        uint256 afterAccAmount = aaERC20Paymaster.accumulatedFee(625850);
        uint256 afterDeposit = aaERC20Paymaster.getDeposit();

        uint256 diffPm = beforeAmount - afterAmount;
        uint256 diffProtocol = afterProtocolAmount - beforeProtocolAmount;
        uint256 diffLiquidator = afterLiquidatorAmount - beforeLiquidatorAmount;
        uint256 diffAcc = beforeAccAmount - afterAccAmount;
        assertEq(diffAcc, diffPm + diffProtocol + diffLiquidator);
        assertEq(diffProtocol / 2, diffLiquidator);
        assertTrue(afterDeposit > beforeDeposit);
    }

    function testLiquidateNotAllowed() external {
        aaERC20Utils();
        vm.startPrank(owner);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.expectRevert("AA-ERC20 : not liquidatable");
        aaERC20Paymaster.liquidate(625850);
    }

    function testLiquidateInsufficientAmount() external {
        aaERC20Utils();
        vm.startPrank(owner);
        aaERC20Paymaster.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.expectRevert("AA-ERC20 : insufficient liquidate amount");
        aaERC20Paymaster.liquidate(28);
    }

    function aaERC20Utils() public {
        vm.startPrank(alice);
        address simpleAccountImpl = address(new SimpleAccount(entryPoint));
        address account = address(
            new ERC1967Proxy(simpleAccountImpl, abi.encodeWithSelector(SimpleAccount.initialize.selector, alice))
        );
        aaERC20Paymaster.transfer(account, 0.05 ether);
        vm.stopPrank();

        UserOperation[] memory userOps = new UserOperation[](1);
        bytes memory paymasterAndData = abi.encodePacked(address(aaERC20Paymaster));
        bytes memory callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(aaERC20Paymaster),
            0,
            abi.encodeWithSelector(aaERC20Paymaster.transfer.selector, bob, 0.01 ether)
        );

        userOps[0] = UserOperation({
            sender: account,
            nonce: uint256(0),
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 200000,
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
