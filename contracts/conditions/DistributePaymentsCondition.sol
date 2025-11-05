// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../interfaces/IAgreement.sol';
import {IAsset} from '../interfaces/IAsset.sol';
import {INeverminedExternalPrice} from '../interfaces/INeverminedExternalPrice.sol';
import {IVault} from '../interfaces/IVault.sol';

import {TokenUtils} from '../utils/TokenUtils.sol';
import {TemplateCondition} from './TemplateCondition.sol';
import {
    ReentrancyGuardTransientUpgradeable
} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title DistributePaymentsCondition
 * @author Nevermined
 * @notice Condition for distributing previously locked payments based on agreement outcomes
 * @dev This contract handles the final distribution of funds that were previously locked
 * by the LockPaymentCondition. The distribution can result in either:
 * 1. Successful execution: Payments are distributed to the intended receivers according to the plan
 * 2. Failed execution: Payments are refunded to the original sender (agreement creator)
 *
 * The condition works in tandem with LockPaymentCondition (prerequisite) and typically checks
 * if a release condition (e.g., TransferCreditsCondition) has been fulfilled before distributing
 * payments. This ensures the payment workflow maintains atomicity in the Nevermined protocol.
 */
contract DistributePaymentsCondition is ReentrancyGuardTransientUpgradeable, TemplateCondition {
    /**
     * @notice Contract name identifier used in the Nevermined ecosystem
     */
    bytes32 public constant NVM_CONTRACT_NAME = keccak256('DistributePaymentsCondition');

    // keccak256(abi.encode(uint256(keccak256("nevermined.distributepaymentscondition.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DISTRIBUTE_PAYMENTS_CONDITION_STORAGE_LOCATION =
        0xe41c4b3e2f7bba486623bae88edfd7e81be9c1146d2f719bf139ea3fc6346a00;

    error InvalidAssetsRegistryAddress();
    error InvalidAgreementStoreAddress();
    error InvalidVaultAddress();

    /// @custom:storage-location erc7201:nevermined.distributepaymentscondition.storage
    struct DistributePaymentsConditionStorage {
        IAsset assetsRegistry;
        IAgreement agreementStore;
        IVault vault;
    }

    /**
     * @notice Initializes the DistributePaymentsCondition contract with required dependencies
     * @param _authority Address of the AccessManager contract for role-based access control
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract for accessing plan information
     * @param _agreementStoreAddress Address of the AgreementsStore contract for managing agreement state
     * @param _vaultAddress Address of the PaymentsVault contract where funds are stored
     * @dev Sets up storage references and initializes the access management system
     */
    function initialize(
        IAccessManager _authority,
        IAsset _assetsRegistryAddress,
        IAgreement _agreementStoreAddress,
        IVault _vaultAddress
    ) external initializer {
        ReentrancyGuardTransientUpgradeable.__ReentrancyGuardTransient_init();
        DistributePaymentsConditionStorage storage $ = _getDistributePaymentsConditionStorage();

        require(_assetsRegistryAddress != IAsset(address(0)), InvalidAssetsRegistryAddress());
        require(_agreementStoreAddress != IAgreement(address(0)), InvalidAgreementStoreAddress());
        require(_vaultAddress != IVault(address(0)), InvalidVaultAddress());

        $.assetsRegistry = _assetsRegistryAddress;
        $.agreementStore = _agreementStoreAddress;
        $.vault = _vaultAddress;
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Fulfills the distribute payments condition for an agreement
     * @param _conditionId Identifier of the condition to fulfill
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _lockCondition Identifier of the lock payment condition that must be fulfilled first
     * @param _releaseCondition Identifier of the release condition (typically transfer credits)
     * @dev Only registered templates can call this function
     * @dev Checks if the lock payment condition is fulfilled before proceeding
     * @dev The condition is marked as fulfilled before any external calls (security best practice)
     * @dev If the release condition is fulfilled, distributes payments according to the plan
     * @dev If the release condition is not fulfilled, refunds the payment to the agreement creator
     * @dev Supports both native token and ERC20 token distributions
     */
    function fulfill(
        bytes32 _conditionId,
        bytes32 _agreementId,
        uint256 _planId,
        bytes32 _lockCondition,
        bytes32 _releaseCondition
    ) external payable nonReentrant restricted {
        DistributePaymentsConditionStorage storage $ = _getDistributePaymentsConditionStorage();

        IAgreement.Agreement memory agreement = $.agreementStore.getAgreement(_agreementId);
        if (agreement.lastUpdated == 0) revert IAgreement.AgreementNotFound(_agreementId);

        if ($.agreementStore.getConditionState(_agreementId, _conditionId) == IAgreement.ConditionState.Fulfilled) {
            revert IAgreement.ConditionAlreadyFulfilled(_agreementId, _conditionId);
        }

        // Check if the plan credits config is correct
        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);

        if ($.agreementStore.getConditionState(_agreementId, _lockCondition) != IAgreement.ConditionState.Fulfilled) {
            revert IAgreement.ConditionPreconditionFailed(_agreementId, _conditionId);
        }

        // Check if the required conditions (LockPayment) are already fulfilled
        // FULFILL THE CONDITION first (before external calls)
        $.agreementStore.updateConditionStatus(_agreementId, _conditionId, IAgreement.ConditionState.Fulfilled);

        if ($.agreementStore.getConditionState(_agreementId, _releaseCondition) == IAgreement.ConditionState.Fulfilled)
        {
            uint256[] memory amounts;
            address[] memory receivers;
            if (plan.price.externalPriceAddress != address(0)) {
                // Recompute dynamic amounts; fees are not applied for SMART_CONTRACT_PRICE
                amounts = INeverminedExternalPrice(plan.price.externalPriceAddress).quote(_planId);
                receivers = plan.price.receivers;
            } else {
                amounts = plan.price.amounts;
                receivers = plan.price.receivers;
            }

            if (plan.price.tokenAddress == address(0)) {
                _distributeNativeTokenPayments(amounts, receivers, agreement.numberOfPurchases);
            } else {
                _distributeERC20Payments(plan.price.tokenAddress, amounts, receivers, agreement.numberOfPurchases);
            }
        } else {
            // SOME CONDITIONS ABORTED
            // Distribute the payments to the who locked the payment
            uint256[] memory _amountToRefund = new uint256[](1);

            _amountToRefund[0] = TokenUtils.calculateAmountSum(plan.price.amounts);
            address[] memory _originalSender = new address[](1);
            _originalSender[0] = agreement.agreementCreator;

            if (plan.price.tokenAddress == address(0)) {
                _distributeNativeTokenPayments(_amountToRefund, _originalSender, agreement.numberOfPurchases);
            } else {
                _distributeERC20Payments(
                    plan.price.tokenAddress, _amountToRefund, _originalSender, agreement.numberOfPurchases
                );
            }
        }
    }

    /**
     * @notice Internal function to distribute native token payments to multiple receivers
     * @param _amounts Array of payment amounts for each receiver
     * @param _receivers Array of payment receiver addresses
     * @param _multiplier Multiplier to apply to each amount (e.g., number of purchases)
     * @dev Withdraws native tokens from the vault to each receiver
     * @dev Iterates through each receiver and transfers their respective amount
     */
    function _distributeNativeTokenPayments(uint256[] memory _amounts, address[] memory _receivers, uint256 _multiplier)
        internal
    {
        DistributePaymentsConditionStorage storage $ = _getDistributePaymentsConditionStorage();

        uint256 length = _receivers.length;
        for (uint256 i = 0; i < length; i++) {
            $.vault.withdrawNativeToken(_amounts[i] * _multiplier, _receivers[i]);
        }
    }

    /**
     * @notice Internal function to distribute ERC20 token payments to multiple receivers
     * @param _erc20TokenAddress Address of the ERC20 token contract
     * @param _amounts Array of payment amounts for each receiver
     * @param _receivers Array of payment receiver addresses
     * @param _multiplier Multiplier to apply to each amount (e.g., number of purchases)
     * @dev Withdraws ERC20 tokens from the vault to each receiver
     * @dev Iterates through each receiver and transfers their respective amount
     */
    function _distributeERC20Payments(
        address _erc20TokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers,
        uint256 _multiplier
    ) internal {
        DistributePaymentsConditionStorage storage $ = _getDistributePaymentsConditionStorage();

        uint256 length = _receivers.length;
        for (uint256 i = 0; i < length; i++) {
            $.vault.withdrawERC20(_erc20TokenAddress, _amounts[i] * _multiplier, _receivers[i]);
        }
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the DistributePaymentsConditionStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getDistributePaymentsConditionStorage()
        internal
        pure
        returns (DistributePaymentsConditionStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := DISTRIBUTE_PAYMENTS_CONDITION_STORAGE_LOCATION
        }
    }
}
