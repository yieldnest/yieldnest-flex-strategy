// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseScript } from "script/BaseScript.sol";
import { UpgradeUtils } from "script/UpgradeUtils.sol";
import { MainnetActors } from "@yieldnest-vault-script/Actors.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";
import { RolesVerification } from "script/verification/RolesVerification.sol";
import { BaseIntegrationTest } from "./BaseIntegrationTest.sol";

contract AllocationIntegrationTest is BaseIntegrationTest {
    address alice = address(0x123);

    address allocationDestination = address(0x456);

    function setUp() public override {
        super.setUp();
        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();
    }

    function testFuzz_allocation(uint256 depositAmount, uint256 allocationAmount) public {
        depositAmount = bound(depositAmount, 1, 1_000_000 ether);
        allocationAmount = bound(allocationAmount, 1, depositAmount);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, depositAmount);

        // Record initial balances
        uint256 aliceInitialBalance = baseAsset.balanceOf(alice);
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 allocationDestinationInitialBalance = baseAsset.balanceOf(allocationDestination);
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Alice approves and deposits
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), depositAmount);
        uint256 shares = strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Impersonate SAFE and move assets to allocation destination
        vm.startPrank(accountingModule.safe());
        baseAsset.transfer(allocationDestination, allocationAmount);
        vm.stopPrank();

        // Assert Alice's balance decreased by deposit amount
        assertEq(
            baseAsset.balanceOf(alice),
            aliceInitialBalance - depositAmount,
            "Alice's balance should decrease by deposit amount"
        );

        // Assert Alice received shares
        assertEq(strategy.balanceOf(alice), aliceInitialShares + shares, "Alice should receive shares for deposit");

        // Assert safe initially received the base assets but then transferred some out
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + depositAmount - allocationAmount,
            "Safe should have transferred out the allocated assets"
        );

        // Assert allocation destination received the allocated funds
        assertEq(
            baseAsset.balanceOf(allocationDestination),
            allocationDestinationInitialBalance + allocationAmount,
            "Allocation destination should receive the allocated funds"
        );

        // Assert strategy received accounting tokens
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + depositAmount,
            "Strategy should receive accounting tokens equal to deposit amount"
        );

        // Assert total supply increased
        assertEq(strategy.totalSupply(), totalSupplyBefore + shares, "Total supply should increase by shares minted");

        // Assert total assets increased
        assertEq(
            strategy.totalAssets(), totalAssetsBefore + depositAmount, "Total assets should increase by deposit amount"
        );

        // Assert strategy's base asset balance stayed the same (assets go to safe, not strategy)
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );

        // Assert shares are correctly calculated (1:1 ratio for first deposit or based on current ratio)
        uint256 expectedShares =
            totalSupplyBefore == 0 ? depositAmount : depositAmount * totalSupplyBefore / totalAssetsBefore;
        assertEq(shares, expectedShares, "Shares should be calculated correctly");
    }

    struct TestData {
        uint256 depositAmount;
        uint256 allocationAmount;
        uint256 withdrawAmount;
        IERC20 baseAsset;
        uint256 aliceInitialBalance;
        uint256 strategyInitialBalance;
        uint256 safeInitialBalance;
        uint256 aliceInitialShares;
        uint256 strategyInitialAccountingTokens;
        uint256 allocationDestinationInitialBalance;
        uint256 totalSupplyBefore;
        uint256 totalAssetsBefore;
        uint256 shares;
        uint256 withdrawnShares;
    }

    function test_deposit_allocate_withdraw_success(
        uint256 depositAmount,
        uint256 allocationAmount,
        uint256 withdrawAmount
    )
        public
    {
        depositAmount = bound(depositAmount, 1 ether, 1_000_000 ether);
        allocationAmount = bound(allocationAmount, 1 ether, depositAmount);
        withdrawAmount = bound(withdrawAmount, 0, depositAmount - allocationAmount);

        TestData memory data;
        data.depositAmount = depositAmount;
        data.allocationAmount = allocationAmount;
        data.withdrawAmount = withdrawAmount;
        data.baseAsset = IERC20(strategy.asset());

        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();

        // Give Alice some tokens to deposit
        deal(address(data.baseAsset), alice, data.depositAmount);

        // Record initial balances
        data.aliceInitialBalance = data.baseAsset.balanceOf(alice);
        data.strategyInitialBalance = data.baseAsset.balanceOf(address(strategy));
        data.safeInitialBalance = data.baseAsset.balanceOf(accountingModule.safe());
        data.aliceInitialShares = strategy.balanceOf(alice);
        data.strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        data.allocationDestinationInitialBalance = data.baseAsset.balanceOf(allocationDestination);
        data.totalSupplyBefore = strategy.totalSupply();
        data.totalAssetsBefore = strategy.totalAssets();

        // Alice approves and deposits
        vm.startPrank(alice);
        data.baseAsset.approve(address(strategy), data.depositAmount);
        data.shares = strategy.deposit(data.depositAmount, alice);
        vm.stopPrank();

        // Allocate some funds by transferring from safe to allocation destination
        vm.startPrank(accountingModule.safe());
        data.baseAsset.transfer(allocationDestination, data.allocationAmount);
        vm.stopPrank();

        // Withdraw some funds
        vm.startPrank(alice);
        data.withdrawnShares = strategy.withdraw(data.withdrawAmount, alice, alice);
        vm.stopPrank();

        // Assert Alice's balance decreased by deposit amount but increased by withdrawal
        assertEq(
            data.baseAsset.balanceOf(alice),
            data.aliceInitialBalance - data.depositAmount + data.withdrawAmount,
            "Alice's balance should decrease by deposit amount but increase by withdrawal"
        );

        // Assert Alice received shares but then burned some for withdrawal
        assertEq(
            strategy.balanceOf(alice),
            data.aliceInitialShares + data.shares - data.withdrawnShares,
            "Alice should have remaining shares after withdrawal"
        );

        // Assert safe received the base assets, transferred some out, and then transferred more out for withdrawal
        assertEq(
            data.baseAsset.balanceOf(accountingModule.safe()),
            data.safeInitialBalance + data.depositAmount - data.allocationAmount - data.withdrawAmount,
            "Safe should have transferred out allocated and withdrawn assets"
        );

        // Assert allocation destination received the allocated funds
        assertEq(
            data.baseAsset.balanceOf(allocationDestination),
            data.allocationDestinationInitialBalance + data.allocationAmount,
            "Allocation destination should receive the allocated funds"
        );

        // Assert strategy received accounting tokens but then burned some for withdrawal
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            data.strategyInitialAccountingTokens + data.depositAmount - data.withdrawAmount,
            "Strategy should have remaining accounting tokens after withdrawal"
        );

        // Assert total supply increased by shares minted but decreased by shares burned
        assertEq(
            strategy.totalSupply(),
            data.totalSupplyBefore + data.shares - data.withdrawnShares,
            "Total supply should reflect minted and burned shares"
        );

        // Assert total assets increased by deposit but decreased by allocation and withdrawal
        assertEq(
            strategy.totalAssets(),
            data.totalAssetsBefore + data.depositAmount - data.withdrawAmount,
            "Total assets should reflect deposit minus allocation and withdrawal"
        );

        // Assert strategy's base asset balance stayed the same (assets go to safe, not strategy)
        assertEq(
            data.baseAsset.balanceOf(address(strategy)),
            data.strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );

        // Assert share calculations are correct
        uint256 expectedShares = data.totalSupplyBefore == 0
            ? data.depositAmount
            : data.depositAmount * data.totalSupplyBefore / data.totalAssetsBefore;
        assertEq(data.shares, expectedShares, "Shares should be calculated correctly");
    }

    function test_deposit_allocate_withdraw_fail(
        uint256 depositAmount,
        uint256 allocationAmount,
        uint256 withdrawAmount
    )
        public
    {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);
        allocationAmount = bound(allocationAmount, 1e18, depositAmount);
        withdrawAmount = bound(withdrawAmount, 1e18, depositAmount);

        // Ensure withdrawal amount is greater than what's available after allocation
        // This will cause the test to fail
        vm.assume(withdrawAmount > depositAmount - allocationAmount);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, depositAmount);

        // Initial deposit
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Allocate some funds by transferring from safe to allocation destination
        vm.startPrank(accountingModule.safe());
        baseAsset.transfer(allocationDestination, allocationAmount);
        vm.stopPrank();

        // Try to withdraw more than available - this should fail
        vm.startPrank(alice);
        vm.expectRevert(); // Expect revert due to insufficient funds
        strategy.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();
    }
}
