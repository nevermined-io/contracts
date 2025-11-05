// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {INVMConfig} from '../../../contracts/interfaces/INVMConfig.sol';

import {NVMConfigV2} from '../../../contracts/mock/NVMConfigV2.sol';
import {BaseTest} from '../common/BaseTest.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import {GOVERNOR_ROLE} from '../../../contracts/common/Roles.sol';

import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';

contract NVMConfigTest is BaseTest {
    address public newGovernor;

    function setUp() public override {
        super.setUp();

        vm.prank(governor);
        nvmConfig.setFeeReceiver(owner);

        newGovernor = makeAddr('newGovernor');
    }

    function test_setFeeReceiver() public {
        vm.prank(governor);

        vm.expectEmit(true, true, true, true);
        emit INVMConfig.NeverminedConfigChange(governor, keccak256('feeReceiver'), abi.encodePacked(governor));

        nvmConfig.setFeeReceiver(governor);

        assertEq(nvmConfig.getFeeReceiver(), governor);
    }

    function test_haveRole() public {
        vm.prank(governor);

        bool haveRole = nvmConfig.haveRole(GOVERNOR_ROLE);
        assertTrue(haveRole);

        bool dontHaveRole = nvmConfig.haveRole(uint64(10197209388572726900));
        assertFalse(dontHaveRole);
    }

    function test_setFeeReceiver_onlyGovernor() public {
        address nonGovernor = makeAddr('nonGovernor');

        vm.prank(nonGovernor);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nvmConfig.setFeeReceiver(governor);
    }

    function test_setParameter() public {
        bytes32 paramName = keccak256('myparam');
        bytes memory paramValue = abi.encodePacked('myvalue');

        vm.prank(governor);
        vm.expectEmit(true, true, true, true);
        emit INVMConfig.NeverminedConfigChange(governor, paramName, paramValue);
        nvmConfig.setParameter(paramName, paramValue);

        (bytes memory value, bool exists,) = nvmConfig.getParameter(paramName);
        assertTrue(exists);
        assertEq(keccak256(value), keccak256(paramValue));
    }

    function test_setParameter_onlyGovernor() public {
        bytes32 paramName = keccak256('myparam');
        bytes memory paramValue = abi.encodePacked('myvalue');

        address nonGovernor = makeAddr('nonGovernor');

        vm.prank(nonGovernor);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nvmConfig.setParameter(paramName, paramValue);
    }

    function test_upgraderShouldBeAbleToUpgradeAfterDelay() public {
        string memory newVersion = '2.0.0';

        uint48 upgradeTime = uint48(vm.getBlockTimestamp() + UPGRADE_DELAY);

        NVMConfigV2 nvmConfigV2Impl = new NVMConfigV2();

        vm.prank(upgrader);
        accessManager.schedule(
            address(nvmConfig),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(nvmConfigV2Impl), bytes(''))),
            upgradeTime
        );

        vm.warp(upgradeTime);

        vm.prank(upgrader);
        accessManager.execute(
            address(nvmConfig), abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(nvmConfigV2Impl), bytes('')))
        );

        NVMConfigV2 nvmConfigV2 = NVMConfigV2(address(nvmConfig));

        vm.prank(governor);
        nvmConfigV2.initializeV2(newVersion);

        assertEq(nvmConfigV2.getVersion(), newVersion);
    }

    function test_getFeeReceiver() public view {
        address feeReceiver = nvmConfig.getFeeReceiver();
        assertEq(feeReceiver, owner);
    }

    function test_parameterExists() public {
        bytes32 paramName = keccak256('testParam');

        // Initially parameter should not exist
        assertFalse(nvmConfig.parameterExists(paramName));

        // Set parameter
        vm.prank(governor);
        nvmConfig.setParameter(paramName, abi.encodePacked('testValue'));

        // Now parameter should exist
        assertTrue(nvmConfig.parameterExists(paramName));

        // Disable parameter
        vm.prank(governor);
        nvmConfig.disableParameter(paramName);

        // Parameter should no longer exist
        assertFalse(nvmConfig.parameterExists(paramName));
    }

    function test_disableParameter() public {
        bytes32 paramName = keccak256('testParam');
        bytes memory paramValue = abi.encodePacked('testValue');

        // Set parameter first
        vm.prank(governor);
        nvmConfig.setParameter(paramName, paramValue);

        // Disable parameter
        vm.prank(governor);
        vm.expectEmit(true, true, true, true);
        emit INVMConfig.NeverminedConfigChange(governor, paramName, paramValue);
        nvmConfig.disableParameter(paramName);

        // Verify parameter is disabled
        (bytes memory value, bool isActive,) = nvmConfig.getParameter(paramName);
        assertFalse(isActive);
        assertEq(keccak256(value), keccak256(paramValue));
    }

    function test_disableParameter_onlyGovernor() public {
        bytes32 paramName = keccak256('testParam');
        bytes memory paramValue = abi.encodePacked('testValue');

        // Set parameter first
        vm.prank(governor);
        nvmConfig.setParameter(paramName, paramValue);

        // Try to disable parameter as non-governor
        address nonGovernor = makeAddr('nonGovernor');
        vm.prank(nonGovernor);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nvmConfig.disableParameter(paramName);
    }

    function test_disableParameter_nonexistent() public {
        bytes32 paramName = keccak256('nonexistentParam');

        // Try to disable non-existent parameter
        vm.prank(governor);
        nvmConfig.disableParameter(paramName);

        // Verify parameter still doesn't exist
        assertFalse(nvmConfig.parameterExists(paramName));
    }

    function test_getFeeReceiver_accessControl() public {
        // View function, no access control needed
        address nonGovernor = makeAddr('nonGovernor');
        vm.prank(nonGovernor);
        address receiver = nvmConfig.getFeeReceiver();
        assertEq(receiver, owner);
    }

    function test_getParameter_accessControl() public {
        // View function, no access control needed
        bytes32 paramName = keccak256('testParam');
        bytes memory paramValue = abi.encodePacked('testValue');

        // Set parameter first
        vm.prank(governor);
        nvmConfig.setParameter(paramName, paramValue);

        // Read parameter as non-governor
        address nonGovernor = makeAddr('nonGovernor');
        vm.prank(nonGovernor);
        (bytes memory value, bool isActive,) = nvmConfig.getParameter(paramName);
        assertTrue(isActive);
        assertEq(keccak256(value), keccak256(paramValue));
    }

    function test_parameterExists_accessControl() public {
        // View function, no access control needed
        bytes32 paramName = keccak256('testParam');
        bytes memory paramValue = abi.encodePacked('testValue');

        // Set parameter first
        vm.prank(governor);
        nvmConfig.setParameter(paramName, paramValue);

        // Check parameter existence as non-governor
        address nonGovernor = makeAddr('nonGovernor');
        vm.prank(nonGovernor);
        assertTrue(nvmConfig.parameterExists(paramName));
    }

    function test_setDefaultFeeController() public {
        // Create a new fee controller
        address newFeeController = makeAddr('newFeeController');

        // Set new default fee controller
        vm.prank(governor);
        nvmConfig.setDefaultFeeController(IFeeController(newFeeController));

        // Verify the default fee controller was updated
        assertEq(address(nvmConfig.getDefaultFeeController()), newFeeController);
    }

    function test_setDefaultFeeController_revertIfNotGovernor() public {
        // Create a new fee controller
        address newFeeController = makeAddr('newFeeController');

        // Try to set default fee controller as non-governor
        address nonGovernor = makeAddr('nonGovernor');
        vm.prank(nonGovernor);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nvmConfig.setDefaultFeeController(IFeeController(newFeeController));
    }

    function test_getDefaultFeeController() public view {
        // Get the current default fee controller
        IFeeController currentFeeController = nvmConfig.getDefaultFeeController();

        // Verify it matches the one set in BaseTest
        assertEq(address(currentFeeController), address(protocolStandardFees));
    }

    function test_setFeeControllerAllowed_success() public {
        // Create test fee controllers
        IFeeController feeController1 = IFeeController(makeAddr('feeController1'));
        IFeeController feeController2 = IFeeController(makeAddr('feeController2'));

        // Create test creators
        address creator1 = makeAddr('creator1');
        address creator2 = makeAddr('creator2');
        address creator3 = makeAddr('creator3');

        // Prepare input arrays
        IFeeController[] memory feeControllers = new IFeeController[](2);
        feeControllers[0] = feeController1;
        feeControllers[1] = feeController2;

        address[][] memory creators = new address[][](2);
        creators[0] = new address[](2);
        creators[0][0] = creator1;
        creators[0][1] = creator2;
        creators[1] = new address[](1);
        creators[1][0] = creator3;

        bool[][] memory allowed = new bool[][](2);
        allowed[0] = new bool[](2);
        allowed[0][0] = true;
        allowed[0][1] = false;
        allowed[1] = new bool[](1);
        allowed[1][0] = true;

        // Set fee controller allowed status
        vm.prank(governor);
        nvmConfig.setFeeControllerAllowed(feeControllers, creators, allowed);

        // Verify the settings were applied correctly
        assertTrue(nvmConfig.isFeeControllerAllowed(feeController1, creator1));
        assertFalse(nvmConfig.isFeeControllerAllowed(feeController1, creator2));
        assertTrue(nvmConfig.isFeeControllerAllowed(feeController2, creator3));
    }

    function test_setFeeControllerAllowed_revertIfNotGovernor() public {
        // Create test arrays
        IFeeController[] memory feeControllers = new IFeeController[](1);
        address[][] memory creators = new address[][](1);
        bool[][] memory allowed = new bool[][](1);

        // Try to set fee controller allowed status as non-governor
        address nonGovernor = makeAddr('nonGovernor');
        vm.prank(nonGovernor);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nvmConfig.setFeeControllerAllowed(feeControllers, creators, allowed);
    }

    function test_setFeeControllerAllowed_revertIfInvalidInputLength() public {
        // Create mismatched arrays
        IFeeController[] memory feeControllers = new IFeeController[](2);
        address[][] memory creators = new address[][](1);
        bool[][] memory allowed = new bool[][](1);

        // Try to set fee controller allowed status with mismatched arrays
        vm.prank(governor);
        vm.expectRevert(INVMConfig.InvalidInputLength.selector);
        nvmConfig.setFeeControllerAllowed(feeControllers, creators, allowed);
    }

    function test_setFeeControllerAllowed_revertIfInvalidInnerArrayLength() public {
        // Create test arrays with mismatched inner array lengths
        IFeeController[] memory feeControllers = new IFeeController[](1);
        address[][] memory creators = new address[][](1);
        creators[0] = new address[](2);
        bool[][] memory allowed = new bool[][](1);
        allowed[0] = new bool[](1);

        // Try to set fee controller allowed status with mismatched inner arrays
        vm.prank(governor);
        vm.expectRevert(INVMConfig.InvalidInputLength.selector);
        nvmConfig.setFeeControllerAllowed(feeControllers, creators, allowed);
    }

    function test_setFeeControllerAllowed_updateExistingSettings() public {
        // Create test fee controller and creator
        IFeeController feeController = IFeeController(makeAddr('feeController'));
        address creator = makeAddr('creator');

        // First set to true
        IFeeController[] memory feeControllers = new IFeeController[](1);
        feeControllers[0] = feeController;
        address[][] memory creators = new address[][](1);
        creators[0] = new address[](1);
        creators[0][0] = creator;
        bool[][] memory allowed = new bool[][](1);
        allowed[0] = new bool[](1);
        allowed[0][0] = true;

        vm.prank(governor);
        nvmConfig.setFeeControllerAllowed(feeControllers, creators, allowed);

        // Verify initial setting
        assertTrue(nvmConfig.isFeeControllerAllowed(feeController, creator));

        // Update to false
        allowed[0][0] = false;
        vm.prank(governor);
        nvmConfig.setFeeControllerAllowed(feeControllers, creators, allowed);

        // Verify updated setting
        assertFalse(nvmConfig.isFeeControllerAllowed(feeController, creator));
    }
}
