// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IERC3009} from './interfaces/IERC3009.sol';
import {IVault} from './interfaces/IVault.sol';

import {DEPOSITOR_ROLE} from './common/Roles.sol';
import {AccessManagedUUPSUpgradeable} from './proxy/AccessManagedUUPSUpgradeable.sol';
import {
    ReentrancyGuardTransientUpgradeable
} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title PaymentsVault
 * @author Nevermined AG
 * @notice This contract serves as a secure vault for holding and managing native tokens (ETH) and ERC20 tokens
 * in the Nevermined ecosystem.
 * @dev The contract implements:
 * - Role-based access control via OpenZeppelin's AccessManager integration
 * - Security against reentrancy attacks via ReentrancyGuardTransientUpgradeable
 * - Upgradeability using UUPS (Universal Upgradeable Proxy Standard) pattern
 * - ERC-7201 namespaced storage pattern to prevent storage collisions during upgrades
 *
 * The contract handles two main token types:
 * 1. Native tokens (ETH)
 * 2. ERC20 tokens
 *
 * Access is controlled via two primary roles:
 * - DEPOSITOR_ROLE: Allows depositing tokens into the vault
 * - WITHDRAW_ROLE: Allows withdrawing tokens from the vault
 */
contract PaymentsVault is IVault, ReentrancyGuardTransientUpgradeable, AccessManagedUUPSUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes the PaymentsVault contract
     * @param _authority Address of the AccessManager contract handling permissions
     * @dev This function can only be called once due to the initializer modifier
     * @dev Sets up the access control system and initializes the reentrancy guard
     * @dev This replaces the constructor for upgradeable contracts
     */
    function initialize(IAccessManager _authority) external initializer {
        ReentrancyGuardTransientUpgradeable.__ReentrancyGuardTransient_init();
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Fallback function to receive native tokens (ETH) sent directly to the contract
     * @dev Only addresses with DEPOSITOR_ROLE can send native tokens directly to the contract
     * @dev Emits ReceivedNativeToken event on successful deposit
     * @dev This function enables the contract to receive ETH transfers
     */
    // solhint-disable-next-line no-complex-fallback
    receive() external payable nonReentrant {
        (bool hasRole,) = IAccessManager(authority()).hasRole(DEPOSITOR_ROLE, msg.sender);
        require(hasRole, InvalidRole(msg.sender, DEPOSITOR_ROLE));
        emit ReceivedNativeToken(msg.sender, msg.value);
    }

    /**
     * @notice Deposits native tokens (ETH) to the vault
     * @dev Caller must have DEPOSITOR_ROLE to call this function
     * @dev Protected against reentrancy attacks with nonReentrant modifier
     * @dev Emits ReceivedNativeToken event on successful deposit
     * @dev This function provides an explicit method to deposit ETH as an alternative to using the receive() function
     */
    function depositNativeToken() external payable nonReentrant restricted {
        emit ReceivedNativeToken(msg.sender, msg.value);
    }

    /**
     * @notice Withdraws native tokens (ETH) from the vault to a specified receiver
     * @param _amount Amount of native tokens to withdraw
     * @param _receiver Address to receive the withdrawn tokens
     * @dev Caller must have WITHDRAW_ROLE to call this function
     * @dev Emits WithdrawNativeToken event on successful withdrawal
     */
    function withdrawNativeToken(uint256 _amount, address _receiver) external nonReentrant restricted {
        // Skip transfer if amount is 0
        if (_amount > 0) {
            (bool sent,) = _receiver.call{value: _amount}('');
            if (!sent) revert FailedToSendNativeToken();
        }

        emit WithdrawNativeToken(msg.sender, _receiver, _amount);
    }

    /**
     * @notice Records a deposit of ERC20 tokens to the vault
     * @param _erc20TokenAddress Address of the ERC20 token contract
     * @param _amount Amount of tokens being deposited
     * @param _from Original sender of the tokens
     * @dev Caller must have DEPOSITOR_ROLE to call this function
     * @dev Emits ReceivedERC20 event on successful deposit
     * @dev This function only records the deposit event; actual token transfer must be done separately
     */
    function depositERC20(address _erc20TokenAddress, uint256 _amount, address _from) external nonReentrant restricted {
        IERC20 token = IERC20(_erc20TokenAddress);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(_from, address(this), _amount);
        // Reject fee-on-transfer / deflationary tokens: the vault must actually receive the amount it
        // records, otherwise distribution (which withdraws the nominal amount) draws from other
        // agreements' funds in the shared pool.
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received != _amount) revert ERC20DepositMismatch(_amount, received);
        emit ReceivedERC20(_erc20TokenAddress, _from, _amount);
    }

    /**
     * @notice Deposits ERC20 tokens into the vault using an EIP-3009 signed authorization
     * @param _erc20TokenAddress Address of the EIP-3009 compatible ERC20 token contract
     * @param _from The token holder that signed the authorization
     * @param _amount Amount of tokens being deposited (must equal the signed authorization value)
     * @param _validAfter The authorization is invalid at or before this Unix timestamp
     * @param _validBefore The authorization is invalid at or after this Unix timestamp
     * @param _nonce Single-use authorization nonce (callers bind this to the agreement)
     * @param _v ECDSA signature recovery byte
     * @param _r ECDSA signature r value
     * @param _s ECDSA signature s value
     * @dev Caller must have DEPOSITOR_ROLE. The vault is the EIP-3009 payee (`to`), so the token's
     *      `to == msg.sender` guard is satisfied. No prior `approve` is needed. The exact transfer
     *      amount, recipient, validity window, nonce uniqueness, and signer are enforced on-chain by
     *      the token contract; a non-matching signature reverts the whole transaction.
     */
    function depositERC20WithAuthorization(
        address _erc20TokenAddress,
        address _from,
        uint256 _amount,
        uint256 _validAfter,
        uint256 _validBefore,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant restricted {
        // Measure the actual amount received so a misbehaving token (fee-on-transfer, or one whose
        // receiveWithAuthorization does not move funds) cannot silently under-fund the vault.
        uint256 balanceBefore = IERC20(_erc20TokenAddress).balanceOf(address(this));
        IERC3009(_erc20TokenAddress)
            .receiveWithAuthorization(_from, address(this), _amount, _validAfter, _validBefore, _nonce, _v, _r, _s);
        uint256 received = IERC20(_erc20TokenAddress).balanceOf(address(this)) - balanceBefore;
        require(received == _amount, ERC20DepositMismatch(_amount, received));

        emit ReceivedERC20(_erc20TokenAddress, _from, _amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from the vault to a specified receiver
     * @param _erc20TokenAddress Address of the ERC20 token contract
     * @param _amount Amount of tokens to withdraw
     * @param _receiver Address to receive the withdrawn tokens
     * @dev Caller must have WITHDRAW_ROLE to call this function
     * @dev Emits WithdrawERC20 event on successful withdrawal
     */
    function withdrawERC20(address _erc20TokenAddress, uint256 _amount, address _receiver)
        external
        nonReentrant
        restricted
    {
        // Skip transfer if amount is 0
        if (_amount > 0) {
            IERC20(_erc20TokenAddress).safeTransfer(_receiver, _amount);
        }

        emit WithdrawERC20(_erc20TokenAddress, msg.sender, _receiver, _amount);
    }

    /**
     * @notice Gets the current balance of native tokens (ETH) in the vault
     * @return balance The current native token balance
     */
    function getBalanceNativeToken() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /**
     * @notice Gets the current balance of a specific ERC20 token in the vault
     * @param _erc20TokenAddress Address of the ERC20 token contract
     * @return balance The current token balance
     */
    function getBalanceERC20(address _erc20TokenAddress) external view returns (uint256 balance) {
        IERC20 token = IERC20(_erc20TokenAddress);
        return token.balanceOf(address(this));
    }
}
