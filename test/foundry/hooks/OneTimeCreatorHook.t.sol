// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {FIAT_SETTLEMENT_ROLE} from '../../../contracts/common/Roles.sol';
import {OneTimeCreatorHook} from '../../../contracts/hooks/OneTimeCreatorHook.sol';
import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';

import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {IHook} from '../../../contracts/interfaces/IHook.sol';

import {BaseTest} from '../common/BaseTest.sol';
import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';

contract OneTimeCreatorHookTest is BaseTest {
    address creator;
    address buyer;
    uint256 planId;

    function setUp() public override {
        super.setUp();
        creator = makeAddr('creator');
        vm.label(creator, 'creator');
        buyer = makeAddr('buyer');
        vm.label(buyer, 'buyer');

        // Grant template role to this contract
        _grantTemplateRole(address(this));
        _grantTemplateRole(buyer);
        _grantRole(FIAT_SETTLEMENT_ROLE, buyer);

        // Create a plan with the OneTimeCreatorHook
        IHook[] memory hooks = new IHook[](1);
        hooks[0] = oneTimeCreatorHook;
        planId = _createPlanWithHooks(hooks);
    }

    function test_WorksWithFiatPaymentTemplate() public {
        // Create agreement using FiatPaymentTemplate
        bytes32 seed = keccak256('test-seed');
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId =
            keccak256(abi.encode(fiatPaymentTemplate.NVM_CONTRACT_NAME(), buyer, seed, planId, buyer, 1, params));

        // Create first agreement
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, buyer);
        fiatPaymentTemplate.order(seed, planId, buyer, 1, params);

        // Second attempt should fail
        vm.prank(buyer);
        vm.expectPartialRevert(OneTimeCreatorHook.CreatorAlreadyCreatedAgreement.selector);
        fiatPaymentTemplate.order(keccak256('test-seed-2'), planId, buyer, 1, params);
    }

    function test_HooksMustBeUnique_reverts() public {
        // Create a hooks array with duplicate hook addresses
        IHook[] memory hooks = new IHook[](2);
        hooks[0] = oneTimeCreatorHook;
        hooks[1] = oneTimeCreatorHook; // duplicate

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100;
        address[] memory _receivers = new address[](1);
        _receivers[0] = creator;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: false,
            tokenAddress: address(0),
            amounts: _amounts,
            receivers: _receivers,
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
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

        uint256 uniqueNonce = 12345;
        vm.prank(creator);
        vm.expectRevert(IAsset.HooksMustBeUnique.selector);
        assetsRegistry.createPlanWithHooks(priceConfig, creditsConfig, hooks, uniqueNonce);
    }

    function test_beforeAgreementRegistered_onlyTemplate_reverts() public {
        address unauthorized = makeAddr('unauthorized');

        bytes32 agreementId = keccak256('test-agreement');
        address testCreator = makeAddr('test-creator');
        uint256 testPlanId = 1;
        bytes32[] memory conditionIds = new bytes32[](0);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](0);
        bytes[] memory params = new bytes[](0);

        // Try to call beforeAgreementRegistered from unauthorized address
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        oneTimeCreatorHook.beforeAgreementRegistered(
            agreementId, testCreator, testPlanId, conditionIds, conditionStates, params
        );
    }

    function test_afterAgreementCreated_onlyTemplate_reverts() public {
        address unauthorized = makeAddr('unauthorized');

        bytes32 agreementId = keccak256('test-agreement');
        address testCreator = makeAddr('test-creator');
        uint256 testPlanId = 1;
        bytes32[] memory conditionIds = new bytes32[](0);
        bytes[] memory params = new bytes[](0);

        // Try to call afterAgreementCreated from unauthorized address
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        oneTimeCreatorHook.afterAgreementCreated(agreementId, testCreator, testPlanId, conditionIds, params);
    }

    function test_beforeAgreementRegistered_template_success() public {
        bytes32 agreementId = keccak256('test-agreement');
        address testCreator = makeAddr('test-creator');
        uint256 testPlanId = 1;
        bytes32[] memory conditionIds = new bytes32[](0);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](0);
        bytes[] memory params = new bytes[](0);

        // Call beforeAgreementRegistered from template (this contract has template role)
        vm.expectEmit(true, true, false, false);
        emit OneTimeCreatorHook.FirstAgreementCreated(testCreator, agreementId);
        oneTimeCreatorHook.beforeAgreementRegistered(
            agreementId, testCreator, testPlanId, conditionIds, conditionStates, params
        );
    }

    function test_afterAgreementCreated_template_success() public {
        bytes32 agreementId = keccak256('test-agreement');
        address testCreator = makeAddr('test-creator');
        uint256 testPlanId = 1;
        bytes32[] memory conditionIds = new bytes32[](0);
        bytes[] memory params = new bytes[](0);

        // Call afterAgreementCreated from template (this contract has template role)
        // Should not revert
        oneTimeCreatorHook.afterAgreementCreated(agreementId, testCreator, testPlanId, conditionIds, params);
    }

    function _createPlanWithHooks(IHook[] memory hooks) internal returns (uint256) {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100;
        address[] memory _receivers = new address[](1);
        _receivers[0] = creator;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: false,
            tokenAddress: address(0),
            amounts: _amounts,
            receivers: _receivers,
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
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

        vm.prank(creator);
        assetsRegistry.createPlanWithHooks(priceConfig, creditsConfig, hooks, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, creator, 0);
    }
}
