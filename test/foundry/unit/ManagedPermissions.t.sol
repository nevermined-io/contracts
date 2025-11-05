// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {
    CREDITS_BURNER_ROLE,
    CREDITS_MINTER_ROLE,
    DEPOSITOR_ROLE,
    FIAT_SETTLEMENT_ROLE,
    GOVERNOR_ROLE,
    WITHDRAW_ROLE
} from '../../../contracts/common/Roles.sol';

import {BaseTest} from '../common/BaseTest.sol';

import {IAgreement} from '../../../contracts/interfaces/IAgreement.sol';

import {INFT1155} from '../../../contracts/interfaces/INFT1155.sol';
import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';
import {ERC1155Holder} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

contract ManagedPermissionsTest is BaseTest, ERC1155Holder {
    address public nonRoleUser;
    address public roleUser;
    uint256 private _nonce;

    function setUp() public override {
        super.setUp();
        nonRoleUser = makeAddr('nonRoleUser');
        roleUser = makeAddr('roleUser');
        deal(roleUser, 100 ether);
        deal(nonRoleUser, 100 ether);
        _grantTemplateRole(address(this));
        _nonce = vm.getBlockTimestamp(); // start with a unique value for this test run
    }

    // Helper to get a unique agreementId
    function _uniqueAgreementId() internal returns (bytes32) {
        return keccak256(abi.encodePacked('agreement', address(this), _nonce++));
    }

    function _uniquePlanId() internal returns (uint256) {
        return uint256(keccak256(abi.encodePacked('plan', address(this), _nonce++)));
    }

    function _uniqueConditionId() internal returns (bytes32) {
        return keccak256(abi.encodePacked('condition', address(this), _nonce++));
    }

    // PaymentsVault: DEPOSITOR_ROLE and WITHDRAW_ROLE
    function testPaymentsVault_depositorRole() public {
        uint256 depositAmount = 1 ether;
        // Grant DEPOSITOR_ROLE to roleUser
        _grantRole(DEPOSITOR_ROLE, roleUser);
        vm.deal(roleUser, depositAmount);
        // Should succeed
        vm.prank(roleUser);
        paymentsVault.depositNativeToken{value: depositAmount}();
        // Should revert for nonRoleUser
        vm.deal(nonRoleUser, depositAmount);
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        paymentsVault.depositNativeToken{value: depositAmount}();
    }

    function testPaymentsVault_withdrawRole() public {
        uint256 depositAmount = 1 ether;
        // Deposit funds as owner (has DEPOSITOR_ROLE)
        _grantRole(DEPOSITOR_ROLE, address(this));
        paymentsVault.depositNativeToken{value: depositAmount}();
        // Grant WITHDRAW_ROLE to roleUser
        _grantRole(WITHDRAW_ROLE, roleUser);
        // Should succeed
        vm.prank(roleUser);
        paymentsVault.withdrawNativeToken(0, address(this));
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        paymentsVault.withdrawNativeToken(0, address(this));
    }

    // LockPaymentCondition: CONTRACT_TEMPLATE_ROLE
    function testLockPaymentCondition_templateRole() public {
        // Setup: create plan, agreement, and conditionId
        uint256 planId = _createExpirablePlan(_nonce++, 100);
        bytes32 agreementId = _uniqueAgreementId();
        bytes32 conditionId =
            lockPaymentCondition.hashConditionId(agreementId, lockPaymentCondition.NVM_CONTRACT_NAME());
        // Add the condition to the agreement
        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = conditionId;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;
        agreementsStore.register(agreementId, address(this), planId, conditionIds, conditionStates, 1, new bytes[](0));
        // Grant template role
        _grantTemplateRole(roleUser);
        // Should succeed
        vm.prank(roleUser);
        lockPaymentCondition.fulfill{value: 100}(conditionId, agreementId, planId, address(this));
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        lockPaymentCondition.fulfill{value: 100}(conditionId, agreementId, planId, address(this));
    }

    // DistributePaymentsCondition: CONTRACT_TEMPLATE_ROLE
    function testDistributePaymentsCondition_templateRole() public {
        // Setup: create plan, agreement, and conditionIds
        deal(address(paymentsVault), 100 ether);
        uint256 planId = _createPlan(_nonce++);
        bytes32 agreementId = _uniqueAgreementId();
        bytes32 lockCond = lockPaymentCondition.hashConditionId(agreementId, lockPaymentCondition.NVM_CONTRACT_NAME());
        bytes32 transferCond =
            transferCreditsCondition.hashConditionId(agreementId, transferCreditsCondition.NVM_CONTRACT_NAME());
        bytes32 distCond =
            distributePaymentsCondition.hashConditionId(agreementId, distributePaymentsCondition.NVM_CONTRACT_NAME());
        bytes32[] memory conditionIds = new bytes32[](3);
        conditionIds[0] = lockCond;
        conditionIds[1] = transferCond;
        conditionIds[2] = distCond;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](3);
        conditionStates[0] = IAgreement.ConditionState.Fulfilled;
        conditionStates[1] = IAgreement.ConditionState.Fulfilled;
        conditionStates[2] = IAgreement.ConditionState.Unfulfilled;
        _grantTemplateRole(address(this));
        agreementsStore.register(agreementId, address(this), planId, conditionIds, conditionStates, 1, new bytes[](0));
        // Grant template role
        _grantTemplateRole(roleUser);
        // Should succeed
        vm.prank(roleUser);
        distributePaymentsCondition.fulfill(distCond, agreementId, planId, lockCond, transferCond);
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        distributePaymentsCondition.fulfill(distCond, agreementId, planId, lockCond, transferCond);
    }

    // TransferCreditsCondition: CONTRACT_TEMPLATE_ROLE
    function testTransferCreditsCondition_templateRole() public {
        // Setup: create plan, agreement, and conditionIds
        uint256 planId = _createPlan(_nonce++);
        bytes32 agreementId = _uniqueAgreementId();
        bytes32 lockCond = lockPaymentCondition.hashConditionId(agreementId, lockPaymentCondition.NVM_CONTRACT_NAME());
        bytes32 transferCond =
            transferCreditsCondition.hashConditionId(agreementId, transferCreditsCondition.NVM_CONTRACT_NAME());
        bytes32[] memory conditionIds = new bytes32[](2);
        conditionIds[0] = lockCond;
        conditionIds[1] = transferCond;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](2);
        conditionStates[0] = IAgreement.ConditionState.Fulfilled;
        conditionStates[1] = IAgreement.ConditionState.Unfulfilled;
        agreementsStore.register(agreementId, address(this), planId, conditionIds, conditionStates, 1, new bytes[](0));
        // Grant template role
        _grantTemplateRole(roleUser);
        // Should succeed
        bytes32[] memory req = new bytes32[](1);
        req[0] = lockCond;
        vm.prank(roleUser);
        transferCreditsCondition.fulfill(transferCond, agreementId, planId, req, address(this));
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        transferCreditsCondition.fulfill(transferCond, agreementId, planId, req, address(this));
    }

    // FiatSettlementCondition: CONTRACT_TEMPLATE_ROLE and FIAT_SETTLEMENT_ROLE
    function testFiatSettlementCondition_roles() public {
        // Setup: create plan, agreement, and conditionId
        uint256 planId = _createPlan(_nonce++);
        bytes32 agreementId = _uniqueAgreementId();
        bytes32 fiatCond =
            fiatSettlementCondition.hashConditionId(agreementId, fiatSettlementCondition.NVM_CONTRACT_NAME());
        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = fiatCond;
        IAgreement.ConditionState[] memory conditionStates = new IAgreement.ConditionState[](1);
        conditionStates[0] = IAgreement.ConditionState.Unfulfilled;
        agreementsStore.register(agreementId, address(this), planId, conditionIds, conditionStates, 1, new bytes[](0));
        // Grant template and FIAT_SETTLEMENT_ROLE
        _grantTemplateRole(roleUser);
        _grantRole(FIAT_SETTLEMENT_ROLE, roleUser);
        bytes[] memory params = new bytes[](0);
        // Should succeed
        vm.prank(roleUser);
        fiatSettlementCondition.fulfill(fiatCond, agreementId, planId, roleUser, params);
        // Should revert for nonRoleUser (no template role)
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        fiatSettlementCondition.fulfill(fiatCond, agreementId, planId, nonRoleUser, params);
    }

    // NVMConfig: GOVERNOR_ROLE
    function testNVMConfig_governorRole() public {
        _grantRole(GOVERNOR_ROLE, roleUser);
        // Should succeed
        vm.prank(roleUser);
        nvmConfig.setFeeReceiver(address(this));
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        nvmConfig.setFeeReceiver(address(this));
    }

    // AgreementsStore: CONTRACT_TEMPLATE_ROLE and CONTRACT_CONDITION_ROLE
    function testAgreementsStore_templateRole() public {
        _grantTemplateRole(roleUser);
        // Should succeed
        bytes32 agreementId1 = _uniqueAgreementId();
        vm.prank(roleUser);
        agreementsStore.register(
            agreementId1, address(this), 1, new bytes32[](0), new IAgreement.ConditionState[](0), 1, new bytes[](0)
        );
        // Should revert for nonRoleUser
        bytes32 agreementId2 = _uniqueAgreementId();
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        agreementsStore.register(
            agreementId2, address(this), 1, new bytes32[](0), new IAgreement.ConditionState[](0), 1, new bytes[](0)
        );
    }

    // NFT1155Credits: CREDITS_MINTER_ROLE and CREDITS_BURNER_ROLE
    function testNFT1155Credits_minterRole() public {
        // Setup: create plan
        uint256 planId = _createPlan(_nonce++);
        uint256[] memory ids = new uint256[](1);
        ids[0] = planId;
        uint256[] memory values = new uint256[](1);
        values[0] = 1;
        // Grant minter role
        _grantRole(CREDITS_MINTER_ROLE, roleUser);
        // Should succeed
        vm.prank(roleUser);
        nftCredits.mintBatch(roleUser, ids, values, '');
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(INFT1155.InvalidRole.selector, nonRoleUser, CREDITS_MINTER_ROLE));
        nftCredits.mintBatch(nonRoleUser, ids, values, '');
    }

    function testNFT1155Credits_burnerRole() public {
        // Setup: create plan and mint credits
        uint256 planId = _createPlan(_nonce++);
        uint256[] memory ids = new uint256[](1);
        ids[0] = planId;
        uint256[] memory values = new uint256[](1);
        values[0] = 1;
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        nftCredits.mintBatch(address(this), ids, values, '');
        // Grant burner role
        _grantRole(CREDITS_BURNER_ROLE, roleUser);
        // Should succeed
        vm.prank(roleUser);
        nftCredits.burnBatch(address(this), ids, values, 0, '');
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        nftCredits.burnBatch(address(this), ids, values, 0, '');
    }

    // NFT1155ExpirableCredits: CREDITS_MINTER_ROLE and CREDITS_BURNER_ROLE
    function testNFT1155ExpirableCredits_minterRole() public {
        // Setup: create plan
        uint256 planId = _createPlan(_nonce++);
        uint256[] memory ids = new uint256[](1);
        ids[0] = planId;
        uint256[] memory values = new uint256[](1);
        values[0] = 1;
        // Grant minter role
        _grantRole(CREDITS_MINTER_ROLE, roleUser);
        // Should succeed
        vm.prank(roleUser);
        nftExpirableCredits.mintBatch(roleUser, ids, values, '');
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(INFT1155.InvalidRole.selector, nonRoleUser, CREDITS_MINTER_ROLE));
        nftExpirableCredits.mintBatch(nonRoleUser, ids, values, '');
    }

    function testNFT1155ExpirableCredits_burnerRole() public {
        // Setup: create plan and mint credits
        uint256 planId = _createPlan(_nonce++);
        uint256[] memory ids = new uint256[](1);
        ids[0] = planId;
        uint256[] memory values = new uint256[](1);
        values[0] = 1;
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        nftExpirableCredits.mintBatch(address(this), ids, values, '');
        // Grant burner role
        _grantRole(CREDITS_BURNER_ROLE, roleUser);
        // Should succeed
        vm.prank(roleUser);
        nftExpirableCredits.burnBatch(address(this), ids, values, 0, '');
        // Should revert for nonRoleUser
        vm.prank(nonRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, nonRoleUser));
        nftExpirableCredits.burnBatch(address(this), ids, values, 0, '');
    }

    receive() external payable {}
}
