// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/**
 * @title Agreement Management Interface
 * @author Nevermined AG
 * @notice Interface defining the core agreement management functionality for the Nevermined Protocol
 * @dev This interface establishes the data structures, events, errors, and functions required
 * for creating and managing agreements between parties in the Nevermined ecosystem
 */
interface IAgreement {
    /**
     * @notice Event that is emitted when a new Agreement is stored
     * @param agreementId The unique identifier of the agreement
     * @param creator The address of the account storing the agreement
     */
    event AgreementRegistered(bytes32 indexed agreementId, address indexed creator);

    /**
     * @notice Event that is emitted when a condition status is updated
     * @param agreementId The unique identifier of the agreement
     * @param conditionId The unique identifier of the condition
     * @param state The new state of the condition
     */
    event ConditionUpdated(bytes32 indexed agreementId, bytes32 indexed conditionId, ConditionState state);

    /**
     * @notice Error thrown when attempting to register an agreement with an ID that already exists
     * @param agreementId The identifier of the agreement that already exists
     */
    error AgreementAlreadyRegistered(bytes32 agreementId);

    /**
     * @notice Error thrown when attempting to access an agreement that doesn't exist
     * @param agreementId The identifier of the non-existent agreement
     */
    error AgreementNotFound(bytes32 agreementId);

    /**
     * @notice Error thrown when attempting to access a condition that doesn't exist within an agreement
     * @param conditionId The identifier of the non-existent condition
     */
    error ConditionIdNotFound(bytes32 conditionId);

    /**
     * @notice Error thrown when the preconditions for a condition are not met
     * @param agreementId The identifier of the agreement associated with the condition
     * @param conditionId The identifier of the condition with unmet preconditions
     */
    error ConditionPreconditionFailed(bytes32 agreementId, bytes32 conditionId);

    /**
     * @notice Error thrown when the caller does not have the required role to perform the operation
     * @param caller The address of the caller
     */
    error OnlyTemplateOrConditionRole(address caller);

    /**
     * @notice Error thrown when the length of the conditionIds and conditionStates arrays are not the same
     */
    error InvalidConditionIdsAndStatesLength();

    /**
     * @notice Error thrown when the number of purchases is invalid. It should be greater than zero.
     */
    error InvalidNumberOfPurchases();

    /**
     * @notice Error thrown when a condition has already been fulfilled
     * @param agreementId The identifier of the agreement
     * @param conditionId The identifier of the condition that has already been fulfilled
     */
    error ConditionAlreadyFulfilled(bytes32 agreementId, bytes32 conditionId);

    /**
     * @notice Error thrown when msg.value is not zero for ERC20 payments
     */
    error MsgValueMustBeZeroForERC20Payments();

    /**
     * @title ConditionState
     * @notice Enum representing the possible states of a condition within an agreement
     * @dev The state transitions typically follow Uninitialized -> Unfulfilled -> Fulfilled,
     * with Aborted being a possible end state for conditions that cannot be fulfilled
     */
    enum ConditionState {
        /**
         * @notice Initial state of a condition before it's been initialized
         */
        Uninitialized,
        /**
         * @notice Condition has been initialized but not yet fulfilled
         */
        Unfulfilled,
        /**
         * @notice Condition has been successfully fulfilled
         */
        Fulfilled,
        /**
         * @notice Condition cannot be fulfilled and has been aborted
         */
        Aborted
    }

    /**
     * @title Agreement
     * @notice Core data structure representing an agreement between parties
     * @dev Stores all the data necessary to track and execute the terms of an agreement
     */
    struct Agreement {
        /**
         * @notice The plan ID associated with this agreement
         */
        uint256 planId;
        /**
         * @notice The address of the account that created the agreement
         */
        address agreementCreator;
        /**
         * @notice Array of condition IDs associated with this agreement
         */
        bytes32[] conditionIds;
        /**
         * @notice Array of states for each condition in the conditionIds array
         */
        ConditionState[] conditionStates;
        /**
         * @notice Array of encoded parameters for each condition
         */
        bytes[] params;
        /**
         * @notice Timestamp of when the agreement was last updated
         */
        uint256 lastUpdated;
        /**
         * @notice The number of times this agreement has been purchased
         */
        uint256 numberOfPurchases;
    }

    /**
     * @notice Retrieves the full details of an agreement
     * @param _agreementId The unique identifier of the agreement
     * @return The Agreement struct containing all agreement details
     */
    function getAgreement(bytes32 _agreementId) external view returns (Agreement memory);

    /**
     * @notice Retrieves the current state of a specific condition within an agreement
     * @param _agreementId The unique identifier of the agreement
     * @param _conditionId The unique identifier of the condition
     * @return state The current state of the condition
     */
    function getConditionState(bytes32 _agreementId, bytes32 _conditionId) external view returns (ConditionState state);

    /**
     * @notice Updates the status of a condition within an agreement
     * @dev Only authorized parties (typically condition contracts) can update condition states
     * @param _agreementId The unique identifier of the agreement
     * @param _conditionId The unique identifier of the condition
     * @param _state The new state to set for the condition
     */
    function updateConditionStatus(bytes32 _agreementId, bytes32 _conditionId, ConditionState _state) external;

    /**
     * @notice Checks if an agreement exists in the registry
     * @param _agreementId The unique identifier of the agreement
     * @return Boolean indicating whether the agreement exists
     */
    function agreementExists(bytes32 _agreementId) external view returns (bool);

    /**
     * @notice Checks if all dependent conditions are fulfilled for a given condition
     * @dev Used to verify that preconditions are met before a condition can be executed
     * @param _agreementId The unique identifier of the agreement
     * @param _conditionId The unique identifier of the condition being checked
     * @param _dependantConditions Array of condition IDs that must be fulfilled first
     * @return Boolean indicating whether all dependent conditions are fulfilled
     */
    function areConditionsFulfilled(bytes32 _agreementId, bytes32 _conditionId, bytes32[] memory _dependantConditions)
        external
        view
        returns (bool);
}
