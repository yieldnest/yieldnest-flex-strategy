// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;
import { BaseAccrualIntegrationTest } from "./BaseAccrualIntegrationTest.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";

contract AccrualTimestampIntegrationTest is BaseAccrualIntegrationTest {
    function test_multipleBlocksSameTimestampDoNotReportTwice() public {
        vm.warp(block.timestamp + 1 days);
        assertGt(accrual.accrue(), 0);
        uint256 snapshots = accountingModule.snapshotsLength();
        uint256 balance = accountingToken.balanceOf(address(strategy));
        uint256 remainder = accrual.remainder();
        for (uint256 i; i < 5; ++i) {
            vm.roll(block.number + 1);
            assertEq(accrual.accrue(), 0);
            assertEq(accrual.remainder(), remainder);
            assertEq(accountingModule.snapshotsLength(), snapshots);
            assertEq(accountingToken.balanceOf(address(strategy)), balance);
        }
        vm.warp(block.timestamp + 1);
        assertGt(accrual.accrue(), 0);
    }

    function test_otherReporterInEarlierBlockWithSameTimestampBlocksAccrual() public {
        vm.warp(block.timestamp + 1 days);
        vm.prank(accountingModule.safe());
        accountingModule.processLosses(1e18);
        vm.roll(block.number + 1);
        vm.expectRevert(IAccountingModule.CurrentTimestampBeforePreviousTimestamp.selector);
        accrual.accrue();
    }
}
