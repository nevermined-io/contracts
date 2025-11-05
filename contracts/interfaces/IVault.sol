// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/**
 * @title Vault Interface
 * @author Nevermined AG
 * @notice Interface defining the functionality for a multi-token vault in the Nevermined ecosystem
 * @dev This interface establishes the functions and events required for managing deposits and
 * withdrawals of both native (ETH) and ERC20 tokens within the protocol
 */
interface IVault {
    /**
     * @notice Event triggered when a native token is received in the vault contract
     * @param from Sender of the native token
     * @param value Amount of native token received
     */
    event ReceivedNativeToken(address indexed from, uint256 value);

    /**
     * @notice Event triggered when a native token is withdrawn from the vault contract
     * @param from Account requesting the withdraw of the native token
     * @param receiver Receiver of the native token
     * @param amount Amount of native token withdrawn
     */
    event WithdrawNativeToken(address indexed from, address indexed receiver, uint256 amount);

    /**
     * @notice Event triggered when an ERC20 token is received in the vault contract
     * @param erc20TokenAddress Address of the ERC20 token
     * @param from Sender of the ERC20 token
     * @param amount Amount of ERC20 token received
     */
    event ReceivedERC20(address indexed erc20TokenAddress, address indexed from, uint256 amount);

    /**
     * @notice Event triggered when an ERC20 token is withdrawn from the vault contract
     * @param erc20TokenAddress Address of the ERC20 token
     * @param from Account requesting the withdraw of the ERC20 token
     * @param receiver Receiver of the ERC20 token
     * @param amount Amount of ERC20 token withdrawn
     */
    event WithdrawERC20(
        address indexed erc20TokenAddress, address indexed from, address indexed receiver, uint256 amount
    );

    /**
     * @notice Error thrown when an address without the required role attempts to access a role-restricted function
     * @param sender The address of the account calling this function
     * @param role The role required to call this function
     */
    error InvalidRole(address sender, uint64 role);

    /**
     * @notice Error thrown when a native token transfer fails
     * @dev This can happen due to various reasons like insufficient gas or receiver contract errors
     */
    error FailedToSendNativeToken();

    /**
     * @notice Deposits native token (e.g., ETH) into the vault
     * @dev The amount is determined by the value sent with the transaction (msg.value)
     */
    function depositNativeToken() external payable;

    /**
     * @notice Deposits ERC20 tokens into the vault
     * @dev Requires prior approval from the token owner for the vault contract
     * @param _erc20TokenAddress The address of the ERC20 token contract
     * @param _amount The amount of tokens to deposit
     * @param _from The address from which to transfer tokens
     */
    function depositERC20(address _erc20TokenAddress, uint256 _amount, address _from) external;

    /**
     * @notice Withdraws ERC20 tokens from the vault to a specified receiver
     * @dev Caller must have appropriate permissions to initiate withdrawals
     * @param _erc20TokenAddress The address of the ERC20 token contract
     * @param _amount The amount of tokens to withdraw
     * @param _receiver The address that will receive the withdrawn tokens
     */
    function withdrawERC20(address _erc20TokenAddress, uint256 _amount, address _receiver) external;

    /**
     * @notice Withdraws native token from the vault to a specified receiver
     * @dev Caller must have appropriate permissions to initiate withdrawals
     * @param _amount The amount of native token to withdraw
     * @param _receiver The address that will receive the withdrawn native token
     */
    function withdrawNativeToken(uint256 _amount, address _receiver) external;

    /**
     * @notice Gets the current native token balance of the vault
     * @return balance The native token balance
     */
    function getBalanceNativeToken() external view returns (uint256 balance);

    /**
     * @notice Gets the current ERC20 token balance of the vault for a specific token
     * @param _erc20TokenAddress The address of the ERC20 token contract
     * @return balance The token balance
     */
    function getBalanceERC20(address _erc20TokenAddress) external view returns (uint256 balance);
}
