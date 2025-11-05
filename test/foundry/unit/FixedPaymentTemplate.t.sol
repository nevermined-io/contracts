// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';

import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {ITemplate} from '../../../contracts/interfaces/ITemplate.sol';
import {MockERC20} from '../../../contracts/test/MockERC20.sol';

import {BaseTest} from '../common/BaseTest.sol';
import {ERC1155Holder} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

contract FixedPaymentTemplateTest is BaseTest, ERC1155Holder {
    address receiver = makeAddr('receiver');
    MockERC20 mockERC20;

    function setUp() public override {
        super.setUp();

        // Deploy MockERC20
        mockERC20 = new MockERC20('Mock Token', 'MTK');

        // Mint tokens to this contract for testing
        mockERC20.mint(address(this), 1000 * 10 ** 18);
    }

    function _createCryptoPricePlan() internal returns (uint256) {
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

        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 0);
    }

    function test_order() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createCryptoPricePlan();

        // Get initial balances
        uint256 initialCreatorBalance = address(this).balance;
        uint256 initialCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        uint256 initialReceiverBalance = address(receiver).balance;

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer
        uint256 finalCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(finalCreatorNftBalance - initialCreatorNftBalance, 100, 'NFT credits should be minted to creator');

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

    function test_orderWithMultiplePurchasesAtOnce() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan
        uint256 planId = _createCryptoPricePlan();

        uint256 numberOfPurchases = 3;

        // Get initial balances
        uint256 initialCreatorBalance = address(this).balance;
        uint256 initialCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        uint256 initialReceiverBalance = address(receiver).balance;

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(
                fixedPaymentTemplate.NVM_CONTRACT_NAME(),
                address(this),
                agreementSeed,
                planId,
                numberOfPurchases,
                params
            )
        );

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));

        fixedPaymentTemplate.order{value: 100 * numberOfPurchases}(
            agreementSeed, planId, address(this), numberOfPurchases, params
        );

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);
        assertEq(agreement.numberOfPurchases, 3);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer
        uint256 finalCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(
            finalCreatorNftBalance - initialCreatorNftBalance,
            100 * numberOfPurchases,
            'NFT credits should be minted to creator'
        );

        // Verify payment distribution
        uint256 finalCreatorBalance = address(this).balance;
        uint256 finalVaultBalance = address(paymentsVault).balance;
        uint256 finalReceiverBalance = address(receiver).balance;

        // Creator should have spent 100 wei
        assertEq(
            initialCreatorBalance - finalCreatorBalance,
            100 * numberOfPurchases,
            'Creator should have spent 100 wei * 3'
        );
        // Vault balance should be 0 since payments were distributed
        assertEq(finalVaultBalance, 0, 'Vault balance should be 0 after distribution');
        // Receiver should have received 100 wei
        assertEq(
            finalReceiverBalance - initialReceiverBalance,
            100 * numberOfPurchases,
            'Receiver should have received 100 wei * 3'
        );
    }

    function test_orderWithERC20() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan with ERC20 payment
        uint256 planId = _createERC20FixedPricePlan();

        // Get initial balances
        uint256 initialCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 initialCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        uint256 initialReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        {
            // Approve tokens for PaymentsVault
            uint256 paymentAmount = 101 * 10 ** 18;
            mockERC20.approve(address(paymentsVault), paymentAmount);
        }

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order(agreementSeed, planId, address(this), 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer
        uint256 finalCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(finalCreatorNftBalance - initialCreatorNftBalance, 100, 'NFT credits should be minted to creator');

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

    function test_orderWithERC20AndMultiplePurchases() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan with ERC20 payment
        uint256 planId = _createERC20FixedPricePlan();

        uint256 numberOfPurchases = 3;

        // Get initial balances
        uint256 initialCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 initialCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        uint256 initialReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(550));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(
                fixedPaymentTemplate.NVM_CONTRACT_NAME(),
                address(this),
                agreementSeed,
                planId,
                numberOfPurchases,
                params
            )
        );

        uint256 paymentAmount = (100 * 10 ** 18) * numberOfPurchases;

        {
            // Approve tokens for PaymentsVault
            mockERC20.approve(address(paymentsVault), paymentAmount);
        }

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order(agreementSeed, planId, address(this), numberOfPurchases, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);
        assertEq(agreement.numberOfPurchases, numberOfPurchases);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer
        uint256 finalCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(
            finalCreatorNftBalance - initialCreatorNftBalance,
            100 * numberOfPurchases,
            'NFT credits should be minted to creator'
        );

        // Verify ERC20 payment distribution
        uint256 finalCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 finalVaultTokenBalance = mockERC20.balanceOf(address(paymentsVault));
        uint256 finalReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Creator should have spent 100 tokens
        assertEq(
            initialCreatorTokenBalance - finalCreatorTokenBalance, paymentAmount, 'Creator should have spent 300 tokens'
        );
        // Vault balance should be 0 since payments were distributed
        assertEq(finalVaultTokenBalance, 0, 'Vault token balance should be 0 after distribution');
        // Receiver should have received 300 tokens
        assertEq(
            finalReceiverTokenBalance - initialReceiverTokenBalance,
            paymentAmount,
            'Receiver should have received 300 tokens'
        );
    }

    function test_order_revertIfPlanNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Try to create agreement with non-existent plan
        bytes32 agreementSeed = bytes32(uint256(2));
        uint256 nonExistentPlanId = 999;
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IAsset.PlanNotFound.selector, nonExistentPlanId));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, nonExistentPlanId, address(this), 1, params);
    }

    function test_order_revertIfInvalidSeed() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan _createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Try to create agreement with zero seed
        bytes32 zeroSeed = bytes32(0);
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidSeed.selector, zeroSeed));
        fixedPaymentTemplate.order{value: 100}(zeroSeed, planId, address(this), 1, params);
    }

    function test_order_revertIfInvalidPlanID() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Try to create agreement with zero plan ID
        bytes32 agreementSeed = bytes32(uint256(2));
        uint256 zeroPlanId = 0;
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidPlanId.selector, zeroPlanId));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, zeroPlanId, address(this), 1, params);
    }

    function test_order_revertIfInvalidReceiver() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan _createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Try to create agreement with zero address receiver
        bytes32 agreementSeed = bytes32(uint256(2));
        address zeroAddress = address(0);
        bytes[] memory params = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(ITemplate.InvalidReceiver.selector, zeroAddress));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, zeroAddress, 1, params);
    }

    function test_order_revertIfInvalidTemplateAddress() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan_createCryptoPricePlan
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

        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        uint256 planId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 0);

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Must revert because the template address associated with the plan is not FixedPaymentTemplate
        vm.expectRevert(
            abi.encodeWithSelector(IAsset.PlanWithInvalidTemplate.selector, planId, address(fixedPaymentTemplate))
        );
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);
    }

    function test_order_revertIfAgreementAlreadyRegistered() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan_createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        // Create first agreement
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);

        // Try to create the same agreement again
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementAlreadyRegistered.selector, expectedAgreementId));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);
    }

    function test_orderWithERC20_refundOnTransferFailure() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan with ERC20 payment
        uint256 planId = _createERC20FixedPricePlan();

        // Get initial balances
        uint256 initialCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 initialCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        uint256 initialReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        {
            // Approve tokens for PaymentsVault
            uint256 paymentAmount = 101 * 10 ** 18;
            mockERC20.approve(address(paymentsVault), paymentAmount);
        }

        // Mock the transfer condition to fail
        vm.mockCall(
            address(transferCreditsCondition),
            abi.encodeWithSelector(transferCreditsCondition.fulfill.selector),
            abi.encode(bytes('Transfer failed'))
        );

        // Create agreement - this should still succeed but transfer condition will fail
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order(agreementSeed, planId, address(this), 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);

        // Lock payment should be fulfilled
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        // Transfer credits should be uninitialized due to our mock
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Uninitialized));
        // Distribute payments should be fulfilled (with refund)
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer agent not happen
        uint256 finalCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(
            finalCreatorNftBalance - initialCreatorNftBalance,
            0,
            'No NFT credits should be minted due to transfer failure'
        );

        // Verify ERC20 payment was refunded
        uint256 finalCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 finalVaultTokenBalance = mockERC20.balanceOf(address(paymentsVault));
        uint256 finalReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Creator should have their tokens back (minus gas)
        assertEq(finalCreatorTokenBalance, initialCreatorTokenBalance, 'Creator should have their tokens refunded');
        // Vault balance should be 0 since payment was refunded
        assertEq(finalVaultTokenBalance, 0, 'Vault token balance should be 0 after refund');
        // Receiver should not have received any tokens
        assertEq(finalReceiverTokenBalance, initialReceiverTokenBalance, 'Receiver should not have received any tokens');
    }

    function test_order_refundOnTransferFailure() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan_createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Get initial balances
        uint256 initialCreatorBalance = address(this).balance;
        uint256 initialCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        uint256 initialReceiverBalance = address(receiver).balance;

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        // Mock the transfer condition to fail
        vm.mockCall(
            address(transferCreditsCondition),
            abi.encodeWithSelector(transferCreditsCondition.fulfill.selector),
            abi.encode(bytes('Transfer failed'))
        );

        // Create agreement - this should still succeed but transfer condition will fail
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);

        // Lock payment should be fulfilled
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        // Transfer credits should be uninitialized due to our mock
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Uninitialized));
        // Distribute payments should be fulfilled (with refund)
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer agent not happen
        uint256 finalCreatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(
            finalCreatorNftBalance - initialCreatorNftBalance,
            0,
            'No NFT credits should be minted due to transfer failure'
        );

        // Verify native ETH payment was refunded
        uint256 finalCreatorBalance = address(this).balance;
        uint256 finalVaultBalance = address(paymentsVault).balance;
        uint256 finalReceiverBalance = address(receiver).balance;

        // Creator should have their ETH back (minus gas)
        assertEq(finalCreatorBalance, initialCreatorBalance, 'Creator should have their ETH refunded');
        // Vault balance should be 0 since payment was refunded
        assertEq(finalVaultBalance, 0, 'Vault balance should be 0 after refund');
        // Receiver should not have received any ETH
        assertEq(finalReceiverBalance, initialReceiverBalance, 'Receiver should not have received any ETH');
    }

    function test_order_revertIfConditionAlreadyFulfilled() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan_createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        // Create first agreement
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);

        // Get the condition IDs
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        bytes32 lockPaymentConditionId = agreement.conditionIds[0];
        bytes32 transferConditionId = agreement.conditionIds[1];
        bytes32 distributeConditionId = agreement.conditionIds[2];

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
                IAgreement.ConditionAlreadyFulfilled.selector, expectedAgreementId, transferConditionId
            )
        );
        transferCreditsCondition.fulfill(
            transferConditionId, expectedAgreementId, planId, requiredConditions, address(this)
        );

        // Try to fulfill distribute condition again
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgreement.ConditionAlreadyFulfilled.selector, expectedAgreementId, distributeConditionId
            )
        );
        distributePaymentsCondition.fulfill(
            distributeConditionId, expectedAgreementId, planId, lockPaymentConditionId, transferConditionId
        );
    }

    function test_order_revertIfConditionPreconditionFailed() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan_createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Create agreement using FixedPaymentTemplate
        bytes32 agreementSeed = bytes32(uint256(2));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        uint256 snapshot = vm.snapshotState();

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);

        // Get the condition IDs
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        bytes32 lockPaymentConditionId = agreement.conditionIds[0];
        bytes32 distributeConditionId = agreement.conditionIds[2];

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

        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, address(this), 1, params);
    }

    function test_order_revertIfAgreementNotFound() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan_createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Create a non-existent agreement ID
        bytes32 nonExistentAgreementId = keccak256(abi.encodePacked('non-existent'));
        bytes32 lockPaymentConditionId = keccak256(abi.encodePacked('lock-payment'));
        bytes32 transferConditionId = keccak256(abi.encodePacked('transfer'));
        bytes32 distributeConditionId = keccak256(abi.encodePacked('distribute'));

        // Try to fulfill lock payment condition for non-existent agreement
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        lockPaymentCondition.fulfill{value: 100}(lockPaymentConditionId, nonExistentAgreementId, planId, address(this));

        // Try to fulfill transfer condition for non-existent agreement
        bytes32[] memory requiredConditions = new bytes32[](1);
        requiredConditions[0] = lockPaymentConditionId;
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        transferCreditsCondition.fulfill(
            transferConditionId, nonExistentAgreementId, planId, requiredConditions, address(this)
        );

        // Try to fulfill distribute condition for non-existent agreement
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementNotFound.selector, nonExistentAgreementId));
        distributePaymentsCondition.fulfill(
            distributeConditionId, nonExistentAgreementId, planId, lockPaymentConditionId, transferConditionId
        );
    }

    function test_order_sendCreditsToArbitraryAddress() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan_createCryptoPricePlan
        uint256 planId = _createCryptoPricePlan();

        // Create an arbitrary receiver address
        address arbitraryReceiver = makeAddr('arbitraryReceiver');

        // Get initial balances
        uint256 initialCreatorBalance = address(this).balance;
        uint256 initialArbitraryReceiverNftBalance = nftCredits.balanceOf(arbitraryReceiver, planId);
        uint256 initialReceiverBalance = address(receiver).balance;

        // Create agreement using FixedPaymentTemplate with arbitrary receiver
        bytes32 agreementSeed = bytes32(uint256(3));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order{value: 100}(agreementSeed, planId, arbitraryReceiver, 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer to arbitrary receiver
        uint256 finalArbitraryReceiverNftBalance = nftCredits.balanceOf(arbitraryReceiver, planId);
        assertEq(
            finalArbitraryReceiverNftBalance - initialArbitraryReceiverNftBalance,
            100,
            'NFT credits should be minted to arbitrary receiver'
        );

        // Verify creator did not receive credits
        uint256 creatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(creatorNftBalance, 0, 'Creator should not have received any credits');

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

    function test_orderWithERC20_sendCreditsToArbitraryAddress() public {
        // Grant template role to this contract
        _grantTemplateRole(address(this));

        // Create a plan with ERC20 payment
        uint256 planId = _createERC20FixedPricePlan();

        // Create an arbitrary receiver address
        address arbitraryReceiver = makeAddr('arbitraryReceiver');

        // Get initial balances
        uint256 initialCreatorTokenBalance = mockERC20.balanceOf(address(this));
        uint256 initialArbitraryReceiverNftBalance = nftCredits.balanceOf(arbitraryReceiver, planId);
        uint256 initialReceiverTokenBalance = mockERC20.balanceOf(receiver);

        // Create agreement using FixedPaymentTemplate with arbitrary receiver
        bytes32 agreementSeed = bytes32(uint256(4));
        bytes[] memory params = new bytes[](0);

        // Calculate expected agreement ID
        bytes32 expectedAgreementId = keccak256(
            abi.encode(fixedPaymentTemplate.NVM_CONTRACT_NAME(), address(this), agreementSeed, planId, 1, params)
        );

        {
            // Approve tokens for PaymentsVault
            uint256 paymentAmount = 101 * 10 ** 18;
            mockERC20.approve(address(paymentsVault), paymentAmount);
        }

        // Create agreement
        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(expectedAgreementId, address(this));
        fixedPaymentTemplate.order(agreementSeed, planId, arbitraryReceiver, 1, params);

        // Verify agreement was registered
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(expectedAgreementId);
        assertEq(agreement.agreementCreator, address(this));
        assertTrue(agreement.lastUpdated > 0);
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);

        // Verify condition states
        IAgreement.ConditionState state1 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[0]);
        IAgreement.ConditionState state2 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[1]);
        IAgreement.ConditionState state3 =
            agreementsStore.getConditionState(expectedAgreementId, agreement.conditionIds[2]);
        assertEq(uint8(state1), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state2), uint8(IAgreement.ConditionState.Fulfilled));
        assertEq(uint8(state3), uint8(IAgreement.ConditionState.Fulfilled));

        // Verify NFT transfer to arbitrary receiver
        uint256 finalArbitraryReceiverNftBalance = nftCredits.balanceOf(arbitraryReceiver, planId);
        assertEq(
            finalArbitraryReceiverNftBalance - initialArbitraryReceiverNftBalance,
            100,
            'NFT credits should be minted to arbitrary receiver'
        );

        // Verify creator did not receive credits
        uint256 creatorNftBalance = nftCredits.balanceOf(address(this), planId);
        assertEq(creatorNftBalance, 0, 'Creator should not have received any credits');

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

    receive() external payable {}
}
