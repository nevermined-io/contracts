// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import '../../../contracts/common/Roles.sol';
import {IVault} from '../../../contracts/interfaces/IVault.sol';
import {MockERC20} from '../../../contracts/test/MockERC20.sol';

import {PaymentsVaultV2} from '../../../contracts/mock/PaymentsVaultV2.sol';
import {BaseTest} from '../common/BaseTest.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IAccessManaged} from '@openzeppelin/contracts/access/manager/IAccessManaged.sol';

contract PaymentsVaultTest is BaseTest {
    address public depositor;
    address public withdrawer;
    address public receiver;
    MockERC20 public mockERC20;
    // Using DEPOSITOR_ROLE and WITHDRAW_ROLE from BaseTest

    function setUp() public override {
        super.setUp();

        depositor = makeAddr('depositor');
        withdrawer = makeAddr('withdrawer');
        receiver = makeAddr('receiver');

        // Deploy MockERC20
        mockERC20 = new MockERC20('Mock Token', 'MTK');

        // Grant roles
        _grantRole(DEPOSITOR_ROLE, depositor);
        _grantRole(WITHDRAW_ROLE, withdrawer);

        // Mint some tokens to depositor
        mockERC20.mint(depositor, 1000 * 10 ** 18);
    }

    function test_depositNativeToken() public {
        uint256 depositAmount = 0.1 ether;

        vm.deal(address(lockPaymentCondition), depositAmount);

        vm.prank(address(lockPaymentCondition));
        vm.expectEmit(true, true, true, true);
        emit IVault.ReceivedNativeToken(address(lockPaymentCondition), depositAmount);
        paymentsVault.depositNativeToken{value: depositAmount}();

        assertEq(paymentsVault.getBalanceNativeToken(), depositAmount);
    }

    function test_depositNativeToken_onlyDepositor() public {
        uint256 depositAmount = 0.1 ether;

        vm.deal(withdrawer, depositAmount);

        vm.prank(withdrawer);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        paymentsVault.depositNativeToken{value: depositAmount}();
    }

    function test_withdrawNativeToken() public {
        uint256 depositAmount = 0.1 ether;
        uint256 withdrawAmount = 0.05 ether;

        // First deposit
        vm.deal(address(lockPaymentCondition), depositAmount);
        vm.prank(address(lockPaymentCondition));
        paymentsVault.depositNativeToken{value: depositAmount}();

        // Get receiver balance before
        uint256 receiverBalanceBefore = address(receiver).balance;

        // Withdraw using distributePaymentsCondition which has WITHDRAW_ROLE
        vm.expectEmit(true, true, true, true);
        emit IVault.WithdrawNativeToken(address(distributePaymentsCondition), receiver, withdrawAmount);
        vm.prank(address(distributePaymentsCondition));
        paymentsVault.withdrawNativeToken(withdrawAmount, receiver);

        // Verify vault balance
        assertEq(paymentsVault.getBalanceNativeToken(), depositAmount - withdrawAmount);

        // Verify receiver balance
        assertEq(address(receiver).balance - receiverBalanceBefore, withdrawAmount);
    }

    function test_withdrawNativeToken_onlyWithdrawer() public {
        uint256 depositAmount = 0.1 ether;
        uint256 withdrawAmount = 0.05 ether;

        // First deposit
        vm.deal(address(lockPaymentCondition), depositAmount);
        vm.prank(address(lockPaymentCondition));
        paymentsVault.depositNativeToken{value: depositAmount}();

        // Try to withdraw as non-withdrawer
        vm.prank(depositor);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        paymentsVault.withdrawNativeToken(withdrawAmount, receiver);
    }

    function test_withdrawNativeToken_failedToSend() public {
        uint256 depositAmount = 0.1 ether;
        uint256 withdrawAmount = 0.05 ether;

        // First deposit
        vm.deal(address(lockPaymentCondition), depositAmount);
        vm.prank(address(lockPaymentCondition));
        paymentsVault.depositNativeToken{value: depositAmount}();

        // Create a contract that can't receive ETH
        address nonPayableContract = address(new MockERC20('Test', 'TEST'));

        // Try to withdraw to non-payable contract
        vm.prank(address(distributePaymentsCondition));
        vm.expectRevert(IVault.FailedToSendNativeToken.selector);
        paymentsVault.withdrawNativeToken(withdrawAmount, nonPayableContract);
    }

    function test_depositERC20() public {
        uint256 depositAmount = 100 * 10 ** 18;

        // Mint tokens to lockPaymentCondition
        mockERC20.mint(address(lockPaymentCondition), depositAmount);

        // Approve tokens first
        vm.prank(address(lockPaymentCondition));
        mockERC20.approve(address(paymentsVault), depositAmount);

        // Deposit (this only emits event, doesn't actually transfer)
        vm.prank(address(lockPaymentCondition));
        vm.expectEmit(true, true, true, true);
        emit IVault.ReceivedERC20(address(mockERC20), address(lockPaymentCondition), depositAmount);
        paymentsVault.depositERC20(address(mockERC20), depositAmount, address(lockPaymentCondition));

        // Verify balance
        assertEq(mockERC20.balanceOf(address(paymentsVault)), depositAmount);
    }

    function test_depositERC20_onlyDepositor() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(withdrawer);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        paymentsVault.depositERC20(address(mockERC20), depositAmount, withdrawer);
    }

    function test_getBalanceNativeToken() public {
        // Initial balance should be 0
        assertEq(paymentsVault.getBalanceNativeToken(), 0);

        // Deposit some tokens
        uint256 depositAmount = 0.1 ether;
        vm.deal(address(lockPaymentCondition), depositAmount);

        // Use lockPaymentCondition which has DEPOSITOR_ROLE
        vm.prank(address(lockPaymentCondition));
        paymentsVault.depositNativeToken{value: depositAmount}();

        // Check balance again
        assertEq(paymentsVault.getBalanceNativeToken(), depositAmount);
    }

    function test_getBalanceERC20() public {
        // Initial balance should be 0
        assertEq(paymentsVault.getBalanceERC20(address(mockERC20)), 0);

        // Transfer some tokens to the vault
        uint256 transferAmount = 100 * 10 ** 18;
        vm.prank(depositor);
        mockERC20.transfer(address(paymentsVault), transferAmount);

        // Check balance again
        assertEq(paymentsVault.getBalanceERC20(address(mockERC20)), transferAmount);
    }

    function test_receiveFunction_depositor() public {
        uint256 depositAmount = 0.1 ether;

        vm.deal(address(lockPaymentCondition), depositAmount);

        // Send ETH directly to the contract using lockPaymentCondition which has DEPOSITOR_ROLE
        vm.prank(address(lockPaymentCondition));
        (bool success,) = address(paymentsVault).call{value: depositAmount}('');

        assertTrue(success);
        assertEq(paymentsVault.getBalanceNativeToken(), depositAmount);
    }

    function test_receiveFunction_nonDepositor() public {
        uint256 depositAmount = 0.1 ether;

        vm.deal(withdrawer, depositAmount);

        // Try to send ETH directly to the contract
        vm.prank(withdrawer);
        (bool success,) = address(paymentsVault).call{value: depositAmount}('');

        assertFalse(success);
    }

    function test_upgraderShouldBeAbleToUpgradeAfterDelay() public {
        string memory newVersion = '2.0.0';

        uint48 upgradeTime = uint48(vm.getBlockTimestamp() + UPGRADE_DELAY);

        PaymentsVaultV2 paymentsVaultV2Impl = new PaymentsVaultV2();

        vm.prank(upgrader);
        accessManager.schedule(
            address(paymentsVault),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(paymentsVaultV2Impl), bytes(''))),
            upgradeTime
        );

        vm.warp(upgradeTime);

        vm.prank(upgrader);
        accessManager.execute(
            address(paymentsVault),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(paymentsVaultV2Impl), bytes('')))
        );

        PaymentsVaultV2 paymentsVaultV2 = PaymentsVaultV2(payable(address(paymentsVault)));

        vm.prank(governor);
        paymentsVaultV2.initializeV2(newVersion);

        assertEq(paymentsVaultV2.getVersion(), newVersion);
    }

    function test_withdrawERC20() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;

        // First deposit
        mockERC20.mint(address(lockPaymentCondition), depositAmount);
        vm.prank(address(lockPaymentCondition));
        mockERC20.approve(address(paymentsVault), depositAmount);
        vm.prank(address(lockPaymentCondition));
        paymentsVault.depositERC20(address(mockERC20), depositAmount, address(lockPaymentCondition));

        // Get receiver balance before
        uint256 receiverBalanceBefore = mockERC20.balanceOf(receiver);

        // Withdraw using distributePaymentsCondition which has WITHDRAW_ROLE
        vm.expectEmit(true, true, true, true);
        emit IVault.WithdrawERC20(address(mockERC20), address(distributePaymentsCondition), receiver, withdrawAmount);
        vm.prank(address(distributePaymentsCondition));
        paymentsVault.withdrawERC20(address(mockERC20), withdrawAmount, receiver);

        // Verify vault balance
        assertEq(mockERC20.balanceOf(address(paymentsVault)), depositAmount - withdrawAmount);

        // Verify receiver balance
        assertEq(mockERC20.balanceOf(receiver) - receiverBalanceBefore, withdrawAmount);
    }

    function test_withdrawERC20_onlyWithdrawer() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;

        // First deposit
        mockERC20.mint(address(lockPaymentCondition), depositAmount);
        vm.prank(address(lockPaymentCondition));
        mockERC20.approve(address(paymentsVault), depositAmount);
        vm.prank(address(lockPaymentCondition));
        paymentsVault.depositERC20(address(mockERC20), depositAmount, address(lockPaymentCondition));

        // Try to withdraw as non-withdrawer
        vm.prank(depositor);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        paymentsVault.withdrawERC20(address(mockERC20), withdrawAmount, receiver);
    }
}
