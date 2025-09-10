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
import { IAccountingModule } from "src/AccountingModule.sol";

contract VaultMainnetUpgradeTest is BaseMainnetTest {
    function setUp() public override {
        super.setUp();
    }

    function test_usdc_ynrwax_spv1_views() public view {
        uint256 i = 0;

        IVault strategy = IVault(address(strategies[i]));
        DeployFlexStrategy deployment = DeployFlexStrategy(address(deployments[i]));

        // Get USDC token and strategy
        IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC on mainnet

        // Test asset and share conversions
        uint256 testAmount = 1000 * 1e6; // 1000 USDC
        {
            uint256 previewDeposit = strategy.previewDeposit(testAmount);
            uint256 previewMint = strategy.previewMint(previewDeposit);
            uint256 previewWithdraw = strategy.previewWithdraw(testAmount);
            uint256 previewRedeem = strategy.previewRedeem(previewDeposit);

            assertGt(previewDeposit, 0, "Preview deposit should return shares");
            assertApproxEqAbs(previewMint, testAmount, 1e6, "Preview mint should be approximately equal to test amount");
            assertGt(previewWithdraw, 0, "Preview withdraw should return shares needed");
            assertApproxEqAbs(
                previewRedeem, testAmount, 1e6, "Preview redeem should be approximately equal to test amount"
            );
        }

        {
            // Test max functions
            uint256 maxDeposit = strategy.maxDeposit(address(this));
            uint256 maxMint = strategy.maxMint(address(this));
            uint256 maxWithdraw = strategy.maxWithdraw(address(this));
            uint256 maxRedeem = strategy.maxRedeem(address(this));

            // These should be reasonable values (not 0 or type(uint256).max unless expected)
            assertGt(maxDeposit, 0, "Max deposit should be greater than 0");
            assertGt(maxMint, 0, "Max mint should be greater than 0");
            // maxWithdraw and maxRedeem might be 0 if user has no shares, which is expected
            assertEq(maxWithdraw, 0, "Max withdraw should be 0 for user with no shares");
            assertEq(maxRedeem, 0, "Max redeem should be 0 for user with no shares");

            // Test asset and share relationship
            assertEq(strategy.asset(), address(usdc), "Asset should be USDC");
        }

        {
            // Test convertToShares and convertToAssets consistency
            uint256 convertToShares = strategy.convertToShares(testAmount);
            uint256 convertToAssets = strategy.convertToAssets(convertToShares);

            assertGt(convertToShares, 0, "Convert to shares should return positive value");
            assertApproxEqAbs(
                convertToAssets, testAmount, 1, "Convert to assets should be approximately equal to original amount"
            );
        }

        // Get AccountingModule from deployment
        IAccountingModule accountingModule = deployment.accountingModule();

        {
            // Test AccountingModule view functions
            assertEq(accountingModule.strategy(), address(strategy), "AccountingModule strategy should match");
            assertEq(accountingModule.baseAsset(), address(usdc), "AccountingModule base asset should be USDC");
            assertEq(accountingModule.safe(), deployment.safe(), "AccountingModule safe should match deployment safe");

            // Test APY and timing parameters
            uint256 targetApy = accountingModule.targetApy();

            assertEq(targetApy, 0.15 ether, "Target APY should be 15%");
        }

        // Test snapshots if any exist
        uint256 snapshotsLength = accountingModule.snapshotsLength();
        if (snapshotsLength > 0) {
            IAccountingModule.StrategySnapshot memory latestSnapshot = accountingModule.snapshots(snapshotsLength - 1);
            assertGt(latestSnapshot.pricePerShare, 0, "Latest snapshot price per share should be greater than 0");
            assertGt(latestSnapshot.timestamp, 0, "Latest snapshot timestamp should be greater than 0");
        }

        // Test constants
        assertEq(accountingModule.YEAR(), 365.25 days, "YEAR constant should be 365.25 days");
        assertEq(accountingModule.DIVISOR(), 1e18, "DIVISOR constant should be 10000");
    }
}
