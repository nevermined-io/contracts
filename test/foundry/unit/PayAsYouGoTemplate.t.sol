// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {FixedPaymentTemplate} from '../../../contracts/agreements/FixedPaymentTemplate.sol';
import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';

import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {INVMConfig} from '../../../contracts/interfaces/INVMConfig.sol';
import {ITemplate} from '../../../contracts/interfaces/ITemplate.sol';
import {MockERC20} from '../../../contracts/test/MockERC20.sol';

import {BaseTest} from '../common/BaseTest.sol';
import {ERC1155Holder} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

contract PayAsYouGoTemplateTest is BaseTest, ERC1155Holder {
    address receiver = makeAddr('receiver');
    MockERC20 mockERC20;

    function setUp() public override {
        super.setUp();

        // Deploy MockERC20
        mockERC20 = new MockERC20('Mock Token', 'MTK');

        // Mint tokens to this contract for testing
        mockERC20.mint(address(this), 1000 * 10 ** 18);
    }

    function _createPayAsYouGoPricePlan() internal returns (uint256) {
        return __createPayAsYouGoPricePlan(address(payAsYouGoTemplate));
    }

    function __createPayAsYouGoPricePlan(address _template) internal returns (uint256) {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100;
        address[] memory _receivers = new address[](1);
        _receivers[0] = receiver;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(0),
            amounts: _amounts,
            receivers: _receivers,
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: _template
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
            assetsRegistry.addFeesToPaymentsDistribution(priceConfig, creditsConfig);

        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 0);
    }

    function _createERC20FixedPricePlan() internal returns (uint256) {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100 * 10 ** 18; // 100 tokens with 18 decimals
        address[] memory _receivers = new address[](1);
        _receivers[0] = receiver;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(mockERC20),
            amounts: _amounts,
            receivers: _receivers,
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: address(payAsYouGoTemplate)
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
            assetsRegistry.addFeesToPaymentsDistribution(priceConfig, creditsConfig);

        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 0);
    }

    function test_order() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createPayAsYouGoPricePlan();

        // Get initial balances
        uint256 initialCreatorBalance = address(this).balance;
        uint256 initialReceiverBalance = address(receiver).balance;

        // Create agreement using PayAsYouGoTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId =
            keccak256(abi.encode(payAsYouGoTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, params));

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        payAsYouGoTemplate.order{value: 100}(agreementSeed, planId, params);

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

        // Verify payment distribution
        uint256 finalCreatorBalance = address(this).balance;
        uint256 finalVaultBalance = address(paymentsVault).balance;
        uint256 finalReceiverBalance = address(receiver).balance;

        // Creator should have spent 100 wei
        assertEq(initialCreatorBalance - finalCreatorBalance, 100, 'Creator should have spent 100 wei');
        // Vault balance should be 0 since payments were distributed
        assertEq(finalVaultBalance, 0, 'Vault balance should be 0 after distribution');
        // Receiver should have received 100 wei
        assertEq(finalReceiverBalance - initialReceiverBalance, 100, 'Receiver should have received 100 wei');
    }

    function test_orderWithERC20() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan with ERC20 payment
        uint256 planId = _createERC20FixedPricePlan();

        // Get initial balances
        uint256 initialCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 initialReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Create agreement using PayAsYouGoTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId =
            keccak256(abi.encode(payAsYouGoTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, params));

        {
            // Approve tokens for PaymentsVault
            uint256 paymentAmount = 101 * 10 ** 18;
            mockERC20.approve(address(paymentsVault), paymentAmount);
        }

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        payAsYouGoTemplate.order(agreementSeed, planId, params);

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

        // Verify ERC20 payment distribution
        uint256 finalCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 finalVaultTokenBalance = mockERC20.balanceOf(address(paymentsVault));
        uint256 finalReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Creator should have spent 100 tokens
        assertEq(
            initialCreatorTokenBalance - finalCreatorTokenBalance,
            100 * 10 ** 18,
            'Creator should have spent 100 tokens'
        );
        // Vault balance should be 0 since payments were distributed
        assertEq(finalVaultTokenBalance, 0, 'Vault token balance should be 0 after distribution');
        // Receiver should have received 100 tokens
        assertEq(
            finalReceiverTokenBalance - initialReceiverTokenBalance,
            100 * 10 ** 18,
            'Receiver should have received 100 tokens'
        );
    }

    function test_order_revertIfInvalidTemplate() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan first
        uint256 planId = __createPayAsYouGoPricePlan(address(0));

        // Create agreement using PayAsYouGoTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(
            abi.encodeWithSelector(IAsset.PlanWithInvalidTemplate.selector, planId, address(payAsYouGoTemplate))
        );
        payAsYouGoTemplate.order{value: 100}(agreementSeed, planId, params);
    }

    function test_order_revertIfPlanNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Try to create agreement with non-existent plan
        bytes32 agreementSeed = bytes32(uint256(2));
        uint256 nonExistentPlanId = 999;
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IAsset.PlanNotFound.selector, nonExistentPlanId));
        payAsYouGoTemplate.order{value: 100}(agreementSeed, nonExistentPlanId, params);
    }

    function test_order_revertIfInvalidSeed() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan first
        uint256 planId = _createPayAsYouGoPricePlan();

        // Try to create agreement with zero seed
        bytes32 zeroSeed = bytes32(0);
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidSeed.selector, zeroSeed));
        payAsYouGoTemplate.order{value: 100}(zeroSeed, planId, params);
    }

    function test_order_revertIfInvalidPlanID() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Try to create agreement with zero plan ID
        bytes32 agreementSeed = bytes32(uint256(2));
        uint256 zeroPlanId = 0;
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidPlanId.selector, zeroPlanId));
        payAsYouGoTemplate.order{value: 100}(agreementSeed, zeroPlanId, params);
    }

    // function test_order_revertIfInvalidReceiver() public {
    //   // Grant template role to this contract
    //   _grantTemplateRole(address(this));

    //   // Create a plan first
    //   uint256 planId = _createPayAsYouGoPricePlan();

    //   // Try to create agreement with zero address receiver
    //   bytes32 agreementSeed = bytes32(uint256(2));
    //   address zeroAddress = address(0);
    //   bytes[] memory params = new bytes[](0);

    //   vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidReceiver.selector, zeroAddress));
    //   payAsYouGoTemplate.order{ value: 100 }(agreementSeed, planId, zeroAddress, params);
    // }

    function test_order_revertIfAgreementAlreadyRegistered() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createPayAsYouGoPricePlan();

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId =
            keccak256(abi.encode(payAsYouGoTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, params));

        // Create first agreement
        payAsYouGoTemplate.order{value: 100}(agreementSeed, planId, params);

        // Try to create the same agreement again
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementAlreadyRegistered.selector, expectedAgreementId));
        payAsYouGoTemplate.order{value: 100}(agreementSeed, planId, params);
    }

    function test_order_revertIfConditionAlreadyFulfilled() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createPayAsYouGoPricePlan();

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId =
            keccak256(abi.encode(payAsYouGoTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, params));

        // Create first agreement
        payAsYouGoTemplate.order{value: 100}(agreementSeed, planId, params);

        // Get the condition IDs
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        bytes32 lockPaymentConditionId = agreement.conditionIds[0];
        bytes32 distributeConditionId = agreement.conditionIds[1];

        // Try to fulfill lock payment condition again
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgreement.ConditionAlreadyFulfilled.selector, expectedAgreementId, lockPaymentConditionId
            )
        );
        lockPaymentCondition.fulfill{value: 100}(lockPaymentConditionId, expectedAgreementId, planId, address(this));

        // Try to fulfill transfer condition again
        bytes32[] memory requiredConditions = new bytes32[](1);
        requiredConditions[0] = lockPaymentConditionId;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgreement.ConditionAlreadyFulfilled.selector, expectedAgreementId, lockPaymentConditionId
            )
        );
        lockPaymentCondition.fulfill(lockPaymentConditionId, expectedAgreementId, planId, address(this));

        // Try to fulfill distribute condition again
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgreement.ConditionAlreadyFulfilled.selector, expectedAgreementId, distributeConditionId
            )
        );
        distributePaymentsCondition.fulfill(
            distributeConditionId, expectedAgreementId, planId, lockPaymentConditionId, lockPaymentConditionId
        );
    }

    function test_order_revertIfConditionPreconditionFailed() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createPayAsYouGoPricePlan();

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId =
            keccak256(abi.encode(payAsYouGoTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, params));

        uint256 snapshot = vm.snapshotState();

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        payAsYouGoTemplate.order{value: 100}(agreementSeed, planId, params);

        // Get the condition IDs
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        bytes32 lockPaymentConditionId = agreement.conditionIds[0];
        bytes32 distributeConditionId = agreement.conditionIds[1];

        vm.revertToState(snapshot);

        // Mock the agreement store to simulate unfulfilled conditions
        vm.mockCall(
            address(agreementsStore),
            abi.encodeWithSelector(
                agreementsStore.getConditionState.selector, expectedAgreementId, lockPaymentConditionId
            ),
            abi.encode(IAgreement.ConditionState.Unfulfilled)
        );

        // Try to fulfill distribute condition before lock payment
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgreement.ConditionPreconditionFailed.selector, expectedAgreementId, distributeConditionId
            )
        );

        payAsYouGoTemplate.order{value: 100}(agreementSeed, planId, params);
    }

    function test_order_revertIfAgreementNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createPayAsYouGoPricePlan();

        // Create a non-existent agreement ID
        bytes32 nonExistentAgreementId = keccak256(abi.encodePacked('non-existent'));
        bytes32 lockPaymentConditionId = keccak256(abi.encodePacked('lock-payment'));
        bytes32 distributeConditionId = keccak256(abi.encodePacked('distribute'));

        // Try to fulfill lock payment condition for non-existent agreement
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        lockPaymentCondition.fulfill{value: 100}(lockPaymentConditionId, nonExistentAgreementId, planId, address(this));

        // // Try to fulfill distribute condition for non-existent agreement
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        distributePaymentsCondition.fulfill(
            distributeConditionId, nonExistentAgreementId, planId, lockPaymentConditionId, nonExistentAgreementId
        );
    }

    receive() external payable {}
}
