// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {FIAT_SETTLEMENT_ROLE} from '../common/Roles.sol';
import {IAgreement} from '../interfaces/IAgreement.sol';
import {IAsset} from '../interfaces/IAsset.sol';
import {IFiatSettlement} from '../interfaces/IFiatSettlement.sol';
import {TemplateCondition} from './TemplateCondition.sol';
import {
    ReentrancyGuardTransientUpgradeable
} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title FiatSettlementCondition
 * @author Nevermined
 * @notice Condition that handles fiat payment settlements for agreements
 * @dev This contract enables integration with traditional payment systems by allowing
 * authorized accounts to confirm fiat payments for agreements. Unlike crypto payments
 * that are handled by LockPaymentCondition, this contract deals with off-chain fiat
 * payments processed through payment providers like Stripe.
 *
 * The contract utilizes a role-based permission system where only accounts with the
 * FIAT_SETTLEMENT_ROLE can fulfill the condition, providing a bridge between
 * traditional payment rails and the Nevermined protocol.
 *
 * This pattern enables hybrid payment models where users can pay in fiat currency
 * while still participating in the token-based ecosystem.
 */
contract FiatSettlementCondition is ReentrancyGuardTransientUpgradeable, TemplateCondition, IFiatSettlement {
    /**
     * @notice Contract name identifier used in the Nevermined ecosystem
     */
    bytes32 public constant NVM_CONTRACT_NAME = keccak256('FiatSettlementCondition');

    // keccak256(abi.encode(uint256(keccak256("nevermined.fiatsettlementcondition.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FIAT_SETTLEMENT_CONDITION_STORAGE_LOCATION =
        0x095caca12ac306f9c5f97a85684602873cc5f88a30652025e72016cece54ad00;

    /// @custom:storage-location erc7201:nevermined.fiatsettlementcondition.storage
    struct FiatSettlementConditionStorage {
        IAsset assetsRegistry;
        IAgreement agreementStore;
    }

    /**
     * @notice Initializes the FiatSettlementCondition contract with required dependencies
     * @param _authority Address of the AccessManager contract for role-based access control
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract for accessing plan information
     * @param _agreementStoreAddress Address of the AgreementsStore contract for managing agreement state
     * @dev Sets up storage references and initializes the access management system
     */
    function initialize(IAccessManager _authority, IAsset _assetsRegistryAddress, IAgreement _agreementStoreAddress)
        external
        initializer
    {
        require(_assetsRegistryAddress != IAsset(address(0)), InvalidAssetsRegistryAddress());
        require(_agreementStoreAddress != IAgreement(address(0)), InvalidAgreementStoreAddress());

        ReentrancyGuardTransientUpgradeable.__ReentrancyGuardTransient_init();
        FiatSettlementConditionStorage storage $ = _getFiatSettlementConditionStorage();

        $.assetsRegistry = _assetsRegistryAddress;
        $.agreementStore = _agreementStoreAddress;
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Fulfills the fiat settlement condition for an agreement
     * @param _conditionId Identifier of the condition to fulfill
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _senderAddress Address of the account that verified the fiat payment
     * @param _params Additional parameters for the settlement (could include payment reference, timestamps, etc.)
     * @dev Only registered templates can call this function
     * @dev Only accounts with FIAT_SETTLEMENT_ROLE can fulfill this condition
     * @dev The sender cannot be the owner of the plan to prevent self-settlement
     * @dev Verifies that the plan has a fiat price type (FIXED_FIAT_PRICE)
     * @dev Validates settlement parameters before fulfilling the condition
     */
    function fulfill(
        bytes32 _conditionId,
        bytes32 _agreementId,
        uint256 _planId,
        address _senderAddress,
        bytes[] memory _params
    ) external nonReentrant restricted {
        FiatSettlementConditionStorage storage $ = _getFiatSettlementConditionStorage();

        // Check if the agreementId is registered in the AssetsRegistry
        if (!$.agreementStore.agreementExists(_agreementId)) {
            revert IAgreement.AgreementNotFound(_agreementId);
        }

        // Check if the plan config (token, amount) is correct
        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);

        // Only an account with FIAT_SETTLEMENT_ROLE and not being the owner can fulfill the Fiat Settlement condition
        (bool hasRole,) = IAccessManager(address(authority())).hasRole(FIAT_SETTLEMENT_ROLE, _senderAddress);
        require(hasRole || plan.owner == _senderAddress, InvalidRole(_senderAddress, FIAT_SETTLEMENT_ROLE));

        if (plan.price.isCrypto) {
            revert OnlyPlanWithFiatPrice(_planId);
        }

        if ($.agreementStore.getConditionState(_agreementId, _conditionId) == IAgreement.ConditionState.Fulfilled) {
            revert IAgreement.ConditionAlreadyFulfilled(_agreementId, _conditionId);
        }

        // Check if the params are valid
        if (!_areSettlementParamsValid(_params)) revert InvalidSettlementParams(_params);

        // FULFILL THE CONDITION
        $.agreementStore.updateConditionStatus(_agreementId, _conditionId, IAgreement.ConditionState.Fulfilled);
    }

    /**
     * @notice Internal function to validate settlement parameters
     * @return Boolean indicating whether the parameters are valid
     * @dev Currently returns true by default, validation to be implemented
     */
    function _areSettlementParamsValid(
        bytes[] memory /*_params*/
    )
        internal
        pure
        returns (bool)
    {
        // TODO: Implement some level of params validation
        return true;
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the FiatSettlementConditionStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getFiatSettlementConditionStorage() internal pure returns (FiatSettlementConditionStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := FIAT_SETTLEMENT_CONDITION_STORAGE_LOCATION
        }
    }
}
