// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {LockPaymentCondition} from '../../../contracts/conditions/LockPaymentCondition.sol';
import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';

import {IERC3009} from '../../../contracts/interfaces/IERC3009.sol';
import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {ITemplate} from '../../../contracts/interfaces/ITemplate.sol';
import {MockEIP3009Token} from '../../../contracts/test/MockEIP3009Token.sol';

import {BaseTest} from '../common/BaseTest.sol';
import {EIP3009Sign} from '../common/EIP3009Sign.sol';
import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';
import {ERC1155Holder} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

/// @notice Tests for the gasless EIP-3009 (`receiveWithAuthorization`) purchase path on
/// `FixedPaymentTemplate.orderWithAuthorization`, where the buyer signs a single off-chain
/// authorization to the PaymentsVault and a relayer submits the tx + pays gas, while the
/// Nevermined protocol fee is captured on-chain via the normal distribution split.
contract FixedPaymentTemplateAuthorizationTest is BaseTest, ERC1155Holder {
    address merchant = makeAddr('merchant');
    address relayer = makeAddr('relayer');

    address buyer;
    uint256 buyerPk;

    MockEIP3009Token token;

    function setUp() public override {
        super.setUp();

        // Configure the protocol fee receiver so plans fold in a real Nevermined fee (1% crypto)
        vm.prank(governor);
        nvmConfig.setFeeReceiver(nvmFeeReceiver);

        (buyer, buyerPk) = makeAddrAndKey('buyer');
        token = new MockEIP3009Token('Mock USDC', 'mUSDC');
        token.mint(buyer, 1_000_000 * 10 ** 18);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /// @dev Builds an ERC20 fixed-price plan paid in the EIP-3009 token, with Nevermined
    /// fees folded into amounts/receivers. Returns the planId, the fee-inclusive total the
    /// buyer pays, the merchant's net share, and the protocol fee.
    function _createEIP3009Plan() internal returns (uint256 planId, uint256 total, uint256 merchantNet, uint256 fee) {
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
            templateAddress: address(0)
        });
        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 1,
            onchainMirror: true,
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

    function _agreementId(
        bytes32 seed,
        uint256 planId,
        address creditsReceiver,
        uint256 numberOfPurchases,
        bytes[] memory params
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                fixedPaymentTemplate.NVM_CONTRACT_NAME(),
                buyer,
                seed,
                planId,
                creditsReceiver,
                numberOfPurchases,
                params
            )
        );
    }

    /// @dev Signs an EIP-3009 ReceiveWithAuthorization as the buyer. `nonce` is bound to the agreementId.
    function _sign(uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce)
        internal
        view
        returns (IERC3009.ReceiveAuthorization memory auth)
    {
        return _signAs(buyerPk, buyer, value, validAfter, validBefore, nonce);
    }

    /// @dev Signs an EIP-3009 ReceiveWithAuthorization with an arbitrary key and declared `from`.
    /// Used to exercise wrong-signer, wrong-value, wrong-nonce, and window-violation cases.
    function _signAs(
        uint256 signerPk,
        address from,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (IERC3009.ReceiveAuthorization memory auth) {
        bytes32 digest = EIP3009Sign.receiveDigest(
            token, from, address(paymentsVault), value, validAfter, validBefore, nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        auth = IERC3009.ReceiveAuthorization({validAfter: validAfter, validBefore: validBefore, v: v, r: r, s: s});
    }

    // ---------------------------------------------------------------------
    // Happy path
    // ---------------------------------------------------------------------

    function test_orderWithAuthorization_happyPath() public {
        (uint256 planId, uint256 total, uint256 merchantNet, uint256 fee) = _createEIP3009Plan();

        bytes32 seed = bytes32(uint256(7));
        bytes[] memory params = new bytes[](0);
        uint256 numberOfPurchases = 1;
        bytes32 agreementId = _agreementId(seed, planId, buyer, numberOfPurchases, params);

        uint256 validBefore = block.timestamp + 1 days;
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, validBefore, agreementId);

        uint256 buyerTokenBefore = token.balanceOf(buyer);
        uint256 merchantTokenBefore = token.balanceOf(merchant);
        uint256 feeReceiverTokenBefore = token.balanceOf(nvmFeeReceiver);

        vm.expectEmit(true, true, true, true);
        emit IAgreement.AgreementRegistered(agreementId, buyer);

        vm.prank(relayer);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, numberOfPurchases, params, auth);

        // Agreement registered with the BUYER as creator (not the relayer)
        IAgreement.Agreement memory agreement = agreementsStore.getAgreement(agreementId);
        assertEq(agreement.agreementCreator, buyer, 'creator must be buyer');
        assertEq(agreement.planId, planId);
        assertEq(agreement.conditionIds.length, 3);
        for (uint256 i; i < 3; i++) {
            assertEq(
                uint8(agreementsStore.getConditionState(agreementId, agreement.conditionIds[i])),
                uint8(IAgreement.ConditionState.Fulfilled),
                'all conditions fulfilled'
            );
        }

        // Credits minted to the buyer
        assertEq(nftCredits.balanceOf(buyer, planId), 100, 'buyer gets credits');

        // Funds split: buyer paid the gross total, merchant got net, fee receiver got the fee, vault drained
        assertGt(fee, 0, 'fee must be non-zero');
        assertEq(merchantNet + fee, total, 'net + fee == total');
        assertEq(buyerTokenBefore - token.balanceOf(buyer), total, 'buyer paid gross total');
        assertEq(token.balanceOf(merchant) - merchantTokenBefore, merchantNet, 'merchant got net');
        assertEq(token.balanceOf(nvmFeeReceiver) - feeReceiverTokenBefore, fee, 'fee captured');
        assertEq(token.balanceOf(address(paymentsVault)), 0, 'vault drained');

        // Authorization nonce consumed (replay-proof)
        assertTrue(token.authorizationState(buyer, agreementId), 'nonce consumed');
    }

    // ---------------------------------------------------------------------
    // Variations
    // ---------------------------------------------------------------------

    function test_orderWithAuthorization_multiplePurchases() public {
        (uint256 planId, uint256 total, uint256 merchantNet, uint256 fee) = _createEIP3009Plan();
        uint256 n = 3;
        bytes32 seed = bytes32(uint256(11));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, n, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total * n, 0, block.timestamp + 1 days, agreementId);

        uint256 buyerBefore = token.balanceOf(buyer);
        vm.prank(relayer);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, n, params, auth);

        assertEq(nftCredits.balanceOf(buyer, planId), 100 * n, 'credits scale with purchases');
        assertEq(buyerBefore - token.balanceOf(buyer), total * n, 'buyer paid n*total');
        assertEq(token.balanceOf(merchant), merchantNet * n, 'merchant got n*net');
        assertEq(token.balanceOf(nvmFeeReceiver), fee * n, 'fee scaled');
        assertEq(token.balanceOf(address(paymentsVault)), 0, 'vault drained');
    }

    function test_orderWithAuthorization_creditsToArbitraryReceiver() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        address creditsReceiver = makeAddr('creditsReceiver');
        bytes32 seed = bytes32(uint256(12));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, creditsReceiver, 1, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, creditsReceiver, 1, params, auth);

        assertEq(nftCredits.balanceOf(creditsReceiver, planId), 100, 'credits to arbitrary receiver');
        assertEq(nftCredits.balanceOf(buyer, planId), 0, 'buyer did not receive credits');
    }

    // ---------------------------------------------------------------------
    // Security / failure modes
    // ---------------------------------------------------------------------

    function test_orderWithAuthorization_revertOnReplay() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(13));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IAgreement.AgreementAlreadyRegistered.selector, agreementId));
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);
    }

    function test_orderWithAuthorization_revertOnWrongSigner() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        (, uint256 attackerPk) = makeAddrAndKey('attacker');
        bytes32 seed = bytes32(uint256(14));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        // from = buyer, but signed by the attacker → on-chain recovery mismatch
        IERC3009.ReceiveAuthorization memory auth =
            _signAs(attackerPk, buyer, total, 0, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.InvalidSignature.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);
    }

    function test_orderWithAuthorization_revertOnWrongValue() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(15));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        // Buyer signs over a value different from the plan total; the protocol pulls exactly the
        // plan total, so the signature does not verify for that amount.
        IERC3009.ReceiveAuthorization memory auth = _sign(total + 1, 0, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.InvalidSignature.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);
    }

    function test_orderWithAuthorization_revertOnWrongNonceBinding() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(16));
        bytes[] memory params = new bytes[](0);
        // Buyer signs with an arbitrary nonce that is NOT the agreementId; the protocol forces the
        // nonce to equal the agreementId, so the signature cannot be applied to this (or any) order.
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, block.timestamp + 1 days, bytes32(uint256(0xDEAD)));

        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.InvalidSignature.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);
    }

    function test_orderWithAuthorization_revertOnExpired() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(17));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        uint256 validBefore = block.timestamp + 100;
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, validBefore, agreementId);

        vm.warp(validBefore + 1);
        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.AuthorizationExpired.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);
    }

    function test_orderWithAuthorization_revertOnNotYetValid() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(18));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        uint256 validAfter = block.timestamp + 1000;
        IERC3009.ReceiveAuthorization memory auth = _sign(total, validAfter, validAfter + 1 days, agreementId);

        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.AuthorizationNotYetValid.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);
    }

    function test_orderWithAuthorization_revertOnZeroBuyer() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(19));
        bytes[] memory params = new bytes[](0);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, block.timestamp + 1 days, bytes32(0));

        vm.prank(relayer);
        vm.expectRevert(ITemplate.InvalidAddress.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, address(0), buyer, 1, params, auth);
    }

    function test_orderWithAuthorization_revertOnNativeTokenPlan() public {
        uint256 planId = _createNativePlan();
        bytes32 seed = bytes32(uint256(20));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(100, 0, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        vm.expectRevert(LockPaymentCondition.NativeTokenNotSupportedForAuthorization.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);
    }

    /// @notice A relayer cannot redirect credits: creditsReceiver is bound into the agreementId/nonce,
    /// so changing it invalidates the buyer's signature.
    function test_orderWithAuthorization_revertOnCreditsReceiverTampering() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        address attacker = makeAddr('attacker');
        bytes32 seed = bytes32(uint256(22));
        bytes[] memory params = new bytes[](0);
        // Buyer signs intending credits to themselves
        bytes32 signedAgreementId = _agreementId(seed, planId, buyer, 1, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, block.timestamp + 1 days, signedAgreementId);

        // Relayer attempts to redirect the credits to the attacker → agreementId (nonce) differs → reverts
        vm.prank(relayer);
        vm.expectRevert(MockEIP3009Token.InvalidSignature.selector);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, attacker, 1, params, auth);
    }

    /// @notice On a downstream failure (credits transfer aborts), the locked funds are refunded to the
    /// BUYER (the agreement creator), never the relayer, and no credits/fee are produced.
    function test_orderWithAuthorization_refundOnTransferFailure() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(21));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, block.timestamp + 1 days, agreementId);

        uint256 buyerBefore = token.balanceOf(buyer);

        // Make the transfer-credits condition a no-op so the release condition stays unfulfilled
        vm.mockCall(
            address(transferCreditsCondition),
            abi.encodeWithSelector(transferCreditsCondition.fulfill.selector),
            abi.encode(bytes('Transfer failed'))
        );

        vm.prank(relayer);
        fixedPaymentTemplate.orderWithAuthorization(seed, planId, buyer, buyer, 1, params, auth);

        assertEq(nftCredits.balanceOf(buyer, planId), 0, 'no credits minted on failure');
        assertEq(token.balanceOf(buyer), buyerBefore, 'buyer fully refunded');
        assertEq(token.balanceOf(merchant), 0, 'merchant got nothing');
        assertEq(token.balanceOf(nvmFeeReceiver), 0, 'no fee on failure');
        assertEq(token.balanceOf(address(paymentsVault)), 0, 'vault drained');
    }

    /// @notice The lock condition's authorization entrypoint is only callable by a template
    /// (CONTRACT_TEMPLATE_ROLE); a direct call from any other address is rejected.
    function test_fulfillWithAuthorization_onlyTemplate() public {
        (uint256 planId, uint256 total,,) = _createEIP3009Plan();
        bytes32 seed = bytes32(uint256(23));
        bytes[] memory params = new bytes[](0);
        bytes32 agreementId = _agreementId(seed, planId, buyer, 1, params);
        IERC3009.ReceiveAuthorization memory auth = _sign(total, 0, block.timestamp + 1 days, agreementId);

        vm.prank(relayer);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        lockPaymentCondition.fulfillWithAuthorization(agreementId, agreementId, planId, buyer, auth);
    }

    /// @dev Native-token (ETH) fixed-price plan — used to assert the authorization path rejects it.
    function _createNativePlan() internal returns (uint256 planId) {
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
            templateAddress: address(0)
        });
        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 1,
            onchainMirror: true,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        assetsRegistry.createPlan(priceConfig, creditsConfig, 1);
        planId = assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 1);
    }
}
