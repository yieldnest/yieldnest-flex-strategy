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

contract AllocationIntegrationTest is BaseIntegrationTest {
    address alice = address(0x123);

    address allocationDestination = address(0x456);

    function setUp() public override {
        super.setUp();
        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();
    }

    function testFuzz_allocation(uint256 depositAmount, uint256 allocationAmount) public {
        depositAmount = bound(depositAmount, 1, 1_000_000 ether);
        allocationAmount = bound(allocationAmount, 1, depositAmount);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, depositAmount);

        // Record initial balances
        uint256 aliceInitialBalance = baseAsset.balanceOf(alice);
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 allocationDestinationInitialBalance = baseAsset.balanceOf(allocationDestination);
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Alice approves and deposits
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), depositAmount);
        uint256 shares = strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Impersonate SAFE and move assets to allocation destination
        vm.startPrank(accountingModule.safe());
        baseAsset.transfer(allocationDestination, allocationAmount);
        vm.stopPrank();

        // Assert Alice's balance decreased by deposit amount
        assertEq(
            baseAsset.balanceOf(alice),
            aliceInitialBalance - depositAmount,
            "Alice's balance should decrease by deposit amount"
        );

        // Assert Alice received shares
        assertEq(strategy.balanceOf(alice), aliceInitialShares + shares, "Alice should receive shares for deposit");

        // Assert safe initially received the base assets but then transferred some out
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + depositAmount - allocationAmount,
            "Safe should have transferred out the allocated assets"
        );

        // Assert allocation destination received the allocated funds
        assertEq(
            baseAsset.balanceOf(allocationDestination),
            allocationDestinationInitialBalance + allocationAmount,
            "Allocation destination should receive the allocated funds"
        );

        // Assert strategy received accounting tokens
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + depositAmount,
            "Strategy should receive accounting tokens equal to deposit amount"
        );

        // Assert total supply increased
        assertEq(strategy.totalSupply(), totalSupplyBefore + shares, "Total supply should increase by shares minted");

        // Assert total assets increased
        assertEq(
            strategy.totalAssets(), totalAssetsBefore + depositAmount, "Total assets should increase by deposit amount"
        );

        // Assert strategy's base asset balance stayed the same (assets go to safe, not strategy)
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );

        // Assert shares are correctly calculated (1:1 ratio for first deposit or based on current ratio)
        uint256 expectedShares =
            totalSupplyBefore == 0 ? depositAmount : depositAmount * totalSupplyBefore / totalAssetsBefore;
        assertEq(shares, expectedShares, "Shares should be calculated correctly");
    }
}
