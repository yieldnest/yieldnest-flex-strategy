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

    function test_initial_deposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);

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

        // Assert Alice's balance decreased by deposit amount
        assertEq(
            baseAsset.balanceOf(alice),
            aliceInitialBalance - amount,
            "Alice's balance should decrease by deposit amount"
        );

        // Assert Alice received shares
        assertEq(strategy.balanceOf(alice), aliceInitialShares + shares, "Alice should receive shares for deposit");

        // Assert safe received the base assets
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + amount,
            "Safe should receive the deposited assets"
        );

        // Assert strategy received accounting tokens
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + amount,
            "Strategy should receive accounting tokens equal to deposit amount"
        );

        // Assert total supply increased
        assertEq(strategy.totalSupply(), totalSupplyBefore + shares, "Total supply should increase by shares minted");

        // Assert total assets increased
        assertEq(strategy.totalAssets(), totalAssetsBefore + amount, "Total assets should increase by deposit amount");

        // Assert strategy's base asset balance stayed the same (assets go to safe, not strategy)
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );

        // Assert shares are correctly calculated (1:1 ratio for first deposit or based on current ratio)
        uint256 expectedShares = totalSupplyBefore == 0 ? amount : amount * totalSupplyBefore / totalAssetsBefore;
        assertEq(shares, expectedShares, "Shares should be calculated correctly");
    }

    function test_initial_mint(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to mint
        deal(address(baseAsset), alice, amount);

        // Setup initial balances
        uint256 aliceInitialBalance = baseAsset.balanceOf(alice);
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Alice approves and mints
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), amount);
        uint256 shares = strategy.mint(amount, alice);
        vm.stopPrank();

        // Assert Alice's balance decreased by mint amount
        assertEq(
            baseAsset.balanceOf(alice), aliceInitialBalance - amount, "Alice's balance should decrease by mint amount"
        );

        // Assert Alice received shares
        assertEq(strategy.balanceOf(alice), aliceInitialShares + shares, "Alice should receive shares for mint");

        // Assert safe received the base assets
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + amount,
            "Safe should receive the minted assets"
        );

        // Assert strategy received accounting tokens
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + amount,
            "Strategy should receive accounting tokens equal to mint amount"
        );

        // Assert total supply increased
        assertEq(strategy.totalSupply(), totalSupplyBefore + shares, "Total supply should increase by shares minted");

        // Assert total assets increased
        assertEq(strategy.totalAssets(), totalAssetsBefore + amount, "Total assets should increase by mint amount");

        // Assert strategy's base asset balance stayed the same (assets go to safe, not strategy)
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );

        // Assert shares are correctly calculated (1:1 ratio for first mint or based on current ratio)
        uint256 expectedShares = totalSupplyBefore == 0 ? amount : amount * totalSupplyBefore / totalAssetsBefore;
        assertEq(shares, expectedShares, "Shares should be calculated correctly");
    }

    struct DepositTestData {
        uint256 deposit1;
        uint256 deposit2;
        uint256 deposit3;
        uint32 timeBetweenDeposits;
        IERC20 baseAsset;
        address bob;
        address charlie;
        uint256 aliceInitialBalance;
        uint256 bobInitialBalance;
        uint256 charlieInitialBalance;
        uint256 safeInitialBalance;
        uint256 strategyInitialAccountingTokens;
        uint256 strategyInitialBalance;
        uint256 totalSupplyBefore;
        uint256 totalAssetsBefore;
        uint256 aliceShares;
        uint256 bobShares;
        uint256 charlieShares;
    }

    function testFuzz_threeSubsequentDeposits_success(
        uint256 deposit1,
        uint256 deposit2,
        uint256 deposit3,
        uint32 timeBetweenDeposits
    )
        public
    {
        deposit1 = bound(deposit1, 1 ether, 1_000_000 ether);
        deposit2 = bound(deposit2, 1 ether, 1_000_000 ether);
        deposit3 = bound(deposit3, 1 ether, 1_000_000 ether);
        timeBetweenDeposits = uint32(bound(timeBetweenDeposits, 1, 30 days));

        DepositTestData memory data;
        data.deposit1 = deposit1;
        data.deposit2 = deposit2;
        data.deposit3 = deposit3;
        data.timeBetweenDeposits = timeBetweenDeposits;
        data.baseAsset = IERC20(strategy.asset());
        data.bob = address(0x456);
        data.charlie = address(0x789);

        // Grant ALLOCATOR_ROLE to bob and charlie
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), data.bob);
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), data.charlie);
        vm.stopPrank();

        // Give tokens to all users
        deal(address(data.baseAsset), alice, data.deposit1);
        deal(address(data.baseAsset), data.bob, data.deposit2);
        deal(address(data.baseAsset), data.charlie, data.deposit3);

        // Initial balances
        data.aliceInitialBalance = data.baseAsset.balanceOf(alice);
        data.bobInitialBalance = data.baseAsset.balanceOf(data.bob);
        data.charlieInitialBalance = data.baseAsset.balanceOf(data.charlie);
        data.safeInitialBalance = data.baseAsset.balanceOf(accountingModule.safe());
        data.strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        data.strategyInitialBalance = data.baseAsset.balanceOf(address(strategy));
        data.totalSupplyBefore = strategy.totalSupply();
        data.totalAssetsBefore = strategy.totalAssets();

        // First deposit - Alice
        vm.startPrank(alice);
        data.baseAsset.approve(address(strategy), data.deposit1);
        data.aliceShares = strategy.deposit(data.deposit1, alice);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + data.timeBetweenDeposits);

        // Second deposit - Bob
        vm.startPrank(data.bob);
        data.baseAsset.approve(address(strategy), data.deposit2);
        data.bobShares = strategy.deposit(data.deposit2, data.bob);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + data.timeBetweenDeposits);

        // Third deposit - Charlie
        vm.startPrank(data.charlie);
        data.baseAsset.approve(address(strategy), data.deposit3);
        data.charlieShares = strategy.deposit(data.deposit3, data.charlie);
        vm.stopPrank();

        // Assert all users' balances decreased by their deposit amounts
        assertEq(
            data.baseAsset.balanceOf(alice),
            data.aliceInitialBalance - data.deposit1,
            "Alice's balance should decrease by deposit1"
        );
        assertEq(
            data.baseAsset.balanceOf(data.bob),
            data.bobInitialBalance - data.deposit2,
            "Bob's balance should decrease by deposit2"
        );
        assertEq(
            data.baseAsset.balanceOf(data.charlie),
            data.charlieInitialBalance - data.deposit3,
            "Charlie's balance should decrease by deposit3"
        );

        // Assert all users received shares
        assertEq(strategy.balanceOf(alice), data.aliceShares, "Alice should have correct shares");
        assertEq(strategy.balanceOf(data.bob), data.bobShares, "Bob should have correct shares");
        assertEq(strategy.balanceOf(data.charlie), data.charlieShares, "Charlie should have correct shares");

        // Assert safe received all the base assets
        assertEq(
            data.baseAsset.balanceOf(accountingModule.safe()),
            data.safeInitialBalance + data.deposit1 + data.deposit2 + data.deposit3,
            "Safe should receive all deposited assets"
        );

        // Assert strategy received accounting tokens for all deposits
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            data.strategyInitialAccountingTokens + data.deposit1 + data.deposit2 + data.deposit3,
            "Strategy should receive accounting tokens for all deposits"
        );

        // Assert total supply increased by all shares
        assertEq(
            strategy.totalSupply(),
            data.totalSupplyBefore + data.aliceShares + data.bobShares + data.charlieShares,
            "Total supply should increase by all shares"
        );

        // Assert total assets increased by all deposits
        assertEq(
            strategy.totalAssets(),
            data.totalAssetsBefore + data.deposit1 + data.deposit2 + data.deposit3,
            "Total assets should increase by all deposits"
        );

        // Assert strategy's base asset balance stayed the same (assets go to safe, not strategy)
        assertEq(
            data.baseAsset.balanceOf(address(strategy)),
            data.strategyInitialBalance,
            "Strategy's base asset balance should remain unchanged"
        );

        // Assert share calculations are correct for subsequent deposits
        uint256 expectedAliceShares = data.totalSupplyBefore == 0
            ? data.deposit1
            : data.deposit1 * data.totalSupplyBefore / data.totalAssetsBefore;
        uint256 expectedBobShares =
            data.deposit2 * (data.totalSupplyBefore + data.aliceShares) / (data.totalAssetsBefore + data.deposit1);
        uint256 expectedCharlieShares = data.deposit3 * (data.totalSupplyBefore + data.aliceShares + data.bobShares)
            / (data.totalAssetsBefore + data.deposit1 + data.deposit2);

        assertEq(data.aliceShares, expectedAliceShares, "Alice's shares should be calculated correctly");
        assertEq(data.bobShares, expectedBobShares, "Bob's shares should be calculated correctly");
        assertEq(data.charlieShares, expectedCharlieShares, "Charlie's shares should be calculated correctly");
    }
}
