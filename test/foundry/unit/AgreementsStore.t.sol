// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';

import {AgreementsStoreV2} from '../../../contracts/mock/AgreementsStoreV2.sol';
import {BaseTest} from '../common/BaseTest.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';

contract AgreementsStoreTest is BaseTest {
    address public template;
    address public user;
    bytes32 public agreementId;
    bytes32 public conditionId;
    bytes32 public requiredConditionId;

    function setUp() public override {
        super.setUp();

        // Setup addresses
        template = makeAddr('template');
        user = makeAddr('user');

        // Grant template role
        _grantTemplateRole(template);

        // Create agreement ID
        agreementId = keccak256('test-agreement');

        // Create condition IDs
        conditionId = keccak256('test-condition');
        requiredConditionId = keccak256('required-condition');
    }

    function test_hashAgreement() public view {
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        assertFalse(testAgreementId == bytes32(0));
    }

    function test_getNonExistentAgreement() public view {
        bytes32 testAgreementId = bytes32(uint256(1));
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(testAgreementId);
        assertEq(agreement.agreementCreator, address(0));
        assertEq(agreement.lastUpdated, 0);
    }

    function test_onlyTemplatesCanRegisterAgreements() public {
        bytes32 testAgreementId = bytes32(uint256(1));

        // Should revert if not called by a template
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);
    }

    function test_registerAgreementSuccessfully() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(testAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
    }

    function test_emitsEventOnAgreementRegistration() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));

        // Expect AgreementCreated event
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(testAgreementId, address(this));

        // Register agreement
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);
    }

    function test_upgraderShouldBeAbleToUpgradeAfterDelay() public {
        string memory newVersion = '2.0.0';

        uint48 upgradeTime = uint48(vm.getBlockTimestamp() + UPGRADE_DELAY);

        AgreementsStoreV2 agreementsStoreV2Impl = new AgreementsStoreV2();

        vm.prank(upgrader);
        accessManager.schedule(
            address(agreementsStore),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(agreementsStoreV2Impl), bytes(''))),
            upgradeTime
        );

        vm.warp(upgradeTime);

        vm.prank(upgrader);
        accessManager.execute(
            address(agreementsStore),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(agreementsStoreV2Impl), bytes('')))
        );

        AgreementsStoreV2 agreementsStoreV2 = AgreementsStoreV2(address(agreementsStore));

        vm.prank(governor);
        agreementsStoreV2.initializeV2(newVersion);

        assertEq(agreementsStoreV2.getVersion(), newVersion);
    }

    function test_registerAgreement_revertIfAlreadyRegistered() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        // Register agreement first time
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Try to register the same agreement again
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementAlreadyRegistered.selector, testAgreementId));
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);
    }

    function test_updateConditionStatus_onlyTemplateOrConditionRole() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        // Register agreement
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Try to update condition status as a regular address (no roles)
        address regularAddress = makeAddr('regular');
        vm.prank(regularAddress);
        vm.expectRevert(abi.encodeWithSelector(IAgreement.OnlyTemplateOrConditionRole.selector, regularAddress));
        agreementsStore.updateConditionStatus(testAgreementId, conditionIds[0], IAgreement.ConditionState.Fulfilled);
    }

    function test_updateConditionStatus_successWithTemplateRole() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        // Register agreement
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Update condition status as template role
        vm.expectEmit(true, true, true, true);
        emit IAgreement.ConditionUpdated(testAgreementId, conditionIds[0], IAgreement.ConditionState.Fulfilled);
        agreementsStore.updateConditionStatus(testAgreementId, conditionIds[0], IAgreement.ConditionState.Fulfilled);

        // Verify condition state was updated
        IAgreement.ConditionState state = agreementsStore.getConditionState(testAgreementId, conditionIds[0]);
        assertEq(uint8(state), uint8(IAgreement.ConditionState.Fulfilled));
    }

    function test_updateConditionStatus_successWithConditionRole() public {
        // Grant template role to this contract for registration
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        // Register agreement
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Create a new address with condition role
        address conditionAddress = makeAddr('condition');
        _grantConditionRole(conditionAddress);

        // Update condition status as condition role
        vm.prank(conditionAddress);
        vm.expectEmit(true, true, true, true);
        emit IAgreement.ConditionUpdated(testAgreementId, conditionIds[0], IAgreement.ConditionState.Fulfilled);
        agreementsStore.updateConditionStatus(testAgreementId, conditionIds[0], IAgreement.ConditionState.Fulfilled);

        // Verify condition state was updated
        IAgreement.ConditionState state = agreementsStore.getConditionState(testAgreementId, conditionIds[0]);
        assertEq(uint8(state), uint8(IAgreement.ConditionState.Fulfilled));
    }

    function test_updateConditionStatus_revertIfAgreementNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Try to update condition status for non-existent agreement
        bytes32 nonExistentAgreementId = bytes32(uint256(999));
        bytes32 testConditionId = bytes32(0);

        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        agreementsStore.updateConditionStatus(
            nonExistentAgreementId, testConditionId, IAgreement.ConditionState.Fulfilled
        );
    }

    function test_updateConditionStatus_revertIfConditionIdNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        // Register agreement
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Try to update non-existent condition
        bytes32 nonExistentConditionId = bytes32(uint256(999));

        vm.expectRevert(abi.encodeWithSelector(IAgreement.ConditionIdNotFound.selector, nonExistentConditionId));
        agreementsStore.updateConditionStatus(
            testAgreementId, nonExistentConditionId, IAgreement.ConditionState.Fulfilled
        );
    }

    function test_getConditionState_revertIfAgreementNotFound() public {
        // Try to get condition state for non-existent agreement
        bytes32 nonExistentAgreementId = bytes32(uint256(999));
        bytes32 testConditionId = bytes32(0);

        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        agreementsStore.getConditionState(nonExistentAgreementId, testConditionId);
    }

    function test_getConditionState_revertIfConditionIdNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        // Register agreement
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Try to get state for non-existent condition
        bytes32 nonExistentConditionId = bytes32(uint256(999));

        vm.expectRevert(abi.encodeWithSelector(IAgreement.ConditionIdNotFound.selector, nonExistentConditionId));
        agreementsStore.getConditionState(testAgreementId, nonExistentConditionId);
    }

    function test_getConditionState_success() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        // Register agreement
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);

        // Get condition state
        IAgreement.ConditionState state = agreementsStore.getConditionState(testAgreementId, conditionIds[0]);
        assertEq(uint8(state), uint8(IAgreement.ConditionState.Unfulfilled));
    }

    function test_registerAgreement_revertIfInvalidConditionIdsAndStatesLength() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement with mismatched arrays
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](2); // Length 2
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1); // Length 1
        bytes[] memory params = new bytes[](0);
        conditionIds[0] = bytes32(0);
        conditionIds[1] = bytes32(uint256(1));
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        vm.expectRevert(IAgreement.InvalidConditionIdsAndStatesLength.selector);
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);
    }

    function test_registerAgreement_revertIfInvalidConditionIdsAndStatesLength_emptyArrays() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create test agreement with empty arrays
        bytes32 testAgreementId = agreementsStore.hashAgreementId(bytes32(0), address(this));
        bytes32[] memory conditionIds = new bytes32[](0);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](0);
        bytes[] memory params = new bytes[](0);

        // Empty arrays are valid, so this should not revert
        agreementsStore.register(testAgreementId, address(this), 0, conditionIds, conditionStates, 1, params);
    }

    function test_areConditionsFulfilled_AgreementNotFound() public {
        // Try to check conditions for non-existent agreement
        bytes32 nonExistentAgreementId = keccak256('non-existent');
        bytes32[] memory requiredConditions = new bytes32[](1);
        requiredConditions[0] = requiredConditionId;

        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        agreementsStore.areConditionsFulfilled(nonExistentAgreementId, conditionId, requiredConditions);
    }

    function test_areConditionsFulfilled_returnsFalseWhenConditionAlreadyFulfilled() public {
        // Register agreement with conditions
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = conditionId;
        conditionIds[1] = requiredConditionId;

        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](2);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;
        conditionStates[1] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(agreementId, user, 1, conditionIds, conditionStates, 1, new bytes[](0));

        // Fulfill the main condition
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, conditionId, IAgreement.ConditionState.Fulfilled);

        // Try to check conditions
        bytes32[] memory requiredConditions = new bytes32[](1);
        requiredConditions[0] = requiredConditionId;

        bool areFulfilled = agreementsStore.areConditionsFulfilled(agreementId, conditionId, requiredConditions);
        assertFalse(areFulfilled, 'Should return false when condition is already fulfilled');
    }

    function test_areConditionsFulfilled_returnsFalseWhenConditionAborted() public {
        // Register agreement with conditions
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = conditionId;
        conditionIds[1] = requiredConditionId;

        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](2);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;
        conditionStates[1] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(agreementId, user, 1, conditionIds, conditionStates, 1, new bytes[](0));

        // Abort the main condition
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, conditionId, IAgreement.ConditionState.Aborted);

        // Try to check conditions
        bytes32[] memory requiredConditions = new bytes32[](1);
        requiredConditions[0] = requiredConditionId;

        bool areFulfilled = agreementsStore.areConditionsFulfilled(agreementId, conditionId, requiredConditions);
        assertFalse(areFulfilled, 'Should return false when condition is aborted');
    }

    function test_areConditionsFulfilled_returnsFalseWhenRequiredConditionNotFulfilled() public {
        // Register agreement with conditions
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = conditionId;
        conditionIds[1] = requiredConditionId;

        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](2);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;
        conditionStates[1] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(agreementId, user, 1, conditionIds, conditionStates, 1, new bytes[](0));

        // Try to check conditions
        bytes32[] memory requiredConditions = new bytes32[](1);
        requiredConditions[0] = requiredConditionId;

        bool areFulfilled = agreementsStore.areConditionsFulfilled(agreementId, conditionId, requiredConditions);
        assertFalse(areFulfilled, 'Should return false when required condition is not fulfilled');
    }

    function test_areConditionsFulfilled_returnsTrueWhenAllConditionsFulfilled() public {
        // Register agreement with conditions
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = conditionId;
        conditionIds[1] = requiredConditionId;

        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](2);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;
        conditionStates[1] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(agreementId, user, 1, conditionIds, conditionStates, 1, new bytes[](0));

        // Fulfill the required condition
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, requiredConditionId, IAgreement.ConditionState.Fulfilled);

        // Try to check conditions
        bytes32[] memory requiredConditions = new bytes32[](1);
        requiredConditions[0] = requiredConditionId;

        bool areFulfilled = agreementsStore.areConditionsFulfilled(agreementId, conditionId, requiredConditions);
        assertTrue(areFulfilled, 'Should return true when all conditions are fulfilled');
    }
}
