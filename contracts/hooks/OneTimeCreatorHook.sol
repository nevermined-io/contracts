// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../interfaces/IAgreement.sol';
import {IHook} from '../interfaces/IHook.sol';
import {AccessManagedUUPSUpgradeable} from '../proxy/AccessManagedUUPSUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title OneTimeCreatorHook
 * @author Nevermined AG
 * @notice Hook that ensures a creator can only create an agreement once
 * @dev This hook maintains a mapping of creators who have already created agreements
 *      and prevents them from creating additional agreements
 */
contract OneTimeCreatorHook is IHook, AccessManagedUUPSUpgradeable {
    bytes32 public constant NVM_CONTRACT_NAME = keccak256('OneTimeCreatorHook');

    // keccak256(abi.encode(uint256(keccak256("nevermined.onetimecreatorhook.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ONETIME_CREATOR_HOOK_STORAGE_LOCATION =
        0xcf4ed15caf8b9f77933f79f629613525046f29018db800fc90a0060c20918000;

    /// @custom:storage-location erc7201:nevermined.onetimecreatorhook.storage
    struct OneTimeCreatorHookStorage {
        // Mapping to track creators who have already created an agreement for a specific plan
        mapping(uint256 => mapping(address => bool)) hasCreatedAgreement;
    }

    // Event emitted when a creator creates their first agreement
    event FirstAgreementCreated(address indexed creator, bytes32 indexed agreementId);

    /**
     * @notice Error thrown when a creator attempts to create a second agreement
     * @param creator The address of the creator
     * @param agreementId The ID of the agreement being created
     */
    error CreatorAlreadyCreatedAgreement(address creator, bytes32 agreementId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with the access manager
     * @param _authority Address of the AccessManager contract
     */
    function initialize(IAccessManager _authority) external initializer {
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Hook executed before an agreement is registered
     * @param _agreementId The ID of the agreement being created
     * @param _creator The address of the agreement creator
     * @param _planId The ID of the plan
     * @dev Reverts if the creator has already created an agreement
     */
    function beforeAgreementRegistered(
        bytes32 _agreementId,
        address _creator,
        uint256 _planId,
        bytes32[] memory,
        IAgreement.ConditionState[] memory,
        bytes[] memory
    ) external restricted {
        OneTimeCreatorHookStorage storage $ = _getOneTimeCreatorHookStorage();

        require(!$.hasCreatedAgreement[_planId][_creator], CreatorAlreadyCreatedAgreement(_creator, _agreementId));

        $.hasCreatedAgreement[_planId][_creator] = true;
        emit FirstAgreementCreated(_creator, _agreementId);
    }

    /**
     * @notice Hook executed after an agreement is created
     * @param _agreementId The ID of the agreement that was created
     * @param _creator The address of the agreement creator
     * @param _planId The ID of the plan
     * @param _conditionIds Array of condition IDs for the agreement
     * @param _params Additional parameters for the agreement
     */
    function afterAgreementCreated(
        bytes32 _agreementId,
        address _creator,
        uint256 _planId,
        bytes32[] memory _conditionIds,
        bytes[] memory _params
    ) external restricted {
        // No action needed after agreement creation
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the OneTimeCreatorHookStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getOneTimeCreatorHookStorage() internal pure returns (OneTimeCreatorHookStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := ONETIME_CREATOR_HOOK_STORAGE_LOCATION
        }
    }
}
