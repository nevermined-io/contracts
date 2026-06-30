// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {INeverminedExternalPrice} from '../../../contracts/interfaces/INeverminedExternalPrice.sol';
import {LinearPricing} from '../../../contracts/pricing/LinearPricing.sol';
import {BaseTest} from '../common/BaseTest.sol';

/// @notice Access-control and validation tests for LinearPricing (regression for security issue #195).
/// Pricing configuration must be restricted to the plan owner recorded in the AssetsRegistry, and
/// all-zero weights (which would make quote() return zeros → free credit acquisition) must be rejected.
contract LinearPricingTest is BaseTest {
    uint256 internal planId;

    function setUp() public override {
        super.setUp();
        // _createPlan() registers a plan owned by address(this)
        planId = _createPlan();
    }

    function _weights(uint256 a, uint256 b) internal pure returns (uint256[] memory w) {
        w = new uint256[](2);
        w[0] = a;
        w[1] = b;
    }

    function _receivers() internal returns (address[] memory r) {
        r = new address[](2);
        r[0] = makeAddr('r0');
        r[1] = makeAddr('r1');
    }

    // ---- access control ----

    function test_setPlan_byPlanOwner_succeeds() public {
        // address(this) owns the plan
        linearPricing.setPlan(planId, 100, 10, _receivers(), _weights(70, 30));

        uint256[] memory amounts = linearPricing.quote(planId);
        assertEq(amounts[0], 70);
        assertEq(amounts[1], 30);
    }

    function test_setPlan_revertIfNotPlanOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LinearPricing.NotPlanOwner.selector, planId, alice));
        linearPricing.setPlan(planId, 100, 10, _receivers(), _weights(70, 30));
    }

    function test_increment_byPlanOwner_succeeds() public {
        linearPricing.setPlan(planId, 100, 10, _receivers(), _weights(70, 30));
        linearPricing.increment(planId, 1);

        // total = 100 + 10*1 = 110 → [77, 33]
        uint256[] memory amounts = linearPricing.quote(planId);
        assertEq(amounts[0], 77);
        assertEq(amounts[1], 33);
    }

    function test_increment_revertIfNotPlanOwner() public {
        linearPricing.setPlan(planId, 100, 10, _receivers(), _weights(70, 30));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LinearPricing.NotPlanOwner.selector, planId, alice));
        linearPricing.increment(planId, 1);
    }

    // ---- validation ----

    function test_setPlan_revertIfZeroWeightSum() public {
        // all-zero weights would make quote() return an all-zero amounts array → free acquisition
        vm.expectRevert(LinearPricing.InvalidWeights.selector);
        linearPricing.setPlan(planId, 100, 10, _receivers(), _weights(0, 0));
    }

    function test_setPlan_revertIfNoReceivers() public {
        vm.expectRevert(LinearPricing.InvalidReceivers.selector);
        linearPricing.setPlan(planId, 100, 10, new address[](0), new uint256[](0));
    }

    function test_setPlan_revertIfPlanDoesNotExist() public {
        // An unknown plan has owner address(0) in the registry, so no caller can configure it.
        uint256 unknownPlanId = uint256(keccak256('does-not-exist'));
        vm.expectRevert(abi.encodeWithSelector(LinearPricing.NotPlanOwner.selector, unknownPlanId, address(this)));
        linearPricing.setPlan(unknownPlanId, 100, 10, _receivers(), _weights(70, 30));
    }

    function test_increment_revertIfPlanDoesNotExist() public {
        // Same guard as setPlan: an unknown plan is owned by address(0) and is unconfigurable.
        uint256 unknownPlanId = uint256(keccak256('does-not-exist'));
        vm.expectRevert(abi.encodeWithSelector(LinearPricing.NotPlanOwner.selector, unknownPlanId, address(this)));
        linearPricing.increment(unknownPlanId, 1);
    }

    function test_constructor_revertIfZeroRegistry() public {
        vm.expectRevert(LinearPricing.InvalidAssetsRegistry.selector);
        new LinearPricing(IAsset(address(0)));
    }

    // ---- ownership transfer ----

    /// @notice Resolving the owner from the registry on every call (instead of caching it in the
    /// constructor) means configuration must follow AssetsRegistry.transferPlanOwnership: after a
    /// transfer the new owner can configure pricing and the previous owner can no longer.
    function test_configuration_followsPlanOwnershipTransfer() public {
        // address(this) currently owns planId; hand it to alice.
        assetsRegistry.transferPlanOwnership(planId, alice);

        // New owner can configure and advance the curve.
        vm.prank(alice);
        linearPricing.setPlan(planId, 100, 10, _receivers(), _weights(70, 30));
        vm.prank(alice);
        linearPricing.increment(planId, 1);
        uint256[] memory amounts = linearPricing.quote(planId); // total 110 → [77, 33]
        assertEq(amounts[0], 77);
        assertEq(amounts[1], 33);

        // The previous owner is now rejected on both configuration functions.
        vm.expectRevert(abi.encodeWithSelector(LinearPricing.NotPlanOwner.selector, planId, address(this)));
        linearPricing.setPlan(planId, 100, 10, _receivers(), _weights(70, 30));
        vm.expectRevert(abi.encodeWithSelector(LinearPricing.NotPlanOwner.selector, planId, address(this)));
        linearPricing.increment(planId, 1);
    }

    /// @notice quote() reverts for a plan that exists in the registry but was never priced here,
    /// locking in that the removed zero-weight branch stays unreachable.
    function test_quote_revertIfPlanNotPriced() public {
        vm.expectRevert(abi.encodeWithSelector(INeverminedExternalPrice.UnsupportedPlanId.selector, planId));
        linearPricing.quote(planId);
    }
}
