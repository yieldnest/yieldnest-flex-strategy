// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;
import { BaseAccrualIntegrationTest } from "./BaseAccrualIntegrationTest.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AccrualRecoveryIntegrationTest is BaseAccrualIntegrationTest {
    function test_skipAccrueDiscardsUnsettledYieldAndRestoresDepositFlow() public {
        vm.warp(block.timestamp + 30 days);
        vm.startPrank(deployment.actors().ADMIN());
        AccountingModule(address(accountingModule)).grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), ALICE);
        vm.stopPrank();
        vm.prank(ALICE);
        accountingModule.processRewards(1e18);
        vm.warp(block.timestamp + 1);
        (uint256 forgone,) = accrual.previewAccrual();
        assertGt(forgone, 0);
        vm.expectPartialRevert(IAccountingModule.AccountingLimitsExceeded.selector);
        accrual.accrue();
        uint256 balance = accountingToken.balanceOf(address(strategy));
        vm.prank(deployment.actors().ADMIN());
        accrual.setAPY(0, true);
        assertEq(accrual.accrue(), 0);
        assertEq(accrual.lastAccrual(), block.timestamp);
        assertEq(accountingToken.balanceOf(address(strategy)), balance);
        deal(strategy.asset(), ALICE, 10e18);
        vm.startPrank(ALICE);
        IERC20(strategy.asset()).approve(address(strategy), 10e18);
        assertGt(strategy.deposit(10e18, ALICE), 0);
        vm.stopPrank();
        vm.prank(ALICE);
        strategy.withdraw(5e18, ALICE, ALICE);
        assertEq(accountingToken.balanceOf(address(strategy)), balance + 5e18);
    }
}
