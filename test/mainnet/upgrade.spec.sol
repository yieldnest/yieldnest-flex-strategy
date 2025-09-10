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
}
