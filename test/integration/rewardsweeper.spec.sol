// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseIntegrationTest } from "test/integration/BaseIntegrationTest.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { IAccountingModule } from "src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
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
        uint256 maxRewards = (depositAmount * maxApy * timeElapsed) / (365.25 days * accountingModule.DIVISOR());

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

        assertEq(
            accountingToken.balanceOf(address(strategy)),
            initialAccountingTokenBalance + depositAmount + expectedAmountSwept,
            "Accounting token balance should include swept rewards"
        );
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            initialBalance + depositAmount + expectedAmountSwept,
            "Safe should have received swept rewards"
        );

        // Verify that any remaining tokens in sweeper are the excess amount
        uint256 remainingInSweeper = baseAsset.balanceOf(address(rewardsSweeper));
        uint256 expectedRemaining = rewardsAmount > maxRewards ? rewardsAmount - maxRewards : 0;
        assertEq(remainingInSweeper, expectedRemaining, "Sweeper should have remaining tokens if rewards exceeded max");
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
        deal(address(accountingModule.BASE_ASSET()), address(rewardsSweeper), 1e6);
        rewardsSweeper.sweepRewardsUpToAPRMax();

        // Set up a scenario where rewards cannot be swept
        // For example, by ensuring the cooldown period has not passed

        skip(10 minutes);

        // Deal USDC to the rewards sweeper to simulate having rewards available
        deal(address(accountingModule.BASE_ASSET()), address(rewardsSweeper), 1e6);

        assertFalse(rewardsSweeper.canSweepRewards(), "canSweepRewards should be false");

        // Cannot sweep because time window is not there yet.
        vm.expectRevert(abi.encodeWithSelector(RewardsSweeper.CannotSweepRewards.selector));
        rewardsSweeper.sweepRewardsUpToAPRMax();
        vm.stopPrank();
    }

    function test_canSweepRewards_correctness() public {
        assertFalse(rewardsSweeper.canSweepRewards(), "canSweepRewards should be false");

        deal(address(accountingModule.BASE_ASSET()), address(rewardsSweeper), 1e6);
        skip(10 minutes);
        assertTrue(rewardsSweeper.canSweepRewards(), "canSweepRewards should be true");

        skip(10 minutes);

        assertTrue(rewardsSweeper.canSweepRewards(), "canSweepRewards should be true again with new time window");
    }
}
