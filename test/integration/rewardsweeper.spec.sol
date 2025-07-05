// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseIntegrationTest } from "test/integration/BaseIntegrationTest.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { IAccountingModule } from "src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { console } from "forge-std/console.sol";

contract RewardsSweeperTest is BaseIntegrationTest {
    RewardsSweeper public rewardsSweeper;

    address public constant REWARDS_SWEEPER = address(0x1234567890123456789012345678901234567890);
    address public constant BOB = address(0x4567890123456789012345678901234567890123);

    function setUp() public override {
        super.setUp();

        // Deploy rewards sweeper
        // Deploy RewardsSweeper behind a TransparentUpgradeableProxy
        RewardsSweeper implementation = new RewardsSweeper();
        bytes memory data =
            abi.encodeWithSelector(RewardsSweeper.initialize.selector, address(this), address(accountingModule));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this), // admin
            data
        );
        rewardsSweeper = RewardsSweeper(address(proxy));

        // Grant rewards sweeper role
        rewardsSweeper.grantRole(rewardsSweeper.REWARDS_SWEEPER_ROLE(), REWARDS_SWEEPER);

        // Grant rewards processor role to rewards sweeper as ADMIN
        vm.startPrank(deployment.actors().ADMIN());
        IAccessControl(address(accountingModule)).grantRole(
            accountingModule.REWARDS_PROCESSOR_ROLE(), address(rewardsSweeper)
        );
        vm.stopPrank();

        // Grant BOB allocator role using ADMIN
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), BOB);
        IAccessControl(address(accountingModule)).grantRole(
            accountingModule.SAFE_MANAGER_ROLE(), deployment.actors().ADMIN()
        );
        vm.stopPrank();
    }

    function test_setAccountingModule_Admin() public {
        rewardsSweeper.setAccountingModule(address(accountingModule));
        vm.stopPrank();
    }

    function test_setAccountingModule_revertIfNotAdmin() public {
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, rewardsSweeper.DEFAULT_ADMIN_ROLE()
            )
        );
        rewardsSweeper.setAccountingModule(address(accountingModule));
        vm.stopPrank();
    }

    function test_rewardsSweeper_basicSweep(uint256 depositAmount, uint256 rewardsToSweep) public {
        // Bound depositAmount to reasonable range (1e18 to 1000e18)
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);

        // Calculate max APY based on time (30 days = ~1 month)
        uint256 timeElapsed = 30 days;
        uint256 maxApy = accountingModule.targetApy();

        // Calculate maximum possible rewards based on APY and time
        // APY is in basis points, so divide by 10000 to get percentage
        uint256 maxRewards = (depositAmount * maxApy * timeElapsed) / (365.25 days * accountingModule.DIVISOR());

        rewardsToSweep = bound(rewardsToSweep, 1e6, maxRewards);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Set initial balance
        uint256 initialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 initialAccountingTokenBalance = accountingToken.balanceOf(address(strategy));

        // Give BOB WETH (baseAsset)
        deal(address(baseAsset), BOB, 100_000_000e18);

        // Initial deposit
        vm.startPrank(BOB);
        baseAsset.approve(address(strategy), type(uint256).max);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();

        // Advance time by 1 month to allow rewards processing
        skip(timeElapsed);

        deal(address(baseAsset), address(rewardsSweeper), rewardsToSweep);

        // Verify initial state
        assertEq(baseAsset.balanceOf(address(rewardsSweeper)), rewardsToSweep, "Rewards sweeper should have tokens");
        assertEq(accountingToken.balanceOf(address(strategy)), depositAmount, "Initial accounting token balance");

        // Sweep rewards
        vm.startPrank(REWARDS_SWEEPER);
        rewardsSweeper.sweepRewards(rewardsToSweep);

        // Verify rewards were processed
        assertEq(baseAsset.balanceOf(address(rewardsSweeper)), 0, "Rewards sweeper should have no tokens left");
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            initialAccountingTokenBalance + depositAmount + rewardsToSweep,
            "Accounting token balance should include swept rewards"
        );
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            initialBalance + depositAmount + rewardsToSweep,
            "Safe should have received swept rewards"
        );
    }

    function test_sweepRewardsUpToAPRMax(uint256 depositAmount, uint256 rewardsAmount) public {
        // Set specific values for testing
        // Bound depositAmount to reasonable range (1e18 to 1000e18)
        depositAmount = bound(depositAmount, 1e18, 1000e18);

        uint256 timeElapsed = 30 days;
        uint256 maxApy = accountingModule.targetApy();

        // Calculate maximum possible rewards based on APY and time
        uint256 maxRewards = (depositAmount * maxApy * timeElapsed) / ((365.25 days + 1) * accountingModule.DIVISOR());

        // Bound rewardsAmount to reasonable range (1e6 to maxRewards * 2 to test both cases)
        rewardsAmount = bound(rewardsAmount, 1e6, maxRewards * 2);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Set initial balance
        uint256 initialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 initialAccountingTokenBalance = accountingToken.balanceOf(address(strategy));

        // Give BOB WETH (baseAsset)
        deal(address(baseAsset), BOB, 100_000_000e18);

        // Initial deposit
        vm.startPrank(BOB);
        baseAsset.approve(address(strategy), type(uint256).max);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();

        // Advance time by 1 month to allow rewards processing
        skip(timeElapsed);

        deal(address(baseAsset), address(rewardsSweeper), rewardsAmount);

        // Verify initial state
        assertEq(baseAsset.balanceOf(address(rewardsSweeper)), rewardsAmount, "Rewards sweeper should have tokens");
        assertEq(accountingToken.balanceOf(address(strategy)), depositAmount, "Initial accounting token balance");

        // Sweep rewards up to APR max
        vm.startPrank(REWARDS_SWEEPER);
        rewardsSweeper.sweepRewardsUpToAPRMax();

        // Calculate expected amount swept (minimum of maxRewards and rewardsAmount)
        uint256 expectedAmountSwept = rewardsAmount < maxRewards ? rewardsAmount : maxRewards;

        assertApproxEqRel(
            accountingToken.balanceOf(address(strategy)),
            initialAccountingTokenBalance + depositAmount + expectedAmountSwept,
            1e10,
            "Accounting token balance should include swept rewards"
        );
        assertApproxEqRel(
            baseAsset.balanceOf(accountingModule.safe()),
            initialBalance + depositAmount + expectedAmountSwept,
            1e10,
            "Safe should have received swept rewards"
        );

        uint256 actualAmountSwept =
            accountingToken.balanceOf(address(strategy)) - initialAccountingTokenBalance - depositAmount;

        // Verify that any remaining tokens in sweeper are the excess amount
        uint256 remainingInSweeper = baseAsset.balanceOf(address(rewardsSweeper));
        uint256 expectedRemaining = rewardsAmount - actualAmountSwept;
        assertEq(remainingInSweeper, expectedRemaining, "Sweeper should have remaining tokens if rewards exceeded max");
    }

    function testfuzz_sweepRewardsUpToAPRMax_excessRewards_multiple(
        uint256 depositAmount,
        uint256 timeElapsed
    )
        public
    {
        // Fuzz depositAmount to a reasonable range (1e18 to 1000e18)
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);

        // Fuzz timeElapsed to a reasonable range (1 hour to 30 days)
        timeElapsed = bound(timeElapsed, 1 hours, 30 days);

        // Set rewardsAmount to be 20x the depositAmount (Excess)
        uint256 rewardsAmount = depositAmount * 20;

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give BOB WETH (baseAsset)
        deal(address(baseAsset), BOB, 100_000_000e18);

        // Initial deposit
        vm.startPrank(BOB);
        baseAsset.approve(address(strategy), type(uint256).max);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();

        // Advance time by fuzzed timeElapsed to allow rewards processing
        skip(timeElapsed);

        // Deal rewards to the rewards sweeper
        deal(address(baseAsset), address(rewardsSweeper), rewardsAmount);

        // Verify initial state

        // Sweep rewards up to APR max with multiple processRewards calls
        vm.startPrank(REWARDS_SWEEPER);

        for (uint256 i = 0; i < 5; i++) {
            rewardsSweeper.sweepRewardsUpToAPRMax();
            skip(timeElapsed);
        }
    }

    function testfuzz_sweepRewardsUpToAPRMax_withDonation(
        uint256 depositAmount,
        uint256 donationAmount,
        uint256 timeElapsed
    )
        public
    {
        // Fuzz depositAmount to a reasonable range (1e18 to 1000e18)
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);

        // Fuzz donationAmount to a reasonable range (1 to 2x depositAmount)
        donationAmount = bound(donationAmount, 1, depositAmount * 2);

        // Fuzz timeElapsed to a reasonable range (1 hour to 30 days)
        timeElapsed = bound(timeElapsed, 1 hours, 30 days);

        // Set rewardsAmount to be 20x the depositAmount (Excess)
        uint256 rewardsAmount = depositAmount * 20;

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give BOB WETH (baseAsset)
        deal(address(baseAsset), BOB, 100_000_000e18);

        // Initial deposit
        vm.startPrank(BOB);
        baseAsset.approve(address(strategy), type(uint256).max);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();

        // Advance time by fuzzed timeElapsed to allow rewards processing
        skip(timeElapsed);

        // Deal rewards to the rewards sweeper
        deal(address(baseAsset), address(rewardsSweeper), rewardsAmount);

        // Bob donates to the strategy
        address bob = address(0x456);
        deal(address(baseAsset), bob, donationAmount);
        vm.startPrank(bob);
        baseAsset.approve(address(strategy), donationAmount);
        baseAsset.transfer(address(strategy), donationAmount);
        vm.stopPrank();

        // Verify initial state
        assertEq(baseAsset.balanceOf(address(rewardsSweeper)), rewardsAmount, "Rewards sweeper should have tokens");
        assertEq(baseAsset.balanceOf(address(strategy)), donationAmount, "Strategy should have donation amount");

        // Sweep rewards up to APR max with multiple processRewards calls
        vm.startPrank(REWARDS_SWEEPER);

        rewardsSweeper.sweepRewardsUpToAPRMax();
    }

    function testfuzz_sweepRewardsUpToAPRMax_withSnapshotIndex_success(
        uint256 depositAmount,
        uint8 snapshotSeed
    )
        public
    {
        // Fuzz depositAmount to a reasonable range (1e18 to 1000e18)
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);
        uint256 rewardRounds = 4;
        uint256 snapshotIndex = bound(uint256(snapshotSeed), 0, rewardRounds - 1);

        uint256 rewardsAmount = depositAmount * 20;

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give BOB WETH (baseAsset)
        deal(address(baseAsset), BOB, 100_000_000e18);

        // Initial deposit
        vm.startPrank(BOB);
        baseAsset.approve(address(strategy), type(uint256).max);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();

        // Advance time by 1 month to allow rewards processing
        skip(30 days);

        // Deal rewards to the rewards sweeper
        deal(address(baseAsset), address(rewardsSweeper), rewardsAmount);

        // Verify initial state
        assertEq(baseAsset.balanceOf(address(rewardsSweeper)), rewardsAmount, "Rewards sweeper should have tokens");

        // Sweep rewards up to APR max with multiple processRewards calls
        vm.startPrank(REWARDS_SWEEPER);

        for (uint256 i = 0; i < rewardRounds; i++) {
            rewardsSweeper.sweepRewardsUpToAPRMax();
            skip(30 days);
        }

        // Assert that the amount swept is equal to the expected rewards after subtraction
        rewardsSweeper.sweepRewardsUpToAPRMax(snapshotIndex);
    }

    function test_sweepRewards_revertIfNotAuthorized() public {
        // Attempt to sweep rewards without the proper role
        vm.startPrank(BOB); // BOB does not have the REWARDS_SWEEPER_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, rewardsSweeper.REWARDS_SWEEPER_ROLE()
            )
        );
        rewardsSweeper.sweepRewardsUpToAPRMax();
        vm.stopPrank();

        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, rewardsSweeper.REWARDS_SWEEPER_ROLE()
            )
        );
        rewardsSweeper.sweepRewards(100, 0);
        vm.stopPrank();
    }

    function test_sweepRewards_revertIfCannotSweepRewards() public {
        {
            IERC20 baseAsset = IERC20(strategy.asset());
            // Give BOB WETH (baseAsset)
            deal(address(baseAsset), BOB, 100_000_000e18);
            uint256 depositAmount = 1000e18;

            // Initial deposit
            vm.startPrank(BOB);
            baseAsset.approve(address(strategy), type(uint256).max);
            strategy.deposit(depositAmount, BOB);
            vm.stopPrank();
        }

        vm.startPrank(REWARDS_SWEEPER);

        skip(10 minutes);

        // Do one sweep.
        deal(address(accountingModule.baseAsset()), address(rewardsSweeper), 1e6);
        rewardsSweeper.sweepRewardsUpToAPRMax();

        // Set up a scenario where rewards cannot be swept
        // For example, by ensuring the cooldown period has not passed

        skip(10 minutes);

        // Deal rewards sweeper to simulate having rewards available
        deal(address(accountingModule.baseAsset()), address(rewardsSweeper), 1e6);

        assertFalse(rewardsSweeper.canSweepRewards(), "canSweepRewards should be false");

        // Cannot sweep because time window is not there yet.
        vm.expectRevert(abi.encodeWithSelector(RewardsSweeper.CannotSweepRewards.selector));
        rewardsSweeper.sweepRewardsUpToAPRMax();
        vm.stopPrank();
    }

    function test_canSweepRewards_correctness() public {
        assertFalse(rewardsSweeper.canSweepRewards(), "canSweepRewards should be false");

        deal(address(accountingModule.baseAsset()), address(rewardsSweeper), 1e6);
        skip(10 minutes);
        assertTrue(rewardsSweeper.canSweepRewards(), "canSweepRewards should be true");

        skip(10 minutes);

        assertTrue(rewardsSweeper.canSweepRewards(), "canSweepRewards should be true again with new time window");
    }

    function test_revertIfAttemptingToSweepPastAPRMax(uint256 depositAmount) public {
        // Ensure depositAmount is at least 1e18
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);

        IERC20 baseAsset = IERC20(strategy.asset());
        // Give BOB WETH (baseAsset)
        deal(address(baseAsset), BOB, 100_000_000e18);

        // Initial deposit
        vm.startPrank(BOB);
        baseAsset.approve(address(strategy), type(uint256).max);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();

        skip(365.25 days);

        // excess rewards
        deal(address(accountingModule.baseAsset()), address(rewardsSweeper), depositAmount * 10);

        uint256 amountToSweep = rewardsSweeper.previewSweepRewardsUpToAPRMax(accountingModule.snapshotsLength() - 1);

        vm.startPrank(REWARDS_SWEEPER);
        vm.expectRevert();
        rewardsSweeper.sweepRewards(amountToSweep + depositAmount / 1e14 + 1);
        vm.stopPrank();
    }

    function test_sweepRewardsDailyForOneYear() public {
        uint256 depositAmount = 10_000 ether;
        uint256 expectedMinApy = 1000; // 10% APY in basis points
        uint256 maxApy = 1050; // 10.5% APY in basis points

        // Deal rewards to sweeper well in excess of depositAmount
        deal(address(accountingModule.baseAsset()), address(rewardsSweeper), depositAmount * 12);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give BOB some tokens to deposit
        deal(address(baseAsset), BOB, depositAmount);

        // Initial deposit
        vm.startPrank(BOB);
        baseAsset.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();

        // Store initial values for invariant checks
        uint256 initialTotalAssets = strategy.totalAssets();
        uint256 initialAccountingTokens = accountingToken.balanceOf(address(strategy));

        uint256 dayCount = 365;
        uint256 totalRewards = 0;

        // Process rewards daily for a year
        for (uint256 i = 0; i < dayCount; i++) {
            // Advance time by 1 day
            skip(1 days);

            // Sweep rewards
            vm.startPrank(REWARDS_SWEEPER);
            uint256 sweptAmount = rewardsSweeper.sweepRewardsUpToAPRMax();
            vm.stopPrank();

            totalRewards += sweptAmount;
        }

        // Calculate final APY
        uint256 apy = (totalRewards * 365 days * 10_000) / (depositAmount * (dayCount * 1 days));

        // Assert APY is within acceptable range
        assertLe(apy, maxApy, "APY should be less than or equal to maximum allowed");
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
    }
}
