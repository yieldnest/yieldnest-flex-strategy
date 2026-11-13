// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;
import { BaseAccrual6IntegrationTest } from "./BaseAccrual6IntegrationTest.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";

contract AccrualPrecisionIntegrationTest is BaseAccrual6IntegrationTest {
    function test_frequentSettlementMatchesIndependentHourOracle() public {
        // Allow for quantized six-decimal share-price snapshots; yield APY stays at 10%.
        vm.prank(address(deployment.timelock()));
        AccountingModule(address(accountingModule)).setTargetApy(1e18);
        uint256 initial = accountingToken.balanceOf(address(strategy));
        uint256 start = block.timestamp;
        for (uint256 i = 1; i <= 60; ++i) {
            vm.warp(start + i * 60);
            (uint256 expected, uint256 fraction) = accrual.previewAccrual();
            assertGt(expected, 0);
            assertEq(accrual.accrue(), expected);
            assertEq(accrual.remainder(), fraction);
        }
        // Independently evaluated at 60-digit decimal precision:
        // (1.1 ** (3600 / 31557600) - 1) * 1e18 = 10872769558087.691...
        uint256 oracle = initial * 1e12 * 10_872_769_558_087 / 1e18;
        uint256 actual = (accountingToken.balanceOf(address(strategy)) - initial) * 1e12 + accrual.remainder();
        assertApproxEqAbs(actual, oracle, initial * 1e12 / 1e12);
    }

    function test_oneSecondReportsCanHitAprCapFromSharePriceQuantization() public {
        uint256 start = block.timestamp;
        bool rejected;
        for (uint256 i = 1; i <= 3600; ++i) {
            vm.warp(start + i);
            uint256 checkpoint = accrual.lastAccrual();
            uint256 fraction = accrual.remainder();
            try accrual.accrue() returns (uint256 rewards) {
                assertGt(rewards, 0);
            } catch (bytes memory reason) {
                assertEq(bytes4(reason), IAccountingModule.AccountingLimitsExceeded.selector);
                assertEq(accrual.lastAccrual(), checkpoint);
                assertEq(accrual.remainder(), fraction);
                rejected = true;
                break;
            }
        }
        assertTrue(rejected, "Expected rounded share-price snapshot to reject a one-second report");
    }

    function test_fractionSurvivesBalanceAndRateChanges() public {
        vm.warp(block.timestamp + 1);
        accrual.accrue();
        uint256 fraction = accrual.remainder();
        assertGt(fraction, 0);
        deal(strategy.asset(), ALICE, 10e6);
        vm.prank(ALICE);
        strategy.deposit(10e6, ALICE);
        assertEq(accrual.remainder(), fraction);
        vm.prank(ALICE);
        strategy.withdraw(10e6, ALICE, ALICE);
        assertEq(accrual.remainder(), fraction);
        vm.prank(accountingModule.safe());
        accountingModule.processLosses(1e6);
        vm.prank(deployment.actors().ADMIN());
        accrual.setAPY(0.05e18, false);
        assertEq(accrual.remainder(), fraction);
        vm.warp(block.timestamp + 1 days);
        (uint256 rewards, uint256 nextFraction) = accrual.previewAccrual();
        assertEq(accrual.accrue(), rewards);
        assertEq(accrual.remainder(), nextFraction);
    }

    function test_fractionUnchangedAcrossBlocksWithSameTimestamp() public {
        vm.warp(block.timestamp + 1);
        accrual.accrue();
        uint256 fraction = accrual.remainder();
        assertGt(fraction, 0);
        uint256 snapshots = accountingModule.snapshotsLength();
        for (uint256 i; i < 5; ++i) {
            vm.roll(block.number + 1);
            assertEq(accrual.accrue(), 0);
            assertEq(accrual.remainder(), fraction);
            assertEq(accountingModule.snapshotsLength(), snapshots);
        }
    }
}
