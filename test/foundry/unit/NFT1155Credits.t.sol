// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../../../contracts/interfaces/IAsset.sol';

import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';
import {INFT1155} from '../../../contracts/interfaces/INFT1155.sol';

import '../../../contracts/common/Roles.sol';
import {NFT1155CreditsV2} from '../../../contracts/mock/NFT1155CreditsV2.sol';
import {BaseTest} from '../common/BaseTest.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';
import {Vm} from 'forge-std/Vm.sol';

contract NFT1155CreditsTest is BaseTest {
    Vm.Wallet private receiverWallet;
    address public receiver;
    address public unauthorized = makeAddr('unauthorized');

    // Using the CREDITS_MINTER_ROLE from BaseTest

    function setUp() public override {
        super.setUp();
        receiverWallet = vm.createWallet('receiver');
        receiver = receiverWallet.addr;
    }

    function test_balanceOf_randomPlan() public view {
        uint256 balance = nftCredits.balanceOf(owner, 1);
        assertEq(balance, 0);
    }

    function test_mint_noPlanRevert() public {
        vm.expectPartialRevert(IAsset.PlanNotFound.selector);
        nftCredits.mint(owner, 1, 1, '');
    }

    function test_minter_role_can_mint() public {
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        uint256 planId = _createPlan();

        nftCredits.mint(receiver, planId, 1, '');
        uint256 balance = nftCredits.balanceOf(receiver, planId);
        assertEq(balance, 1);
    }

    function test_plan_owner_can_mint() public {
        uint256 planId = _createPlan();

        nftCredits.mint(receiver, planId, 2, '');
        uint256 balance = nftCredits.balanceOf(receiver, planId);
        assertEq(balance, 2);
    }

    function test_mint_unauthorized() public {
        uint256 planId = _createPlan();

        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRole.selector);
        nftCredits.mint(receiver, planId, 1, '');
    }

    function test_mintBatch_correct() public {
        // Grant CREDITS_MINTER_ROLE to this contract
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Create unique plans with different configurations
        uint256 planId1 = _createPlanWithAmount(100);
        uint256 planId2 = _createPlanWithAmount(200);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        ids[0] = planId1;
        ids[1] = planId2;
        amounts[0] = 100;
        amounts[1] = 200;

        nftCredits.mintBatch(receiver, ids, amounts, '');

        uint256 balance1 = nftCredits.balanceOf(receiver, planId1);
        uint256 balance2 = nftCredits.balanceOf(receiver, planId2);

        assertEq(balance1, 100);
        assertEq(balance2, 200);
    }

    // Helper function to create plans with different amounts
    function _createPlanWithAmount(uint256 amount) internal returns (uint256) {
        return _createPlanWithAmountAndRedemptionType(amount, IAsset.RedemptionType.ONLY_GLOBAL_ROLE);
    }

    function _createPlanWithAmountAndRedemptionType(uint256 amount, IAsset.RedemptionType redemptionType)
        internal
        override
        returns (uint256)
    {
        uint256 nonce = 0; // Use 0 to match the default createPlan behavior
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
            proofRequired: false,
            durationSecs: 0,
            amount: amount,
            minAmount: 1,
            maxAmount: 100,
            nftAddress: address(nftCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);

        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        vm.prank(owner);
        assetsRegistry.createPlan(priceConfig, creditsConfig, nonce);
        return assetsRegistry.hashPlanId(priceConfig, creditsConfig, owner, nonce);
    }

    function test_mintBatch_unauthorized() public {
        // Create unique plans with different configurations
        uint256 planId1 = _createPlanWithAmount(300);
        uint256 planId2 = _createPlanWithAmount(400);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        ids[0] = planId1;
        ids[1] = planId2;
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(INFT1155.InvalidRole.selector, unauthorized, uint64(CREDITS_MINTER_ROLE))
        );
        nftCredits.mintBatch(receiver, ids, amounts, '');
    }

    function test_burn_noPlanRevert() public {
        vm.expectPartialRevert(IAsset.PlanNotFound.selector);
        nftCredits.burn(owner, 1, 1, 0, '');
    }

    function test_burn_correct() public {
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        _grantRole(CREDITS_BURNER_ROLE, address(this));

        uint256 planId = _createPlan();

        nftCredits.mint(receiver, planId, 5, '');
        nftCredits.burn(receiver, planId, 1, 0, '');
        uint256 balance = nftCredits.balanceOf(receiver, planId);
        assertEq(balance, 4);
    }

    function test_burn_owner_or_global_role_correct() public {
        uint256 planIdRedemption =
            _createPlanWithAmountAndRedemptionType(1100, IAsset.RedemptionType.OWNER_OR_GLOBAL_ROLE);
        vm.prank(owner);
        nftCredits.mint(receiver, planIdRedemption, 10, '');

        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planIdRedemption, 1, 0, '');

        vm.prank(owner);
        nftCredits.burn(receiver, planIdRedemption, 2, 0, '');
        assertEq(nftCredits.balanceOf(receiver, planIdRedemption), 8);

        _grantRole(CREDITS_BURNER_ROLE, address(unauthorized));
        vm.prank(unauthorized);
        nftCredits.burn(receiver, planIdRedemption, 1, 0, '');

        assertEq(nftCredits.balanceOf(receiver, planIdRedemption), 7);
    }

    function test_burn_unauthorized() public {
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        uint256 planId = _createPlan();
        nftCredits.mint(receiver, planId, 5, '');

        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');
    }

    function test_burn_withSignature_required() public {
        // Create a plan that requires proof
        uint256 planId = _createPlanWithProofRequired(0);

        // Grant necessary roles
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        _grantRole(CREDITS_BURNER_ROLE, address(this));

        // Mint some credits
        nftCredits.mint(receiver, planId, 5, '');

        // Get the next nonce for the keyspace
        uint256[] memory keyspaces = new uint256[](1);
        keyspaces[0] = 0;
        uint256[] memory nonces = nftCredits.nextNonce(receiver, keyspaces);
        uint256 nonce = nonces[0];

        // Create the proof data
        uint256[] memory planIds = new uint256[](1);
        planIds[0] = planId;
        INFT1155.CreditsBurnProofData memory proof =
            INFT1155.CreditsBurnProofData({keyspace: 0, nonce: nonce, planIds: planIds});

        // Sign the proof
        bytes32 digest = nftCredits.hashCreditsBurnProof(proof);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(receiverWallet, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Burn with valid signature
        nftCredits.burn(receiver, planId, 1, 0, signature);

        // Verify balance after burn
        uint256 balance = nftCredits.balanceOf(receiver, planId);
        assertEq(balance, 4);
    }

    function test_burn_withSignature_invalid() public {
        // Create a plan that requires proof
        uint256 planId = _createPlanWithProofRequired(0);

        // Grant necessary roles
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        _grantRole(CREDITS_BURNER_ROLE, address(this));

        // Mint some credits
        nftCredits.mint(receiver, planId, 5, '');

        // Get the next nonce for the keyspace
        uint256[] memory keyspaces = new uint256[](1);
        keyspaces[0] = 0;
        uint256[] memory nonces = nftCredits.nextNonce(receiver, keyspaces);
        uint256 nonce = nonces[0];

        // Create the proof data
        uint256[] memory planIds = new uint256[](1);
        planIds[0] = planId;
        INFT1155.CreditsBurnProofData memory proof =
            INFT1155.CreditsBurnProofData({keyspace: 0, nonce: nonce, planIds: planIds});

        // Sign the proof with a different private key (not the receiver's)
        Vm.Wallet memory otherWallet = vm.createWallet('other');
        bytes32 digest = nftCredits.hashCreditsBurnProof(proof);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherWallet, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to burn with invalid signature
        vm.expectRevert(abi.encodeWithSelector(INFT1155.InvalidCreditsBurnProof.selector, otherWallet.addr, receiver));
        nftCredits.burn(receiver, planId, 1, 0, signature);
    }

    function test_burnBatch_correct() public {
        // Grant CREDITS_MINTER_ROLE to this contract
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Grant CREDITS_BURNER_ROLE to this contract
        _grantRole(CREDITS_BURNER_ROLE, address(this));

        // Create unique plans with different configurations
        uint256 planId1 = _createPlanWithAmount(500);
        uint256 planId2 = _createPlanWithAmount(600);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory mintAmounts = new uint256[](2);
        uint256[] memory burnAmounts = new uint256[](2);

        ids[0] = planId1;
        ids[1] = planId2;
        mintAmounts[0] = 100;
        mintAmounts[1] = 200;
        burnAmounts[0] = 50;
        burnAmounts[1] = 75;

        nftCredits.mintBatch(receiver, ids, mintAmounts, '');
        nftCredits.burnBatch(receiver, ids, burnAmounts, 0, '');

        uint256 balance1 = nftCredits.balanceOf(receiver, planId1);
        uint256 balance2 = nftCredits.balanceOf(receiver, planId2);

        assertEq(balance1, 50);
        assertEq(balance2, 125);
    }

    function test_burnBatch_unauthorized() public {
        // Grant CREDITS_MINTER_ROLE to this contract
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Create unique plans with different configurations
        uint256 planId1 = _createPlanWithAmount(700);
        uint256 planId2 = _createPlanWithAmount(800);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory mintAmounts = new uint256[](2);
        uint256[] memory burnAmounts = new uint256[](2);

        ids[0] = planId1;
        ids[1] = planId2;
        mintAmounts[0] = 100;
        mintAmounts[1] = 200;
        burnAmounts[0] = 50;
        burnAmounts[1] = 75;

        nftCredits.mintBatch(receiver, ids, mintAmounts, '');

        vm.prank(unauthorized);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nftCredits.burnBatch(receiver, ids, burnAmounts, 0, '');
    }

    function test_burnBatch_withSignature_required() public {
        // Create plans that require proof
        uint256 planId1 = _createPlanWithProofRequired(0);
        uint256 planId2 = _createPlanWithProofRequired(1);

        // Grant necessary roles
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        _grantRole(CREDITS_BURNER_ROLE, address(this));

        // Mint credits for both plans
        uint256[] memory ids = new uint256[](2);
        {
            uint256[] memory amounts = new uint256[](2);
            ids[0] = planId1;
            ids[1] = planId2;
            amounts[0] = 100;
            amounts[1] = 200;
            nftCredits.mintBatch(receiver, ids, amounts, '');
        }

        // Get the next nonce for the keyspace
        uint256 nonce;
        {
            uint256[] memory keyspaces = new uint256[](1);
            keyspaces[0] = 0;
            uint256[] memory nonces = nftCredits.nextNonce(receiver, keyspaces);
            nonce = nonces[0];
        }

        // Create the proof data
        uint256[] memory planIds = new uint256[](2);
        planIds[0] = planId1;
        planIds[1] = planId2;
        INFT1155.CreditsBurnProofData memory proof =
            INFT1155.CreditsBurnProofData({keyspace: 0, nonce: nonce, planIds: planIds});

        // Sign the proof
        bytes32 digest = nftCredits.hashCreditsBurnProof(proof);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(receiverWallet, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Burn batch with valid signature
        uint256[] memory burnAmounts = new uint256[](2);
        burnAmounts[0] = 50;
        burnAmounts[1] = 75;
        nftCredits.burnBatch(receiver, ids, burnAmounts, 0, signature);

        // Verify balances after burn
        uint256 balance1 = nftCredits.balanceOf(receiver, planId1);
        uint256 balance2 = nftCredits.balanceOf(receiver, planId2);
        assertEq(balance1, 99);
        assertEq(balance2, 199);
    }

    function test_upgraderShouldBeAbleToUpgradeAfterDelay() public {
        string memory newVersion = '2.0.0';

        uint48 upgradeTime = uint48(vm.getBlockTimestamp() + UPGRADE_DELAY);

        NFT1155CreditsV2 nft1155CreditsV2Impl = new NFT1155CreditsV2();

        vm.prank(upgrader);
        accessManager.schedule(
            address(nftCredits),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(nft1155CreditsV2Impl), bytes(''))),
            upgradeTime
        );

        vm.warp(upgradeTime);

        vm.prank(upgrader);
        accessManager.execute(
            address(nftCredits),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(nft1155CreditsV2Impl), bytes('')))
        );

        NFT1155CreditsV2 nft1155CreditsV2 = NFT1155CreditsV2(address(nftCredits));

        vm.prank(governor);
        nft1155CreditsV2.initializeV2(newVersion);

        assertEq(nft1155CreditsV2.getVersion(), newVersion);
    }

    function test_balanceOfBatch_allZero() public view {
        address[] memory owners = new address[](2);
        uint256[] memory ids = new uint256[](2);
        owners[0] = owner;
        owners[1] = receiver;
        ids[0] = 1;
        ids[1] = 2;
        uint256[] memory balances = nftCredits.balanceOfBatch(owners, ids);
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
    }

    function test_balanceOfBatch_mixed() public {
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        uint256 planId1 = _createPlan();
        uint256 planId2 = _createPlanWithAmount(2);
        nftCredits.mint(owner, planId1, 3, '');
        // receiver/planId2 not minted
        address[] memory owners = new address[](2);
        uint256[] memory ids = new uint256[](2);
        owners[0] = owner;
        owners[1] = receiver;
        ids[0] = planId1;
        ids[1] = planId2;
        uint256[] memory balances = nftCredits.balanceOfBatch(owners, ids);
        assertEq(balances[0], 3);
        assertEq(balances[1], 0);
    }

    function test_burn_plan_role_redemption_type() public {
        // Create a fresh address for plan creation
        address planOwner = makeAddr('planOwner');

        // Create a plan with ONLY_PLAN_ROLE redemption type, owned by the fresh address
        uint256 planId =
            _createPlanWithAmountAndRedemptionTypeAsOwner(100, IAsset.RedemptionType.ONLY_PLAN_ROLE, planOwner);

        // Grant CREDITS_MINTER_ROLE to mint credits
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Mint some credits to the receiver
        nftCredits.mint(receiver, planId, 10, '');

        // Verify initial balance
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Grant the plan-specific role to an unauthorized address using the plan owner
        vm.prank(planOwner);
        nftCredits.allowBurn(unauthorized, planId);

        // Now the unauthorized address should be able to burn credits
        vm.prank(unauthorized);
        nftCredits.burn(receiver, planId, 3, 0, '');

        // Verify balance after burn
        assertEq(nftCredits.balanceOf(receiver, planId), 7);

        // Test that someone without the plan role cannot burn
        address anotherAddress = makeAddr('another');
        vm.prank(anotherAddress);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');

        // Test that the plan owner cannot burn (only plan role holders can)
        vm.prank(planOwner);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');

        // Test that someone with global CREDITS_BURNER_ROLE cannot burn (only plan role holders can)
        _grantRole(CREDITS_BURNER_ROLE, anotherAddress);
        vm.prank(anotherAddress);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');
    }

    function test_burn_plan_role_redemption_type_with_proof() public {
        // Create a fresh address for plan creation
        address planOwner = makeAddr('planOwner');

        // Create a plan with ONLY_PLAN_ROLE redemption type and proof required, owned by the fresh address
        uint256 planId =
            _createPlanWithProofRequiredAndRedemptionTypeAsOwner(IAsset.RedemptionType.ONLY_PLAN_ROLE, planOwner);

        // Grant CREDITS_MINTER_ROLE to mint credits
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Mint some credits to the receiver
        nftCredits.mint(receiver, planId, 10, '');

        // Verify initial balance
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Verify that initially no one can burn
        assertFalse(nftCredits.canBurn(unauthorized, planId));
        assertFalse(nftCredits.canBurn(planOwner, planId));

        // Plan owner allows the unauthorized address to burn credits
        vm.prank(planOwner);
        nftCredits.allowBurn(unauthorized, planId);

        // Verify that the unauthorized address can now burn
        assertTrue(nftCredits.canBurn(unauthorized, planId));

        // Get the next nonce for the keyspace
        uint256[] memory keyspaces = new uint256[](1);
        keyspaces[0] = 0;
        uint256[] memory nonces = nftCredits.nextNonce(receiver, keyspaces);
        uint256 nonce = nonces[0];

        // Create the proof data
        uint256[] memory planIds = new uint256[](1);
        planIds[0] = planId;
        INFT1155.CreditsBurnProofData memory proof =
            INFT1155.CreditsBurnProofData({keyspace: 0, nonce: nonce, planIds: planIds});

        // Sign the proof with the receiver's wallet (the _from address)
        bytes32 digest = nftCredits.hashCreditsBurnProof(proof);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(receiverWallet, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Now the unauthorized address should be able to burn credits with valid proof
        // The signature must be from the receiver (the _from address)
        vm.prank(unauthorized);
        nftCredits.burn(receiver, planId, 3, 0, signature);

        // Verify balance after burn
        assertEq(nftCredits.balanceOf(receiver, planId), 7);
    }

    function test_burn_only_subscriber_redemption() public {
        // Create a fresh address for plan creation
        address planOwner = makeAddr('planOwner');

        // Create a plan with ONLY_SUBSCRIBER redemption type, owned by the fresh address
        uint256 planId =
            _createPlanWithAmountAndRedemptionTypeAsOwner(100, IAsset.RedemptionType.ONLY_SUBSCRIBER, planOwner);

        // Grant CREDITS_MINTER_ROLE to mint credits
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Mint some credits to the receiver
        nftCredits.mint(receiver, planId, 10, '');

        // Verify initial balance
        assertEq(nftCredits.balanceOf(receiver, planId), 10);
        vm.prank(receiver);
        nftCredits.burn(receiver, planId, 5, 0, '');
        assertEq(nftCredits.balanceOf(receiver, planId), 5);
    }

    function test_burn_plan_role_redemption_type_no_subs_without_role_fails() public {
        // Create a fresh address for plan creation
        address planOwner = makeAddr('planOwner');

        // Create a plan with ONLY_PLAN_ROLE redemption type, owned by the fresh address
        uint256 planId =
            _createPlanWithAmountAndRedemptionTypeAsOwner(100, IAsset.RedemptionType.ONLY_PLAN_ROLE, planOwner);

        // Grant CREDITS_MINTER_ROLE to mint credits
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Mint some credits to the receiver
        nftCredits.mint(receiver, planId, 10, '');

        // Verify initial balance
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Verify that initially no one can burn
        assertFalse(nftCredits.canBurn(unauthorized, planId));
        assertFalse(nftCredits.canBurn(planOwner, planId));

        // Test that an address without burn permission cannot burn credits
        address unauthorizedAddress = makeAddr('unauthorized');
        vm.prank(unauthorizedAddress);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');

        // Verify balance remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Test that even the plan owner cannot burn without explicit permission
        vm.prank(planOwner);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');

        // Verify balance still remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Test that someone with global CREDITS_BURNER_ROLE cannot burn without the plan role
        address globalBurner = makeAddr('globalBurner');
        _grantRole(CREDITS_BURNER_ROLE, globalBurner);
        vm.prank(globalBurner);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');

        // Verify balance still remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Test that the receiver CAN burn without the role
        vm.prank(receiver);
        // vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');

        // Verify balance still remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 10 - 1);
    }

    function test_burn_plan_role_redemption_type_without_role_fails_with_proof() public {
        // Create a fresh address for plan creation
        address planOwner = makeAddr('planOwner');

        // Create a plan with ONLY_PLAN_ROLE redemption type and proof required, owned by the fresh address
        uint256 planId =
            _createPlanWithProofRequiredAndRedemptionTypeAsOwner(IAsset.RedemptionType.ONLY_PLAN_ROLE, planOwner);

        // Grant CREDITS_MINTER_ROLE to mint credits
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Mint some credits to the receiver
        nftCredits.mint(receiver, planId, 10, '');

        // Verify initial balance
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Verify that initially no one can burn
        assertFalse(nftCredits.canBurn(unauthorized, planId));
        assertFalse(nftCredits.canBurn(planOwner, planId));

        // Get the next nonce for the keyspace
        uint256[] memory keyspaces = new uint256[](1);
        keyspaces[0] = 0;
        uint256[] memory nonces = nftCredits.nextNonce(receiver, keyspaces);
        uint256 nonce = nonces[0];

        // Create the proof data
        uint256[] memory planIds = new uint256[](1);
        planIds[0] = planId;
        INFT1155.CreditsBurnProofData memory proof =
            INFT1155.CreditsBurnProofData({keyspace: 0, nonce: nonce, planIds: planIds});

        // Sign the proof with the receiver's wallet (the _from address)
        bytes32 digest = nftCredits.hashCreditsBurnProof(proof);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(receiverWallet, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test that an address without burn permission cannot burn credits even with valid proof
        address unauthorizedAddress = makeAddr('unauthorized');
        vm.prank(unauthorizedAddress);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, signature);

        // Verify balance remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Test that even the plan owner cannot burn without explicit permission, even with valid proof
        vm.prank(planOwner);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, signature);

        // Verify balance still remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Test that someone with global CREDITS_BURNER_ROLE cannot burn without the plan role, even with valid proof
        address globalBurner = makeAddr('globalBurner');
        _grantRole(CREDITS_BURNER_ROLE, globalBurner);
        vm.prank(globalBurner);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, signature);

        // Verify balance still remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 10);
    }

    function test_revoke_burn_functionality() public {
        // Create a fresh address for plan creation
        address planOwner = makeAddr('planOwner');

        // Create a plan with ONLY_PLAN_ROLE redemption type, owned by the fresh address
        uint256 planId =
            _createPlanWithAmountAndRedemptionTypeAsOwner(100, IAsset.RedemptionType.ONLY_PLAN_ROLE, planOwner);

        // Grant CREDITS_MINTER_ROLE to mint credits
        _grantRole(CREDITS_MINTER_ROLE, address(this));

        // Mint some credits to the receiver
        nftCredits.mint(receiver, planId, 10, '');

        // Verify initial balance
        assertEq(nftCredits.balanceOf(receiver, planId), 10);

        // Verify that initially no one can burn
        assertFalse(nftCredits.canBurn(unauthorized, planId));
        assertFalse(nftCredits.canBurn(planOwner, planId));

        // Plan owner allows the unauthorized address to burn credits
        vm.prank(planOwner);
        nftCredits.allowBurn(unauthorized, planId);

        // Verify that the unauthorized address can now burn
        assertTrue(nftCredits.canBurn(unauthorized, planId));

        // Now the unauthorized address should be able to burn credits
        vm.prank(unauthorized);
        nftCredits.burn(receiver, planId, 3, 0, '');

        // Verify balance after burn
        assertEq(nftCredits.balanceOf(receiver, planId), 7);

        // Plan owner revokes burn permission from the unauthorized address
        vm.prank(planOwner);
        nftCredits.revokeBurn(unauthorized, planId);

        // Verify that the unauthorized address can no longer burn
        assertFalse(nftCredits.canBurn(unauthorized, planId));

        // Test that the unauthorized address cannot burn after revocation
        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftCredits.burn(receiver, planId, 1, 0, '');

        // Verify balance remains unchanged
        assertEq(nftCredits.balanceOf(receiver, planId), 7);

        // Test that someone else cannot call revokeBurn (only plan owner can)
        address anotherAddress = makeAddr('another');
        vm.prank(anotherAddress);
        vm.expectRevert(abi.encodeWithSelector(INFT1155.OnlyOwnerCanAllowBurn.selector, anotherAddress, planId));
        nftCredits.revokeBurn(unauthorized, planId);

        // Verify that the unauthorized address still cannot burn
        assertFalse(nftCredits.canBurn(unauthorized, planId));
    }
}
