// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/**
 * @title Nevermined External Price Interface
 * @author Nevermined AG
 * @notice Interface for external smart contracts that provide dynamic pricing for Nevermined plans
 * @dev This interface defines the standard contract that external price providers must implement
 * when the price config's price type is set to SMART_CONTRACT_PRICE. The contract should be
 * capable of calculating dynamic prices based on plan IDs and returning the payment amounts
 * array that corresponds to the payment distribution for the plan.
 */
interface INeverminedExternalPrice {
    /**
     * @notice Retrieves the payment amounts for a given plan ID
     * @dev This function should return an array of payment amounts that can be used
     * by the Nevermined protocol to process payments. The amounts should correspond
     * to the payment distribution for the plan.
     * @param planId The unique identifier of the plan to get pricing for
     * @return amounts The array of payment amounts for the plan
     */
    function quote(uint256 planId) external view returns (uint256[] memory amounts);

    /**
     * @notice Emitted when a price quote is requested for a plan
     * @param planId The plan ID that was quoted
     * @param caller The address that requested the quote
     * @param amounts The payment amounts that were returned
     */
    event PriceQuoted(uint256 indexed planId, address indexed caller, uint256[] amounts);

    /**
     * @notice Error thrown when a plan ID is not supported by this price provider
     * @param planId The unsupported plan ID
     */
    error UnsupportedPlanId(uint256 planId);

    /**
     * @notice Error thrown when the price calculation fails
     * @param planId The plan ID that failed to calculate
     * @param reason The reason for the failure
     */
    error PriceCalculationFailed(uint256 planId, string reason);
}
