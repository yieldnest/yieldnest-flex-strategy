// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseIntegrationTest_6Decimals } from "./BaseIntegrationTest_6Decimals.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { IAccountingModule } from "src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { console } from "forge-std/console.sol";

contract RewardsSweeperTest is BaseIntegrationTest_6Decimals {
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

    function test_sweepRewardsUpToAPRMax_6Decimals(uint256 depositAmount, uint256 rewardsAmount) public {
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
            1e12,
            "Accounting token balance should include swept rewards"
        );
        assertApproxEqRel(
            baseAsset.balanceOf(accountingModule.safe()),
            initialBalance + depositAmount + expectedAmountSwept,
            1e12,
            "Safe should have received swept rewards"
        );

        uint256 actualAmountSwept =
            accountingToken.balanceOf(address(strategy)) - initialAccountingTokenBalance - depositAmount;

        // Verify that any remaining tokens in sweeper are the excess amount
        uint256 remainingInSweeper = baseAsset.balanceOf(address(rewardsSweeper));
        uint256 expectedRemaining = rewardsAmount - actualAmountSwept;
        assertEq(remainingInSweeper, expectedRemaining, "Sweeper should have remaining tokens if rewards exceeded max");
    }

    function test_sweepRewardsDailyForOneYear_6Decimals() public {
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
