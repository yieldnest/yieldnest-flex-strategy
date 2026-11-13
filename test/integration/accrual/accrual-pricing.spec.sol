// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;
import { BaseAccrualIntegrationTest } from "./BaseAccrualIntegrationTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Calls are deliberately ordered in one transaction. Production entry points still need this wiring.
contract AccrualPricingIntegrationTest is BaseAccrualIntegrationTest {
    function test_accrueBeforeDepositPricesNewSharesAfterYield() public {
        vm.warp(block.timestamp + 30 days);
        uint256 staleShares = strategy.previewDeposit(100e18);
        uint256 sharesBefore = strategy.balanceOf(ALICE);
        accrual.accrue();
        uint256 expected = strategy.previewDeposit(100e18);
        assertLt(expected, staleShares);
        deal(strategy.asset(), ALICE, 100e18);
        vm.startPrank(ALICE);
        IERC20(strategy.asset()).approve(address(strategy), 100e18);
        assertEq(strategy.deposit(100e18, ALICE), expected);
        vm.stopPrank();
        assertEq(strategy.balanceOf(ALICE), sharesBefore + expected);
    }

    function test_accrueBeforeMintChargesUpdatedAssetPrice() public {
        vm.warp(block.timestamp + 30 days);
        uint256 staleAssets = strategy.previewMint(100e18);
        accrual.accrue();
        uint256 expected = strategy.previewMint(100e18);
        assertGt(expected, staleAssets);
        deal(strategy.asset(), ALICE, expected);
        vm.startPrank(ALICE);
        IERC20(strategy.asset()).approve(address(strategy), expected);
        assertEq(strategy.mint(100e18, ALICE), expected);
        vm.stopPrank();
    }

    function test_accrueBeforeWithdrawBurnsFewerShares() public {
        vm.warp(block.timestamp + 30 days);
        uint256 staleShares = strategy.previewWithdraw(100e18);
        uint256 sharesBefore = strategy.balanceOf(ALICE);
        accrual.accrue();
        uint256 expected = strategy.previewWithdraw(100e18);
        assertLt(expected, staleShares);
        vm.prank(ALICE);
        assertEq(strategy.withdraw(100e18, ALICE, ALICE), expected);
        assertEq(strategy.balanceOf(ALICE), sharesBefore - expected);
        assertEq(IERC20(strategy.asset()).balanceOf(ALICE), 100e18);
    }

    function test_accrueBeforeRedeemPaysEarnedYield() public {
        vm.warp(block.timestamp + 30 days);
        uint256 shares = strategy.balanceOf(ALICE) / 2;
        uint256 staleAssets = strategy.previewRedeem(shares);
        accrual.accrue();
        uint256 expected = strategy.previewRedeem(shares);
        assertGt(expected, staleAssets);
        vm.prank(ALICE);
        assertEq(strategy.redeem(shares, ALICE, ALICE), expected);
        assertEq(IERC20(strategy.asset()).balanceOf(ALICE), expected);
    }
}
