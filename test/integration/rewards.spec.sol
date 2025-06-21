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
    }

    function testFuzz_processRewards_success(uint128 depositAmount, uint128 rewardAmount, uint32 timeElapsed) public {
        vm.assume(depositAmount > 1 ether && depositAmount < 1_000_000 ether);
        vm.assume(timeElapsed > 0 && timeElapsed < 365 days);

        // Calculate max rewards based on time elapsed and target APY
        uint256 maxRewards = (depositAmount * accountingModule.targetApy() * timeElapsed)
            / (365 days * 10_000 * accountingModule.DIVISOR());
        vm.assume(rewardAmount <= maxRewards);

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

    function test_processRewards_daily_for_one_year() public {
        uint256 depositAmount = 1_000_000 ether;
        uint256 expectedMinApy = 1000; // 10% APY in basis points
        uint256 maxApy = 1053; // 10.53% APY in basis points

        IERC20 baseAsset = IERC20(strategy.asset());

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

    function test_processRewardsWithMultipleCheckpointsAndPastIndex() public {
        // Setup initial state

        uint256 depositAmount = 1000e18;
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

        vm.warp(block.timestamp + 1 days);

        for (uint256 i = 0; i < 5; i++) {

            // Calculate daily reward based on current total supply
            uint256 currentTotalSupply = accountingToken.totalSupply();
            uint256 dailyRewardAmount =
                (currentTotalSupply * accountingModule.targetApy()) * 1e18 / (accountingModule.DIVISOR() * 365.5 ether);

            // Process rewards and store snapshot index
            vm.startPrank(accountingModule.safe());
            accountingModule.processRewards(dailyRewardAmount);
            vm.stopPrank();

            snapshotIndices[i] = accountingModule.snapshotsLength() - 1;
            totalRewards += dailyRewardAmount;

            // Fast forward to next update window
            vm.warp(block.timestamp + 1 days);
        }

        // Now process rewards using a past snapshot index (e.g., index 1)
        uint256 pastSnapshotIndex = 1;
        vm.warp(accountingModule.nextUpdateWindow());

        uint256 currentTotalSupply = accountingToken.totalSupply();
        uint256 additionalRewardAmount =
            (currentTotalSupply * accountingModule.targetApy()) * 1e18 / (accountingModule.DIVISOR() * 365.5 ether);

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
        IAccountingModule.StrategySnapshot memory pastSnapshot = accountingModule.snapshots(pastSnapshotIndex);
        assertGt(pastSnapshot.timestamp, 0, "Past snapshot should have valid timestamp");
        assertGt(pastSnapshot.pricePerShare, 0, "Past snapshot should have valid price per share");
    }
}
