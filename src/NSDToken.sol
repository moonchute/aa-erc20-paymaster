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
import {NSDERC20} from "./NSDERC20.sol";

contract NSDToken is IAccount, BasePaymaster, NSDERC20 {
    uint256 public constant PRICE_DENOMINATOR = 1e6;
    uint256 public constant REFUND_POSTOP_COST = 40000;
    uint256 public constant PRICE_MARKUP = 110e4;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;
    uint256 public immutable tokenDecimals;
    uint192 public previousPrice;

    // IEntryPoint immutable entryPoint;
    address immutable token;
    IOracle immutable tokenOracle;
    IOracle immutable nativeOracle;

    constructor(
        IEntryPoint _entryPoint, 
        IERC20Metadata _token, 
        IOracle _tokenoOracle, 
        IOracle _nativeOracle, 
        address _owner
    ) BasePaymaster(_entryPoint) {
        token = address(_token);
        tokenOracle = _tokenoOracle;
        nativeOracle = _nativeOracle;
        tokenDecimals = 10 ** _token.decimals();
        _transferOwnership(_owner);
    }

    function mint(address to, uint256 amount) external {
        IERC20(token).transferFrom(to, address(this), amount);
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        _burn(msg.sender, amount);
        IERC20(token).transfer(to, amount);
    }

    function withdrawNSDToken(address to, uint256 amount) public onlyOwner {
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
        require(answer > 0, "NSDToken : Chainlink price <= 0");
        // 2 days old price is considered stale since the price is updated every 24 hours
        require(updatedAt >= block.timestamp - 60 * 60 * 24 * 2, "NSDToken : Incomplete round");
        require(answeredInRound >= roundId, "NSDToken : Stale price");
        price = uint192(int192(answer));
    }

    function updatePrice() external {
        // This function updates the cached ERC20/ETH price ratio
        uint192 tokenPrice = _fetchPrice(tokenOracle);
        uint192 nativeAssetPrice = _fetchPrice(nativeOracle);
        previousPrice = nativeAssetPrice * uint192(tokenDecimals) / tokenPrice;
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256
    ) external virtual override returns (uint256 validationData) {
        _requireFromEntryPoint();
        bytes4 selector = bytes4(userOp.callData[0:4]);
        (address from,,) = abi.decode(userOp.callData[4:], (address, address, uint256));

        // transferWithFee(address,address,uint256)
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

    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    ) internal override returns (bytes memory context, uint256 validationData) {
        require(userOp.sender == address(this), "NSDToken: only NSDToken can call paymaster");
        (address from,, uint256 amount) = abi.decode(userOp.callData[4:], (address, address, uint256));

        unchecked {
            uint256 cachedPrice = previousPrice;
            require(cachedPrice != 0, "NSDToken : price not set");
            
            uint256 tokenAmount = (requiredPreFund + (REFUND_POSTOP_COST) * userOp.maxFeePerGas) * PRICE_MARKUP
              * cachedPrice / (PRICE_DENOMINATOR * 1e18);
            
            require(tokenAmount + amount <= balanceOf[from], "NSDToken : insufficient balance");
            _transfer(from, address(this), tokenAmount);

            validationData = 0;
        }
    }
}
