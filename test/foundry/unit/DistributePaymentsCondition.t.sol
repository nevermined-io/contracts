// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';

import {LinearPricing} from '../../../contracts/pricing/LinearPricing.sol';
import {MockERC20} from '../../../contracts/test/MockERC20.sol';
import {BaseTest} from '../common/BaseTest.sol';

contract DistributePaymentsConditionTest is BaseTest {
    address public receiver;
    address public receiver2;
    address public template;
    address public user;
    MockERC20 public mockERC20;

    function setUp() public override {
        super.setUp();

        // Setup addresses
        receiver = makeAddr('receiver');
        receiver2 = makeAddr('receiver2');
        template = makeAddr('template');
        user = makeAddr('user');

        // Deploy MockERC20
        mockERC20 = new MockERC20('Test Token', 'TST');

        // Grant template role
        _grantTemplateRole(template);
    }

    function test_dynamicPricing_distributeNativeToken() public {
        // Setup pricing parameters
        uint256 baseAmount = 100 ether;
        uint256 slope = 10 ether;
        address[] memory receivers = new address[](2);
        receivers[0] = receiver;
        receivers[1] = receiver2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 60; // 60% to receiver
        weights[1] = 40; // 40% to receiver2

        // Configure the pricing contract - we'll set it after we know the plan ID

        // Create price config with SMART_CONTRACT_PRICE
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0; // Required for SMART_CONTRACT_PRICE
        amounts[1] = 0;
        address[] memory planReceivers = new address[](2);
        planReceivers[0] = receiver;
        planReceivers[1] = receiver2;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(0), // Native token
            amounts: amounts,
            receivers: planReceivers,
            externalPriceAddress: address(linearPricing),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
        });

        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_OWNER,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 100,
            proofRequired: false,
            nftAddress: address(nftCredits)
        });

        // Register asset and plan
        bytes32 seed = bytes32(uint256(100));
        vm.prank(address(this));
        assetsRegistry.registerAgentAndPlan(seed, 'https://nevermined.io', priceConfig, creditsConfig);

        uint256 dynamicPlanId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), uint256(seed));

        // Configure the pricing contract with the actual plan ID
        linearPricing.setPlan(dynamicPlanId, baseAmount, slope, receivers, weights);

        // Create agreement and condition ids
        bytes32 agreementSeed = bytes32(uint256(200));
        bytes32 testAgreementId = agreementsStore.hashAgreementId(agreementSeed, user);
        bytes32 lockName = lockPaymentCondition.NVM_CONTRACT_NAME();
        bytes32 releaseName = transferCreditsCondition.NVM_CONTRACT_NAME();
        bytes32 distributeName = distributePaymentsCondition.NVM_CONTRACT_NAME();
        bytes32 lockConditionId = lockPaymentCondition.hashConditionId(testAgreementId, lockName);
        bytes32 releaseConditionId = transferCreditsCondition.hashConditionId(testAgreementId, releaseName);
        bytes32 testConditionId = distributePaymentsCondition.hashConditionId(testAgreementId, distributeName);

        // Register agreement with lock and release preconditions fulfilled
        bytes32[] memory conditionIds = new bytes32[](3);
        conditionIds[0] = lockConditionId;
        conditionIds[1] = releaseConditionId;
        conditionIds[2] = testConditionId;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](3);
        conditionStates[0] = IAgreement.ConditionState.Fulfilled;
        conditionStates[1] = IAgreement.ConditionState.Fulfilled;
        conditionStates[2] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(testAgreementId, user, dynamicPlanId, conditionIds, conditionStates, 1, new bytes[](0));

        // Fund the vault with the expected amount (simulating locked payment)
        uint256 totalAmount = baseAmount; // First purchase
        vm.deal(address(paymentsVault), totalAmount);

        // Record initial balances
        uint256 initialReceiverBalance = receiver.balance;
        uint256 initialReceiver2Balance = receiver2.balance;

        // Fulfill distribute payments condition
        vm.prank(template);
        distributePaymentsCondition.fulfill(
            testConditionId, testAgreementId, dynamicPlanId, lockConditionId, releaseConditionId
        );

        // Verify condition state
        IAgreement.ConditionState conditionState = agreementsStore.getConditionState(testAgreementId, testConditionId);
        assertEq(uint8(conditionState), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify distribution amounts
        uint256 expectedReceiver1Amount = (totalAmount * 60) / 100; // 60%
        uint256 expectedReceiver2Amount = (totalAmount * 40) / 100; // 40%

        assertEq(receiver.balance, initialReceiverBalance + expectedReceiver1Amount);
        assertEq(receiver2.balance, initialReceiver2Balance + expectedReceiver2Amount);

        // Verify vault is empty
        uint256 vaultBalance = paymentsVault.getBalanceNativeToken();
        assertEq(vaultBalance, 0);
    }

    function test_dynamicPricing_distributeERC20Token() public {
        // Setup pricing parameters
        uint256 baseAmount = 1000e18; // 1000 tokens
        uint256 slope = 100e18; // 100 tokens increase per purchase
        address[] memory receivers = new address[](2);
        receivers[0] = receiver;
        receivers[1] = receiver2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 70; // 70% to receiver
        weights[1] = 30; // 30% to receiver2

        // Configure the pricing contract - we'll set it after we know the plan ID

        // Create price config with SMART_CONTRACT_PRICE for ERC20
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0; // Required for SMART_CONTRACT_PRICE
        amounts[1] = 0;
        address[] memory planReceivers = new address[](2);
        planReceivers[0] = receiver;
        planReceivers[1] = receiver2;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(mockERC20),
            amounts: amounts,
            receivers: planReceivers,
            externalPriceAddress: address(linearPricing),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
        });

        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_OWNER,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 100,
            proofRequired: false,
            nftAddress: address(nftCredits)
        });

        // Register asset and plan
        bytes32 seed = bytes32(uint256(101));
        vm.prank(address(this));
        assetsRegistry.registerAgentAndPlan(seed, 'https://nevermined.io', priceConfig, creditsConfig);

        uint256 dynamicPlanId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), uint256(seed));

        // Configure the pricing contract with the actual plan ID
        linearPricing.setPlan(dynamicPlanId, baseAmount, slope, receivers, weights);

        // Create agreement and condition ids
        bytes32 agreementSeed = bytes32(uint256(201));
        bytes32 testAgreementId2 = agreementsStore.hashAgreementId(agreementSeed, user);
        bytes32 lockName2 = lockPaymentCondition.NVM_CONTRACT_NAME();
        bytes32 releaseName2 = transferCreditsCondition.NVM_CONTRACT_NAME();
        bytes32 distributeName2 = distributePaymentsCondition.NVM_CONTRACT_NAME();
        bytes32 lockConditionId2 = lockPaymentCondition.hashConditionId(testAgreementId2, lockName2);
        bytes32 releaseConditionId2 = transferCreditsCondition.hashConditionId(testAgreementId2, releaseName2);
        bytes32 testConditionId2 = distributePaymentsCondition.hashConditionId(testAgreementId2, distributeName2);

        // Register agreement with lock and release preconditions fulfilled
        bytes32[] memory conditionIds = new bytes32[](3);
        conditionIds[0] = lockConditionId2;
        conditionIds[1] = releaseConditionId2;
        conditionIds[2] = testConditionId2;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](3);
        conditionStates[0] = IAgreement.ConditionState.Fulfilled;
        conditionStates[1] = IAgreement.ConditionState.Fulfilled;
        conditionStates[2] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(
            testAgreementId2, user, dynamicPlanId, conditionIds, conditionStates, 1, new bytes[](0)
        );

        // Fund the vault with ERC20 tokens (simulating locked payment)
        uint256 totalAmount = baseAmount; // First purchase
        mockERC20.mint(address(paymentsVault), totalAmount);

        // Record initial balances
        uint256 initialReceiverBalance = mockERC20.balanceOf(receiver);
        uint256 initialReceiver2Balance = mockERC20.balanceOf(receiver2);

        // Fulfill distribute payments condition
        vm.prank(template);
        distributePaymentsCondition.fulfill(
            testConditionId2, testAgreementId2, dynamicPlanId, lockConditionId2, releaseConditionId2
        );

        // Verify condition state
        IAgreement.ConditionState conditionState = agreementsStore.getConditionState(testAgreementId2, testConditionId2);
        assertEq(uint8(conditionState), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify distribution amounts
        uint256 expectedReceiver1Amount = (totalAmount * 70) / 100; // 70%
        uint256 expectedReceiver2Amount = (totalAmount * 30) / 100; // 30%

        assertEq(mockERC20.balanceOf(receiver), initialReceiverBalance + expectedReceiver1Amount);
        assertEq(mockERC20.balanceOf(receiver2), initialReceiver2Balance + expectedReceiver2Amount);

        // Verify vault is empty
        uint256 vaultBalance = paymentsVault.getBalanceERC20(address(mockERC20));
        assertEq(vaultBalance, 0);
    }

    function test_dynamicPricing_increasingPrices() public {
        // Use deployed LinearPricing from BaseTest
        LinearPricing linearPricing = linearPricing;

        // Setup pricing parameters
        uint256 baseAmount = 50 ether;
        uint256 slope = 5 ether;
        address[] memory receivers = new address[](1);
        receivers[0] = receiver;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // 100% to receiver

        // Configure the pricing contract - we'll set it after we know the plan ID

        // Create price config with SMART_CONTRACT_PRICE
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0; // Required for SMART_CONTRACT_PRICE
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(0), // Native token
            amounts: amounts,
            receivers: planReceivers,
            externalPriceAddress: address(linearPricing),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
        });

        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_OWNER,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 100,
            proofRequired: false,
            nftAddress: address(nftCredits)
        });

        // Register asset and plan
        bytes32 seed = bytes32(uint256(102));
        vm.prank(address(this));
        assetsRegistry.registerAgentAndPlan(seed, 'https://nevermined.io', priceConfig, creditsConfig);

        uint256 dynamicPlanId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), uint256(seed));

        // Configure the pricing contract with the actual plan ID
        linearPricing.setPlan(dynamicPlanId, baseAmount, slope, receivers, weights);

        // Test multiple purchases with increasing prices
        for (uint256 i = 0; i < 5; i++) {
            uint256 expectedPrice = baseAmount + (slope * i);

            // Create agreement and condition ids for this purchase
            bytes32 agreementSeed = bytes32(uint256(300 + i));
            bytes32 testAgreementId = agreementsStore.hashAgreementId(agreementSeed, user);
            bytes32 lockNameI = lockPaymentCondition.NVM_CONTRACT_NAME();
            bytes32 releaseNameI = transferCreditsCondition.NVM_CONTRACT_NAME();
            bytes32 distributeNameI = distributePaymentsCondition.NVM_CONTRACT_NAME();
            bytes32 lockConditionIdI = lockPaymentCondition.hashConditionId(testAgreementId, lockNameI);
            bytes32 releaseConditionIdI = transferCreditsCondition.hashConditionId(testAgreementId, releaseNameI);
            bytes32 testConditionId = distributePaymentsCondition.hashConditionId(testAgreementId, distributeNameI);

            // Register agreement with lock and release preconditions fulfilled
            bytes32[] memory conditionIds = new bytes32[](3);
            conditionIds[0] = lockConditionIdI;
            conditionIds[1] = releaseConditionIdI;
            conditionIds[2] = testConditionId;
            IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](3);
            conditionStates[0] = IAgreement.ConditionState.Fulfilled;
            conditionStates[1] = IAgreement.ConditionState.Fulfilled;
            conditionStates[2] = IAgreement.ConditionState.Unfulfilled;

            vm.prank(template);
            agreementsStore.register(
                testAgreementId, user, dynamicPlanId, conditionIds, conditionStates, 1, new bytes[](0)
            );

            // Fund the vault with the expected amount
            vm.deal(address(paymentsVault), expectedPrice);

            // Record initial balance
            uint256 initialReceiverBalance = receiver.balance;

            // Fulfill distribute payments condition
            vm.prank(template);
            distributePaymentsCondition.fulfill(
                testConditionId, testAgreementId, dynamicPlanId, lockConditionIdI, releaseConditionIdI
            );

            // Verify condition state
            IAgreement.ConditionState conditionState =
                agreementsStore.getConditionState(testAgreementId, testConditionId);
            assertEq(uint8(conditionState), uint8(IAgreement.ConditionState.Fulfilled));

            // Verify distribution (100% to receiver)
            assertEq(receiver.balance, initialReceiverBalance + expectedPrice);

            // Verify vault is empty
            uint256 vaultBalance = paymentsVault.getBalanceNativeToken();
            assertEq(vaultBalance, 0);

            // Increment the purchase counter in the pricing contract
            linearPricing.increment(dynamicPlanId, 1);
        }
    }

    function test_dynamicPricing_revertIfContractAddressZero() public {
        // Create price config with SMART_CONTRACT_PRICE but zero contract address
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(0),
            amounts: amounts,
            receivers: receivers,
            externalPriceAddress: address(0), // Zero address should cause revert
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
        });

        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_OWNER,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 100,
            proofRequired: false,
            nftAddress: address(nftCredits)
        });

        // Register asset and plan
        bytes32 seed = bytes32(uint256(103));
        vm.prank(address(this));
        assetsRegistry.registerAgentAndPlan(seed, 'https://nevermined.io', priceConfig, creditsConfig);

        uint256 dynamicPlanId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this));

        // Create agreement
        bytes32 agreementSeed = bytes32(uint256(203));
        bytes32 testAgreementId3 = agreementsStore.hashAgreementId(agreementSeed, user);
        bytes32 contractName = distributePaymentsCondition.NVM_CONTRACT_NAME();
        bytes32 testConditionId3 = distributePaymentsCondition.hashConditionId(testAgreementId3, contractName);

        // Register agreement with the condition
        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = testConditionId3;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(
            testAgreementId3, user, dynamicPlanId, conditionIds, conditionStates, 1, new bytes[](0)
        );

        // Fund the vault
        vm.deal(address(paymentsVault), 100 ether);

        // Attempt to fulfill should revert due to zero contract address
        vm.expectRevert(); // Low-level call to address(0) will revert
        vm.prank(template);
        distributePaymentsCondition.fulfill(testConditionId3, testAgreementId3, dynamicPlanId, bytes32(0), bytes32(0));
    }
}
