// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {DistributePaymentsCondition} from '../conditions/DistributePaymentsCondition.sol';
import {LockPaymentCondition} from '../conditions/LockPaymentCondition.sol';
import {IAgreement} from '../interfaces/IAgreement.sol';

import {IAsset} from '../interfaces/IAsset.sol';
import {INVMConfig} from '../interfaces/INVMConfig.sol';
import {AgreementsStore} from './AgreementsStore.sol';
import {BaseTemplate} from './BaseTemplate.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title PayAsYouGoTemplate
 * @author Nevermined
 * @notice Agreement template that facilitates on-chain cryptocurrency payments for assets
 * @dev The PayAsYouGoTemplate enables users to purchase assets/plans using cryptocurrency,
 *      with the payment flow handled entirely on-chain. This template orchestrates the
 *      two-step payment and asset transfer workflow through conditions:
 *
 *      1. LockPaymentCondition - Locks the buyer's payment in a vault
 *      2. DistributePaymentsCondition - Distributes the locked payment to the asset owner
 *
 *      This creates an atomic swap between payment and asset access rights, ensuring
 *      that both parties (buyer and seller) are protected throughout the transaction.
 *      Unlike the FiatPaymentTemplate, all steps happen on-chain without requiring
 *      off-chain verification by oracles.
 */
contract PayAsYouGoTemplate is BaseTemplate {
    bytes32 public constant NVM_CONTRACT_NAME = keccak256('PayAsYouGoTemplate');

    // keccak256(abi.encode(uint256(keccak256("nevermined.payasyougotemplate.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PAY_AS_YOU_GO_TEMPLATE_STORAGE_LOCATION =
        0x1c8e77afbc92450058709fbf173782622a617d5fc09c7ba6fdfca3c79e5eaf00;

    /// @custom:storage-location erc7201:nevermined.payasyougotemplate.storage
    struct PayAsYouGoTemplateStorage {
        /// @notice Reference to the NVMConfig contract for system configuration
        INVMConfig nvmConfig;
        // Conditions required to execute this template
        /// @notice Condition that locks the payment in a secure vault
        LockPaymentCondition lockPaymentCondition;
        /// @notice Condition that distributes the locked payment to the asset owner
        DistributePaymentsCondition distributePaymentsCondition;
        /// @notice Reference to the AgreementsStore contract for managing agreements
        AgreementsStore agreementStore;
    }

    constructor(address _trustedForwarder) BaseTemplate(_trustedForwarder) {}

    /**
     * @notice Initializes the PayAsYouGoTemplate contract with required dependencies
     * @param _nvmConfigAddress Address of the NVMConfig contract
     * @param _authority Address of the AccessManager contract
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract
     * @param _agreementStoreAddress Address of the AgreementsStore contract
     * @param _lockPaymentConditionAddress Address of the LockPaymentCondition contract
     * @param _distributePaymentsCondition Address of the DistributePaymentsCondition contract
     * @dev Sets up storage references and initializes the access management system
     */
    function initialize(
        INVMConfig _nvmConfigAddress,
        IAccessManager _authority,
        IAsset _assetsRegistryAddress,
        AgreementsStore _agreementStoreAddress,
        LockPaymentCondition _lockPaymentConditionAddress,
        DistributePaymentsCondition _distributePaymentsCondition
    ) external initializer {
        __BaseTemplate_init(_assetsRegistryAddress);
        PayAsYouGoTemplateStorage storage $ = _getPayAsYouGoTemplateStorage();

        $.nvmConfig = _nvmConfigAddress;
        $.agreementStore = _agreementStoreAddress;
        $.lockPaymentCondition = _lockPaymentConditionAddress;
        $.distributePaymentsCondition = _distributePaymentsCondition;
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Creates a new pay-as-you-go agreement
     * @param _seed Unique seed for generating the agreement ID
     * @param _planId Identifier of the pricing plan to use
     * @param _params Additional parameters for the agreement
     * @dev Validates inputs, checks plan existence, and registers the agreement
     * @dev Sets up and fulfills the required conditions: lock payment, transfer credits, and distribute payments
     * @dev The agreement ID is computed from multiple parameters to ensure uniqueness
     * @dev Payable function that accepts the payment amount for the plan in native cryptocurrency
     */
    function order(bytes32 _seed, uint256 _planId, bytes[] memory _params) external payable {
        PayAsYouGoTemplateStorage storage $ = _getPayAsYouGoTemplateStorage();

        // Validate inputs
        if (_seed == bytes32(0)) revert InvalidSeed(_seed);
        if (_planId == 0) revert InvalidPlanId(_planId);

        // Check if the Plan is registered in the AssetsRegistry
        if (!_getBaseTemplateStorage().assetsRegistry.planExists(_planId)) {
            revert IAsset.PlanNotFound(_planId);
        }

        // Check if the Plan has associated the PayAsYouGoTemplate
        if (!_getBaseTemplateStorage().assetsRegistry.isPlanTemplate(_planId, address(this))) {
            revert IAsset.PlanWithInvalidTemplate(_planId, address(this));
        }

        // Calculate agreementId
        bytes32 agreementId = keccak256(abi.encode(NVM_CONTRACT_NAME, _msgSender(), _seed, _planId, _params));

        // Check if the agreement is already registered
        IAgreement.Agreement memory agreement = $.agreementStore.getAgreement(agreementId);

        if (agreement.lastUpdated != 0) {
            revert IAgreement.AgreementAlreadyRegistered(agreementId);
        }

        // Register the agreement in the AgreementsStore
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] =
            $.lockPaymentCondition.hashConditionId(agreementId, $.lockPaymentCondition.NVM_CONTRACT_NAME());
        conditionIds[1] = $.distributePaymentsCondition
            .hashConditionId(agreementId, $.distributePaymentsCondition.NVM_CONTRACT_NAME());

        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](2);

        // Execute before hooks
        _executeBeforeHooks(_planId, agreementId, _msgSender(), conditionIds, conditionStates, _params);

        $.agreementStore.register(agreementId, _msgSender(), _planId, conditionIds, conditionStates, 1, _params);

        // Lock the payment
        _lockPayment(conditionIds[0], agreementId, _planId, _msgSender());
        _distributePayments(conditionIds[1], agreementId, _planId, conditionIds[0], conditionIds[0]);

        // Execute after hooks
        _executeAfterHooks(_planId, agreementId, _msgSender(), conditionIds, _params);
    }

    /**
     * @notice Internal function to lock payment for an agreement
     * @param _conditionId Identifier of the lock payment condition
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _senderAddress Address of the payment sender
     * @dev Forwards the message value to the lock payment condition
     * @dev The payment remains locked until the transfer condition is fulfilled
     */
    function _lockPayment(bytes32 _conditionId, bytes32 _agreementId, uint256 _planId, address _senderAddress)
        internal
    {
        PayAsYouGoTemplateStorage storage $ = _getPayAsYouGoTemplateStorage();

        $.lockPaymentCondition.fulfill{value: msg.value}(_conditionId, _agreementId, _planId, _senderAddress);
    }

    /**
     * @notice Internal function to distribute locked payments
     * @param _conditionId Identifier of the distribute payments condition
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _lockPaymentCondition Identifier of the lock payment condition
     * @param _releaseCondition Identifier of the release condition (transfer credits)
     * @dev Requires both lock payment and transfer credits conditions to be fulfilled first
     * @dev Releases the locked payment to the asset owner, completing the transaction
     */
    function _distributePayments(
        bytes32 _conditionId,
        bytes32 _agreementId,
        uint256 _planId,
        bytes32 _lockPaymentCondition,
        bytes32 _releaseCondition
    ) internal {
        PayAsYouGoTemplateStorage storage $ = _getPayAsYouGoTemplateStorage();

        $.distributePaymentsCondition
            .fulfill(_conditionId, _agreementId, _planId, _lockPaymentCondition, _releaseCondition);
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the FixedPaymentTemplateStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getPayAsYouGoTemplateStorage() internal pure returns (PayAsYouGoTemplateStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := PAY_AS_YOU_GO_TEMPLATE_STORAGE_LOCATION
        }
    }
}
