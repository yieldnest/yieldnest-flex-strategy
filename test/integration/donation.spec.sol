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
import { BaseIntegrationTest } from "./BaseIntegrationTest.sol";

contract DepositIntegrationTest is BaseIntegrationTest {
    address alice = address(0x123);

    function setUp() public override {
        super.setUp();
        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();
    }

    function test_donation(uint256 amount, uint256 donationAmount) public {
        amount = bound(amount, 1, 1_000_000 ether);
        donationAmount = bound(donationAmount, 1, amount * 2);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, amount);

        // Record initial balances
        uint256 aliceInitialBalance = baseAsset.balanceOf(alice);
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Alice approves and deposits
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), amount);
        uint256 shares = strategy.deposit(amount, alice);
        vm.stopPrank();

        {
            address bob = address(0x456);

            // Send baseAsset to Bob
            deal(address(baseAsset), bob, donationAmount);

            // Bob transfers the donation amount to the strategy
            vm.startPrank(bob);
            baseAsset.approve(address(strategy), donationAmount);
            baseAsset.transfer(address(strategy), donationAmount);
            vm.stopPrank();
        }

        strategy.processAccounting();

        // Assert Alice's balance decreased by deposit amount
        assertEq(
            baseAsset.balanceOf(alice),
            aliceInitialBalance - amount,
            "Alice's balance should decrease by deposit amount"
        );

        // Assert Alice received shares
        assertEq(strategy.balanceOf(alice), aliceInitialShares + shares, "Alice should receive shares for deposit");

        // Assert safe received the base assets plus donation
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + amount,
            "Safe should receive the deposited assets without donation"
        );

        // Assert strategy received accounting tokens for deposit only
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + amount,
            "Strategy should receive accounting tokens equal to deposit amount"
        );

        // Assert total supply increased by shares minted
        assertEq(strategy.totalSupply(), totalSupplyBefore + shares, "Total supply should increase by shares minted");

        // Assert total assets increased by deposit and donation
        assertEq(
            strategy.totalAssets(),
            totalAssetsBefore + amount + donationAmount,
            "Total assets should increase by deposit and donation amount"
        );

        // Assert strategy's base asset balance increased by donation amount
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance + donationAmount,
            "Strategy's base asset balance should increase by donation amount"
        );

        // Assert shares are correctly calculated (1:1 ratio for first deposit or based on current ratio)
        uint256 expectedShares = totalSupplyBefore == 0 ? amount : amount * totalSupplyBefore / totalAssetsBefore;
        assertEq(shares, expectedShares, "Shares should be calculated correctly");
    }
}
