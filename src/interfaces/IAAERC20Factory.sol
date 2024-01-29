// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title The interface for the AAERC20 Paymaster Factory.
 */
interface IAAERC20Factory {
    /**
     * @dev Emitted when a new AAERC20 is created.
     * @param aaerc20 The address of the AAERC20 contract.
     * @param token The address of the token.
     * @param oracle The address of the oracle.
     * @param swap The address of the swap.
     * @param entryPoint The address of the entryPoint.
     */
    event AAERC20Created(
        address indexed aaerc20, address indexed token, address oracle, address swap, address entryPoint
    );

    /**
     * @dev Emitted when the owner is changed.
     * @param newOwner The address of the new owner.
     */
    event SetOwner(address indexed newOwner);

    /**
     * @dev Creates a new AAERC20 contract.
     * @param _entryPoint The address of the entryPoint.
     * @param _token The address of the token.
     * @param _oracle The address of the oracle.
     * @param _swap The address of the swap.
     * @param _owner The address of the owner.
     */
    function createAAERC20(
        address _entryPoint,
        address _token,
        address _oracle,
        address _swap,
        address _owner
    ) external;

    /**
     * @dev Sets the owner.
     * @param newOwner The address of the new owner.
     */
    function setOwner(address newOwner) external;

    /**
     * @dev Returns the address of the AAERC20 contract.
     * @param _token The address of the token.
     * @param _oracle The address of the oracle.
     * @param _swap The address of the swap.
     * @param _entryPoint The address of the entryPoint.
     */
    function getAAErc20(address _token, address _oracle, address _swap, address _entryPoint)
        external
        view
        returns (address);

    /**
     * @dev Returns the address of the owner.
     */
    function owner() external view returns (address);

    /**
     * @dev Returns the address of the wrapped native token.
     */
    function nativeToken() external view returns (address);
}
