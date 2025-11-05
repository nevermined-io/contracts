// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../interfaces/IAgreement.sol';
import {IAsset} from '../interfaces/IAsset.sol';
import {INVMConfig} from '../interfaces/INVMConfig.sol';
import {INeverminedExternalPrice} from '../interfaces/INeverminedExternalPrice.sol';
import {IVault} from '../interfaces/IVault.sol';

import {TokenUtils} from '../utils/TokenUtils.sol';
import {TemplateCondition} from './TemplateCondition.sol';
import {
    ReentrancyGuardTransientUpgradeable
} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title LockPaymentCondition
 * @author Nevermined
 * @notice Condition that locks payments in the PaymentsVault until other conditions are fulfilled
 * @dev This contract is responsible for processing and locking payments for agreements.
 * It supports both native token (ETH) and ERC20 token payments, which are locked in the
 * PaymentsVault contract until other agreement conditions are satisfied. The locked funds can
 * later be distributed or refunded by the DistributePaymentsCondition contract.
 *
 * Currently supported price types:
 * - FIXED_PRICE: Fixed amount in crypto (native or ERC20)
 *
 * Unsupported price types that trigger errors:
 * - FIXED_FIAT_PRICE: Handled by FiatSettlementCondition
 * - SMART_CONTRACT_PRICE: Not yet implemented
 */
contract LockPaymentCondition is ReentrancyGuardTransientUpgradeable, TemplateCondition {
    /**
     * @notice Contract name identifier used in the Nevermined ecosystem
     */
    bytes32 public constant NVM_CONTRACT_NAME = keccak256('LockPaymentCondition');

    // keccak256(abi.encode(uint256(keccak256("nevermined.lockpaymentcondition.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LOCK_PAYMENT_CONDITION_STORAGE_LOCATION =
        0x249686b58dc8ad820998e3d83bd78653adb95e2993297822a42d3d4df7f1ae00;

    /**
     * @notice Error thrown when an invalid assets registry address is provided in an agreement creation process
     * @dev The assets registry address must be a valid address
     */
    error InvalidAssetsRegistryAddress();

    /**
     * @notice Error thrown when an invalid agreement store address is provided in an agreement creation process
     * @dev The agreement store address must be a valid address
     */
    error InvalidAgreementStoreAddress();

    /**
     * /**
     * @notice Error thrown when an invalid vault address is provided in an agreement creation process
     * @dev The vault address must be a valid address
     */
    error InvalidVaultAddress();

    /// @custom:storage-location erc7201:nevermined.lockpaymentcondition.storage
    struct LockPaymentConditionStorage {
        INVMConfig nvmConfig;
        IAsset assetsRegistry;
        IAgreement agreementStore;
        IVault vault;
    }

    /**
     * @notice The price type provided is not supported by this condition
     */
    error UnsupportedPriceTypeOption();

    /**
     * @notice Initializes the LockPaymentCondition contract with required dependencies
     * @param _authority Address of the AccessManager contract for role-based access control
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract for accessing plan information
     * @param _agreementStoreAddress Address of the AgreementsStore contract for managing agreement state
     * @param _vaultAddress Address of the PaymentsVault contract where funds will be locked
     * @dev Sets up storage references and initializes the access management system
     */
    function initialize(
        IAccessManager _authority,
        IAsset _assetsRegistryAddress,
        IAgreement _agreementStoreAddress,
        IVault _vaultAddress
    ) external initializer {
        require(_assetsRegistryAddress != IAsset(address(0)), InvalidAssetsRegistryAddress());
        require(_agreementStoreAddress != IAgreement(address(0)), InvalidAgreementStoreAddress());
        require(_vaultAddress != IVault(address(0)), InvalidVaultAddress());

        ReentrancyGuardTransientUpgradeable.__ReentrancyGuardTransient_init();
        LockPaymentConditionStorage storage $ = _getLockPaymentConditionStorage();

        $.assetsRegistry = _assetsRegistryAddress;
        $.agreementStore = _agreementStoreAddress;
        $.vault = _vaultAddress;
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Fulfills the lock payment condition for an agreement
     * @param _conditionId Identifier of the condition to fulfill
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _senderAddress Address of the payment sender
     * @dev Only registered templates can call this function
     * @dev Checks that the agreement exists and plan configuration is correct
     * @dev For FIXED_PRICE type: Locks payment in vault until other conditions are fulfilled
     * @dev Supports both native token and ERC20 token payments
     * @dev Validates that payment amounts match receivers and include Nevermined fees
     * @dev Reverts for unsupported price types (fiat or smart contract)
     */
    function fulfill(bytes32 _conditionId, bytes32 _agreementId, uint256 _planId, address _senderAddress)
        external
        payable
        restricted
        nonReentrant
    {
        LockPaymentConditionStorage storage $ = _getLockPaymentConditionStorage();

        // Check if the agreementId is registered in the AssetsRegistry
        if (!$.agreementStore.agreementExists(_agreementId)) {
            revert IAgreement.AgreementNotFound(_agreementId);
        }

        if ($.agreementStore.getConditionState(_agreementId, _conditionId) == IAgreement.ConditionState.Fulfilled) {
            revert IAgreement.ConditionAlreadyFulfilled(_agreementId, _conditionId);
        }

        // Check if the plan config (token, amount) is correct
        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);

        if (!plan.price.isCrypto) revert UnsupportedPriceTypeOption();

        IAgreement.Agreement memory agreement = $.agreementStore.getAgreement(_agreementId);

        if (plan.price.externalPriceAddress == address(0)) {
            // FIXED_PRICE
            // Check if the amounts and receivers include the Nevermined fees
            if (!$.assetsRegistry.areNeverminedFeesIncluded(_planId)) {
                revert IAsset.NeverminedFeesNotIncluded(plan.price.amounts, plan.price.receivers);
            }

            uint256 amountToTransfer = TokenUtils.calculateAmountSum(plan.price.amounts) * agreement.numberOfPurchases;
            // Only process payment if amount is greater than zero
            if (amountToTransfer > 0) {
                if (plan.price.tokenAddress == address(0)) {
                    // Native token payment
                    if (msg.value != amountToTransfer) {
                        revert TokenUtils.InvalidTransactionAmount(msg.value, amountToTransfer);
                    }
                    $.vault.depositNativeToken{value: amountToTransfer}();
                } else {
                    // Record the deposit in the vault
                    require(msg.value == 0, IAgreement.MsgValueMustBeZeroForERC20Payments());
                    $.vault.depositERC20(plan.price.tokenAddress, amountToTransfer, _senderAddress);
                }
            }

            // FULFILL THE CONDITION
            $.agreementStore.updateConditionStatus(_agreementId, _conditionId, IAgreement.ConditionState.Fulfilled);
        } else {
            // Dynamic pricing via external contract quote
            uint256[] memory quotedAmounts = INeverminedExternalPrice(plan.price.externalPriceAddress).quote(_planId);

            // For SMART_CONTRACT_PRICE, protocol fees are currently 0 by policy
            uint256 amountToTransfer = TokenUtils.calculateAmountSum(quotedAmounts) * agreement.numberOfPurchases;
            if (amountToTransfer > 0) {
                if (plan.price.tokenAddress == address(0)) {
                    if (msg.value != amountToTransfer) {
                        revert TokenUtils.InvalidTransactionAmount(msg.value, amountToTransfer);
                    }
                    $.vault.depositNativeToken{value: amountToTransfer}();
                } else {
                    require(msg.value == 0, IAgreement.MsgValueMustBeZeroForERC20Payments());
                    $.vault.depositERC20(plan.price.tokenAddress, amountToTransfer, _senderAddress);
                }
            }

            $.agreementStore.updateConditionStatus(_agreementId, _conditionId, IAgreement.ConditionState.Fulfilled);
        }
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the LockPaymentConditionStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getLockPaymentConditionStorage() internal pure returns (LockPaymentConditionStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := LOCK_PAYMENT_CONDITION_STORAGE_LOCATION
        }
    }
}
