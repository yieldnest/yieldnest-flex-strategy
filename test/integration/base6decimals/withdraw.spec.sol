// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseScript } from "script/BaseScript.sol";
import { UpgradeUtils } from "script/UpgradeUtils.sol";
import { MainnetActors } from "@yieldnest-vault-script/Actors.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";
import { RolesVerification } from "script/verification/RolesVerification.sol";
import { BaseIntegrationTest_6Decimals } from "./BaseIntegrationTest_6Decimals.sol";

contract WithdrawIntegrationBaseTest_6Decimals is BaseIntegrationTest_6Decimals {
    address alice = address(0x123);

    function setUp() public override {
        super.setUp();
        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();
    }

    function testFuzz_withdraw_success_6decimals(uint128 amount) public {
        vm.assume(amount > 0 && amount < 1_000_000_000e6);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, amount);

        // Initial balances
        uint256 aliceInitialBalance = baseAsset.balanceOf(alice);
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Alice deposits first
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), amount);
        uint256 shares = strategy.deposit(amount, alice);
        vm.stopPrank();

        // Now withdraw half
        uint256 withdrawAmount = amount / 2;
        uint256 sharesToBurn = strategy.previewWithdraw(withdrawAmount);

        vm.startPrank(alice);
        strategy.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Assert Alice's balance increased by withdraw amount
        assertEq(
            baseAsset.balanceOf(alice),
            aliceInitialBalance - amount + withdrawAmount,
            "Alice's balance should increase by withdraw amount"
        );

        // Assert Alice's shares decreased
        assertEq(
            strategy.balanceOf(alice),
            aliceInitialShares + shares - sharesToBurn,
            "Alice's shares should decrease by burned shares"
        );

        // Assert safe's balance decreased
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + amount - withdrawAmount,
            "Safe's balance should decrease by withdraw amount"
        );

        // Assert strategy's accounting tokens decreased
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + amount - withdrawAmount,
            "Strategy's accounting tokens should decrease by withdraw amount"
        );

        // Assert total supply decreased
        assertEq(
            strategy.totalSupply(),
            totalSupplyBefore + shares - sharesToBurn,
            "Total supply should decrease by burned shares"
        );

        // Assert total assets decreased
        assertEq(
            strategy.totalAssets(),
            totalAssetsBefore + amount - withdrawAmount,
            "Total assets should decrease by withdraw amount"
        );

        // Assert strategy's base asset balance stayed the same
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );
    }
}
