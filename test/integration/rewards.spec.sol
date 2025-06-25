// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseScript } from "script/BaseScript.sol";
import { UpgradeUtils } from "script/UpgradeUtils.sol";
import { MainnetActors } from "@yieldnest-vault-script/Actors.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";
import { RolesVerification } from "script/verification/RolesVerification.sol";
import { BaseIntegrationTest } from "./BaseIntegrationTest.sol";

contract RewardsIntegrationTest is BaseIntegrationTest {
    address alice = address(0x123);

    function setUp() public override {
        super.setUp();
        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();

        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), deployment.actors().ADMIN());
        vm.stopPrank();
    }

    function testFuzz_processRewards_success(
        uint128 depositAmount,
        uint128 rewardAmount,
        uint32 timeElapsed,
        bool alwaysComputeTotalAssets
    )
        public
    {
        vm.assume(depositAmount > 1 ether && depositAmount < 1_000_000 ether);
        vm.assume(timeElapsed > 0 && timeElapsed < 365 days);

        vm.startPrank(deployment.actors().ADMIN());
        strategy.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);
        vm.stopPrank();

        {
            // Calculate max rewards based on time elapsed and target APY
            uint256 maxRewards = (depositAmount * accountingModule.targetApy() * timeElapsed)
                / (365 days * 10_000 * accountingModule.DIVISOR());
            vm.assume(rewardAmount <= maxRewards);
        }

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, depositAmount);

        // Initial balances
        uint256 aliceInitialBalance = baseAsset.balanceOf(alice);
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Alice deposits
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), depositAmount);
        uint256 shares = strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + timeElapsed);

        // Process rewards
        vm.startPrank(accountingModule.safe());
        accountingModule.processRewards(rewardAmount);
        vm.stopPrank();

        // Assert strategy received accounting tokens for rewards
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + depositAmount + rewardAmount,
            "Strategy should receive accounting tokens for rewards"
        );

        // Assert total assets increased by reward amount
        assertEq(
            strategy.totalAssets(),
            totalAssetsBefore + depositAmount + rewardAmount,
            "Total assets should increase by deposit and reward amounts"
        );

        // Assert total supply increased by deposit shares
        assertEq(strategy.totalSupply(), totalSupplyBefore + shares, "Total supply should increase by deposit shares");

        // Assert Alice's shares increased by deposit amount
        assertEq(
            strategy.balanceOf(alice), aliceInitialShares + shares, "Alice's shares should increase by deposit amount"
        );

        // Assert safe's balance increased by deposit amount
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + depositAmount,
            "Safe's balance should increase by deposit amount"
        );

        // Assert Alice's balance decreased by deposit amount
        assertEq(
            baseAsset.balanceOf(alice),
            aliceInitialBalance - depositAmount,
            "Alice's balance should decrease by deposit amount"
        );

        // Assert strategy's base asset balance stayed the same (assets go to safe, not strategy)
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );
    }

    function testFuzz_processRewards_daily_for_one_year(bool alwaysComputeTotalAssets) public {
        uint256 depositAmount = 10_000 ether;
        uint256 expectedMinApy = 1000; // 10% APY in basis points
        uint256 maxApy = 1053; // 10.53% APY in basis points

        IERC20 baseAsset = IERC20(strategy.asset());

        vm.startPrank(deployment.actors().ADMIN());
        strategy.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);
        vm.stopPrank();

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, depositAmount);

        // Initial deposit
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Store initial values for invariant checks
        uint256 initialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 initialTotalAssets = strategy.totalAssets();
        uint256 initialSafeBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 initialStrategyBalance = baseAsset.balanceOf(address(strategy));
        uint256 initialAliceShares = strategy.balanceOf(alice);
        uint256 initialTotalSupply = strategy.totalSupply();

        uint256 dayCount = 365;

        uint256 totalRewards;
        // Process rewards daily for a month
        for (uint256 i = 0; i < dayCount; i++) {
            // Advance time by 1 day
            vm.warp(block.timestamp + 1 days);

            // Calculate daily reward based on current total supply
            uint256 currentTotalSupply = accountingToken.totalSupply();
            uint256 dailyRewardAmount =
                (currentTotalSupply * accountingModule.targetApy()) * 1e18 / (accountingModule.DIVISOR() * 365.5 ether); // slightly
                // below max APR with 365.5 days

            // Process rewards
            vm.startPrank(accountingModule.safe());
            accountingModule.processRewards(dailyRewardAmount);
            vm.stopPrank();

            totalRewards += dailyRewardAmount;
        }

        // Calculate final APY
        uint256 totalAssets = strategy.totalAssets();
        uint256 apy = (totalRewards * 365 days * 10_000) / (depositAmount * (dayCount * 1 days));
        // Assert APY is within acceptable range
        assertLt(apy, maxApy, "APY should be less than maximum allowed");
        assertGt(apy, expectedMinApy, "APY should be greater than minimum allowed");

        // Assert other invariants
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            initialAccountingTokens + totalRewards,
            "Strategy should have accounting tokens equal to initial plus total rewards"
        );

        assertEq(
            strategy.totalAssets(),
            initialTotalAssets + totalRewards,
            "Strategy total assets should equal initial plus total rewards"
        );

        assertEq(strategy.totalSupply(), initialTotalSupply, "Strategy total supply should remain unchanged");

        assertEq(
            baseAsset.balanceOf(accountingModule.safe()), initialSafeBalance, "Safe balance should remain unchanged"
        );

        assertEq(
            baseAsset.balanceOf(address(strategy)),
            initialStrategyBalance,
            "Strategy base asset balance should remain unchanged"
        );

        assertEq(strategy.balanceOf(alice), initialAliceShares, "Alice's shares should remain unchanged");
    }

    function test_processRewardsWithMultipleCheckpointsAndPastIndex(
        uint256 depositAmount,
        uint256 timeInterval,
        bool alwaysComputeTotalAssets
    )
        public
    {
        // Fuzz depositAmount between 0.1 ether and 100_000 ether
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);

        // Fuzz timeInterval between 1 hour and 30 days
        timeInterval = bound(timeInterval, 1 hours, 30 days);

        vm.startPrank(deployment.actors().ADMIN());
        strategy.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);
        vm.stopPrank();

        // Setup initial state
        {
            IERC20 baseAsset = IERC20(strategy.asset());

            // Give Alice tokens and deposit
            deal(address(baseAsset), alice, depositAmount);
            vm.startPrank(alice);
            baseAsset.approve(address(strategy), depositAmount);
            strategy.deposit(depositAmount, alice);
            vm.stopPrank();
        }

        // Process rewards multiple times to create several snapshots
        uint256[] memory snapshotIndices = new uint256[](5);
        uint256 totalRewards = 0;

        vm.warp(block.timestamp + timeInterval);

        for (uint256 i = 0; i < 5; i++) {
            // Calculate daily reward based on current total supply
            uint256 currentTotalSupply = accountingToken.totalSupply();
            // accumulates at half the rate of the target APY
            uint256 dailyRewardAmount = (currentTotalSupply * accountingModule.targetApy() * timeInterval)
                / (accountingModule.DIVISOR() * 365.5 days) / 2;

            // Process rewards and store snapshot index
            vm.startPrank(accountingModule.safe());
            accountingModule.processRewards(dailyRewardAmount);
            vm.stopPrank();

            snapshotIndices[i] = accountingModule.snapshotsLength() - 1;
            totalRewards += dailyRewardAmount;

            // Fast forward to next update window
            vm.warp(block.timestamp + timeInterval);
        }

        // Now process rewards using a past snapshot index (e.g., index 1)
        uint256 pastSnapshotIndex = 1;
        vm.warp(accountingModule.nextUpdateWindow());

        // Get the total supply at the past snapshot index
        IAccountingModule.StrategySnapshot memory pastSnapshot = accountingModule.snapshots(pastSnapshotIndex);
        uint256 totalSupplyAtSnapshot = pastSnapshot.totalSupply;
        uint256 additionalRewardAmount = (totalSupplyAtSnapshot * accountingModule.targetApy() * timeInterval)
            / (accountingModule.DIVISOR() * 365.5 days);

        // Process rewards using the past snapshot index
        vm.startPrank(accountingModule.safe());
        accountingModule.processRewards(additionalRewardAmount, pastSnapshotIndex);
        vm.stopPrank();

        totalRewards += additionalRewardAmount;

        // Verify the system state
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            depositAmount + totalRewards,
            "Strategy should have accounting tokens equal to deposit plus total rewards"
        );

        assertEq(
            strategy.totalAssets(),
            depositAmount + totalRewards,
            "Strategy total assets should equal deposit plus total rewards"
        );

        // Verify that we have the expected number of snapshots
        assertEq(accountingModule.snapshotsLength(), 7, "Should have 7 snapshots (1 initial + 5 daily + 1 final)");

        // Verify that the past snapshot index still exists and is valid
        assertGt(pastSnapshot.timestamp, 0, "Past snapshot should have valid timestamp");
        assertGt(pastSnapshot.pricePerShare, 0, "Past snapshot should have valid price per share");
    }

    function test_processRewards_revertIfAprTooHigh() public {
        // Assume initial setup and deposits have been made
        uint256 depositAmount = 1e18;

        // Setup initial state
        {
            IERC20 baseAsset = IERC20(strategy.asset());

            // Give Alice tokens and deposit
            deal(address(baseAsset), alice, depositAmount);
            vm.startPrank(alice);
            baseAsset.approve(address(strategy), depositAmount);
            strategy.deposit(depositAmount, alice);
            vm.stopPrank();
        }

        uint256 timeInterval = 1 days;

        vm.warp(block.timestamp + timeInterval);

        uint256 dailyRewardAmount =
            (depositAmount * accountingModule.targetApy() * timeInterval) / (accountingModule.DIVISOR() * 365.5 days);

        // Process rewards for a few days to create snapshots
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(accountingModule.safe());
            accountingModule.processRewards(dailyRewardAmount);
            vm.stopPrank();
            vm.warp(block.timestamp + timeInterval);
        }

        // Use a past snapshot index
        uint256 pastSnapshotIndex = 1;
        vm.warp(accountingModule.nextUpdateWindow());

        // Get the total supply at the past snapshot index
        IAccountingModule.StrategySnapshot memory pastSnapshot = accountingModule.snapshots(pastSnapshotIndex);
        uint256 totalSupplyAtSnapshot = pastSnapshot.totalSupply;

        // Calculate an excessive reward amount to trigger APR too high
        uint256 excessiveRewardAmount = (totalSupplyAtSnapshot * accountingModule.targetApy() * timeInterval * 2)
            / (accountingModule.DIVISOR() * 365.5 days);

        // Attempt to process rewards using the past snapshot index and expect a revert
        vm.startPrank(accountingModule.safe());

        vm.expectRevert();
        accountingModule.processRewards(excessiveRewardAmount, pastSnapshotIndex);
        vm.stopPrank();
    }

    function test_processRewards_WithUpdatedTargetApy() public {
        // Assume initial setup and deposits have been made
        uint256 depositAmount = 1e18;

        // Setup initial state
        {
            IERC20 baseAsset = IERC20(strategy.asset());

            // Give Alice tokens and deposit
            deal(address(baseAsset), alice, depositAmount);
            vm.startPrank(alice);
            baseAsset.approve(address(strategy), depositAmount);
            strategy.deposit(depositAmount, alice);
            vm.stopPrank();
        }

        uint256 timeInterval = 1 days;

        vm.warp(block.timestamp + timeInterval);

        uint256 dailyRewardAmount =
            (depositAmount * accountingModule.targetApy() * timeInterval) / (accountingModule.DIVISOR() * 365.5 days);

        // Process rewards for a few days to create snapshots
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(accountingModule.safe());
            accountingModule.processRewards(dailyRewardAmount);
            vm.stopPrank();
            vm.warp(block.timestamp + timeInterval);
        }

        // Use a past snapshot index
        uint256 pastSnapshotIndex = 1;
        vm.warp(accountingModule.nextUpdateWindow());

        // Get the total supply at the past snapshot index
        IAccountingModule.StrategySnapshot memory pastSnapshot = accountingModule.snapshots(pastSnapshotIndex);
        uint256 totalSupplyAtSnapshot = pastSnapshot.totalSupply;

        // Calculate an excessive reward amount to trigger APR too high
        uint256 excessiveRewardAmount = (totalSupplyAtSnapshot * accountingModule.targetApy() * timeInterval * 2)
            / (accountingModule.DIVISOR() * 365.5 days);

        // Attempt to process rewards using the past snapshot index and expect a revert
        vm.startPrank(accountingModule.safe());

        vm.expectRevert();
        accountingModule.processRewards(excessiveRewardAmount, pastSnapshotIndex);
        vm.stopPrank();

        vm.startPrank(address(deployment.timelock()));
        AccountingModule(payable(address(accountingModule))).setTargetApy(accountingModule.targetApy() * 2);
        vm.stopPrank();

        vm.startPrank(accountingModule.safe());
        accountingModule.processRewards(excessiveRewardAmount, pastSnapshotIndex);
        vm.stopPrank();
    }
}
