// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

import {IPaymasterOracle} from "./interfaces/IPaymasterOracle.sol";
import {IPaymasterSwap} from "./interfaces/IPaymasterSwap.sol";
import {IAAERC20Factory} from "./interfaces/IAAERC20Factory.sol";
import {IAAERC20Paymaster} from "./interfaces/IAAERC20Paymaster.sol";
import {AAERC20Paymaster} from "./AAERC20Paymaster.sol";

contract AAERC20Factory is IAAERC20Factory {
    /// @inheritdoc IAAERC20Factory
    address public override owner;

    /// @inheritdoc IAAERC20Factory
    address public immutable override nativeToken;

    /// @inheritdoc IAAERC20Factory
    mapping(address => mapping(address => mapping(address => mapping(address => address)))) public override getAAErc20;

    constructor(address _nativeToken) {
        nativeToken = _nativeToken;
        owner = msg.sender;
    }

    /// @inheritdoc IAAERC20Factory
    function createAAERC20(address _entryPoint, address _token, address _oracle, address _swap, address _owner)
        external
        override
    {
        require(getAAErc20[_token][_oracle][_swap][_entryPoint] == address(0), "AAERC20Factory: already created");

        bytes32 salt = keccak256(abi.encodePacked(_token, _oracle, _swap, _entryPoint));
        address aaerc20Address = address(
            new AAERC20Paymaster{salt: salt}(
                address(this),
                IEntryPoint(_entryPoint),
                nativeToken,
                IERC20Metadata(_token),
                IPaymasterOracle(_oracle),
                IPaymasterSwap(_swap),
                _owner
            )
        );
        getAAErc20[_token][_oracle][_swap][_entryPoint] = aaerc20Address;
        emit AAERC20Created(aaerc20Address, _token, _oracle, _swap, _entryPoint);
    }

    /// @inheritdoc IAAERC20Factory
    function setOwner(address newOwner) external override {
        require(msg.sender == owner, "AAERC20Factory: not owner");
        owner = newOwner;
        emit SetOwner(newOwner);
    }
}
