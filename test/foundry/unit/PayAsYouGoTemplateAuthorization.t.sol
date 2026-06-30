// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {LockPaymentCondition} from '../../../contracts/conditions/LockPaymentCondition.sol';
import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';

import {IERC3009} from '../../../contracts/interfaces/IERC3009.sol';
import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {MockEIP3009Token} from '../../../contracts/test/MockEIP3009Token.sol';

import {BaseTest} from '../common/BaseTest.sol';
import {EIP3009Sign} from '../common/EIP3009Sign.sol';
import {ERC1155Holder} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

/// @notice Tests for the gasless EIP-3009 purchase path on `PayAsYouGoTemplate.orderWithAuthorization`.
/// PayAsYouGo distributes the payment directly (merchant net + Nevermined fee) without minting credits.
contract PayAsYouGoTemplateAuthorizationTest is BaseTest, ERC1155Holder {
    address merchant = makeAddr('merchant');
    address relayer = makeAddr('relayer');

    address buyer;
    uint256 buyerPk;

    MockEIP3009Token token;

    function setUp() public override {
        super.setUp();

        vm.prank(governor);
        nvmConfig.setFeeReceiver(nvmFeeReceiver);

        (buyer, buyerPk) = makeAddrAndKey('buyer');
        token = new MockEIP3009Token('Mock USDC', 'mUSDC');
        token.mint(buyer, 1_000_000 * 10 ** 18);
    }

    function _createPayGoPlan() internal returns (uint256 planId, uint256 total, uint256 merchantNet, uint256 fee) {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100 * 10 ** 18;
        address[] memory _receivers = new address[](1);
        _receivers[0] = merchant;

        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(token),
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
            onchainMirror: false,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        for (uint256 i; i < amounts.length; i++) {
            total += amounts[i];
            if (receivers[i] == nvmFeeReceiver) fee += amounts[i];
            else if (receivers[i] == merchant) merchantNet += amounts[i];
        }

        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        planId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 0);
    }

    function _agreementId(bytes32 seed, uint256 planId, bytes[] memory params) internal view returns (bytes32) {
        return keccak256(abi.encode(payAsYouGoTemplate.NVM_CONTRACT_NAME(), buyer, seed, planId, params));
    }

    function _signAs(uint256 signerPk, address from, uint256 value, uint256 validBefore, bytes32 nonce)
        internal
        view
        returns (IERC3009.ReceiveAuthorization memory auth)
    {
        bytes32 digest = EIP3009Sign.receiveDigest(token, from, address(paymentsVault), value, 0, validBefore, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        auth = IERC3009.ReceiveAuthorization({validAfter: 0, validBefore: validBefore, v: v, r: r, s: s});
    }

    function _sign(uint256 value, uint256 validBefore, bytes32 nonce)
        internal
        view
        returns (IERC3009.ReceiveAuthorization memory auth)
    {
        return _signAs(buyerPk, buyer, value, validBefore, nonce);
    }

    function test_orderWithAuthorization_happyPath() public {
        (uint256 planId, uint256 total, uint256 merchantNet, uint256 fee) = _createPayGoPlan();
        bytes32 seed = bytes32(uint256(7));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, block.timestamp + 1 days, agreementId);

        uint256 buyerBefore = token.balanceOf(buyer);

        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(agreementId, buyer);

        vm.prank(relayer);
        payAsYouGoTemplate.orderWithAuthorization(seed, planId, buyer, params, auth);

        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(agreementId);
        assertEq(agreement.agreementCreator, buyer, 'creator must be buyer');
        assertEq(agreement.conditionIds.length, 2);
        for (uint256 i; i < 2; i++) {
            assertEq(
                uint8(agreementsStore.getConditionState(agreementId, agreement.conditionIds[i])),
                uint8(IAgreement.ConditionState.Fulfilled),
                'conditions fulfilled'
            );
        }

        assertGt(fee, 0, 'fee must be non-zero');
        assertEq(merchantNet + fee, total, 'net + fee == total');
        assertEq(buyerBefore - token.balanceOf(buyer), total, 'buyer paid gross total');
        assertEq(token.balanceOf(merchant), merchantNet, 'merchant got net');
        assertEq(token.balanceOf(nvmFeeReceiver), fee, 'fee captured');
        assertEq(token.balanceOf(address(paymentsVault)), 0, 'vault drained');
        assertTrue(token.authorizationState(buyer, agreementId), 'nonce consumed');
    }

    function test_orderWithAuthorization_revertOnReplay() public {
        (uint256 planId, uint256 total,,) = _createPayGoPlan();
        bytes32 seed = bytes32(uint256(8));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        payAsYouGoTemplate.orderWithAuthorization(seed, planId, buyer, params, auth);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementAlreadyRegistered.selector, agreementId));
        payAsYouGoTemplate.orderWithAuthorization(seed, planId, buyer, params, auth);
    }

    function test_orderWithAuthorization_revertOnWrongSigner() public {
        (uint256 planId, uint256 total,,) = _createPayGoPlan();
        (, uint256 attackerPk) = makeAddrAndKey('attacker');
        bytes32 seed = bytes32(uint256(9));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, params);
        IERC3009.ReceiveAuthorization memory auth =
            _signAs(attackerPk, buyer, total, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.InvalidSignature.selector);
        payAsYouGoTemplate.orderWithAuthorization(seed, planId, buyer, params, auth);
    }

    function test_orderWithAuthorization_revertOnWrongNonceBinding() public {
        (uint256 planId, uint256 total,,) = _createPayGoPlan();
        bytes32 seed = bytes32(uint256(10));
        bytes[] memory params = new bytes[](0);
        // Signed with an arbitrary nonce, not the agreementId → protocol forces nonce=agreementId
        IERC3009.ReceiveAuthorization memory auth = _sign(total, block.timestamp + 1 days, bytes32(uint256(0xBEEF)));

        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.InvalidSignature.selector);
        payAsYouGoTemplate.orderWithAuthorization(seed, planId, buyer, params, auth);
    }

    function test_orderWithAuthorization_revertOnZeroBuyer() public {
        (uint256 planId, uint256 total,,) = _createPayGoPlan();
        bytes32 seed = bytes32(uint256(11));
        bytes[] memory params = new bytes[](0);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, block.timestamp + 1 days, bytes32(0));

        vm.prank(relayer);
        vm.expectRevert();
        payAsYouGoTemplate.orderWithAuthorization(seed, planId, address(0), params, auth);
    }

    function test_orderWithAuthorization_revertOnNativeTokenPlan() public {
        // Native-token plan associated with PayAsYouGo cannot use the ERC20 authorization path
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100;
        address[] memory _receivers = new address[](1);
        _receivers[0] = merchant;
        IAsset.PriceConfig memory priceConfig = IAsset.PriceConfig({
            isCrypto: true,
            tokenAddress: address(0),
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
            onchainMirror: false,
            nftAddress: address(nftCredits)
        });
        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;
        assetsRegistry.createPlan(priceConfig, creditsConfig, 1);
        uint256 planId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 1);

        bytes32 seed = bytes32(uint256(12));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(100, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        vm.expectRevert(LockPaymentCondition.NativeTokenNotSupportedForAuthorization.selector);
        payAsYouGoTemplate.orderWithAuthorization(seed, planId, buyer, params, auth);
    }
}
