// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {FIAT_SETTLEMENT_ROLE} from '../../../contracts/common/Roles.sol';
import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IFiatSettlement} from '../../../contracts/interfaces/IFiatSettlement.sol';
import {BaseTest} from '../common/BaseTest.sol';

import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';

contract FiatSettlementConditionTest is BaseTest {
    address public receiver;

    function setUp() public override {
        super.setUp();
    }

    function test_fulfill_noTemplateRevert() public {
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);

        fiatSettlementCondition.fulfill(bytes32(0), bytes32(0), 1, address(this), new bytes[](0));
    }

    function test_fulfill_noAgreementRevert() public {
        _grantTemplateRole(address(this));

        vm.expectPartialRevert(IAgreement.AgreementNotFound.selector);
        fiatSettlementCondition.fulfill(bytes32(0), bytes32(0), 1, address(this), new bytes[](0));
    }

    function test_fulfill_noSettlementRoleRevert() public {
        _grantTemplateRole(address(this));

        bytes32 agreementId = _order(address(this), 1);
        vm.expectPartialRevert(IFiatSettlement.InvalidRole.selector);
        fiatSettlementCondition.fulfill(bytes32(0), agreementId, 1, address(this), new bytes[](0));
    }

    function test_fulfill_invalidPriceTypeRevert() public {
        _grantTemplateRole(address(this));
        _grantRole(FIAT_SETTLEMENT_ROLE, address(this));

        uint256 planId = _createExpirablePlan(1, 10);
        bytes32 agreementId = _order(address(this), planId);
        vm.expectPartialRevert(IFiatSettlement.OnlyPlanWithFiatPrice.selector);
        fiatSettlementCondition.fulfill(bytes32(0), agreementId, planId, address(this), new bytes[](0));
    }

    function test_fulfill_okay() public {
        address caller = address(1);
        _grantTemplateRole(address(this));
        _grantRole(FIAT_SETTLEMENT_ROLE, caller);
        _grantConditionRole(address(fiatSettlementCondition));

        uint256 planId = _createPlan();

        bytes32 agreementId = _order(caller, planId);

        fiatSettlementCondition.fulfill(keccak256('abc'), agreementId, planId, caller, new bytes[](0));
    }

    function test_fulfill_revertIfConditionAlreadyFulfilled() public {
        // Grant condition role to this contract
        _grantConditionRole(address(this));

        // Create a plan
        uint256 planId = _createPlan();

        // Get the condition ID first
        bytes32 agreementId = keccak256('123');
        bytes32 conditionId =
            fiatSettlementCondition.hashConditionId(agreementId, fiatSettlementCondition.NVM_CONTRACT_NAME());

        // Register the agreement with the correct condition ID
        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = conditionId;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        _grantTemplateRole(address(this));
        agreementsStore.register(agreementId, address(this), planId, conditionIds, conditionStates, 1, new bytes[](0));

        // Fulfill the condition first time
        fiatSettlementCondition.fulfill(conditionId, agreementId, planId, address(this), new bytes[](0));

        // Try to fulfill again
        vm.expectRevert(abi.encodeWithSelector(IAgreement.ConditionAlreadyFulfilled.selector, agreementId, conditionId));
        fiatSettlementCondition.fulfill(conditionId, agreementId, planId, address(this), new bytes[](0));
    }
}
