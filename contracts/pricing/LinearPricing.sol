// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {INeverminedExternalPrice} from '../interfaces/INeverminedExternalPrice.sol';

/**
 * @title LinearPricing
 * @notice Simple external pricing contract that returns amounts growing linearly with a plan-specific counter
 * @dev For simplicity, this contract maintains an internal purchased counter per plan. Integrations may
 *      call increment after successful purchase distribution to advance the curve for next quotes.
 */
contract LinearPricing is INeverminedExternalPrice {
    struct PlanParams {
        uint256 base; // base amount
        uint256 slope; // slope per unit purchased
        address[] receivers; // distribution receivers (excluding protocol fee)
        uint256[] weights; // relative weights for splitting the total among receivers
    }

    mapping(uint256 => PlanParams) public plans;
    mapping(uint256 => uint256) public purchased; // simple counter per plan

    error InvalidWeights();
    error InvalidReceivers();

    function setPlan(
        uint256 planId,
        uint256 base,
        uint256 slope,
        address[] calldata receivers,
        uint256[] calldata weights
    ) external {
        if (receivers.length == 0) revert InvalidReceivers();
        if (receivers.length != weights.length) revert InvalidWeights();

        plans[planId] = PlanParams({base: base, slope: slope, receivers: receivers, weights: weights});
    }

    function increment(uint256 planId, uint256 amount) external {
        purchased[planId] += amount;
    }

    function quote(uint256 planId) external view override returns (uint256[] memory amounts) {
        PlanParams storage p = plans[planId];
        if (p.receivers.length == 0) revert UnsupportedPlanId(planId);

        // total = base + slope * purchased
        uint256 total = p.base + (p.slope * purchased[planId]);

        // sum weights
        uint256 sumWeights = 0;
        for (uint256 i = 0; i < p.weights.length; i++) {
            sumWeights += p.weights[i];
        }
        if (sumWeights == 0) {
            amounts = new uint256[](p.receivers.length);
            return amounts;
        }

        amounts = new uint256[](p.receivers.length);
        for (uint256 i = 0; i < p.receivers.length; i++) {
            amounts[i] = (total * p.weights[i]) / sumWeights;
        }
    }
}
