// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {FiatSettlementCondition} from '../conditions/FiatSettlementCondition.sol';
import {TransferCreditsCondition} from '../conditions/TransferCreditsCondition.sol';
import {IAgreement} from '../interfaces/IAgreement.sol';
import {IAsset} from '../interfaces/IAsset.sol';
import {INVMConfig} from '../interfaces/INVMConfig.sol';
import {AgreementsStore} from './AgreementsStore.sol';
import {BaseTemplate} from './BaseTemplate.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title FiatPaymentTemplate
 * @author Nevermined
 * @notice Agreement template that facilitates fiat payments for assets in the Nevermined protocol
 * @dev The FiatPaymentTemplate enables users to purchase assets/plans using traditional fiat
 *      currencies (USD, EUR, etc.) rather than cryptocurrencies. This template orchestrates
 *      the workflow between off-chain fiat payments and on-chain fulfillment.
 *
 *      The template follows a two-step execution flow:
 *      1. FiatSettlementCondition - Verified by authorized oracles after off-chain payment is confirmed
 *      2. TransferCreditsCondition - Transfers the asset credits to the buyer once settlement is verified
 *
 *      This template is particularly useful for integrating traditional payment systems like
 *      credit cards, bank transfers, or payment processors (e.g., Stripe) with blockchain-based
 *      asset management systems.
 */
contract FiatPaymentTemplate is BaseTemplate {
    bytes32 public constant NVM_CONTRACT_NAME = keccak256('FiatPaymentTemplate');

    // keccak256(abi.encode(uint256(keccak256("nevermined.fiatpaymenttemplate.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FIAT_PAYMENT_TEMPLATE_STORAGE_LOCATION =
        0xe0a010157e7dd2b09e0e2079c38064b9d6a47bc988a33749931879f4b0128000;

    /// @custom:storage-location erc7201:nevermined.fiatpaymenttemplate.storage
    struct FiatPaymentTemplateStorage {
        /// @notice Reference to the NVMConfig contract for system configuration
        INVMConfig nvmConfig;
        // Conditions required to execute this template
        /// @notice Condition that handles fiat settlement verification by authorized oracles
        FiatSettlementCondition fiatSettlementCondition;
        /// @notice Condition that handles transferring credits after payment is settled
        TransferCreditsCondition transferCondition;
        /// @notice Reference to the AgreementsStore contract for managing agreements
        AgreementsStore agreementStore;
    }

    constructor(address _trustedForwarder) BaseTemplate(_trustedForwarder) {}

    /**
     * @notice Initializes the FiatPaymentTemplate contract with required dependencies
     * @param _nvmConfigAddress Address of the NVMConfig contract
     * @param _authority Address of the AccessManager contract
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract
     * @param _agreementStoreAddress Address of the AgreementsStore contract
     * @param _fiatSettlementConditionAddress Address of the FiatSettlementCondition contract
     * @param _transferCondtionAddress Address of the TransferCreditsCondition contract
     * @dev Sets up storage references and initializes the access management system
     */
    function initialize(
        INVMConfig _nvmConfigAddress,
        IAccessManager _authority,
        IAsset _assetsRegistryAddress,
        AgreementsStore _agreementStoreAddress,
        FiatSettlementCondition _fiatSettlementConditionAddress,
        TransferCreditsCondition _transferCondtionAddress
    ) external initializer {
        __BaseTemplate_init(_assetsRegistryAddress);
        __AccessManagedUUPSUpgradeable_init(address(_authority));

        FiatPaymentTemplateStorage storage $ = _getFiatPaymentTemplateStorage();

        require(_nvmConfigAddress != INVMConfig(address(0)), InvalidAddress());
        require(
            _fiatSettlementConditionAddress != FiatSettlementCondition(address(0)),
            InvalidFiatSettlementConditionAddress()
        );
        require(
            _transferCondtionAddress != TransferCreditsCondition(address(0)), InvalidTransferCreditsConditionAddress()
        );
        require(_agreementStoreAddress != AgreementsStore(address(0)), InvalidAgreementStoreAddress());

        $.nvmConfig = _nvmConfigAddress;
        $.fiatSettlementCondition = _fiatSettlementConditionAddress;
        $.transferCondition = _transferCondtionAddress;
        $.agreementStore = _agreementStoreAddress;
    }

    /**
     * @notice Creates a new fiat payment agreement
     * @param _seed Unique seed for generating the agreement ID
     * @param _planId Identifier of the pricing plan to use
     * @param _creditsReceiver Address that will receive the credits
     * @param _params Additional parameters for the agreement
     * @dev Validates inputs, checks plan existence, and registers the agreement
     * @dev Sets up and fulfills the required conditions: fiat settlement and transfer credits
     * @dev The agreement ID is computed from multiple parameters to ensure uniqueness
     * @dev Payment verification happens off-chain through authorized settlement agents
     */
    function order(
        bytes32 _seed,
        uint256 _planId,
        address _creditsReceiver,
        uint256 _numberOfPurchases,
        bytes[] memory _params
    ) external {
        FiatPaymentTemplateStorage storage $ = _getFiatPaymentTemplateStorage();

        // Validate inputs
        if (_seed == bytes32(0)) revert InvalidSeed(_seed);
        if (_planId == 0) revert InvalidPlanId(_planId);
        if (_creditsReceiver == address(0)) revert InvalidReceiver(_creditsReceiver);

        IAsset.Plan memory plan = _getBaseTemplateStorage().assetsRegistry.getPlan(_planId);
        if (plan.lastUpdated == 0) revert IAsset.PlanNotFound(_planId);

        // Revert if the Plan has associated a template AND is not the FiatPaymentTemplate
        if (plan.price.templateAddress != address(0) && plan.price.templateAddress != address(this)) {
            revert IAsset.PlanWithInvalidTemplate(_planId, address(this));
        }

        // Calculate agreementId
        bytes32 agreementId = keccak256(
            abi.encode(NVM_CONTRACT_NAME, _msgSender(), _seed, _planId, _creditsReceiver, _numberOfPurchases, _params)
        );

        // Check if the agreement is already registered
        IAgreement.Agreement memory agreement = $.agreementStore.getAgreement(agreementId);

        if (agreement.lastUpdated != 0) {
            revert IAgreement.AgreementAlreadyRegistered(agreementId);
        }

        // Register the agreement in the AgreementsStore
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] =
            $.fiatSettlementCondition.hashConditionId(agreementId, $.fiatSettlementCondition.NVM_CONTRACT_NAME());
        conditionIds[1] = $.transferCondition.hashConditionId(agreementId, $.transferCondition.NVM_CONTRACT_NAME());

        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](2);

        // Execute before hooks
        _executeBeforeHooks(_planId, agreementId, _msgSender(), conditionIds, conditionStates, _params);

        $.agreementStore
            .register(agreementId, _msgSender(), _planId, conditionIds, conditionStates, _numberOfPurchases, _params);

        // Register fiat settlement
        _fiatSettlement(conditionIds[0], agreementId, _planId, _msgSender(), _params);
        _transferPlan(conditionIds[1], agreementId, _planId, conditionIds[0], _creditsReceiver);

        // Execute after hooks
        _executeAfterHooks(_planId, agreementId, _msgSender(), conditionIds, _params);
    }

    /**
     * @notice Internal function to fulfill the fiat settlement condition
     * @param _conditionId Identifier of the fiat settlement condition
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _senderAddress Address of the payment sender
     * @param _params Additional parameters for the settlement
     * @dev Calls the fiat settlement condition's fulfill function
     * @dev This condition will be fulfilled later by an authorized oracle confirming payment
     */
    function _fiatSettlement(
        bytes32 _conditionId,
        bytes32 _agreementId,
        uint256 _planId,
        address _senderAddress,
        bytes[] memory _params
    ) internal {
        FiatPaymentTemplateStorage storage $ = _getFiatPaymentTemplateStorage();

        $.fiatSettlementCondition.fulfill(_conditionId, _agreementId, _planId, _senderAddress, _params);
    }

    /**
     * @notice Internal function to transfer credits for a plan
     * @param _conditionId Identifier of the transfer credits condition
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _fiatSettlementCondition Identifier of the fiat settlement condition that must be fulfilled first
     * @param _receiverAddress Address of the credits receiver
     * @dev Requires the fiat settlement condition to be fulfilled first
     * @dev The transfer will execute automatically once the settlement condition is fulfilled
     */
    function _transferPlan(
        bytes32 _conditionId,
        bytes32 _agreementId,
        uint256 _planId,
        bytes32 _fiatSettlementCondition,
        address _receiverAddress
    ) internal {
        bytes32[] memory _requiredConditions = new bytes32[](1);
        FiatPaymentTemplateStorage storage $ = _getFiatPaymentTemplateStorage();

        // GAS - Is the required condition fullfil check even needed? If fiat settlement fails, the transaction will revert
        // cc - @aaitor
        _requiredConditions[0] = _fiatSettlementCondition;
        $.transferCondition.fulfill(_conditionId, _agreementId, _planId, _requiredConditions, _receiverAddress);
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the FiatPaymentTemplateStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getFiatPaymentTemplateStorage() internal pure returns (FiatPaymentTemplateStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := FIAT_PAYMENT_TEMPLATE_STORAGE_LOCATION
        }
    }
}
