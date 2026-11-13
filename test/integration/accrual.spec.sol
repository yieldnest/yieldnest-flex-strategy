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
        (uint256 preview, uint256 previewRemainder) = accrual.previewAccrual();
        assertGt(preview, 0);
        assertEq(accrual.accrue(), preview);
        assertEq(accrual.remainder(), previewRemainder);
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
        (uint256 preview,) = accrual.previewAccrual();
        assertGt(preview, 0);

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

    function test_rewardsThenAccrue_sameTimestampRevertsWithZeroCooldown() public {
        uint256 start = accrual.lastAccrual();
        vm.warp(start + 1 days);
        uint256 initialBalance = accountingToken.balanceOf(address(strategy));

        // Authorize a separate reporter to exercise the raw processRewards path.
        vm.startPrank(deployment.actors().ADMIN());
        AccountingModule(address(accountingModule)).grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), ALICE);
        vm.stopPrank();
        vm.prank(ALICE);
        accountingModule.processRewards(0.01e18);

        uint256 snapshotsAfterReport = accountingModule.snapshotsLength();
        uint256 assetsAfterReport = strategy.totalAssets();
        assertEq(accountingToken.balanceOf(address(strategy)), initialBalance + 0.01e18);
        assertEq(accountingModule.lastSnapshot().timestamp, block.timestamp);
        assertEq(accountingModule.cooldownSeconds(), 0);
        assertEq(accountingModule.nextUpdateWindow(), block.timestamp);
        assertEq(accrual.lastAccrual(), start);
        (uint256 preview,) = accrual.previewAccrual();
        assertGt(preview, 0);

        vm.expectRevert(IAccountingModule.CurrentTimestampBeforePreviousTimestamp.selector);
        accrual.accrue();
        assertEq(accountingToken.balanceOf(address(strategy)), initialBalance + 0.01e18);
        assertEq(strategy.totalAssets(), assetsAfterReport);
        assertEq(accountingModule.snapshotsLength(), snapshotsAfterReport);
        assertEq(accrual.lastAccrual(), start);
        assertEq(accrual.remainder(), 0);
    }

    function test_directRewardsLeaveAccrualBlockedByAprCapAcrossLaterAttempts() public {
        address admin = deployment.actors().ADMIN();
        vm.startPrank(admin);
        AccountingModule(address(accountingModule)).grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), ALICE);
        vm.stopPrank();
        uint256 start = accrual.lastAccrual();
        uint256 reportTime = start + 30 days;
        vm.warp(reportTime);

        // Control: the outstanding fixed-APY accrual is accepted before the direct report.
        uint256 state = vm.snapshotState();
        assertGt(accrual.accrue(), 0);
        assertTrue(vm.revertToState(state));

        uint256 initialBalance = accountingToken.balanceOf(address(strategy));
        vm.prank(ALICE);
        accountingModule.processRewards(1e18); // Valid report: passes the existing 10% APR cap.
        uint256 snapshotsAfterReport = accountingModule.snapshotsLength();
        uint256 assetsAfterReport = strategy.totalAssets();
        assertEq(accountingToken.balanceOf(address(strategy)), initialBalance + 1e18);
        assertEq(accountingModule.lastSnapshot().timestamp, reportTime);
        assertEq(accrual.lastAccrual(), start);
        assertEq(accountingModule.cooldownSeconds(), 0);
        assertEq(accountingModule.targetApy(), 0.1e18);

        // These are later blocks, not the same-timestamp failure. The report reset the APR
        // snapshot while accrual still includes the preceding 30 days and the added rewards.
        // Sample repeated failures; this does not assert failure at every possible future time.
        uint256[6] memory delays = [uint256(1), 1 hours, 1 days, 30 days, 365 days, 730 days];
        uint256 previousPreview;
        for (uint256 i; i < delays.length; ++i) {
            vm.roll(block.number + 1);
            vm.warp(reportTime + delays[i]);
            (uint256 preview,) = accrual.previewAccrual();
            assertGt(preview, previousPreview);
            previousPreview = preview;
            vm.expectPartialRevert(IAccountingModule.AccountingLimitsExceeded.selector);
            accrual.accrue();
            assertEq(accrual.lastAccrual(), start);
            assertEq(accrual.remainder(), 0);
            assertEq(accountingToken.balanceOf(address(strategy)), initialBalance + 1e18);
            assertEq(strategy.totalAssets(), assetsAfterReport);
            assertEq(accountingModule.snapshotsLength(), snapshotsAfterReport);
        }
    }

    function test_accrueThenRewards_sameTimestampRevertsWithZeroCooldown() public {
        vm.startPrank(deployment.actors().ADMIN());
        AccountingModule(address(accountingModule)).grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), ALICE);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);
        assertGt(accrual.accrue(), 0);
        uint256 balanceAfterAccrual = accountingToken.balanceOf(address(strategy));
        uint256 assetsAfterAccrual = strategy.totalAssets();
        uint256 snapshotsAfterAccrual = accountingModule.snapshotsLength();
        uint256 remainderAfterAccrual = accrual.remainder();
        assertEq(accountingModule.lastSnapshot().timestamp, block.timestamp);
        assertEq(accountingModule.cooldownSeconds(), 0);
        assertEq(accountingModule.nextUpdateWindow(), block.timestamp);

        vm.prank(ALICE);
        vm.expectRevert(IAccountingModule.CurrentTimestampBeforePreviousTimestamp.selector);
        accountingModule.processRewards(0.01e18);
        assertEq(accountingToken.balanceOf(address(strategy)), balanceAfterAccrual);
        assertEq(strategy.totalAssets(), assetsAfterAccrual);
        assertEq(accountingModule.snapshotsLength(), snapshotsAfterAccrual);
        assertEq(accrual.lastAccrual(), block.timestamp);
        assertEq(accrual.remainder(), remainderAfterAccrual);
    }
}
