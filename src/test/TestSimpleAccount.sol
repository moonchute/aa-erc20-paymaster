// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {SimpleAccount} from "account-abstraction/samples/SimpleAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TestSimpleAccount is SimpleAccount {
    using ECDSA for bytes32;

    constructor(IEntryPoint anEntryPoint) SimpleAccount(anEntryPoint) {}

    function isValidSignature(bytes32 userOpHash, bytes calldata signature) public view returns (bytes4) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner == hash.recover(signature)) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }
}
