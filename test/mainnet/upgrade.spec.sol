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
    function setUp() public override {
        super.setUp();
    }

    function upgradeStrategy(
        IVault vault,
        address timelock,
        address admin
    )
        internal
        returns (FlexStrategy implementation)
    {
        {
            implementation = new FlexStrategy();
            UpgradeUtils.timelockUpgrade(
                TimelockController(payable(timelock)), admin, address(vault), address(implementation)
            );
        }
    }

    function test_Vault_Upgrade_Implementation_Set_Correctly(uint8 i) public {
        i = uint8(bound(i, 0, strategies.length - 1));

        IVault vault = IVault(address(strategies[i]));
        FlexStrategy implementation =
            upgradeStrategy(vault, address(deployments[i].timelock()), deployments[i].actors().ADMIN());
        // Verify the vault implementation was upgraded correctly
        address currentVaultImpl = ProxyUtils.getImplementation(address(vault));
        assertEq(currentVaultImpl, address(implementation), "Vault implementation not set correctly");
    }

    function test_Vault_Upgrade_totalAssets_unchanged(uint8 i, bool processAccountingBeforeCheck) public {
        i = uint8(bound(i, 0, strategies.length - 1));

        IVault vault = IVault(address(strategies[i]));

        if (processAccountingBeforeCheck) {
            vault.processAccounting();
        }

        // Get totalAssets before upgrade
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Perform the upgrade
        upgradeStrategy(vault, address(deployments[i].timelock()), deployments[i].actors().ADMIN());

        if (processAccountingBeforeCheck) {
            vault.processAccounting();
        }

        // Get totalAssets after upgrade
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // Assert that totalAssets after upgrade is greater than or equal to totalAssets before upgrade
        assertGe(
            totalAssetsAfter,
            totalAssetsBefore,
            "Total assets after upgrade should be greater than or equal to total assets before upgrade"
        );

        // Increase due to sfrxETH and potentially other assets that accumulate rewards in a streaming fashion
        assertApproxEqRel(
            totalAssetsAfter, totalAssetsBefore, 1e16, "Total assets should be equal within 1e16 (1%) relative error"
        );

        // Assert that totalSupply remains unchanged after the upgrade
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged after upgrade");
    }
}
