// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {IAgreement} from './IAgreement.sol';

/**
 * @title IHook
 * @author Nevermined
 * @notice Interface for agreement hooks that can be executed before and after agreement creation
 */
interface IHook {
    /**
     * @notice Called before an agreement is registered in the agreement store
     * @param agreementId The ID of the agreement being created
     * @param creator The address of the agreement creator
     * @param planId The ID of the plan being used
     * @param conditionIds Array of condition IDs for the agreement
     * @param conditionStates Array of condition states for the agreement
     * @param params Additional parameters for the agreement
     * @dev This function can be used to validate or modify agreement parameters before registration
     * @dev Should revert if validation fails
     */
    function beforeAgreementRegistered(
        bytes32 agreementId,
        address creator,
        uint256 planId,
        bytes32[] calldata conditionIds,
        IAgreement.ConditionState[] calldata conditionStates,
        bytes[] calldata params
    ) external;

    /**
     * @notice Called after an agreement is fully created and all conditions are set up
     * @param agreementId The ID of the agreement that was created
     * @param creator The address of the agreement creator
     * @param planId The ID of the plan used
     * @param conditionIds Array of condition IDs for the agreement
     * @param params Additional parameters for the agreement
     * @dev This function can be used to perform any post-creation actions
     */
    function afterAgreementCreated(
        bytes32 agreementId,
        address creator,
        uint256 planId,
        bytes32[] calldata conditionIds,
        bytes[] calldata params
    ) external;
}
