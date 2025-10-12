// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
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
    address BOB = address(0x456);

    function setUp() public override {
        super.setUp();
        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), BOB);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), deployment.actors().ADMIN());
        vm.stopPrank();
    }

    function test_convert_to_accounting_tokens(
        uint256 amount,
        uint256 donationAmount,
        bool alwaysComputeTotalAssets
    )
        public
    {
        amount = bound(amount, 1e18, 1_000_000 ether);
        donationAmount = bound(donationAmount, 1, amount * 2);

        // Set the alwaysComputeTotalAssets flag in the strategy
        vm.startPrank(deployment.actors().ADMIN());
        strategy.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);
        vm.stopPrank();

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, amount);

        // Alice approves and deposits
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), amount);
        vm.stopPrank();

        // Record initial balances
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

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

        {
            // Build calldata for the processor to convert all donationAmount to accountingToken
            address[] memory targets = new address[](1);
            targets[0] = address(accountingModule);

            bytes[] memory data = new bytes[](1);
            data[0] = abi.encodeWithSelector(accountingModule.deposit.selector, donationAmount);

            uint256[] memory values = new uint256[](1);
            values[0] = 0;

            // Call strategy.processor with the built calldata
            vm.startPrank(deployment.actors().PROCESSOR());
            strategy.processor(targets, values, data);
            vm.stopPrank();
        }

        // Assert accountingToken balance increased correctly
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens + donationAmount,
            "AccountingToken balance should increase by donation amount"
        );

        // Assert strategy's base asset balance is 0
        assertEq(
            baseAsset.balanceOf(address(strategy)), 0, "Strategy's base asset balance should be 0 after processing"
        );

        // Assert total supply remains unchanged after processing
        assertEq(strategy.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged after processing");

        // Assert total assets remain unchanged after processing
        assertEq(
            strategy.totalAssets(),
            totalAssetsBefore + donationAmount,
            "Total assets should remain unchanged after processing"
        );

        // Assert safe's balance remains unchanged after processing
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance + donationAmount,
            "Safe's balance should remain unchanged after processing"
        );

        // Assert Alice's shares remain unchanged after processing
        assertEq(
            strategy.balanceOf(alice), aliceInitialShares, "Alice's shares should remain unchanged after processing"
        );
        // Assert strategy's base asset balance is strategyInitialBalance minus donationAmount
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance,
            "Strategy's base asset balance should decrease by donation amount"
        );
    }

    function test_convert_accounting_tokens_to_base_asset(
        uint256 amount,
        uint256 conversionAmount,
        bool alwaysComputeTotalAssets
    )
        public
    {
        amount = bound(amount, 1e18, 1_000_000 ether);
        conversionAmount = bound(conversionAmount, 1, amount);

        // Set the alwaysComputeTotalAssets flag in the strategy
        vm.startPrank(deployment.actors().ADMIN());
        strategy.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);
        vm.stopPrank();

        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice some tokens to deposit
        deal(address(baseAsset), alice, amount);

        // Alice approves and deposits
        vm.startPrank(alice);
        baseAsset.approve(address(strategy), amount);
        strategy.deposit(amount, alice);
        vm.stopPrank();

        strategy.processAccounting();

        // Record initial balances
        uint256 strategyInitialBalance = baseAsset.balanceOf(address(strategy));
        uint256 safeInitialBalance = baseAsset.balanceOf(accountingModule.safe());
        uint256 aliceInitialShares = strategy.balanceOf(alice);
        uint256 strategyInitialAccountingTokens = accountingToken.balanceOf(address(strategy));
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 totalAssetsBefore = strategy.totalAssets();

        {
            // Build calldata for the processor to convert all conversionAmount to accountingToken
            address[] memory targets = new address[](1);
            targets[0] = address(accountingModule);

            bytes[] memory data = new bytes[](1);
            data[0] = abi.encodeWithSelector(accountingModule.withdraw.selector, conversionAmount, address(strategy));

            uint256[] memory values = new uint256[](1);
            values[0] = 0;

            // Call strategy.processor with the built calldata
            vm.startPrank(deployment.actors().PROCESSOR());
            strategy.processor(targets, values, data);
            vm.stopPrank();
        }

        // Assert Alice received shares
        assertEq(strategy.balanceOf(alice), aliceInitialShares, "Alice should be the same");

        // Assert safe's balance is unchanged as assets are converted back
        assertEq(
            baseAsset.balanceOf(accountingModule.safe()),
            safeInitialBalance - conversionAmount,
            "Safe's balance should remain unchanged after conversion back to assets"
        );

        // Assert strategy's accounting tokens decreased by conversionAmount
        assertEq(
            accountingToken.balanceOf(address(strategy)),
            strategyInitialAccountingTokens - conversionAmount,
            "Strategy's accounting tokens should decrease by conversionAmount"
        );

        // Assert total supply remains unchanged as shares are unaffected
        assertEq(strategy.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");

        // Assert total assets decreased by conversionAmount
        assertEq(strategy.totalAssets(), totalAssetsBefore, "Total assets stayed the same");

        // Assert strategy's base asset balance increased by conversionAmount
        assertEq(
            baseAsset.balanceOf(address(strategy)),
            strategyInitialBalance + conversionAmount,
            "Strategy's base asset balance should increase by conversionAmount"
        );
    }
}
