// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {BasePaymaster} from "account-abstraction/core/BasePaymaster.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

import {IOracle} from "./interface/IOracle.sol";
import {AAERC20} from "./AAERC20.sol";

contract AAERC20Paymaster is IAccount, BasePaymaster, AAERC20 {
    uint256 public constant PRICE_DENOMINATOR = 1e6;
    uint256 public constant REFUND_POSTOP_COST = 40000;
    uint256 public constant PRICE_MARKUP = 110e4;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;
    uint192 public previousPrice;

    // IEntryPoint immutable entryPoint;
    IOracle immutable tokenOracle;
    IOracle immutable nativeOracle;

    constructor(
        IEntryPoint _entryPoint,
        IERC20Metadata _token,
        IOracle _tokenoOracle,
        IOracle _nativeOracle,
        address _owner
    ) AAERC20(_token) BasePaymaster(_entryPoint) {
        tokenOracle = _tokenoOracle;
        nativeOracle = _nativeOracle;
        _transferOwnership(_owner);
    }

    function withdrawAAERC20Token(address to, uint256 amount) public onlyOwner {
        _transfer(address(this), to, amount);
    }

    function transferWithFee(address from, address to, uint256 amount) external returns (bool) {
        _requireFromEntryPoint();
        _transfer(from, to, amount);
        return true;
    }

    function burnWithFee(address from, address to, uint256 amount) external {
        _requireFromEntryPoint();
        _burn(from, amount);
        IERC20(token).transfer(to, amount);
    }

    function _fetchPrice(IOracle _oracle) internal view returns (uint192 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();
        require(answer > 0, "AA-ERC20 : Chainlink price <= 0");
        // 2 days old price is considered stale since the price is updated every 24 hours
        require(updatedAt >= block.timestamp - 60 * 60 * 24 * 2, "AA-ERC20 : Incomplete round");
        require(answeredInRound >= roundId, "AA-ERC20 : Stale price");
        price = uint192(int192(answer));
    }

    function updatePrice() external {
        // This function updates the cached ERC20/ETH price ratio
        uint192 tokenPrice = _fetchPrice(tokenOracle);
        uint192 nativeAssetPrice = _fetchPrice(nativeOracle);
        previousPrice = nativeAssetPrice * uint192(tokenDecimals) / tokenPrice;
    }

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

    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 requiredPreFund)
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        address sender =
            userOp.sender == address(this) ? address(uint160(uint256(bytes32(userOp.callData[4:36])))) : userOp.sender;

        unchecked {
            uint256 cachedPrice = previousPrice;
            require(cachedPrice != 0, "AA-ERC20 : price not set");

            uint256 tokenAmount = (requiredPreFund + (REFUND_POSTOP_COST) * userOp.maxFeePerGas) * PRICE_MARKUP
                * cachedPrice / (PRICE_DENOMINATOR * 1e18);

            require(tokenAmount <= balanceOf[sender], "AA-ERC20 : insufficient balance");
            _transfer(sender, address(this), tokenAmount);

            validationData = 0;
        }
    }
}
