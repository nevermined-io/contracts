// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {IProtocolStandardFees} from '../../../contracts/interfaces/IProtocolStandardFees.sol';
import {BaseTest} from '../common/BaseTest.sol';

contract ProtocolStandardFeesTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialization() public view {
        (uint256 cryptoFeeRate, uint256 fiatFeeRate, uint256 feeDenominator) = protocolStandardFees.getFeeRates();
        assertEq(cryptoFeeRate, 100); // 1%
        assertEq(fiatFeeRate, 200); // 2%
        assertEq(feeDenominator, 10000); // Basis points
    }

    function test_updateFeeRates() public {
        vm.prank(governor);
        protocolStandardFees.updateFeeRates(150, 250); // 1.5% and 2.5%

        (uint256 cryptoFeeRate, uint256 fiatFeeRate, uint256 feeDenominator) = protocolStandardFees.getFeeRates();
        assertEq(cryptoFeeRate, 150);
        assertEq(fiatFeeRate, 250);
        assertEq(feeDenominator, 10000);
    }

    function test_updateFeeRates_revertIfNotGovernor() public {
        vm.prank(address(1));
        vm.expectRevert();
        protocolStandardFees.updateFeeRates(150, 250);
    }

    function test_updateFeeRates_revertIfInvalidFeeRate() public {
        vm.prank(governor);
        vm.expectRevert(IProtocolStandardFees.InvalidFeeRate.selector);
        protocolStandardFees.updateFeeRates(10001, 200); // cryptoFeeRate > feeDenominator
    }

    function test_updateFeeRates_revertIfInvalidFeeRate2() public {
        vm.prank(governor);
        vm.expectRevert(IProtocolStandardFees.InvalidFeeRate.selector);
        protocolStandardFees.updateFeeRates(100, 10001); // fiatFeeRate > feeDenominator
    }

    function test_calculateFee_crypto() public view {
        // Create a plan with crypto price type
        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(0),
            amounts: new uint256[](1),
            receivers: new address[](1),
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
        });
        priceConfig.amounts[0] = 1000; // 1000 wei
        priceConfig.receivers[0] = address(1);

        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 1,
            proofRequired: false,
            nftAddress: address(0)
        });

        IAsset.Plan memory plan = IAsset.Plan({
            owner: address(1), price: priceConfig, credits: creditsConfig, lastUpdated: vm.getBlockTimestamp()
        });

        uint256 totalAmount = priceConfig.amounts[0];
        (uint256 fee,,) = protocolStandardFees.calculateFee(totalAmount, plan.price, plan.credits);
        assertEq(fee, 10); // 1% of 1000 = 10
    }

    function test_calculateFee_fiat() public view {
        // Create a plan with fiat price type
        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: false,
            tokenAddress: address(0),
            amounts: new uint256[](1),
            receivers: new address[](1),
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
        });
        priceConfig.amounts[0] = 1000; // 1000 wei
        priceConfig.receivers[0] = address(1);

        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 1,
            proofRequired: false,
            nftAddress: address(0)
        });

        IAsset.Plan memory plan = IAsset.Plan({
            owner: address(1), price: priceConfig, credits: creditsConfig, lastUpdated: vm.getBlockTimestamp()
        });

        uint256 totalAmount = priceConfig.amounts[0];
        (uint256 fee,,) = protocolStandardFees.calculateFee(totalAmount, plan.price, plan.credits);
        assertEq(fee, 20); // 2% of 1000 = 20
    }

    function test_calculateFee_multipleReceivers() public view {
        // Create a plan with multiple receivers
        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(0),
            amounts: new uint256[](2),
            receivers: new address[](2),
            externalPriceAddress: address(0),
            feeController: IFeeController(address(0)),
            templateAddress: address(0)
        });
        priceConfig.amounts[0] = 1000; // 1000 wei
        priceConfig.amounts[1] = 2000; // 2000 wei
        priceConfig.receivers[0] = address(1);
        priceConfig.receivers[1] = address(2);

        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 1,
            proofRequired: false,
            nftAddress: address(0)
        });

        IAsset.Plan memory plan = IAsset.Plan({
            owner: address(1), price: priceConfig, credits: creditsConfig, lastUpdated: vm.getBlockTimestamp()
        });

        uint256 totalAmount = priceConfig.amounts[0] + priceConfig.amounts[1];
        (uint256 fee,,) = protocolStandardFees.calculateFee(totalAmount, plan.price, plan.credits);
        assertEq(fee, 30); // 1% of (1000 + 2000) = 30
    }
}
