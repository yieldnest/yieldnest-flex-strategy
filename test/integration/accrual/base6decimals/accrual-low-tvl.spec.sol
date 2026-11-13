// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;
import { BaseAccrual6IntegrationTest } from "./BaseAccrual6IntegrationTest.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";

contract AccrualLowTvlIntegrationTest is BaseAccrual6IntegrationTest {
    function test_withdrawBelowMinimumBlocksNextPositiveAccrual() public {
        vm.warp(block.timestamp + 1);
        accrual.accrue();
        uint256 amount = accountingToken.balanceOf(address(strategy)) - 500e6;
        vm.prank(ALICE);
        strategy.withdraw(amount, ALICE, ALICE);
        assertLt(accountingToken.totalSupply(), 1000e6);
        uint256 checkpoint = accrual.lastAccrual();
        uint256 fraction = accrual.remainder();
        vm.warp(block.timestamp + 1 days);
        (uint256 rewards,) = accrual.previewAccrual();
        assertGt(rewards, 0);
        vm.expectRevert(IAccountingModule.TvlTooLow.selector);
        accrual.accrue();
        assertEq(accrual.lastAccrual(), checkpoint);
        assertEq(accrual.remainder(), fraction);
    }

    function test_fullUserExitRetainsCollectiveFractionForLaterDeposits() public {
        vm.warp(block.timestamp + 1);
        accrual.accrue();
        uint256 fraction = accrual.remainder();
        assertGt(fraction, 0);
        deal(strategy.asset(), accountingModule.safe(), strategy.totalAssets() + 1e6);
        uint256 shares = strategy.balanceOf(ALICE);
        vm.prank(ALICE);
        strategy.redeem(shares, ALICE, ALICE);
        assertEq(strategy.balanceOf(ALICE), 0);
        assertEq(accrual.remainder(), fraction);
        assertEq(strategy.totalSupply(), 0);
        // Virtual-share rounding can leave one asset unit after all real shares are redeemed.
        assertLe(accountingToken.balanceOf(address(strategy)), 1);
        vm.warp(block.timestamp + 1 days);
        assertEq(accrual.accrue(), 0);
        assertGt(accrual.remainder(), fraction);
        fraction = accrual.remainder();
        assertEq(accrual.lastAccrual(), block.timestamp);
        deal(strategy.asset(), ALICE, 2000e6);
        vm.prank(ALICE);
        strategy.deposit(2000e6, ALICE);
        assertEq(accrual.remainder(), fraction);
        vm.warp(block.timestamp + 1);
        (uint256 rewards,) = accrual.previewAccrual();
        assertGt(rewards, 0);
        // Reopening after a full exit can change PPS through virtual-share rounding. The
        // accounting snapshot predates that change, so the next positive report is rejected.
        uint256 checkpoint = accrual.lastAccrual();
        vm.expectPartialRevert(IAccountingModule.AccountingLimitsExceeded.selector);
        accrual.accrue();
        assertEq(accrual.remainder(), fraction);
        assertEq(accrual.lastAccrual(), checkpoint);
    }
}
