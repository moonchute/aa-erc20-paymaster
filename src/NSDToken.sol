// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {BasePaymaster} from "account-abstraction/core/BasePaymaster.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

import {IOracle} from "./interface/IOracle.sol";
import {NSDERC20} from "./NSDERC20.sol";

contract NSDToken is IAccount, BasePaymaster, NSDERC20 {
    uint256 public constant priceDenominator = 1e6;
    uint256 public constant REFUND_POSTOP_COST = 40000;
    uint256 public constant priceMarkup = 110e4;
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
    ) BasePaymaster(_entryPoint) Ownable(_owner) {
        token = address(_token);
        tokenOracle = _tokenoOracle;
        nativeOracle = _nativeOracle;
        tokenDecimals = 10 ** _token.decimals();
    }

    function mint(address to, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
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

    function fetchPrice(IOracle _oracle) internal view returns (uint192 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();
        require(answer > 0, "NSDToken : Chainlink price <= 0");
        // 2 days old price is considered stale since the price is updated every 24 hours
        require(updatedAt >= block.timestamp - 60 * 60 * 24 * 2, "NSDToken : Incomplete round");
        require(answeredInRound >= roundId, "NSDToken : Stale price");
        price = uint192(int192(answer));
    }

    function updatePrice() external {
        // This function updates the cached ERC20/ETH price ratio
        uint192 tokenPrice = fetchPrice(tokenOracle);
        uint192 nativeAssetPrice = fetchPrice(nativeOracle);
        previousPrice = nativeAssetPrice * uint192(tokenDecimals) / tokenPrice;
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external virtual override returns (uint256 validationData) {
        _requireFromEntryPoint();
        bytes4 selector = bytes4(userOp.callData[0:4]);
        address from = address(bytes20(userOp.callData[4:24]));
        // address to = address(bytes20(userOp.callData[24:44]));
        uint256 amount = uint256(bytes32(userOp.callData[44:76]));

        if (selector != bytes4(0xf3408110)) {
            return SIG_VALIDATION_FAILED;
        }
        bytes32 hash = ECDSA.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(hash, userOp.signature);
        if (signer != from) {
            return SIG_VALIDATION_FAILED;
        }
          
        return 0;
    }

    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    ) internal override returns (bytes memory context, uint256 validationData) {
        require(userOp.sender == address(this), "NSDToken: only NSDToken can call paymaster");
        address from = address(bytes20(userOp.callData[4:24]));
        uint256 amount = uint256(bytes32(userOp.callData[44:76]));

        unchecked {
            uint256 cachedPrice = previousPrice;
            require(cachedPrice != 0, "NSDToken : price not set");
            
            uint256 tokenAmount = (requiredPreFund + (REFUND_POSTOP_COST) * userOp.maxFeePerGas) * priceMarkup
              * cachedPrice / (1e18 * priceDenominator);
            
            require(tokenAmount + amount < IERC20(token).balanceOf(from), "NSDToken : insufficient balance");
            _transfer(userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, userOp.sender);

            validationData = 0;
        }
    }
}