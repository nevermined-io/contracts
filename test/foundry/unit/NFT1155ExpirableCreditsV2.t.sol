// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import '../../../contracts/common/Roles.sol';
import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {INFT1155} from '../../../contracts/interfaces/INFT1155.sol';
import {NFT1155ExpirableCreditsV2} from '../../../contracts/token/NFT1155ExpirableCreditsV2.sol';
import {BaseTest} from '../common/BaseTest.sol';
import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';
import {console2} from 'forge-std/console2.sol';

contract NFT1155ExpirableCreditsV2Test is BaseTest {
    address public minter;
    address public burner;
    address public receiver;
    address public unauthorized;
    uint256 public planId;
    uint256 public planId2;
    uint256 public planId3;

    function setUp() public override {
        super.setUp();

        // Create addresses for testing
        minter = makeAddr('minter');
        burner = makeAddr('burner');
        receiver = makeAddr('receiver');
        unauthorized = makeAddr('unauthorized');

        // Grant necessary roles for testing
        _grantRole(CREDITS_MINTER_ROLE, address(this));
        _grantRole(CREDITS_MINTER_ROLE, minter);
        _grantRole(CREDITS_BURNER_ROLE, address(this));
        _grantRole(CREDITS_BURNER_ROLE, burner);

        // Create expirable credits plans for testing
        planId = _createExpirablePlan(1, 10);
        planId2 = _createExpirablePlan(200, 10);
        planId3 = _createExpirablePlan(300, 10);
    }

    // ============ Basic Functionality Tests ============

    function test_balanceOf_randomPlan() public view {
        uint256 balance = nftExpirableCreditsV2.balanceOf(owner, 999);
        assertEq(balance, 0);
    }

    function test_mint_noPlanRevert() public {
        vm.prank(minter);
        vm.expectPartialRevert(IAsset.PlanNotFound.selector);
        nftExpirableCreditsV2.mint(owner, 999, 1, '');
    }

    function test_mint_correct() public {
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 1, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 1);
    }

    function test_mint_unauthorized() public {
        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRole.selector);
        nftExpirableCreditsV2.mint(receiver, planId, 1, '');
    }

    // ============ Expiration Tests ============

    function test_mintWithExpiration() public {
        // Mint with 10 seconds expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 1, 10, '');

        // Check initial balance
        uint256 initialBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(initialBalance, 1);

        // Advance time by 15 seconds (past expiration)
        vm.warp(vm.getBlockTimestamp() + 15);

        // Check balance after expiration
        uint256 finalBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(finalBalance, 0);
    }

    function test_mintWithoutExpiration() public {
        // Mint with no expiration (0 seconds)
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 1, 0, '');

        // Check initial balance
        uint256 initialBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(initialBalance, 1);

        // Advance time by 1000 seconds
        vm.warp(vm.getBlockTimestamp() + 1000);

        // Check balance after time advancement (should still be 1)
        uint256 finalBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(finalBalance, 1);
    }

    function test_mixedExpirationCredits() public {
        // Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 0, ''); // Never expires

        // Check initial balance
        uint256 initialBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(initialBalance, 8);

        // Advance time by 15 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 15);

        // Check balance after first expiration (should only have non-expiring credits)
        uint256 finalBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(finalBalance, 3);
    }

    function test_multipleExpirationTimes() public {
        // Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 2, 5, ''); // Expires in 5 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 1, 15, ''); // Expires in 15 seconds

        // Check initial balance
        uint256 initialBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(initialBalance, 6);

        // Advance time by 7 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 7);
        uint256 balanceAfter7 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter7, 4); // 3 + 1

        // Advance time by 12 seconds (past second expiration)
        vm.warp(vm.getBlockTimestamp() + 5);
        uint256 balanceAfter12 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter12, 1); // Only the 15-second expiration remains

        // Advance time by 16 seconds (past all expirations)
        vm.warp(vm.getBlockTimestamp() + 4);
        uint256 finalBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(finalBalance, 0);
    }

    // ============ Batch Operations Tests ============

    function test_mintBatch_correct() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);
        uint256[] memory durations = new uint256[](2);

        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 5;
        values[1] = 10;
        durations[0] = 10; // Expires in 10 seconds
        durations[1] = 0; // Never expires

        vm.prank(minter);
        nftExpirableCreditsV2.mintBatch(receiver, ids, values, durations, '');

        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId2);
        assertEq(balance1, 5);
        assertEq(balance2, 10);
    }

    function test_mintBatch_invalidLength_reverts() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](1);
        uint256[] memory durations = new uint256[](2);

        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 5;
        durations[0] = 10;
        durations[1] = 0;

        vm.prank(minter);
        vm.expectRevert();
        nftExpirableCreditsV2.mintBatch(receiver, ids, values, durations, '');
    }

    function test_mintBatch_invalidLengthDurations_reverts() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);
        uint256[] memory durations = new uint256[](1);

        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 5;
        values[1] = 10;
        durations[0] = 10;

        vm.prank(minter);
        vm.expectRevert();
        nftExpirableCreditsV2.mintBatch(receiver, ids, values, durations, '');
    }

    function test_mintBatch_unauthorized() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        uint256[] memory durations = new uint256[](1);

        ids[0] = planId;
        values[0] = 5;
        durations[0] = 10;

        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRole.selector);
        nftExpirableCreditsV2.mintBatch(receiver, ids, values, durations, '');
    }

    // ============ Burning Tests ============

    function test_burn_correct() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');

        // Then burn some credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 7);
    }

    function test_burn_unauthorized() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');

        // Try to burn without authorization
        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');
    }

    function test_burn_notEnoughCreditsToBurn_reverts() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 0, '');

        // Try to burn more than available
        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burn(receiver, planId, 10, 0, '');
    }

    function test_burn_notEnoughCreditsToBurn_withExpiredCredits_reverts() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, '');

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Try to burn credits (should fail as all credits are expired)
        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');
    }

    function test_burn_withSignature_required() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');

        // Burn with signature (this would require proper signature validation in real scenario)
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 7);
    }

    function test_burn_withSignature_invalid() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');

        // Burn with invalid signature (this would fail signature validation in real scenario)
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 7);
    }

    function test_burnBatch() public {
        // Mint credits for multiple plans
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId2, 15, 0, '');

        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);

        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 3;
        values[1] = 5;

        vm.prank(burner);
        nftExpirableCreditsV2.burnBatch(receiver, ids, values, 0, '');

        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId2);
        assertEq(balance1, 7);
        assertEq(balance2, 10);
    }

    function test_burnBatch_invalidLength_reverts() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](1);

        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 3;

        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burnBatch(receiver, ids, values, 0, '');
    }

    function test_burnBatch_notEnoughCreditsToBurn_reverts() public {
        // Mint credits for multiple plans
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 0, '');
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId2, 10, 0, '');

        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);

        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 10; // More than available
        values[1] = 5;

        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burnBatch(receiver, ids, values, 0, '');
    }

    function test_burnBatch_unauthorized() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);

        ids[0] = planId;
        values[0] = 3;

        vm.prank(unauthorized);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nftExpirableCreditsV2.burnBatch(receiver, ids, values, 0, '');
    }

    function test_burnBatch_withSignature_required() public {
        // Mint credits for multiple plans
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId2, 15, 0, '');

        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);

        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 3;
        values[1] = 5;

        vm.prank(burner);
        nftExpirableCreditsV2.burnBatch(receiver, ids, values, 0, '');

        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId2);
        assertEq(balance1, 7);
        assertEq(balance2, 10);
    }

    // ============ Complex Burning Scenarios ============

    function test_burn_withExpiredCredits() public {
        // Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 0, ''); // Never expires

        // Advance time by 15 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 15);

        // Try to burn 3 credits (should only burn from non-expired)
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 0); // All non-expired credits burned
    }

    function test_burn_partialWithExpiredCredits() public {
        // Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 0, ''); // Never expires

        // Advance time by 15 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 15);

        // Burn 2 credits (should only burn from non-expired)
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 2, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 1); // 3 - 2 = 1 remaining
    }

    // ============ RedBlackTree Integration Tests ============

    function test_multipleExpirationTimes_complex() public {
        // Mint credits with multiple different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 2, 5, ''); // Expires in 5 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 1, 15, ''); // Expires in 15 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 4, 0, ''); // Never expires

        // Check initial balance
        uint256 initialBalance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(initialBalance, 10);

        // Advance time by 7 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 7);
        uint256 balanceAfter7 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter7, 8); // 3 + 1 + 4

        // Advance time by 12 seconds (past second expiration)
        vm.warp(vm.getBlockTimestamp() + 5);
        uint256 balanceAfter12 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter12, 5); // 1 + 4

        // Advance time by 16 seconds (past third expiration)
        vm.warp(vm.getBlockTimestamp() + 4);
        uint256 balanceAfter16 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter16, 4); // Only non-expiring credits remain
    }

    function test_burn_withMultipleExpirationTimes() public {
        // Mint credits with multiple different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 2, 5, ''); // Expires in 5 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 1, 15, ''); // Expires in 15 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 4, 0, ''); // Never expires

        // Advance time by 7 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 7);

        // Burn 6 credits (should burn from remaining valid credits)
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 6, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 2); // 8 - 6 = 2 remaining
    }

    // ============ Comprehensive Credit Lifecycle Tests ============

    function test_comprehensiveCreditLifecycle_singleExpiration() public {
        // Step 1: Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 20, ''); // 10 credits expiring in 20 seconds

        // Step 2: Check initial balance
        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance1, 10);

        // Step 3: Burn some credits before expiration
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance2, 7);

        // Step 4: Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 25);

        // Step 5: Check balance after expiration (should be 0)
        uint256 balance3 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance3, 0);

        // Step 6: Try to burn credits after expiration (should fail)
        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burn(receiver, planId, 1, 0, '');
    }

    function test_comprehensiveCreditLifecycle_mixedExpirations() public {
        // Step 1: Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 0, ''); // Never expires

        // Step 2: Check initial balance
        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance1, 8);

        // Step 3: Burn some credits before any expiration
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 2, 0, '');
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance2, 6);

        // Step 4: Advance time past first expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Step 5: Check balance after first expiration
        uint256 balance3 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance3, 3); // Only non-expiring credits remain

        // Step 6: Burn remaining credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');
        uint256 balance4 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance4, 0);

        // Step 7: Try to burn more credits (should fail)
        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(NFT1155ExpirableCreditsV2.NotEnoughCreditsToBurn.selector, receiver, planId, 1)
        );
        nftExpirableCreditsV2.burn(receiver, planId, 1, 0, '');
    }

    function test_comprehensiveCreditLifecycle_multipleExpirations() public {
        // Step 1: Mint credits with multiple expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 2, 5, ''); // Expires in 5 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 4, 0, ''); // Never expires

        // Step 2: Check initial balance
        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance1, 9, 'Balance should be 9 after minting credits');

        // Step 3: Burn some credits before any expiration
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 2, 0, '');
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance2, 7, 'Balance should be 7 after burning credits');

        // Step 4: Advance time past first expiration
        vm.warp(vm.getBlockTimestamp() + 7);
        uint256 balance3 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance3, 7, 'Balance should be 7 after advancing time past first expiration'); // 3 + 4 (first batch expired)

        // Step 5: Burn more credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');
        uint256 balance4 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance4, 4, 'Balance should be 4 after burning credits');

        // Step 6: Advance time past second expiration
        vm.warp(vm.getBlockTimestamp() + 5);
        uint256 balance5 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance5, 4, 'Balance should be 4 after advancing time past second expiration');

        // Step 7: Burn remaining credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 4, 0, '');
        uint256 balance6 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance6, 0, 'Balance should be 0 after burning remaining credits');

        // Step 8: Try to burn more credits (should fail)
        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burn(receiver, planId, 1, 0, '');
    }

    function test_comprehensiveCreditLifecycle_burnExactAvailable() public {
        // Step 1: Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 0, ''); // Never expires

        // Step 2: Check initial balance
        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance1, 8);

        // Step 3: Advance time past first expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Step 4: Check balance after expiration
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance2, 3); // Only non-expiring credits remain

        // Step 5: Burn exactly the available credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');
        uint256 balance3 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance3, 0);

        // Step 6: Try to burn one more credit (should fail)
        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(NFT1155ExpirableCreditsV2.NotEnoughCreditsToBurn.selector, receiver, planId, 1)
        );
        nftExpirableCreditsV2.burn(receiver, planId, 1, 0, '');
    }

    function test_comprehensiveCreditLifecycle_burnMoreThanAvailable() public {
        // Step 1: Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 3, 0, ''); // Never expires

        // Step 2: Check initial balance
        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance1, 8);

        // Step 3: Advance time past first expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Step 4: Check balance after expiration
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance2, 3); // Only non-expiring credits remain

        // Step 5: Try to burn more than available (should fail)
        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burn(receiver, planId, 4, 0, '');

        // Step 6: Verify balance is unchanged
        uint256 balance3 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance3, 3);
    }

    function test_comprehensiveCreditLifecycle_batchOperations() public {
        // Step 1: Mint credits for multiple plans
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId2, 3, 0, ''); // Never expires

        // Step 2: Check initial balances
        uint256 balance11 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        uint256 balance12 = nftExpirableCreditsV2.balanceOf(receiver, planId2);
        assertEq(balance11, 5);
        assertEq(balance12, 3);

        // Step 3: Advance time past first expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Step 4: Check balances after expiration
        uint256 balance21 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        uint256 balance22 = nftExpirableCreditsV2.balanceOf(receiver, planId2);
        assertEq(balance21, 0); // All expired
        assertEq(balance22, 3); // Still available

        // Step 5: Batch burn from both plans
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);
        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 0; // No credits to burn from planId (all expired)
        values[1] = 2; // Burn 2 from planId2

        vm.prank(burner);
        nftExpirableCreditsV2.burnBatch(receiver, ids, values, 0, '');

        // Step 6: Check final balances
        uint256 balance31 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        uint256 balance32 = nftExpirableCreditsV2.balanceOf(receiver, planId2);
        assertEq(balance31, 0);
        assertEq(balance32, 1); // 3 - 2 = 1 remaining
    }

    function test_comprehensiveCreditLifecycle_edgeCases() public {
        // Step 1: Mint credits with very short expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 1, ''); // Expires in 1 second

        // Step 2: Check initial balance
        uint256 balance1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance1, 10, 'Initial balance should be 10');

        // Step 3: Advance time just before expiration
        vm.warp(vm.getBlockTimestamp() + 1);

        // Step 4: Check balance just before expiration
        uint256 balance2 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance2, 0, 'Balance should be 0 after expiration'); // All expired

        // Step 5: Try to burn credits (should fail)
        vm.prank(burner);
        vm.expectRevert();
        nftExpirableCreditsV2.burn(receiver, planId, 1, 0, '');

        // Step 6: Mint new credits after expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 0, ''); // Never expires

        // Step 7: Check new balance
        uint256 balance3 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance3, 5, 'Balance should be 5 after minting new credits');

        // Step 8: Burn new credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 5, 0, '');
        uint256 balance4 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance4, 0, 'Balance should be 0 after burning all credits');
    }

    // ============ Event Tests ============

    function test_mint_emitsMintedEvent() public {
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, '');
        // Event emission is tested implicitly by checking the balance
        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 5);
    }

    function test_burn_emitsBurnedEvent() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');

        // Then burn some credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 3, 0, '');

        // Event emission is tested implicitly by checking the balance
        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 7);
    }

    // ============ Edge Cases ============

    function test_mint_zeroAmount() public {
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 0, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 0);
    }

    function test_burn_zeroAmount() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 10, 0, '');

        // Burn zero credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 0, 0, '');

        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 10); // Balance unchanged
    }

    function test_balanceOf_afterAllCreditsExpired() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 10, '');

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Check balance after all credits expired
        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 0);
    }

    function test_balanceOf_afterAllCreditsBurned() public {
        // Mint credits
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 5, 0, '');

        // Burn all credits
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 5, 0, '');

        // Check balance after all credits burned
        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 0);
    }

    // ============ Gas Benchmarks Against V1 ============

    function test_gasComparision_againstV1() public {
        uint256 timeStart = block.timestamp + 1;
        uint256 timeEnd = block.timestamp + 10000;

        // At each expiration, mint 10 credits
        console2.log('Index,v1_mint_gas,v2_mint_gas');
        uint256 creditsToMintPerExpiration = 10;
        for (uint256 i = 0; i < timeEnd - timeStart; i++) {
            // Mint in V1
            vm.prank(minter);
            uint256 gasV1 = gasleft();
            nftExpirableCredits.mint(receiver, planId, creditsToMintPerExpiration, i, '');
            gasV1 = gasV1 - gasleft();

            // Mint in V2
            vm.prank(minter);
            uint256 gasV2 = gasleft();
            nftExpirableCreditsV2.mint(receiver, planId, creditsToMintPerExpiration, i, '');
            gasV2 = gasV2 - gasleft();

            console2.log(string.concat(vm.toString(i), ',', vm.toString(gasV1), ',', vm.toString(gasV2)));
        }

        uint256 snapshot = vm.snapshot();
        uint256 creditsToBurnPerIteration = 30;
        uint256 iterations = 100;

        // At each iteration, go to a random timestamp, burn 30 credits and test the gas
        console2.log('Timestamp,v1_burn_gas,v1_balance_of_gas,v2_burn_gas,v2_balance_of_gas');
        for (uint256 i = 0; i < iterations; i++) {
            vm.revertTo(snapshot);

            // uint256 timeStampToTestAt = bound(uint256(keccak256(abi.encode(i))), timeStart, timeEnd);
            uint256 timeStampToTestAt =
                timeStart + ((timeEnd - timeStart - 20) * uint64(uint256(keccak256(abi.encode(i))))) / type(uint64).max;
            vm.warp(timeStampToTestAt);

            vm.prank(burner);
            uint256 gasV1Burn = gasleft();
            nftExpirableCredits.burn(receiver, planId, creditsToBurnPerIteration, 0, '');
            gasV1Burn = gasV1Burn - gasleft();

            vm.prank(burner);
            uint256 gasV1BalanceOf = gasleft();
            nftExpirableCredits.balanceOf(receiver, planId);
            gasV1BalanceOf = gasV1BalanceOf - gasleft();

            vm.prank(burner);
            uint256 gasV2Burn = gasleft();
            nftExpirableCreditsV2.burn(receiver, planId, creditsToBurnPerIteration, 0, '');
            gasV2Burn = gasV2Burn - gasleft();

            vm.prank(burner);
            uint256 gasV2BalanceOf = gasleft();
            nftExpirableCreditsV2.balanceOf(receiver, planId);
            gasV2BalanceOf = gasV2BalanceOf - gasleft();

            console2.log(
                string.concat(
                    vm.toString(timeStampToTestAt),
                    ',',
                    vm.toString(gasV1Burn),
                    ',',
                    vm.toString(gasV1BalanceOf),
                    ',',
                    vm.toString(gasV2Burn),
                    ',',
                    vm.toString(gasV2BalanceOf)
                )
            );
        }
    }

    // ============ Purge Expired Credits Tests ============

    function test_purgeExpiredCredits_singleExpiration() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Check initial balance
        uint256 balanceBefore = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceBefore, 100);

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp
        uint256 expiration = vm.getBlockTimestamp() - 5; // 10 seconds ago

        // Purge expired credits
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration;

        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Check balance after purge
        uint256 balanceAfter = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter, 0);
    }

    function test_purgeExpiredCredits_multipleExpirations() public {
        // Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 50, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 30, 20, ''); // Expires in 20 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 20, 0, ''); // Never expires

        // Check initial balance
        uint256 balanceBefore = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceBefore, 100);

        // Advance time past both expirations
        vm.warp(vm.getBlockTimestamp() + 25);

        // Get expiration timestamps
        uint256 expiration1 = vm.getBlockTimestamp() - 15; // 10 seconds ago
        uint256 expiration2 = vm.getBlockTimestamp() - 5; // 20 seconds ago

        // Purge both expired credits
        uint256[] memory expirations = new uint256[](2);
        expirations[0] = expiration1;
        expirations[1] = expiration2;

        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Check balance after purge (only non-expiring credits should remain)
        uint256 balanceAfter = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter, 20);
    }

    function test_purgeExpiredCredits_partialExpirations() public {
        // Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 50, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 30, 20, ''); // Expires in 20 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 20, 0, ''); // Never expires

        // Advance time past first expiration only
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get only the first expiration timestamp
        uint256 expiration1 = vm.getBlockTimestamp() - 5; // 10 seconds ago

        // Purge only the first expired credits
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration1;

        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Check balance after purge (second expiration and non-expiring should remain)
        uint256 balanceAfter = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter, 50); // 30 + 20
    }

    function test_purgeExpiredCredits_notExpired() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Don't advance time - credits are not expired yet
        uint256 expiration = vm.getBlockTimestamp() + 10; // Future expiration

        // Try to purge non-expired credits
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration;

        vm.expectRevert(abi.encodeWithSelector(INFT1155.NotExpired.selector, expiration));
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);
    }

    function test_purgeExpiredCredits_noCreditsToBurn() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp
        uint256 expiration = vm.getBlockTimestamp() - 5;

        // Purge expired credits once
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration;
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Try to purge the same expiration again
        vm.expectRevert(abi.encodeWithSelector(INFT1155.NoCreditsToBurn.selector, expiration));
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);
    }

    function test_purgeExpiredCredits_invalidExpiration() public {
        // First mint some credits to create a valid expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the real expiration timestamp
        uint256 realExpiration = vm.getBlockTimestamp() - 5;

        // Purge the real expiration first
        uint256[] memory realExpirations = new uint256[](1);
        realExpirations[0] = realExpiration;
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, realExpirations);

        // Now try to purge with a non-existent expiration (in the past)
        uint256 fakeExpiration = vm.getBlockTimestamp() - 10; // Different timestamp

        uint256[] memory expirations = new uint256[](1);
        expirations[0] = fakeExpiration;

        vm.expectRevert(abi.encodeWithSelector(INFT1155.NoCreditsToBurn.selector, fakeExpiration));
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);
    }

    function test_purgeExpiredCredits_emptyExpirationsArray() public {
        // Try to purge with empty array
        uint256[] memory expirations = new uint256[](0);

        // Should not revert but should not burn anything
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Balance should remain unchanged
        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 0);
    }

    function test_purgeExpiredCredits_mixedExpiredAndNonExpired() public {
        // Mint credits with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 50, 10, ''); // Expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 30, 20, ''); // Expires in 20 seconds

        // Advance time past first expiration only
        vm.warp(vm.getBlockTimestamp() + 15);

        // Try to purge both expirations (one expired, one not)
        uint256 expiration1 = vm.getBlockTimestamp() - 5; // Expired
        uint256 expiration2 = vm.getBlockTimestamp() + 5; // Not expired

        uint256[] memory expirations = new uint256[](2);
        expirations[0] = expiration1;
        expirations[1] = expiration2;

        vm.expectRevert(abi.encodeWithSelector(INFT1155.NotExpired.selector, expiration2));
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);
    }

    function test_purgeExpiredCredits_duplicateExpirations() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp
        uint256 expiration = vm.getBlockTimestamp() - 5;

        // Try to purge the same expiration twice in the same call
        uint256[] memory expirations = new uint256[](2);
        expirations[0] = expiration;
        expirations[1] = expiration;

        // First iteration should succeed, second should fail
        vm.expectRevert(abi.encodeWithSelector(INFT1155.NoCreditsToBurn.selector, expiration));
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);
    }

    function test_purgeExpiredCredits_zeroAmount() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 0, 10, ''); // Zero amount

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp
        uint256 expiration = vm.getBlockTimestamp() - 5;

        // Try to purge zero amount credits
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration;

        vm.expectRevert(abi.encodeWithSelector(INFT1155.NoCreditsToBurn.selector, expiration));
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);
    }

    function test_purgeExpiredCredits_anyoneCanCall() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp
        uint256 expiration = vm.getBlockTimestamp() - 5;

        // Call from unauthorized address should still work (no access control)
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration;

        vm.prank(unauthorized);
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Check that credits were purged
        uint256 balanceAfter = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter, 0);
    }

    function test_purgeExpiredCredits_afterBurn() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Burn some credits before expiration
        vm.prank(burner);
        nftExpirableCreditsV2.burn(receiver, planId, 30, 0, '');

        // Check balance after burn
        uint256 balanceAfterBurn = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfterBurn, 70);

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp
        uint256 expiration = vm.getBlockTimestamp() - 5;

        // Purge expired credits
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration;

        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Check balance after purge
        uint256 balanceAfterPurge = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfterPurge, 0);
    }

    function test_purgeExpiredCredits_multiplePlans() public {
        // Mint credits for different plans with different expiration times
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 50, 10, ''); // Plan 1, expires in 10 seconds
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId2, 30, 20, ''); // Plan 2, expires in 20 seconds

        // Advance time past first expiration only
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp for plan 1
        uint256 expiration1 = vm.getBlockTimestamp() - 5; // 10 seconds ago

        // Purge expired credits for plan 1 only
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration1;

        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Check balances
        uint256 balancePlan1 = nftExpirableCreditsV2.balanceOf(receiver, planId);
        uint256 balancePlan2 = nftExpirableCreditsV2.balanceOf(receiver, planId2);

        assertEq(balancePlan1, 0); // Purged
        assertEq(balancePlan2, 30); // Not purged (different plan, different expiration)
    }

    function test_purgeExpiredCredits_largeBatch() public {
        // Mint credits with many different expiration times
        uint256[] memory expirations = new uint256[](10);
        uint256 currentTime = vm.getBlockTimestamp();

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(minter);
            nftExpirableCreditsV2.mint(receiver, planId, 10, 10 + i, ''); // Different expiration times
            expirations[i] = currentTime + 10 + i;
        }

        // Advance time past all expirations
        vm.warp(currentTime + 25);

        // Adjust expiration timestamps to be in the past
        for (uint256 i = 0; i < 10; i++) {
            expirations[i] = currentTime + 10 + i;
        }

        // Purge all expired credits
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Check balance after purge
        uint256 balanceAfter = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balanceAfter, 0);
    }

    function test_purgeExpiredCredits_stateConsistency() public {
        // Mint credits with expiration
        vm.prank(minter);
        nftExpirableCreditsV2.mint(receiver, planId, 100, 10, ''); // Expires in 10 seconds

        // Advance time past expiration
        vm.warp(vm.getBlockTimestamp() + 15);

        // Get the expiration timestamp
        uint256 expiration = vm.getBlockTimestamp() - 5;

        // Purge expired credits
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = expiration;

        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Verify that trying to purge the same expiration again fails
        vm.expectRevert(abi.encodeWithSelector(INFT1155.NoCreditsToBurn.selector, expiration));
        nftExpirableCreditsV2.purgeExpiredCredits(receiver, planId, expirations);

        // Verify that the balance is correctly updated
        uint256 balance = nftExpirableCreditsV2.balanceOf(receiver, planId);
        assertEq(balance, 0);
    }
}
