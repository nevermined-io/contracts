// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/**
 * @title Agreement Template Interface
 * @author Nevermined AG
 * @notice Interface defining the core error handling for Agreement Templates in the Nevermined Protocol
 * @dev This interface establishes the error types thrown by Agreement Template contracts,
 * which are used to define structured agreements between parties in the ecosystem
 */
interface ITemplate {
    /**
     * @notice Error thrown when an invalid seed is provided for agreement ID generation
     * @dev Agreement IDs are deterministic and generated from a seed that must meet specific criteria
     * @param seed The invalid seed provided to generate the agreementId
     */
    error InvalidSeed(bytes32 seed);

    /**
     * @notice Error thrown when an invalid agentId is provided in an agreement creation process
     * @dev The agentId must correspond to a registered asset in the Nevermined ecosystem
     * @param agentId The invalid agentId of the asset related to the agreement being created
     */
    error InvalidAgentId(uint256 agentId);

    /**
     * @notice Error thrown when an invalid plan ID is provided in an agreement creation process
     * @dev The plan ID must correspond to a registered plan in the Nevermined ecosystem
     * @param planId The invalid plan ID being used in the agreement
     */
    error InvalidPlanId(uint256 planId);

    /**
     * @notice Error thrown when an invalid receiver address is provided in an agreement creation process
     * @dev The receiver address must be a valid address
     * @param receiver The invalid receiver address being used in the agreement
     */
    error InvalidReceiver(address receiver);

    /**
     * @notice Error thrown when an invalid assets registry address is provided in an agreement creation process
     * @dev The assets registry address must be a valid address
     */
    error InvalidAssetsRegistryAddress();

    /**
     * @notice Error thrown when an invalid NVMConfig address is provided in an agreement creation process
     * @dev The NVMConfig address must be a valid address
     */
    error InvalidAddress();

    /**
     * @notice Error thrown when an invalid fiat settlement condition address is provided in an agreement creation process
     * @dev The fiat settlement condition address must be a valid address
     */
    error InvalidFiatSettlementConditionAddress();

    /**
     * @notice Error thrown when an invalid transfer credits condition address is provided in an agreement creation process
     * @dev The transfer credits condition address must be a valid address
     */
    error InvalidTransferCreditsConditionAddress();

    /**
     * @notice Error thrown when an invalid agreement store address is provided in an agreement creation process
     * @dev The agreement store address must be a valid address
     */
    error InvalidAgreementStoreAddress();
}
