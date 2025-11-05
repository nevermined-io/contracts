// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {AssetsRegistry} from '../../../contracts/AssetsRegistry.sol';
import {NVMConfig} from '../../../contracts/NVMConfig.sol';

import {PaymentsVault} from '../../../contracts/PaymentsVault.sol';
import {AgreementsStore} from '../../../contracts/agreements/AgreementsStore.sol';
import {FiatPaymentTemplate} from '../../../contracts/agreements/FiatPaymentTemplate.sol';
import {FixedPaymentTemplate} from '../../../contracts/agreements/FixedPaymentTemplate.sol';
import {PayAsYouGoTemplate} from '../../../contracts/agreements/PayAsYouGoTemplate.sol';
import '../../../contracts/common/Roles.sol';
import {DistributePaymentsCondition} from '../../../contracts/conditions/DistributePaymentsCondition.sol';
import {FiatSettlementCondition} from '../../../contracts/conditions/FiatSettlementCondition.sol';
import {LockPaymentCondition} from '../../../contracts/conditions/LockPaymentCondition.sol';
import {TransferCreditsCondition} from '../../../contracts/conditions/TransferCreditsCondition.sol';

import {ProtocolStandardFees} from '../../../contracts/fees/ProtocolStandardFees.sol';
import {OneTimeCreatorHook} from '../../../contracts/hooks/OneTimeCreatorHook.sol';
import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {AgreementsStoreV2} from '../../../contracts/mock/AgreementsStoreV2.sol';
import {AssetsRegistryV2} from '../../../contracts/mock/AssetsRegistryV2.sol';
import {NFT1155CreditsV2} from '../../../contracts/mock/NFT1155CreditsV2.sol';
import {NFT1155ExpirableCreditsMock} from '../../../contracts/mock/NFT1155ExpirableCreditsMock.sol';
import {NVMConfigV2} from '../../../contracts/mock/NVMConfigV2.sol';
import {PaymentsVaultV2} from '../../../contracts/mock/PaymentsVaultV2.sol';

import {LinearPricing} from '../../../contracts/pricing/LinearPricing.sol';
import {NFT1155Credits} from '../../../contracts/token/NFT1155Credits.sol';
import {NFT1155ExpirableCredits} from '../../../contracts/token/NFT1155ExpirableCredits.sol';
import {NFT1155ExpirableCreditsV2} from '../../../contracts/token/NFT1155ExpirableCreditsV2.sol';
import {DeployAll, DeployedContracts} from '../../../scripts/deploy/DeployAll.sol';
import {ManagePermissions} from '../../../scripts/deploy/ManagePermissions.sol';
import {ToArrayUtils} from './ToArrayUtils.sol';
import {AccessManager} from '@openzeppelin/contracts/access/manager/AccessManager.sol';
import {Test} from 'forge-std/Test.sol';

abstract contract BaseTest is Test, ToArrayUtils {
    // Configuration
    uint32 constant UPGRADE_DELAY = 7 days;

    // Addresses
    address owner = makeAddr('owner');
    address upgrader = makeAddr('upgrader');
    address governor = makeAddr('governor');
    address nvmFeeReceiver = makeAddr('nvmFeeReceiver');
    address alice = makeAddr('alice');

    // Contracts
    AccessManager accessManager;
    NVMConfig nvmConfig;
    AssetsRegistry assetsRegistry;
    AgreementsStore agreementsStore;
    PaymentsVault paymentsVault;
    NFT1155Credits nftCredits;
    NFT1155ExpirableCredits nftExpirableCredits;
    NFT1155ExpirableCreditsV2 nftExpirableCreditsV2;
    LockPaymentCondition lockPaymentCondition;
    TransferCreditsCondition transferCreditsCondition;
    DistributePaymentsCondition distributePaymentsCondition;
    FiatSettlementCondition fiatSettlementCondition;
    FixedPaymentTemplate fixedPaymentTemplate;
    PayAsYouGoTemplate payAsYouGoTemplate;
    FiatPaymentTemplate fiatPaymentTemplate;
    OneTimeCreatorHook oneTimeCreatorHook;
    ProtocolStandardFees protocolStandardFees;
    LinearPricing linearPricing;

    function setUp() public virtual {
        _deployContracts();

        // Setup the roles for v2 initializations
        vm.startPrank(owner);
        accessManager.setTargetFunctionRole(
            address(nvmConfig), toArray(NVMConfigV2.initializeV2.selector), GOVERNOR_ROLE
        );
        accessManager.setTargetFunctionRole(
            address(agreementsStore), toArray(AgreementsStoreV2.initializeV2.selector), GOVERNOR_ROLE
        );
        accessManager.setTargetFunctionRole(
            address(nftCredits), toArray(NFT1155CreditsV2.initializeV2.selector), GOVERNOR_ROLE
        );
        accessManager.setTargetFunctionRole(
            address(paymentsVault), toArray(PaymentsVaultV2.initializeV2.selector), GOVERNOR_ROLE
        );
        accessManager.setTargetFunctionRole(
            address(assetsRegistry), toArray(AssetsRegistryV2.initializeV2.selector), GOVERNOR_ROLE
        );
        accessManager.setTargetFunctionRole(
            address(nftExpirableCredits), toArray(NFT1155ExpirableCreditsMock.initializeV2.selector), GOVERNOR_ROLE
        );
        vm.stopPrank();
    }

    function _deployContracts() internal virtual {
        // Set the addresses
        vm.setEnv('GOVERNOR_ADDRESS', vm.toString(governor));
        vm.setEnv('OWNER_ADDRESS', vm.toString(owner));
        vm.setEnv('CONTRACTS_DEPLOYMENT_VERSION', '1.3.1');

        // Deploy the contracts
        DeployedContracts memory deployed = new DeployAll().run();

        accessManager = deployed.accessManager;
        nvmConfig = deployed.nvmConfig;
        assetsRegistry = deployed.assetsRegistry;
        agreementsStore = deployed.agreementsStore;
        paymentsVault = deployed.paymentsVault;
        nftCredits = deployed.nftCredits;
        nftExpirableCredits = deployed.nftExpirableCredits;
        nftExpirableCreditsV2 = deployed.nftExpirableCreditsV2;
        lockPaymentCondition = deployed.lockPaymentCondition;
        transferCreditsCondition = deployed.transferCreditsCondition;
        distributePaymentsCondition = deployed.distributePaymentsCondition;
        fiatSettlementCondition = deployed.fiatSettlementCondition;
        fixedPaymentTemplate = deployed.fixedPaymentTemplate;
        fiatPaymentTemplate = deployed.fiatPaymentTemplate;
        payAsYouGoTemplate = deployed.payAsYouGoTemplate;
        oneTimeCreatorHook = deployed.oneTimeCreatorHook;
        protocolStandardFees = deployed.protocolStandardFees;
        linearPricing = deployed.linearPricing;

        ManagePermissions.Config memory config = ManagePermissions.Config({
            owner: owner,
            upgrader: upgrader,
            governor: governor,
            nvmConfig: nvmConfig,
            assetsRegistry: assetsRegistry,
            agreementsStore: agreementsStore,
            paymentsVault: paymentsVault,
            nftCredits: nftCredits,
            nftExpirableCredits: nftExpirableCredits,
            nftExpirableCreditsV2: nftExpirableCreditsV2,
            lockPaymentCondition: lockPaymentCondition,
            distributePaymentsCondition: distributePaymentsCondition,
            transferCreditsCondition: transferCreditsCondition,
            fiatSettlementCondition: fiatSettlementCondition,
            fixedPaymentTemplate: fixedPaymentTemplate,
            fiatPaymentTemplate: fiatPaymentTemplate,
            payAsYouGoTemplate: payAsYouGoTemplate,
            oneTimeCreatorHook: oneTimeCreatorHook,
            protocolStandardFees: protocolStandardFees,
            accessManager: accessManager
        });

        // Grant permissions
        new ManagePermissions().run(config);
    }

    function _grantRole(uint64 role, address _caller) internal virtual {
        vm.prank(owner);
        accessManager.grantRole(role, _caller, 0);
    }

    function _grantRoleAs(uint64 role, address _granter, address _grantee) internal virtual {
        vm.prank(_granter);
        accessManager.grantRole(role, _grantee, 0);
    }

    function _setRoleAdmin(uint64 role, uint64 adminRole) internal virtual {
        vm.prank(owner);
        accessManager.setRoleAdmin(role, adminRole);
    }

    function _grantTemplateRole(address _caller) internal virtual {
        vm.prank(governor);
        accessManager.grantRole(CONTRACT_TEMPLATE_ROLE, _caller, 0);
    }

    function _grantConditionRole(address _caller) internal virtual {
        vm.prank(governor);
        accessManager.grantRole(CONTRACT_CONDITION_ROLE, _caller, 0);
    }

    function _order(address _caller, uint256 _planId) internal virtual returns (bytes32) {
        bytes32[] memory conditionIds = new bytes32[](1);
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);

        conditionIds[0] = keccak256('abc');
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;

        _grantTemplateRole(address(this));
        bytes32 agreementId = keccak256('123');

        agreementsStore.register(agreementId, _caller, _planId, conditionIds, conditionStates, 1, new bytes[](0));
        return agreementId;
    }

    function _createPlan() internal returns (uint256) {
        uint256 nonce = block.number;
        return _createPlan(nonce);
    }

    function _createPlan(uint256 nonce) internal returns (uint256) {
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

        assetsRegistry.createPlan(priceConfig, creditsConfig, nonce);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), nonce);
    }

    function _createPlanWithProofRequired(uint256 nonce) internal returns (uint256) {
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
            templateAddress: address(0)
        });
        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: true,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 1,
            proofRequired: true,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        assetsRegistry.createPlan(priceConfig, creditsConfig, nonce);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), nonce);
    }

    function _createPlanWithProofRequiredAndRedemptionType(IAsset.RedemptionType redemptionType)
        internal
        returns (uint256)
    {
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
            templateAddress: address(0)
        });
        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: false,
            redemptionType: redemptionType,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 100,
            proofRequired: true,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, address(this), 0);
    }

    function _createPlanWithAmountAndRedemptionType(uint256 amount, IAsset.RedemptionType redemptionType)
        internal
        virtual
        returns (uint256)
    {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = amount;
        address[] memory _receivers = new address[](1);
        _receivers[0] = address(this);

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
            isRedemptionAmountFixed: false,
            redemptionType: redemptionType,
            durationSecs: 0,
            amount: amount,
            minAmount: 1,
            maxAmount: 100,
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

    function _createPlanWithAmountAndRedemptionTypeAsOwner(
        uint256 amount,
        IAsset.RedemptionType redemptionType,
        address planOwner
    ) internal returns (uint256) {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = amount;
        address[] memory _receivers = new address[](1);
        _receivers[0] = planOwner;

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
            isRedemptionAmountFixed: false,
            redemptionType: redemptionType,
            durationSecs: 0,
            amount: amount,
            minAmount: 1,
            maxAmount: 100,
            proofRequired: false,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        vm.prank(planOwner);
        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, planOwner, 0);
    }

    function _createPlanWithProofRequiredAndRedemptionTypeAsOwner(
        IAsset.RedemptionType redemptionType,
        address planOwner
    ) internal returns (uint256) {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100;
        address[] memory _receivers = new address[](1);
        _receivers[0] = planOwner;

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
            isRedemptionAmountFixed: false,
            redemptionType: redemptionType,
            durationSecs: 0,
            amount: 100,
            minAmount: 1,
            maxAmount: 100,
            proofRequired: true,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        vm.prank(planOwner);
        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, planOwner, 0);
    }

    function _registerAsset(uint256 _planId) internal returns (uint256) {
        uint256[] memory planIds = new uint256[](1);
        planIds[0] = _planId;

        // Get the agentId that will be hashed
        uint256 agentId = assetsRegistry.hashAgentId('test-agentid', address(this));

        vm.prank(address(this));
        vm.expectEmit(true, true, false, false);
        emit IAsset.AgentRegistered(agentId, address(this));

        assetsRegistry.register('test-agentid', 'https://example.com', planIds);
        return agentId;
    }

    function _createExpirablePlan(uint256 amount, uint256 durationSecs) internal returns (uint256) {
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 100;
        address[] memory _receivers = new address[](1);
        _receivers[0] = owner;

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
            isRedemptionAmountFixed: false,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: durationSecs,
            amount: amount,
            minAmount: 1,
            maxAmount: amount,
            proofRequired: false,
            nftAddress: address(nftExpirableCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        vm.prank(owner);
        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, owner);
    }
}
