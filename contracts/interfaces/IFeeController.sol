// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from './IAsset.sol';

/**
 * @title IFeeController
 * @author Nevermined AG
 * @notice Interface for fee controllers that calculate fees for plans
 */
interface IFeeController {
    /**
     * @notice Calculates the fee for a given plan
     * @param totalAmount The total amount for which the fee is calculated
     * @param priceConfig The price configuration of the plan
     * @param creditsConfig The credits configuration of the plan
     * @return fee The calculated fee amount
     * @return feeRate The fee rate applied
     * @return feeDenominator The denominator used for fee calculation
     */
    function calculateFee(
        uint256 totalAmount,
        IAsset.PriceConfig calldata priceConfig,
        IAsset.CreditsConfig calldata creditsConfig
    ) external view returns (uint256 fee, uint256 feeRate, uint256 feeDenominator);
}
