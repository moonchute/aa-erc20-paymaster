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

import {IAAERC20Factory} from "./interfaces/IAAERC20Factory.sol";
import {IPaymasterOracle} from "./interfaces/IPaymasterOracle.sol";
import {IPaymasterSwap} from "./interfaces/IPaymasterSwap.sol";
import {IAAERC20Paymaster} from "./interfaces/IAAERC20Paymaster.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {AAERC20} from "./AAERC20.sol";

contract AAERC20Paymaster is IAAERC20Paymaster, BasePaymaster, AAERC20 {
    uint256 public constant REFUND_POSTOP_COST = 41200;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    // protocol parameter in basis
    uint256 public constant PRICE_MARKUP = 1000;
    uint256 public constant PROTOCOL_FEE = 100;
    uint256 public constant OWNER_FEE = 100;
    uint256 public constant LIQUIDATOR_FEE = 50;
    uint256 public constant LIQUIDATOR_THRESHOLD = 700;

    uint256 public minDepositAmount = 1 ether;
    uint256 public override currentPrice;

    address public immutable override factory;
    IWETH public immutable override nativeToken;
    IPaymasterOracle public immutable override oracle;
    IPaymasterSwap public immutable override swap;

    mapping(uint256 => uint256) public override accumulatedFee;
    mapping(address => uint256) public override accumulatedLiquidateFee;

    constructor(
        address _factory,
        IEntryPoint _entryPoint,
        address _nativetoken,
        IERC20Metadata _token,
        IPaymasterOracle _oracle,
        IPaymasterSwap _swap,
        address _owner
    ) AAERC20(_token) BasePaymaster(_entryPoint) {
        factory = _factory;
        nativeToken = IWETH(_nativetoken);
        oracle = _oracle;
        swap = _swap;
        _oracle.initialize(address(_token));
        _swap.initialize(address(_token));
        _transferOwnership(_owner);
    }

    /// @inheritdoc IAAERC20Paymaster
    function transferWithFee(address from, address to, uint256 amount) external override returns (bool) {
        _requireFromEntryPoint();
        require(amount <= balanceOf[from], "AA-ERC20 : insufficient balance");
        _transfer(from, to, amount);
        return true;
    }

    /// @inheritdoc IAAERC20Paymaster
    function burnWithFee(address from, address to, uint256 amount) external override {
        _requireFromEntryPoint();
        require(amount <= balanceOf[from], "AA-ERC20 : insufficient balance");
        _burn(from, amount);
        IERC20(token).transfer(to, amount);
    }

    /// @inheritdoc IAAERC20Paymaster
    function liquidate(uint256 price) external payable override {
        uint256 amount = accumulatedFee[price];
        require(amount > 0, "AA-ERC20 : insufficient liquidate amount");
        require(_isLidquidateAllowed(price), "AA-ERC20 : not liquidatable");

        accumulatedFee[price] = 0;
        uint256 protocolAmount = amount * PROTOCOL_FEE / 10000;
        uint256 ownerAmount = amount * OWNER_FEE / 10000;
        uint256 liquidatorAmount = amount * LIQUIDATOR_FEE / 10000;
        uint256 remainAmount = amount - protocolAmount - ownerAmount - liquidatorAmount;

        accumulatedLiquidateFee[IAAERC20Factory(factory).owner()] += protocolAmount;
        accumulatedLiquidateFee[owner()] += ownerAmount;
        accumulatedLiquidateFee[msg.sender] += liquidatorAmount;

        _burn(address(this), remainAmount);
        IERC20(token).transfer(address(swap), remainAmount);
        uint256 amountOut = swap.swap(uint128(remainAmount));

        nativeToken.withdraw(amountOut);

        entryPoint.depositTo{value: amountOut}(address(this));
    }

    /// @inheritdoc IAAERC20Paymaster
    function withdrawLiquidatorFee(address to) external override {
        uint256 amount = accumulatedLiquidateFee[msg.sender];
        require(amount > 0, "AA-ERC20 : insufficient withdraw amount");

        accumulatedLiquidateFee[msg.sender] = 0;
        _transfer(address(this), to, amount);
    }

    /// @inheritdoc IAAERC20Paymaster
    function isLiquidateAllowed(uint256 price) public override returns (bool) {
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
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund)
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        address sender = userOp.sender == address(this) ? address(bytes20(userOp.callData[16:36])) : userOp.sender;

        unchecked {
            uint256 feeAmount =
                (requiredPreFund + (REFUND_POSTOP_COST) * userOp.maxFeePerGas) * (PRICE_MARKUP + 10000) / 10000;

            uint256 tokenAmount = oracle.getPrice(address(this), uint128(feeAmount));
            uint256 price = (tokenAmount * 1 ether / feeAmount);
            uint256 feeRange = price * PRICE_MARKUP / 10000;
            uint256 feePrice = (price - 1) / feeRange * feeRange;
            currentPrice = price;

            require(tokenAmount <= balanceOf[sender], "AA-ERC20 : insufficient balance");
            accumulatedFee[feePrice] += tokenAmount;

            _transfer(sender, address(this), tokenAmount);
            validationData = 0;
            context = abi.encodePacked(tokenAmount, sender);
        }
    }

    /// inheritdoc BasePaymaster
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        if (mode == PostOpMode.postOpReverted) {
            return;
        }

        unchecked {
            uint256 actualTokenNeeded = (actualGasCost + REFUND_POSTOP_COST * tx.gasprice) * currentPrice / 1 ether
                * (PRICE_MARKUP + 10000) / 10000;

            if (uint256(bytes32(context[0:32])) > actualTokenNeeded) {
                uint256 refund = (uint256(bytes32(context[0:32])) - actualTokenNeeded);
                uint256 feeRange = currentPrice * PRICE_MARKUP / 10000;
                uint256 feePrice = (currentPrice - 1) / feeRange * feeRange;

                _transfer(address(this), address(bytes20(context[32:52])), refund);
                accumulatedFee[feePrice] -= refund;
            }
        }
    }

    /**
     * @dev Check if the liquidation is allowed. The liquidation is allowed if the fee is insolvent or
     *      the deposit amount in entrypoint is insufficient.
     * @param price The fee price to liquidate
     * @return isAllowed true if allowed
     */
    function _isLidquidateAllowed(uint256 price) internal returns (bool isAllowed) {
        uint256 liquidatePrice = oracle.getPrice(msg.sender, 1 ether);
        uint256 balance = getDeposit();

        if (liquidatePrice > price * (LIQUIDATOR_THRESHOLD + 10000) / 10000 || minDepositAmount > balance) {
            isAllowed = true;
        }
    }

    receive() external payable {
        require(msg.sender == address(nativeToken), "AA-ERC20 : fallback not allowed");
    }
}
