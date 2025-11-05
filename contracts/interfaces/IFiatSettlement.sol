// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/**
 * @title Fiat Settlement Interface
 * @author Nevermined AG
 * @notice Interface defining the errors and functionality for processing fiat currency settlements
 * @dev This interface is used by contracts that handle settlement of transactions in fiat currencies,
 * which are processed off-chain but verified on-chain
 */
interface IFiatSettlement {
    /**
     * @notice Error thrown when invalid settlement parameters are provided
     * @dev Settlement parameters must follow a specific format to be validated correctly
     * @param params The invalid settlement parameters that were provided
     */
    error InvalidSettlementParams(bytes[] params);

    /**
     * @notice Error thrown when attempting to process a non-fiat price plan with fiat settlement
     * @dev The fiat settlement can only be used with plans explicitly marked as FIXED_FIAT_PRICE
     * @param planId The identifier of the plan that was incorrectly passed
     */
    error OnlyPlanWithFiatPrice(uint256 planId);

    /**
     * @notice Error thrown when an invalid role is provided
     * @dev The role must be a valid role for the contract
     * @param addr The address that was provided
     * @param expectedRole The expected role that was provided
     */
    error InvalidRole(address addr, uint64 expectedRole);

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
}
