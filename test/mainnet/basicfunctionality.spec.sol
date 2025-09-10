// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import { Test } from "lib/forge-std/src/Test.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { BaseMainnetTest } from "test/mainnet/BaseMainnetTest.sol";
import { UpgradeUtils } from "script/UpgradeUtils.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";

contract VaultMainnetUpgradeTest is BaseMainnetTest {
    address public constant DEPOSITOR = address(0x1234567890123456789012345678901234567890);

    function setUp() public override {
        super.setUp();
    }

    function test_deposit_usdc_ynrwax_spv1() public {
        uint256 i = 0;

        // Get USDC token and strategy
        IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC on mainnet
        IVault strategy = IVault(address(strategies[i])); // Using index i for strategy selection

        DeployFlexStrategy deployment = DeployFlexStrategy(address(deployments[i]));

        // Grant ALLOCATOR_ROLE to depositor
        vm.startPrank(deployment.actors().ADMIN());
        FlexStrategy(payable(address(strategy))).grantRole(
            FlexStrategy(payable(address(strategy))).ALLOCATOR_ROLE(), DEPOSITOR
        );
        vm.stopPrank();
        // 1 million USDC (6 decimals)
        uint256 depositAmount = 1_000_000 * 1e6;

        // Deal USDC to depositor
        deal(address(usdc), DEPOSITOR, depositAmount);

        // Switch to depositor for the deposit
        vm.startPrank(DEPOSITOR);

        // Approve strategy to spend USDC
        usdc.approve(address(strategy), depositAmount);

        // Get balances before deposit
        uint256 usdcBalanceBefore = usdc.balanceOf(DEPOSITOR);
        uint256 sharesBefore = strategy.balanceOf(DEPOSITOR);
        uint256 totalAssetsBefore = strategy.totalAssets();
        // Get safe balance before deposit
        uint256 safeUsdcBalanceBefore = usdc.balanceOf(deployment.safe());

        // Perform deposit
        uint256 shares = strategy.deposit(depositAmount, DEPOSITOR);

        // Verify deposit was successful
        assertEq(
            usdc.balanceOf(DEPOSITOR),
            usdcBalanceBefore - depositAmount,
            "USDC balance should decrease by deposit amount"
        );
        assertEq(strategy.balanceOf(DEPOSITOR), sharesBefore + shares, "Shares balance should increase");
        assertGt(shares, 0, "Should receive shares for deposit");
        assertGe(
            strategy.totalAssets(),
            totalAssetsBefore + depositAmount,
            "Total assets should increase by at least deposit amount"
        );

        // Assert balance of USDC in safe is now increased
        uint256 safeUsdcBalanceAfter = usdc.balanceOf(deployment.safe());
        assertGe(
            safeUsdcBalanceAfter,
            safeUsdcBalanceBefore + depositAmount,
            "Safe USDC balance should increase by at least deposit amount"
        );

        vm.stopPrank();

        // Test moving money from SAFE to a random receiver
        address randomReceiver = address(0x123456789);
        uint256 safeBalanceBeforeTransfer = usdc.balanceOf(deployment.safe());
        uint256 totalAssetsBeforeTransfer = strategy.totalAssets();

        // Move money from SAFE to random receiver
        vm.startPrank(deployment.safe());
        usdc.transfer(randomReceiver, safeBalanceBeforeTransfer);
        vm.stopPrank();

        // Verify the transfer was successful
        assertEq(usdc.balanceOf(deployment.safe()), 0, "SAFE should have zero USDC balance after transfer");
        assertEq(
            usdc.balanceOf(randomReceiver),
            safeBalanceBeforeTransfer,
            "Random receiver should have received all USDC from SAFE"
        );

        strategy.processAccounting();

        // Assert totalAssets is still the same
        uint256 totalAssetsAfterTransfer = strategy.totalAssets();
        assertEq(
            totalAssetsAfterTransfer,
            totalAssetsBeforeTransfer,
            "Total assets should remain the same after transfer from SAFE"
        );
    }

    function test_deposit_and_withdraw_roundtrip(uint8 i) public {
        i = uint8(bound(i, 0, strategies.length - 1));

        FlexStrategy strategy = strategies[i];
        DeployFlexStrategy deployment = deployments[i];
        IERC20 usdc = IERC20(strategy.asset());

        // Grant DEPOSITOR the ALLOCATOR_ROLE
        vm.startPrank(deployment.actors().ADMIN());
        FlexStrategy(payable(address(strategy))).grantRole(
            FlexStrategy(payable(address(strategy))).ALLOCATOR_ROLE(), DEPOSITOR
        );
        vm.stopPrank();

        // 1 million USDC (6 decimals)
        uint256 depositAmount = 1_000_000 * 1e6;

        // Deal USDC to depositor
        deal(address(usdc), DEPOSITOR, depositAmount);

        // Switch to depositor for the deposit
        vm.startPrank(DEPOSITOR);

        // Approve strategy to spend USDC
        usdc.approve(address(strategy), depositAmount);

        // Get totalAssets before deposit
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Perform deposit
        uint256 shares = strategy.deposit(depositAmount, DEPOSITOR);

        // Perform withdrawal of the same amount
        strategy.withdraw(depositAmount, DEPOSITOR, DEPOSITOR);

        vm.stopPrank();

        strategy.processAccounting();

        // Get totalAssets after withdrawal
        uint256 totalAssetsAfter = strategy.totalAssets();

        // Assert that totalAssets before and after are the same
        assertEq(
            totalAssetsAfter,
            totalAssetsBefore,
            "Total assets should be the same before and after deposit/withdrawal roundtrip"
        );

        // Assert that the depositor's share balance is now zero
        uint256 depositorSharesAfter = strategy.balanceOf(DEPOSITOR);
        assertEq(depositorSharesAfter, 0, "Depositor should have zero shares after withdrawal");

        // Assert that the depositor's USDC balance is back to the original amount
        uint256 depositorUsdcAfter = usdc.balanceOf(DEPOSITOR);
        assertEq(depositorUsdcAfter, depositAmount, "Depositor should have received back exactly the same USDC amount");

        // Assert that total supply decreased by exactly the shares that were burned
        uint256 totalSupplyAfter = strategy.totalSupply();
        assertEq(totalSupplyAfter, 0, "Total supply should be zero after complete withdrawal");
    }
}
