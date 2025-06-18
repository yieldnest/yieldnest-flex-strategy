// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseIntegrationTest } from "test/integration/BaseIntegrationTest.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { IAccountingModule } from "src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract RewardsSweeperTest is BaseIntegrationTest {
    RewardsSweeper public rewardsSweeper;
    
    address public constant REWARDS_SWEEPER = address(0x1234567890123456789012345678901234567890);
    address public constant BOB = address(0x4567890123456789012345678901234567890123);

    function setUp() public override {
        super.setUp();
        
        // Deploy rewards sweeper
        // Deploy RewardsSweeper behind a TransparentUpgradeableProxy
        RewardsSweeper implementation = new RewardsSweeper();
        bytes memory data = abi.encodeWithSelector(
            RewardsSweeper.initialize.selector,
            address(this),
            address(accountingModule)
        );
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
        IAccessControl(address(accountingModule)).grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), address(rewardsSweeper));
        vm.stopPrank();

        // Grant BOB allocator role using ADMIN
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), BOB);
        vm.stopPrank();
    }

    function test_rewardsSweeper_basicSweep() public {
        IERC20 baseAsset = IERC20(strategy.asset());
        
        // Set initial balance
        uint256 initialBalance = baseAsset.balanceOf(accountingModule.safe());

        // Give BOB WETH (baseAsset)
        deal(address(baseAsset), BOB, 100_000_000e18);

        // Initial deposit
        vm.startPrank(BOB);
        uint256 depositAmount = 100e18;
        baseAsset.approve(address(strategy), type(uint256).max);
        strategy.deposit(depositAmount, BOB);
        vm.stopPrank();
        
        // Advance time by 1 month to allow rewards processing
        skip(30 days);
        
        // Fund rewards sweeper with some tokens to sweep
        uint256 rewardsToSweep = 0.1 ether;
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
            depositAmount + rewardsToSweep, 
            "Accounting token balance should include swept rewards"
        );
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()), 
            initialBalance + depositAmount + rewardsToSweep, 
            "Safe should have received swept rewards"
        );
    }
}

