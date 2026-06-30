// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {DistributePaymentsCondition} from '../../../contracts/conditions/DistributePaymentsCondition.sol';
import {LockPaymentCondition} from '../../../contracts/conditions/LockPaymentCondition.sol';
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
            onchainMirror: false,
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

        // Snapshot locked amounts as LockPaymentCondition would (these tests bypass the lock path)
        uint256[] memory locked = linearPricing.quote(dynamicPlanId);
        vm.prank(template);
        agreementsStore.setLockedAmounts(testAgreementId, locked);

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
            onchainMirror: false,
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

        // Snapshot locked amounts as LockPaymentCondition would (these tests bypass the lock path)
        uint256[] memory locked = linearPricing.quote(dynamicPlanId);
        vm.prank(template);
        agreementsStore.setLockedAmounts(testAgreementId2, locked);

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
            onchainMirror: false,
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

            // Snapshot locked amounts as LockPaymentCondition would (these tests bypass the lock path)
            uint256[] memory locked = linearPricing.quote(dynamicPlanId);
            vm.prank(template);
            agreementsStore.setLockedAmounts(testAgreementId, locked);

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
            onchainMirror: false,
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

    // ============ Escrow integrity regression tests (#194) ============

    /// @dev Builds an external-price native-token plan and an agreement carrying lock/release/distribute
    /// conditions (all Unfulfilled), registered by the template. Returns the plan id, agreement id and
    /// the three condition ids. The plan's receivers are `planReceivers`; pricing is configured separately.
    function _buildExternalAgreement(uint256 _seed, address[] memory planReceivers)
        internal
        returns (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId)
    {
        return _buildExternalAgreement(_seed, planReceivers, 1, address(0));
    }

    function _buildExternalAgreement(
        uint256 _seed,
        address[] memory planReceivers,
        uint256 _numberOfPurchases,
        address _tokenAddress
    ) internal returns (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) {
        uint256[] memory amounts = new uint256[](planReceivers.length); // zeros: required for SMART_CONTRACT_PRICE
        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: _tokenAddress,
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
            onchainMirror: false,
            nftAddress: address(nftCredits)
        });

        bytes32 seed = bytes32(_seed);
        vm.prank(address(this));
        assetsRegistry.registerAgentAndPlan(seed, 'https://nevermined.io', priceConfig, creditsConfig);
        planId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), _seed);

        agreementId = agreementsStore.hashAgreementId(bytes32(_seed + 1), user);
        lockId = lockPaymentCondition.hashConditionId(agreementId, lockPaymentCondition.NVM_CONTRACT_NAME());
        releaseId = transferCreditsCondition.hashConditionId(agreementId, transferCreditsCondition.NVM_CONTRACT_NAME());
        distId =
            distributePaymentsCondition.hashConditionId(agreementId, distributePaymentsCondition.NVM_CONTRACT_NAME());

        bytes32[] memory conditionIds = new bytes32[](3);
        conditionIds[0] = lockId;
        conditionIds[1] = releaseId;
        conditionIds[2] = distId;
        IAgreement.ConditionState[] memory states = new IAgreement.ConditionState[](3);
        states[0] = IAgreement.ConditionState.Unfulfilled;
        states[1] = IAgreement.ConditionState.Unfulfilled;
        states[2] = IAgreement.ConditionState.Unfulfilled;

        vm.prank(template);
        agreementsStore.register(agreementId, user, planId, conditionIds, states, _numberOfPurchases, new bytes[](0));
    }

    /// @notice Distribution must use the amount locked at lock time, not a re-quote. A plan-owned price
    /// contract that returns a higher value after lock must NOT be able to over-withdraw from the vault.
    function test_escrow_distributeUsesLockedAmountNotRequote() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(901, planReceivers);

        // Configure the curve to quote 100 at lock time.
        address[] memory priceReceivers = new address[](1);
        priceReceivers[0] = receiver;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        linearPricing.setPlan(planId, 100, 0, priceReceivers, weights);

        // Real lock: snapshots [100] and deposits 100.
        vm.deal(template, 100);
        vm.prank(template);
        lockPaymentCondition.fulfill{value: 100}(lockId, agreementId, planId, user);

        // Attacker-controlled price bumps the quote AFTER lock.
        linearPricing.setPlan(planId, 1000, 0, priceReceivers, weights);

        // Mark the release condition fulfilled so distribution takes the success branch.
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, releaseId, IAgreement.ConditionState.Fulfilled);

        uint256 receiverBefore = receiver.balance;
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);

        // Receiver gets the LOCKED 100, not the re-quoted 1000; the vault is fully drained to ~0.
        assertEq(receiver.balance - receiverBefore, 100, 'must distribute the locked amount');
        assertEq(paymentsVault.getBalanceNativeToken(), 0, 'vault must be emptied, not over-withdrawn');
    }

    /// @notice On abort, an external-price plan must refund the actually-locked amount (not the empty
    /// plan.price.amounts, which would refund 0 and strand the locked funds).
    function test_escrow_refundsLockedAmountForExternalPlan() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(903, planReceivers);

        address[] memory priceReceivers = new address[](1);
        priceReceivers[0] = receiver;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        linearPricing.setPlan(planId, 100, 0, priceReceivers, weights);

        vm.deal(template, 100);
        vm.prank(template);
        lockPaymentCondition.fulfill{value: 100}(lockId, agreementId, planId, user);

        // Release stays Unfulfilled → distribution takes the refund branch.
        uint256 creatorBefore = user.balance;
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);

        assertEq(user.balance - creatorBefore, 100, 'creator must be refunded the locked amount');
        assertEq(paymentsVault.getBalanceNativeToken(), 0, 'vault must be emptied on refund');
    }

    /// @notice A quote that does not align 1:1 with the plan receivers must be rejected at lock time,
    /// so funds can never be locked under a configuration that distribution cannot fully release.
    function test_escrow_lockRevertsOnQuoteReceiversLengthMismatch() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId,,) = _buildExternalAgreement(905, planReceivers);

        // Configure the curve with TWO receivers while the plan has ONE → quote length 2 != receivers 1.
        address[] memory priceReceivers = new address[](2);
        priceReceivers[0] = receiver;
        priceReceivers[1] = receiver2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;
        linearPricing.setPlan(planId, 100, 0, priceReceivers, weights);

        vm.expectRevert(
            abi.encodeWithSelector(LockPaymentCondition.QuotedAmountsReceiversLengthMismatch.selector, 2, 1)
        );
        vm.prank(template);
        lockPaymentCondition.fulfill(lockId, agreementId, planId, user);
    }

    /// @notice The locked==distributed invariant holds with numberOfPurchases > 1: lock deposits
    /// sum(quoted) * N and distribute withdraws lockedAmounts[i] * N, emptying the vault exactly.
    function test_escrow_distributesLockedAmountTimesNumberOfPurchases() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(907, planReceivers, 3, address(0)); // numberOfPurchases = 3

        address[] memory priceReceivers = new address[](1);
        priceReceivers[0] = receiver;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        linearPricing.setPlan(planId, 100, 0, priceReceivers, weights); // per-purchase quote = [100]

        // Lock 100 * 3 = 300.
        vm.deal(template, 300);
        vm.prank(template);
        lockPaymentCondition.fulfill{value: 300}(lockId, agreementId, planId, user);
        assertEq(paymentsVault.getBalanceNativeToken(), 300);

        // Bump the quote AFTER lock: the old re-quote code would try to withdraw 1000*3 from a vault
        // holding only 300 and revert; the snapshot-based code distributes the locked 300.
        linearPricing.setPlan(planId, 1000, 0, priceReceivers, weights);

        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, releaseId, IAgreement.ConditionState.Fulfilled);

        uint256 receiverBefore = receiver.balance;
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);

        assertEq(receiver.balance - receiverBefore, 300, 'distributes locked * numberOfPurchases');
        assertEq(paymentsVault.getBalanceNativeToken(), 0, 'vault emptied exactly');
    }

    /// @notice ERC20 variant: distribution reuses the locked snapshot (not a re-quote) for token plans too.
    function test_escrow_distributeUsesLockedAmountNotRequote_erc20() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(909, planReceivers, 1, address(mockERC20));

        address[] memory priceReceivers = new address[](1);
        priceReceivers[0] = receiver;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        linearPricing.setPlan(planId, 100, 0, priceReceivers, weights); // quote = [100]

        // Fund the payer and approve the vault, then lock (snapshots [100], pulls 100 ERC20).
        mockERC20.mint(user, 100);
        vm.prank(user);
        mockERC20.approve(address(paymentsVault), 100);
        vm.prank(template);
        lockPaymentCondition.fulfill(lockId, agreementId, planId, user);
        assertEq(mockERC20.balanceOf(address(paymentsVault)), 100);

        // Bump the quote after lock; distribution must still pay the locked 100.
        linearPricing.setPlan(planId, 1000, 0, priceReceivers, weights);
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, releaseId, IAgreement.ConditionState.Fulfilled);

        uint256 receiverBefore = mockERC20.balanceOf(receiver);
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);

        assertEq(mockERC20.balanceOf(receiver) - receiverBefore, 100, 'ERC20 distributes the locked amount');
        assertEq(mockERC20.balanceOf(address(paymentsVault)), 0, 'vault emptied');
    }

    /// @notice The locked-amounts snapshot is write-once even when the first recorded snapshot is empty,
    /// so a privileged role cannot later rewrite an empty snapshot into a non-empty one.
    function test_escrow_setLockedAmountsWriteOnceEvenForEmptySnapshot() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (, bytes32 agreementId,,,) = _buildExternalAgreement(911, planReceivers);

        // First snapshot is empty — still recorded, so the slot is now claimed.
        uint256[] memory empty = new uint256[](0);
        vm.prank(template);
        agreementsStore.setLockedAmounts(agreementId, empty);

        // Any later write (including a non-empty one) must revert, not silently overwrite.
        uint256[] memory nonEmpty = new uint256[](1);
        nonEmpty[0] = 1000;
        vm.expectRevert(abi.encodeWithSelector(IAgreement.LockedAmountsAlreadySet.selector, agreementId));
        vm.prank(template);
        agreementsStore.setLockedAmounts(agreementId, nonEmpty);
    }

    /// @notice The refund branch fails closed for external-price plans: if the lock condition is marked
    /// fulfilled without a snapshot, distribution reverts instead of refunding 0 and stranding the funds.
    function test_escrow_refundFailsClosedOnMissingSnapshot() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(913, planReceivers);

        // Mark lock fulfilled WITHOUT going through the real lock condition, so no snapshot is recorded.
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, lockId, IAgreement.ConditionState.Fulfilled);

        // Release stays Unfulfilled → refund branch. Missing snapshot (length 0) != receivers (1) → revert.
        vm.expectRevert(
            abi.encodeWithSelector(DistributePaymentsCondition.LockedAmountsReceiversLengthMismatch.selector, 0, 1)
        );
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);
    }

    /// @notice ERC20 variant of the refund branch: on abort, an external-price ERC20 plan refunds the
    /// actually-locked token amount (not the empty plan.price.amounts) and empties the vault.
    function test_escrow_refundsLockedAmountForExternalPlan_erc20() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(915, planReceivers, 1, address(mockERC20));

        address[] memory priceReceivers = new address[](1);
        priceReceivers[0] = receiver;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        linearPricing.setPlan(planId, 100, 0, priceReceivers, weights);

        mockERC20.mint(user, 100);
        vm.prank(user);
        mockERC20.approve(address(paymentsVault), 100);
        vm.prank(template);
        lockPaymentCondition.fulfill(lockId, agreementId, planId, user);
        assertEq(mockERC20.balanceOf(address(paymentsVault)), 100);

        // Release stays Unfulfilled → refund branch.
        uint256 creatorBefore = mockERC20.balanceOf(user);
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);

        assertEq(mockERC20.balanceOf(user) - creatorBefore, 100, 'creator refunded the locked ERC20 amount');
        assertEq(mockERC20.balanceOf(address(paymentsVault)), 0, 'vault ERC20 emptied on refund');
    }

    /// @notice The success branch (which pays receivers) also fails closed on a missing snapshot:
    /// lock + release marked fulfilled without a snapshot must revert, never withdraw on a zero array.
    function test_escrow_successFailsClosedOnMissingSnapshot() public {
        address[] memory planReceivers = new address[](1);
        planReceivers[0] = receiver;
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(917, planReceivers);

        // Force both lock and release Fulfilled WITHOUT the real lock condition (no snapshot recorded).
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, lockId, IAgreement.ConditionState.Fulfilled);
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, releaseId, IAgreement.ConditionState.Fulfilled);

        vm.expectRevert(
            abi.encodeWithSelector(DistributePaymentsCondition.LockedAmountsReceiversLengthMismatch.selector, 0, 1)
        );
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);
    }

    /// @notice Multi-receiver (length > 1) binding: distribution and refund both use the per-receiver
    /// locked snapshot, so index alignment is exercised (a single-element array can't catch this).
    function test_escrow_multiReceiverBindingAndRefund() public {
        address[] memory planReceivers = new address[](2);
        planReceivers[0] = receiver;
        planReceivers[1] = receiver2;

        // --- distribution (success) path ---
        (uint256 planId, bytes32 agreementId, bytes32 lockId, bytes32 releaseId, bytes32 distId) =
            _buildExternalAgreement(919, planReceivers);
        address[] memory priceReceivers = new address[](2);
        priceReceivers[0] = receiver;
        priceReceivers[1] = receiver2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 30; // quote splits 120 as [90, 30]
        weights[1] = 10;
        linearPricing.setPlan(planId, 120, 0, priceReceivers, weights);

        vm.deal(template, 120);
        vm.prank(template);
        lockPaymentCondition.fulfill{value: 120}(lockId, agreementId, planId, user);

        // Bump the quote post-lock; distribution must still pay the locked [90, 30].
        linearPricing.setPlan(planId, 1200, 0, priceReceivers, weights);
        vm.prank(template);
        agreementsStore.updateConditionStatus(agreementId, releaseId, IAgreement.ConditionState.Fulfilled);

        uint256 r0 = receiver.balance;
        uint256 r1 = receiver2.balance;
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId, agreementId, planId, lockId, releaseId);
        assertEq(receiver.balance - r0, 90, 'receiver0 gets locked weight share');
        assertEq(receiver2.balance - r1, 30, 'receiver1 gets locked weight share');
        assertEq(paymentsVault.getBalanceNativeToken(), 0, 'vault emptied across receivers');

        // --- refund path on a separate two-receiver agreement ---
        (uint256 planId2, bytes32 aId2, bytes32 lockId2, bytes32 releaseId2, bytes32 distId2) =
            _buildExternalAgreement(921, planReceivers);
        linearPricing.setPlan(planId2, 120, 0, priceReceivers, weights);
        vm.deal(template, 120);
        vm.prank(template);
        lockPaymentCondition.fulfill{value: 120}(lockId2, aId2, planId2, user);

        uint256 creatorBefore = user.balance;
        vm.prank(template);
        distributePaymentsCondition.fulfill(distId2, aId2, planId2, lockId2, releaseId2);
        assertEq(user.balance - creatorBefore, 120, 'creator refunded full locked total across receivers');
        assertEq(paymentsVault.getBalanceNativeToken(), 0, 'vault emptied on multi-receiver refund');
    }
}
