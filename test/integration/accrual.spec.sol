// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseIntegrationTest } from "./BaseIntegrationTest.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { FixedAPYAccrual } from "src/yield/FixedAPYAccrual.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccountingToken } from "src/AccountingToken.sol";

contract FixedAPYAccrualIntegrationTest is BaseIntegrationTest {
    FixedAPYAccrual internal accrual;
    address internal constant ALICE = address(0x123);

    function setUp() public override {
        super.setUp();
        address admin = deployment.actors().ADMIN();
        accrual = FixedAPYAccrual(
            address(
                new TransparentUpgradeableProxy(
                    address(new FixedAPYAccrual()),
                    admin,
                    abi.encodeCall(FixedAPYAccrual.initialize, (admin, address(strategy), 0.1e18, block.timestamp))
                )
            )
        );
        vm.startPrank(admin);
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), ALICE);
        AccountingModule(address(accountingModule))
            .grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), address(accrual));
        vm.stopPrank();
        vm.prank(address(deployment.timelock()));
        accountingModule.setCooldownSeconds(0);

        IERC20 asset = IERC20(strategy.asset());
        deal(address(asset), ALICE, 1000e18);
        vm.startPrank(ALICE);
        asset.approve(address(strategy), 1000e18);
        strategy.deposit(1000e18, ALICE);
        vm.stopPrank();
    }

    function test_accrue_followsAccountingModuleRotation() public {
        vm.warp(block.timestamp + 1 days);
        assertGt(accrual.accrue(), 0);
        uint256 checkpoint = accrual.lastAccrual();
        uint256 retained = accrual.remainder();
        uint256 oldSnapshots = accountingModule.snapshotsLength();
        address admin = deployment.actors().ADMIN();
        AccountingModule replacement = AccountingModule(
            address(
                new TransparentUpgradeableProxy(
                    address(new AccountingModule()),
                    admin,
                    abi.encodeCall(
                        AccountingModule.initialize,
                        (
                            address(strategy),
                            admin,
                            accountingModule.safe(),
                            accountingToken,
                            accountingModule.targetApy(),
                            accountingModule.lowerBound(),
                            1e18,
                            0
                        )
                    )
                )
            )
        );
        vm.startPrank(admin);
        replacement.grantRole(replacement.REWARDS_PROCESSOR_ROLE(), address(accrual));
        strategy.setAccountingModule(address(replacement));
        AccountingToken(address(accountingToken)).setAccountingModule(address(replacement));
        vm.stopPrank();

        assertEq(address(accrual.strategy()), address(strategy));
        assertEq(address(accrual.accountingModule()), address(replacement));
        assertEq(accrual.lastAccrual(), checkpoint);
        assertEq(accrual.remainder(), retained);
        vm.warp(block.timestamp + 1 days);
        uint256 balanceBefore = accountingToken.balanceOf(address(strategy));
        uint256 preview = accrual.previewAccrual();
        assertGt(preview, 0);
        assertEq(accrual.accrue(), preview);
        assertEq(accountingToken.balanceOf(address(strategy)), balanceBefore + preview);
        assertEq(replacement.snapshotsLength(), 2);
        assertEq(accountingModule.snapshotsLength(), oldSnapshots);
    }

    function test_lossThenAccrue_sameTimestampRevertsWithZeroCooldown() public {
        uint256 initialBalance = accountingToken.balanceOf(address(strategy));
        uint256 start = accrual.lastAccrual();
        vm.warp(start + 1 days);

        vm.prank(accountingModule.safe());
        accountingModule.processLosses(10e18);
        uint256 snapshotsAfterLoss = accountingModule.snapshotsLength();
        uint256 assetsAfterLoss = strategy.totalAssets();
        assertEq(accountingModule.lastSnapshot().timestamp, block.timestamp);
        assertEq(accountingModule.cooldownSeconds(), 0);
        assertEq(accountingModule.nextUpdateWindow(), block.timestamp);
        assertGt(accrual.previewAccrual(), 0);

        // The loss already succeeded. Accrual reaches APR validation, not a cooldown failure.
        vm.expectRevert(IAccountingModule.CurrentTimestampBeforePreviousTimestamp.selector);
        accrual.accrue();
        assertEq(accountingToken.balanceOf(address(strategy)), initialBalance - 10e18);
        assertEq(accountingModule.snapshotsLength(), snapshotsAfterLoss);
        assertEq(accrual.lastAccrual(), start);
        assertEq(accrual.remainder(), 0);
        assertEq(strategy.totalAssets(), assetsAfterLoss);
    }

    function test_accrueThenLoss_sameTimestampSucceedsWithZeroCooldown() public {
        vm.warp(block.timestamp + 1 days);
        uint256 initialBalance = accountingToken.balanceOf(address(strategy));
        uint256 assetsBefore = strategy.totalAssets();
        uint256 snapshotsBefore = accountingModule.snapshotsLength();
        uint256 rewards = accrual.accrue();
        assertGt(rewards, 0);

        // Loss reporting has no APR timestamp comparison, so this order succeeds.
        vm.prank(accountingModule.safe());
        accountingModule.processLosses(10e18);
        assertEq(accountingToken.balanceOf(address(strategy)), initialBalance + rewards - 10e18);
        assertEq(strategy.totalAssets(), assetsBefore + rewards - 10e18);
        assertEq(accountingModule.snapshotsLength(), snapshotsBefore + 2);
        assertEq(accrual.lastAccrual(), block.timestamp);
    }
}
