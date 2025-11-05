// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../../../contracts/interfaces/IAsset.sol';

import {IFeeController} from '../../../contracts/interfaces/IFeeController.sol';

import '../../../contracts/common/Roles.sol';

import {INFT1155} from '../../../contracts/interfaces/INFT1155.sol';
import {NFT1155ExpirableCreditsMock} from '../../../contracts/mock/NFT1155ExpirableCreditsMock.sol';
import {NFT1155ExpirableCredits} from '../../../contracts/token/NFT1155ExpirableCredits.sol';
import {BaseTest} from '../common/BaseTest.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';

contract NFT1155ExpirableCreditsTest is BaseTest {
    address public minter;
    address public burner;
    address public receiver;
    address public unauthorized;
    uint256 public planId;
    uint256 public planId2;

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
    }

    function test_balanceOf_randomPlan() public view {
        uint256 balance = nftExpirableCredits.balanceOf(owner, 999);
        assertEq(balance, 0);
    }

    function test_mint_noPlanRevert() public {
        vm.prank(minter);
        vm.expectPartialRevert(IAsset.PlanNotFound.selector);
        nftExpirableCredits.mint(owner, 999, 1, '');
    }

    function test_mint_correct() public {
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 1, '');

        uint256 balance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(balance, 1);
    }

    function test_mint_unauthorized() public {
        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRole.selector);
        nftExpirableCredits.mint(receiver, planId, 1, '');
    }

    function test_mintWithExpiration() public {
        // Mint with 10 seconds expiration
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 1, 10, '');

        // Check initial balance
        uint256 initialBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(initialBalance, 1);

        // Advance time by 15 seconds (past expiration)
        vm.warp(vm.getBlockTimestamp() + 15);

        // Check balance after expiration
        uint256 finalBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(finalBalance, 0);
    }

    function test_mintWithoutExpiration() public {
        // Mint with no expiration (0 seconds)
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 1, 0, '');

        // Check initial balance
        uint256 initialBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(initialBalance, 1);

        // Advance time by 100 seconds
        vm.warp(vm.getBlockTimestamp() + 100);

        // Check balance after time advance - should still be the same
        uint256 finalBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(finalBalance, 1);
    }

    function test_mixedExpirationCredits() public {
        vm.startPrank(minter);

        // Mint expirable credits (50 tokens with 20 seconds expiration)
        nftExpirableCredits.mint(receiver, planId, 50, 20, '');

        // Mint permanent credits (100 tokens with no expiration)
        nftExpirableCredits.mint(receiver, planId, 100, 0, '');

        vm.stopPrank();

        // Check initial balance (should be sum of both)
        uint256 initialBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(initialBalance, 150);

        // Advance time by 30 seconds (past expiration of first batch)
        vm.warp(vm.getBlockTimestamp() + 30);

        // Check balance after partial expiration
        uint256 finalBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(finalBalance, 100);
    }

    function test_multipleExpirationTimes() public {
        vm.startPrank(minter);

        // Mint with different expiration times
        nftExpirableCredits.mint(receiver, planId, 50, 10, ''); // 10 seconds
        nftExpirableCredits.mint(receiver, planId, 75, 30, ''); // 30 seconds
        nftExpirableCredits.mint(receiver, planId, 100, 60, ''); // 60 seconds

        vm.stopPrank();

        // Check initial balance
        uint256 initialBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(initialBalance, 225);

        // Advance time by 15 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 15);
        uint256 balanceAfterFirstExpiration = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(balanceAfterFirstExpiration, 175);

        // Advance time by another 20 seconds (past second expiration)
        vm.warp(vm.getBlockTimestamp() + 20);
        uint256 balanceAfterSecondExpiration = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(balanceAfterSecondExpiration, 100);

        // Advance time by another 30 seconds (past all expirations)
        vm.warp(vm.getBlockTimestamp() + 30);
        uint256 finalBalance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(finalBalance, 0);
    }

    function test_burn_correct() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 5, 0, '');

        // Then burn some as authorized burner
        vm.prank(burner);
        nftExpirableCredits.burn(receiver, planId, 1, 0, '');

        // Check balance after burn
        uint256 balance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(balance, 4);
    }

    function test_burn_unauthorized() public {
        // First mint some credits
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 5, 0, '');

        // Try to burn as unauthorized account
        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRedemptionPermission.selector);
        nftExpirableCredits.burn(receiver, planId, 1, 0, '');
    }

    function test_burnBatch() public {
        // Mint credits for both plans
        vm.startPrank(minter);
        nftExpirableCredits.mint(receiver, planId, 100, '');
        nftExpirableCredits.mint(receiver, planId2, 200, '');
        vm.stopPrank();

        // Prepare batch burn data
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = planId;
        ids[1] = planId2;
        amounts[0] = 50;
        amounts[1] = 75;

        // Burn batch as authorized burner
        vm.prank(burner);
        nftExpirableCredits.burnBatch(receiver, ids, amounts, 0, '');

        // Check balances after burn
        uint256 balance1 = nftExpirableCredits.balanceOf(receiver, planId);
        uint256 balance2 = nftExpirableCredits.balanceOf(receiver, planId2);

        assertEq(balance1, 50);
        assertEq(balance2, 125);
    }

    function test_burnBatch_unauthorized() public {
        // Mint credits for both plans
        vm.startPrank(minter);
        nftExpirableCredits.mint(receiver, planId, 100, 0, '');
        nftExpirableCredits.mint(receiver, planId2, 200, 0, '');
        vm.stopPrank();

        // Prepare batch burn data
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = planId;
        ids[1] = planId2;
        amounts[0] = 50;
        amounts[1] = 75;

        // Try to burn batch as unauthorized account
        vm.prank(unauthorized);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        nftExpirableCredits.burnBatch(receiver, ids, amounts, 0, '');
    }

    function test_mintBatch() public {
        // Prepare batch mint data
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory durations = new uint256[](2);

        ids[0] = planId;
        ids[1] = planId2;
        amounts[0] = 50;
        amounts[1] = 75;
        durations[0] = 10;
        durations[1] = 20;

        // Mint batch as authorized minter
        vm.prank(minter);
        nftExpirableCredits.mintBatch(receiver, ids, amounts, durations, '');

        // Check balances after mint
        uint256 balance1 = nftExpirableCredits.balanceOf(receiver, planId);
        uint256 balance2 = nftExpirableCredits.balanceOf(receiver, planId2);

        assertEq(balance1, 50);
        assertEq(balance2, 75);

        // Advance time by 15 seconds (past first expiration)
        vm.warp(vm.getBlockTimestamp() + 15);

        // Check balances after first expiration
        balance1 = nftExpirableCredits.balanceOf(receiver, planId);
        balance2 = nftExpirableCredits.balanceOf(receiver, planId2);

        assertEq(balance1, 0);
        assertEq(balance2, 75);

        // Advance time by 10 more seconds (past second expiration)
        vm.warp(vm.getBlockTimestamp() + 10);

        // Check balances after second expiration
        balance1 = nftExpirableCredits.balanceOf(receiver, planId);
        balance2 = nftExpirableCredits.balanceOf(receiver, planId2);

        assertEq(balance1, 0);
        assertEq(balance2, 0);
    }

    function test_mintBatch_unauthorized() public {
        // Prepare batch mint data
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory durations = new uint256[](2);

        ids[0] = planId;
        ids[1] = planId2;
        amounts[0] = 50;
        amounts[1] = 75;
        durations[0] = 10;
        durations[1] = 20;

        // Try to mint batch as unauthorized account
        vm.prank(unauthorized);
        vm.expectPartialRevert(INFT1155.InvalidRole.selector);
        nftExpirableCredits.mintBatch(receiver, ids, amounts, durations, '');
    }

    function test_upgraderShouldBeAbleToUpgradeAfterDelay() public {
        string memory newVersion = '2.0.0';

        // Grant upgrade permissions to NFT1155ExpirableCredits
        vm.prank(owner);
        accessManager.setTargetFunctionRole(
            address(nftExpirableCredits), toArray(UUPSUpgradeable.upgradeToAndCall.selector), UPGRADE_ROLE
        );

        uint48 upgradeTime = uint48(vm.getBlockTimestamp() + UPGRADE_DELAY);

        NFT1155ExpirableCreditsMock nft1155ExpirableCreditsV2Impl = new NFT1155ExpirableCreditsMock();

        // Schedule the upgrade
        vm.prank(upgrader);
        accessManager.schedule(
            address(nftExpirableCredits),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(nft1155ExpirableCreditsV2Impl), bytes(''))),
            upgradeTime
        );

        // Advance time to the upgrade time
        vm.warp(upgradeTime);

        // Execute the upgrade
        vm.prank(upgrader);
        accessManager.execute(
            address(nftExpirableCredits),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(nft1155ExpirableCreditsV2Impl), bytes('')))
        );

        // Cast to V2 to access new functions
        NFT1155ExpirableCreditsMock nft1155ExpirableCreditsV2 =
            NFT1155ExpirableCreditsMock(address(nftExpirableCredits));

        // Initialize V2 with the new version
        vm.prank(governor);
        nft1155ExpirableCreditsV2.initializeV2(newVersion);

        // Verify the version was set correctly
        assertEq(nft1155ExpirableCreditsV2.getVersion(), newVersion);
    }

    function test_whenWasMinted_returnsTimestamps() public {
        // Mint credits with different timestamps
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 1, 10, '');
        vm.warp(vm.getBlockTimestamp() + 5);
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 2, 20, '');

        uint256[] memory timestamps = nftExpirableCredits.whenWasMinted(receiver, planId);
        // Should have at least two entries
        assertGt(timestamps.length, 1);
        assertGt(timestamps[1], timestamps[0]);
    }

    function test_getMintedEntries_returnsCorrectEntries() public {
        // Mint and burn credits
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 3, 10, '');
        vm.prank(burner);
        nftExpirableCredits.burn(receiver, planId, 1, 0, '');
        NFT1155ExpirableCredits.MintedCredits[] memory entries = nftExpirableCredits.getMintedEntries(receiver, planId);
        // Should have at least two entries: one mint, one burn
        assertGt(entries.length, 1);
        assertTrue(entries[0].isMintOps);
        assertFalse(entries[1].isMintOps);
        assertEq(entries[0].amountMinted, 3);
        assertEq(entries[1].amountMinted, 1);
    }

    function test_mintBatch_invalidLength_reverts() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](1); // Mismatched length
        uint256[] memory durations = new uint256[](2);
        ids[0] = planId;
        ids[1] = planId2;
        durations[0] = 10;
        durations[1] = 20;
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(INFT1155.InvalidLength.selector, ids.length, values.length));
        nftExpirableCredits.mintBatch(receiver, ids, values, durations, '');
    }

    function test_mintBatch_invalidLengthDurations_reverts() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);
        uint256[] memory durations = new uint256[](1); // Mismatched length
        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 1;
        values[1] = 2;
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(INFT1155.InvalidLength.selector, ids.length, durations.length));
        nftExpirableCredits.mintBatch(receiver, ids, values, durations, '');
    }

    function test_burnBatch_invalidLength_reverts() public {
        // Mint credits for both plans
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 10, 0, '');
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId2, 10, 0, '');
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](1); // Mismatched length
        ids[0] = planId;
        ids[1] = planId2;
        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(INFT1155.InvalidLength.selector, ids.length, values.length));
        nftExpirableCredits.burnBatch(receiver, ids, values, 0, '');
    }

    function test_processPreCreditBurn_skipsBurnEntries() public {
        // Mint credits in multiple batches
        vm.startPrank(minter);
        nftExpirableCredits.mint(receiver, planId, 100, 0, ''); // First mint: 100 credits
        nftExpirableCredits.mint(receiver, planId, 50, 0, ''); // Second mint: 50 credits
        vm.stopPrank();

        // Perform first burn operation
        vm.prank(burner);
        nftExpirableCredits.burn(receiver, planId, 30, 0, ''); // Burn 30 credits

        // Get entries after first burn to verify burn entry was created
        NFT1155ExpirableCredits.MintedCredits[] memory entriesAfterFirstBurn =
            nftExpirableCredits.getMintedEntries(receiver, planId);

        // Should have 3 entries: 2 mints + 1 burn
        assertEq(entriesAfterFirstBurn.length, 3);
        assertTrue(entriesAfterFirstBurn[0].isMintOps); // First mint
        assertTrue(entriesAfterFirstBurn[1].isMintOps); // Second mint
        assertFalse(entriesAfterFirstBurn[2].isMintOps); // First burn

        // Perform second burn operation - this should skip the burn entry from first burn
        vm.prank(burner);
        nftExpirableCredits.burn(receiver, planId, 40, 0, ''); // Burn 40 more credits

        // Get entries after second burn
        NFT1155ExpirableCredits.MintedCredits[] memory entriesAfterSecondBurn =
            nftExpirableCredits.getMintedEntries(receiver, planId);

        // Should have 4 entries: 2 mints + 2 burns (the second burn creates 1 new burn entry)
        assertEq(entriesAfterSecondBurn.length, 4);

        // Verify the burn entries from second burn operation
        // The second burn should have processed against the remaining valid mint entries
        // and created appropriate burn entries, skipping the previous burn entry

        // Check that we have the correct number of mint and burn operations
        uint256 mintCount = 0;
        uint256 burnCount = 0;
        for (uint256 i = 0; i < entriesAfterSecondBurn.length; i++) {
            if (entriesAfterSecondBurn[i].isMintOps) {
                mintCount++;
            } else {
                burnCount++;
            }
        }

        assertEq(mintCount, 2); // Should have 2 mint operations
        assertEq(burnCount, 2); // Should have 2 burn operations (1 from first burn + 1 from second burn)

        // Verify final balance
        uint256 finalBalance = nftExpirableCredits.balanceOf(receiver, planId);
        // Initial: 100 + 50 = 150, Burned: 30 + 40 = 70, Final: 150 - 70 = 80
        assertEq(finalBalance, 80);
    }

    function test_processPreCreditBurn_skipsBurnEntriesSimple() public {
        // Mint credits
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 100, 0, ''); // 100 credits, no expiration

        // Perform first burn operation
        vm.prank(burner);
        nftExpirableCredits.burn(receiver, planId, 30, 0, ''); // Burn 30 credits

        // Get entries after first burn
        NFT1155ExpirableCredits.MintedCredits[] memory entriesAfterFirstBurn =
            nftExpirableCredits.getMintedEntries(receiver, planId);

        // Should have 2 entries: 1 mint + 1 burn
        assertEq(entriesAfterFirstBurn.length, 2);
        assertTrue(entriesAfterFirstBurn[0].isMintOps); // Mint
        assertFalse(entriesAfterFirstBurn[1].isMintOps); // Burn

        // Perform second burn operation - this should skip the burn entry from first burn
        vm.prank(burner);
        nftExpirableCredits.burn(receiver, planId, 40, 0, ''); // Burn 40 more credits

        // Get entries after second burn
        NFT1155ExpirableCredits.MintedCredits[] memory entriesAfterSecondBurn =
            nftExpirableCredits.getMintedEntries(receiver, planId);

        // Should have 3 entries: 1 mint + 2 burns
        assertEq(entriesAfterSecondBurn.length, 3);

        // Verify all entries
        assertTrue(entriesAfterSecondBurn[0].isMintOps); // Mint
        assertFalse(entriesAfterSecondBurn[1].isMintOps); // First burn
        assertFalse(entriesAfterSecondBurn[2].isMintOps); // Second burn

        // Verify final balance
        uint256 finalBalance = nftExpirableCredits.balanceOf(receiver, planId);
        // Initial: 100, Burned: 30 + 40 = 70, Final: 100 - 70 = 30
        assertEq(finalBalance, 30);
    }

    function test_burn_notEnoughCreditsToBurn_reverts() public {
        // Mint only 50 credits
        vm.prank(minter);
        nftExpirableCredits.mint(receiver, planId, 50, 0, '');

        // Try to burn 100 credits (more than available)
        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(NFT1155ExpirableCredits.NotEnoughCreditsToBurn.selector, receiver, planId, 100)
        );
        nftExpirableCredits.burn(receiver, planId, 100, 0, '');

        // Verify balance is unchanged
        uint256 balance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(balance, 50);
    }

    function test_burnBatch_notEnoughCreditsToBurn_reverts() public {
        // Mint credits for both plans
        vm.startPrank(minter);
        nftExpirableCredits.mint(receiver, planId, 50, 0, ''); // 50 credits for planId
        nftExpirableCredits.mint(receiver, planId2, 30, 0, ''); // 30 credits for planId2
        vm.stopPrank();

        // Try to burn more credits than available for planId2
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);
        ids[0] = planId;
        ids[1] = planId2;
        values[0] = 25; // Valid burn for planId
        values[1] = 50; // Invalid burn for planId2 (only 30 available)

        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(NFT1155ExpirableCredits.NotEnoughCreditsToBurn.selector, receiver, planId2, 50)
        );
        nftExpirableCredits.burnBatch(receiver, ids, values, 0, '');

        // Verify balances are unchanged
        uint256 balance1 = nftExpirableCredits.balanceOf(receiver, planId);
        uint256 balance2 = nftExpirableCredits.balanceOf(receiver, planId2);
        assertEq(balance1, 50);
        assertEq(balance2, 30);
    }

    function test_burn_notEnoughCreditsToBurn_withExpiredCredits_reverts() public {
        // Mint credits with expiration
        vm.startPrank(minter);
        nftExpirableCredits.mint(receiver, planId, 100, 60, ''); // 100 credits, 60s expiration
        nftExpirableCredits.mint(receiver, planId, 50, 0, ''); // 50 credits, no expiration
        vm.stopPrank();

        // Advance time to expire first batch
        vm.warp(vm.getBlockTimestamp() + 70);

        // Try to burn more credits than are available (only 50 non-expired credits remain)
        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(NFT1155ExpirableCredits.NotEnoughCreditsToBurn.selector, receiver, planId, 80)
        );
        nftExpirableCredits.burn(receiver, planId, 80, 0, '');

        // Verify balance is unchanged (only non-expired credits count)
        uint256 balance = nftExpirableCredits.balanceOf(receiver, planId);
        assertEq(balance, 50);
    }

    function test_createPlan_invalidCreditsConfigAmounts_reverts() public {
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

        // Create credits config with minAmount > maxAmount (invalid configuration)
        IAsset.CreditsConfig memory creditsConfig = IAsset.CreditsConfig({
            isRedemptionAmountFixed: false,
            redemptionType: IAsset.RedemptionType.ONLY_GLOBAL_ROLE,
            durationSecs: 10,
            amount: 100,
            minAmount: 50, // minAmount is greater than maxAmount
            maxAmount: 30, // maxAmount is less than minAmount
            proofRequired: false,
            nftAddress: address(nftExpirableCredits)
        });

        (uint256[] memory amounts, address[] memory receivers) =
            assetsRegistry.includeFeesInPaymentsDistribution(priceConfig, creditsConfig);
        priceConfig.amounts = amounts;
        priceConfig.receivers = receivers;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IAsset.InvalidCreditsConfigAmounts.selector, 50, 30));
        assetsRegistry.createPlan(priceConfig, creditsConfig, 0);
    }
}
