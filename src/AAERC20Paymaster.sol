// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {BasePaymaster} from "account-abstraction/core/BasePaymaster.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

import {IPaymasterOracle} from "./interfaces/IPaymasterOracle.sol";
import {IPaymasterSwap} from "./interfaces/IPaymasterSwap.sol";
import {IAAERC20Paymaster} from "./interfaces/IAAERC20Paymaster.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {AAERC20} from "./AAERC20.sol";
import "forge-std/console.sol";

contract AAERC20Paymaster is IAAERC20Paymaster, BasePaymaster, AAERC20 {
    uint256 public constant REFUND_POSTOP_COST = 40000;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;
    
    // protocol parameter in basis
    uint256 public constant priceMarkup = 1000;
    uint256 public constant protocolFee = 100;
    uint256 public constant liquidatorFee = 50;
    uint256 public constant liquidateThreshold = 700;

    uint256 public minDepositAmount = 1 ether;

    IWETH immutable public nativeToken; 
    IPaymasterOracle immutable public oracle;
    IPaymasterSwap immutable public swap;

    mapping (uint256 => uint256) public accumulatedFee;
    mapping (address => uint256) public accumulatedLiquidateFee;

    constructor(
        IEntryPoint _entryPoint,
        address _nativetoken, 
        IERC20Metadata _token,
        IPaymasterOracle _oracle,
        IPaymasterSwap _swap,
        address _owner
    ) AAERC20(_token) BasePaymaster(_entryPoint) {
        nativeToken = IWETH(_nativetoken);
        oracle = _oracle;
        swap = _swap;
        _oracle.enable(address(_token));
        _swap.enable(address(_token));
        _transferOwnership(_owner);
    }

    function withdrawAAERC20Token(address to) external {
        uint256 amount = accumulatedLiquidateFee[msg.sender];
        require(amount > 0, "AA-ERC20 : insufficient withdraw amount");

        accumulatedLiquidateFee[msg.sender] = 0;
        _transfer(address(this), to, amount);
    }

    function transferWithFee(address from, address to, uint256 amount) external returns (bool) {
        _requireFromEntryPoint();
        require(amount <= balanceOf[from], "AA-ERC20 : insufficient balance");
        _transfer(from, to, amount);
        return true;
    }

    function burnWithFee(address from, address to, uint256 amount) external {
        _requireFromEntryPoint();
        require(amount <= balanceOf[from], "AA-ERC20 : insufficient balance");
        _burn(from, amount);
        IERC20(token).transfer(to, amount);
    }

    function liquidate(uint256 price) external payable override {
        uint256 amount = accumulatedFee[price];
        require(amount > 0, "AA-ERC20 : insufficient liquidate amount");
        require(_isLidquidateAllowed(price), "AA-ERC20 : not liquidatable");

        accumulatedFee[price] = 0;
        uint256 protocolAmount = amount * protocolFee / 10000;
        uint256 liquidatorAmount = amount * liquidatorFee / 10000;
        uint256 remainAmount = amount - protocolAmount - liquidatorAmount;

        accumulatedLiquidateFee[msg.sender] += liquidatorAmount;
        accumulatedLiquidateFee[owner()] += protocolAmount;

        _burn(address(this), remainAmount);
        IERC20(token).transfer(address(swap), remainAmount); 
        swap.swap(uint128(remainAmount));

        uint256 balance = nativeToken.balanceOf(address(this));
        nativeToken.withdraw(balance);

        entryPoint.depositTo{value: balance}(address(this));
    }

    function isLiquidateAllowed(uint256 price) public returns (bool) {
       return _isLidquidateAllowed(price); 
    }

    /// inheritdoc IAccount
    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256)
        external
        virtual
        override
        returns (uint256 validationData)
    {
        _requireFromEntryPoint();
        bytes4 selector = bytes4(userOp.callData[0:4]);
        (address from,,) = abi.decode(userOp.callData[4:], (address, address, uint256));

        /// @dev 0xf3408110: transferWithFee(address,address,uint256)
        ///      0xea37cb54: burnWithFee(address from, address to, uint256 amount)
        if (selector != bytes4(0xf3408110) && selector != bytes4(0xea37cb54)) {
            return SIG_VALIDATION_FAILED;
        }

        if (from.code.length > 0) {
            bytes4 valid = IERC1271(from).isValidSignature(userOpHash, userOp.signature);
            return (valid == bytes4(0x1626ba7e)) ? 0 : SIG_VALIDATION_FAILED;
        } else {
            bytes32 hash = ECDSA.toEthSignedMessageHash(userOpHash);
            address signer = ECDSA.recover(hash, userOp.signature);

            if (signer != from) {
                return SIG_VALIDATION_FAILED;
            }
            return 0;
        }
    }

    /// inheritdoc BasePaymaster
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 requiredPreFund)
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        address sender =
            userOp.sender == address(this) ? address(uint160(uint256(bytes32(userOp.callData[4:36])))) : userOp.sender;

        unchecked {
            uint256 feeAmount = (requiredPreFund + (REFUND_POSTOP_COST) * userOp.maxFeePerGas) * (priceMarkup + 10000) / 10000;

            (uint256 tokenAmount,) = oracle.getPrice(address(this), uint128(feeAmount));
            uint256 currentPrice = (tokenAmount * 1 ether / feeAmount);
            uint256 feeRange = currentPrice * priceMarkup / 10000;
            uint256 feePrice = (currentPrice - 1) / feeRange * feeRange; 

            require(tokenAmount <= balanceOf[sender], "AA-ERC20 : insufficient balance");

            accumulatedFee[feePrice] += tokenAmount;
            
            _transfer(sender, address(this), tokenAmount);

            validationData = 0;
        }
    }

    function _isLidquidateAllowed(uint256 price) internal returns (bool) {
       (uint256 currentPrice,) = oracle.getPrice(msg.sender, 1 ether);
        uint256 balance = getDeposit();
        if (currentPrice > price * (liquidateThreshold + 10000) / 10000 || minDepositAmount > balance) {
            return true;
        }

        return false; 
    }

    fallback() external payable {
        require(msg.sender == address(nativeToken), "AA-ERC20 : fallback not allowed");
    }
}
