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

contract RewardsIntegrationTest is BaseIntegrationTest {
    address alice = address(0x123);

    function setUp() public override {
        super.setUp();
        // Grant ALLOCATOR_ROLE to alice so she can deposit
        vm.startPrank(deployment.actors().ADMIN());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();
    }

    function testFuzz_processLosses(uint256 amount) public {
        // Setup: Alice deposits some tokens first
        uint256 depositAmount = 1000e18;
        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice tokens to deposit
        deal(address(baseAsset), alice, depositAmount);

        vm.startPrank(alice);
        baseAsset.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Calculate maximum allowed loss based on lower bound
        uint256 maxAllowedLoss = depositAmount * accountingModule.lowerBound() / accountingModule.DIVISOR();

        // Bound the fuzzed amount to be within valid range
        amount = bound(amount, 1, maxAllowedLoss);

        // Record initial state
        uint256 initialTotalSupply = accountingModule.accountingToken().totalSupply();
        uint256 initialBalance = accountingModule.accountingToken().balanceOf(address(strategy));

        // Process losses as safe
        vm.startPrank(accountingModule.safe());
        accountingModule.processLosses(amount);
        vm.stopPrank();

        // Verify final state
        uint256 finalTotalSupply = accountingModule.accountingToken().totalSupply();
        uint256 finalBalance = accountingModule.accountingToken().balanceOf(address(strategy));

        // Check that tokens were burned correctly
        assertEq(finalTotalSupply, initialTotalSupply - amount, "Total supply should decrease by loss amount");
        assertEq(finalBalance, initialBalance - amount, "Strategy balance should decrease by loss amount");
    }

    function testProcessLossesExceedsLowerBound() public {
        // Setup: Alice deposits some tokens first
        uint256 depositAmount = 1000e18;
        IERC20 baseAsset = IERC20(strategy.asset());

        // Give Alice tokens to deposit
        deal(address(baseAsset), alice, depositAmount);

        vm.startPrank(alice);
        baseAsset.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Calculate loss amount that exceeds lower bound
        uint256 maxAllowedLoss = depositAmount * accountingModule.lowerBound() / accountingModule.DIVISOR();
        uint256 excessiveLoss = maxAllowedLoss + 1;

        // Attempt to process excessive losses as safe
        vm.startPrank(accountingModule.safe());
        vm.expectRevert(
            abi.encodeWithSelector(IAccountingModule.LossLimitsExceeded.selector, excessiveLoss, maxAllowedLoss)
        );
        accountingModule.processLosses(excessiveLoss);
        vm.stopPrank();
    }
}
