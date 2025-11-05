// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {AccessManagedUUPSUpgradeable} from '../proxy/AccessManagedUUPSUpgradeable.sol';

/**
 * @title TemplateCondition
 * @author Nevermined
 * @notice Base abstract contract for all condition contracts in the Nevermined ecosystem
 * @dev All condition contracts inherit from this base contract, which provides common
 * functionality and access control through the AccessManagedUUPSUpgradeable contract.
 * This design allows for a consistent approach to condition management and permissions across
 * the entire Nevermined protocol.
 */
abstract contract TemplateCondition is AccessManagedUUPSUpgradeable {
    /**
     * @notice Generates a unique condition identifier from an agreement ID and condition name
     * @param _agreementId The unique identifier of the agreement
     * @param _conditionName The name of the condition as a bytes32
     * @return bytes32 A unique hash representing the condition within the agreement context
     * @dev Used to create deterministic identifiers for conditions within agreements
     */
    function hashConditionId(bytes32 _agreementId, bytes32 _conditionName) external pure returns (bytes32) {
        return keccak256(abi.encode(_agreementId, _conditionName));
    }
}
