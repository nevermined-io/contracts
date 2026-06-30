// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../interfaces/IAsset.sol';
import {INeverminedExternalPrice} from '../interfaces/INeverminedExternalPrice.sol';

/**
 * @title LinearPricing
 * @notice Simple external pricing contract that returns amounts growing linearly with a plan-specific counter
 * @dev For simplicity, this contract maintains an internal purchased counter per plan. Integrations may
 *      call increment after successful purchase distribution to advance the curve for next quotes.
 *
 *      Pricing configuration (`setPlan`/`increment`) is restricted to the plan owner recorded in the
 *      AssetsRegistry. This prevents an unprivileged third party from rewriting another plan's price
 *      (e.g. setting it to zero for free credit acquisition, or inflating it to deny service).
 */
contract LinearPricing is INeverminedExternalPrice {
    struct PlanParams {
        uint256 base; // base amount
        uint256 slope; // slope per unit purchased
        address[] receivers; // distribution receivers (excluding protocol fee)
        uint256[] weights; // relative weights for splitting the total among receivers
    }

    /**
     * @notice AssetsRegistry used to resolve the owner authorized to configure each plan's pricing
     */
    // solhint-disable-next-line immutable-vars-naming
    IAsset public immutable assetsRegistry;

    mapping(uint256 => PlanParams) public plans;
    mapping(uint256 => uint256) public purchased; // simple counter per plan

    error InvalidWeights();
    error InvalidReceivers();
    error InvalidAssetsRegistry();

    /**
     * @notice Error thrown when a caller other than the plan owner attempts to configure pricing
     * @param planId The plan being configured
     * @param caller The unauthorized caller
     */
    error NotPlanOwner(uint256 planId, address caller);

    /**
     * @notice Restricts configuration to the plan owner recorded in the AssetsRegistry
     * @param planId The plan whose owner is authorized
     * @dev For an unknown plan the registry returns a zero-initialized plan (owner == address(0)), so the
     *      require always fails — no caller can be address(0). Pricing therefore cannot be set for plans
     *      that do not exist, and only the registry-recorded owner can configure an existing plan.
     */
    modifier onlyPlanOwner(uint256 planId) {
        address owner = assetsRegistry.getPlan(planId).owner;
        require(msg.sender == owner, NotPlanOwner(planId, msg.sender));
        _;
    }

    /**
     * @notice Binds the pricing contract to the AssetsRegistry that owns the plans it prices
     * @param _assetsRegistry Address of the AssetsRegistry contract
     */
    constructor(IAsset _assetsRegistry) {
        require(address(_assetsRegistry) != address(0), InvalidAssetsRegistry());
        assetsRegistry = _assetsRegistry;
    }

    /**
     * @notice Configures the linear pricing parameters for a plan
     * @param planId The plan to configure
     * @param base Base amount of the curve
     * @param slope Per-unit increase applied to the purchased counter
     * @param receivers Distribution receivers (excluding protocol fee)
     * @param weights Relative weights for splitting the total among receivers; the sum must be non-zero
     * @dev Only the plan owner (per the AssetsRegistry) may configure pricing
     */
    function setPlan(
        uint256 planId,
        uint256 base,
        uint256 slope,
        address[] calldata receivers,
        uint256[] calldata weights
    ) external onlyPlanOwner(planId) {
        if (receivers.length == 0) revert InvalidReceivers();
        if (receivers.length != weights.length) revert InvalidWeights();

        uint256 sumWeights = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            sumWeights += weights[i];
        }
        // Require a non-zero weight sum so quote() always has a non-zero divisor; this is what lets the
        // zero-sum guard be omitted from quote(). (Free acquisition by a third party is prevented by the
        // onlyPlanOwner gate; an owner can still choose base == 0 && slope == 0 for their own plan.)
        if (sumWeights == 0) revert InvalidWeights();

        plans[planId] = PlanParams({base: base, slope: slope, receivers: receivers, weights: weights});
    }

    /**
     * @notice Advances the purchased counter for a plan, moving the curve to its next quote
     * @param planId The plan whose counter is advanced
     * @param amount The amount to add to the purchased counter
     * @dev Only the plan owner (per the AssetsRegistry) may advance the counter
     */
    function increment(uint256 planId, uint256 amount) external onlyPlanOwner(planId) {
        purchased[planId] += amount;
    }

    /// @inheritdoc INeverminedExternalPrice
    function quote(uint256 planId) external view override returns (uint256[] memory amounts) {
        PlanParams storage p = plans[planId];
        if (p.receivers.length == 0) revert UnsupportedPlanId(planId);

        // total = base + slope * purchased
        uint256 total = p.base + (p.slope * purchased[planId]);

        // sum weights — setPlan enforces sumWeights > 0 for any stored plan, so the division below is safe
        uint256 sumWeights = 0;
        for (uint256 i = 0; i < p.weights.length; i++) {
            sumWeights += p.weights[i];
        }

        amounts = new uint256[](p.receivers.length);
        for (uint256 i = 0; i < p.receivers.length; i++) {
            amounts[i] = (total * p.weights[i]) / sumWeights;
        }
    }
}
