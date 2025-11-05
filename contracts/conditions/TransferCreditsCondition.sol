// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../interfaces/IAgreement.sol';
import {IAsset} from '../interfaces/IAsset.sol';

import {NFT1155Credits} from '../token/NFT1155Credits.sol';
import {NFT1155ExpirableCredits} from '../token/NFT1155ExpirableCredits.sol';
import {TemplateCondition} from './TemplateCondition.sol';
import {
    ReentrancyGuardTransientUpgradeable
} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title TransferCreditsCondition
 * @author Nevermined
 * @notice Condition that handles the transfer of credits from payment plans to users
 * @dev This contract is responsible for minting credits to a receiver based on a predefined
 * plan configuration. The credits can be either fixed or expirable. The condition requires
 * other conditions (e.g., LockPaymentCondition) to be fulfilled before executing.
 *
 * The contract handles different credit types:
 * - EXPIRABLE: Credits with an expiration time
 * - FIXED: Credits with no expiration
 * - DYNAMIC: Currently not supported in this implementation
 */
contract TransferCreditsCondition is ReentrancyGuardTransientUpgradeable, TemplateCondition {
    // keccak256(abi.encode(uint256(keccak256("nevermined.transfercreditscondition.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TRANSFER_CREDITS_CONDITION_STORAGE_LOCATION =
        0x11e83ddb7fc8dc31a8b791a97ca4f63a6582f72d5627230814ad0de9199e1400;

    /**
     * @notice Contract name identifier used in the Nevermined ecosystem
     */
    bytes32 public constant NVM_CONTRACT_NAME = keccak256('TransferCreditsCondition');

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

    /// @custom:storage-location erc7201:nevermined.transfercreditscondition.storage
    struct TransferCreditsConditionStorage {
        IAsset assetsRegistry;
        IAgreement agreementStore;
    }

    /**
     * @notice Initializes the TransferCreditsCondition contract with required dependencies
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
        TransferCreditsConditionStorage storage $ = _getTransferCreditsConditionStorage();

        $.assetsRegistry = IAsset(_assetsRegistryAddress);
        $.agreementStore = IAgreement(_agreementStoreAddress);
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Fulfills the transfer credits condition for an agreement
     * @param _conditionId Identifier of the condition to fulfill
     * @param _agreementId Identifier of the agreement
     * @param _planId Identifier of the pricing plan
     * @param _requiredConditions Array of condition identifiers that must be fulfilled first
     * @param _receiverAddress Address that will receive the credits
     * @dev Only registered templates can call this function
     * @dev Checks if required conditions are fulfilled before proceeding
     * @dev Mints credits based on the plan's configuration (expirable or fixed)
     * @dev Reverts for unsupported credit types (dynamic)
     * @dev The condition is fulfilled before external calls to maintain security
     */
    function fulfill(
        bytes32 _conditionId,
        bytes32 _agreementId,
        uint256 _planId,
        bytes32[] memory _requiredConditions,
        address _receiverAddress
    ) external payable nonReentrant restricted {
        TransferCreditsConditionStorage storage $ = _getTransferCreditsConditionStorage();

        if ($.agreementStore.getConditionState(_agreementId, _conditionId) == IAgreement.ConditionState.Fulfilled) {
            revert IAgreement.ConditionAlreadyFulfilled(_agreementId, _conditionId);
        }

        // Check if the required conditions (LockPayment) are already fulfilled
        if (!$.agreementStore.areConditionsFulfilled(_agreementId, _conditionId, _requiredConditions)) {
            revert IAgreement.ConditionPreconditionFailed(_agreementId, _conditionId);
        }

        // Check if the plan credits config is correct
        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);
        IAgreement.Agreement memory agreement = $.agreementStore.getAgreement(_agreementId);

        // FULFILL THE CONDITION first (before external calls)
        $.agreementStore.updateConditionStatus(_agreementId, _conditionId, IAgreement.ConditionState.Fulfilled);

        // Only mint if amount is greater than zero
        if (plan.credits.amount > 0) {
            if (plan.credits.durationSecs > 0) {
                NFT1155ExpirableCredits nft1155 = NFT1155ExpirableCredits(plan.credits.nftAddress);
                nft1155.mint(
                    _receiverAddress,
                    uint256(_planId),
                    plan.credits.amount * agreement.numberOfPurchases,
                    plan.credits.durationSecs * agreement.numberOfPurchases,
                    ''
                );
            } else {
                NFT1155Credits nft1155 = NFT1155Credits(plan.credits.nftAddress);
                nft1155.mint(_receiverAddress, uint256(_planId), plan.credits.amount * agreement.numberOfPurchases, '');
            }
        }
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the TransferCreditsConditionStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getTransferCreditsConditionStorage() internal pure returns (TransferCreditsConditionStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := TRANSFER_CREDITS_CONDITION_STORAGE_LOCATION
        }
    }
}
