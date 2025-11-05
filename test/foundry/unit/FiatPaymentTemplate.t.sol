// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {FIAT_SETTLEMENT_ROLE} from '../../../contracts/common/Roles.sol';
import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {ITemplate} from '../../../contracts/interfaces/ITemplate.sol';

import {BaseTest} from '../common/BaseTest.sol';

contract FiatPaymentTemplateTest is BaseTest {
    function setUp() public override {
        super.setUp();
        // Grant FIAT_SETTLEMENT_ROLE to this test contract so it can fulfill fiat settlement conditions
        _grantRole(FIAT_SETTLEMENT_ROLE, address(this));
    }

    function test_fiatSettlementRoleGranted() public view {
        // Verify that this test contract has the FIAT_SETTLEMENT_ROLE
        (bool hasRole,) = accessManager.hasRole(FIAT_SETTLEMENT_ROLE, address(this));
        assertTrue(hasRole, 'Test contract should have FIAT_SETTLEMENT_ROLE');
    }

    function test_order() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createPlan();

        // Create agreement using FiatPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        address creditsReceiver = makeAddr('creditsReceiver');
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(
                fiatPaymentTemplate.NVM_CONTRACT_NAME(),
                address(this),
                agreementSeed,
                planId,
                creditsReceiver,
                1,
                params
            )
        );

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fiatPaymentTemplate.order(agreementSeed, planId, creditsReceiver, 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 2);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT credits were minted to the receiver
        assertEq(nftCredits.balanceOf(creditsReceiver, planId), 100, 'Credits should be minted to receiver');
        assertEq(nftCredits.balanceOf(address(this), planId), 0, 'Creator should not have credits');
    }

    function test_order_revertIfPlanNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Try to create agreement with non-existent plan
        bytes32 agreementSeed = bytes32(uint256(2));
        uint256 nonExistentPlanId = 999;
        address creditsReceiver = makeAddr('creditsReceiver');
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IAsset.PlanNotFound.selector, nonExistentPlanId));
        fiatPaymentTemplate.order(agreementSeed, nonExistentPlanId, creditsReceiver, 1, params);
    }

    function test_order_revertIfZeroAddressReceiver() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan first
        uint256 planId = _createPlan();

        // Try to create agreement with zero address receiver
        bytes32 agreementSeed = bytes32(uint256(2));
        address zeroAddress = address(0);
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidReceiver.selector, zeroAddress));
        fiatPaymentTemplate.order(agreementSeed, planId, zeroAddress, 1, params);
    }

    function test_order_revertIfInvalidSeed() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan first
        uint256 planId = _createPlan();

        // Try to create agreement with zero seed
        bytes32 zeroSeed = bytes32(0);
        address creditsReceiver = makeAddr('creditsReceiver');
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidSeed.selector, zeroSeed));
        fiatPaymentTemplate.order(zeroSeed, planId, creditsReceiver, 1, params);
    }

    function test_order_revertIfInvalidPlanID() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Try to create agreement with zero plan ID
        bytes32 agreementSeed = bytes32(uint256(2));
        uint256 zeroPlanId = 0;
        address creditsReceiver = makeAddr('creditsReceiver');
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidPlanId.selector, zeroPlanId));
        fiatPaymentTemplate.order(agreementSeed, zeroPlanId, creditsReceiver, 1, params);
    }

    function test_order_revertIfInvalidTemplateAddressd() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100;
        address[] memory _receivers = new address[](1);
        _receivers[0] = address(this);

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: false,
            tokenAddress: address(0),
            amounts: _amounts,
            receivers: _receivers,
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: address(alice)
        });
        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 1,
            proofRequired: false,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        uint256 nonce = 127;
        assetsRegistry.createPlan(priceConfig, creditsConfig, nonce);
        uint256 planId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), nonce);

        // Create agreement using FiatPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        address creditsReceiver = makeAddr('creditsReceiver');
        bytes[] memory params = new bytes[](0);

        // Must revert because the template address associated with the plan is not FiatPaymentTemplate
        vm.expectRevert(
            abi.encodeWithSelector(IAsset.PlanWithInvalidTemplate.selector, planId, address(fiatPaymentTemplate))
        );
        fiatPaymentTemplate.order(agreementSeed, planId, creditsReceiver, 1, params);
    }

    function test_order_revertIfAgreementAlreadyRegistered() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createPlan();

        // Create agreement using FiatPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        address creditsReceiver = makeAddr('creditsReceiver');
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(
                fiatPaymentTemplate.NVM_CONTRACT_NAME(),
                address(this),
                agreementSeed,
                planId,
                creditsReceiver,
                1,
                params
            )
        );

        // Create first agreement
        fiatPaymentTemplate.order(agreementSeed, planId, creditsReceiver, 1, params);

        // Try to create the same agreement again
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementAlreadyRegistered.selector, expectedAgreementId));
        fiatPaymentTemplate.order(agreementSeed, planId, creditsReceiver, 1, params);
    }
}
