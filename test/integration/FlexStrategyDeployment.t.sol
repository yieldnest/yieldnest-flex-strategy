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
import { IContracts, L1Contracts } from "@yieldnest-vault-script/Contracts.sol";

contract FlexStrategyDeployment is BaseIntegrationTest {
    function test_verify_setup() public {
        VerifyFlexStrategy verify = new VerifyFlexStrategy();
        verify.setEnv(BaseScript.Env.TEST);

        IContracts contracts = IContracts(new L1Contracts());

        verify.setDeploymentParameters(
            BaseScript.DeploymentParameters({
                name: "YieldNest Flex Strategy",
                symbol_: "ynFlexEth",
                accountTokenName: "YieldNest Flex Strategy IOU",
                accountTokenSymbol: "ynFlex_iou",
                decimals: 18,
                paused: true,
                targetApy: 0.1 ether, // max rewards per year: 10% of tvl
                lowerBound: 0.1 ether, // max loss: 10% of tvl
                minRewardableAssets: 1e18,
                accountingProcessor: 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64,
                baseAsset: IVault(contracts.YNETHX()).asset(),
                allocator: contracts.YNETHX(),
                safe: 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64,
                alwaysComputeTotalAssets: true
            })
        );
        verify.run();
    }

    function test_upgrade_success() public {
        FlexStrategy newImpl = new FlexStrategy();
        address securityCouncil = MainnetActors(address(deployment.actors())).YnSecurityCouncil();
        UpgradeUtils.timelockUpgrade(
            deployment.timelock(), securityCouncil, address(deployment.strategy()), address(newImpl)
        );

        assertEq(address(ProxyUtils.getImplementation(address(deployment.strategy()))), address(newImpl));
    }

    function test_addNewAdmin_success() public {
        address newAdmin = address(0x1234567890123456789012345678901234567890);

        vm.startPrank(deployment.actors().ADMIN());
        deployment.strategy().grantRole(deployment.strategy().DEFAULT_ADMIN_ROLE(), newAdmin);
        RolesVerification.verifyRole(
            deployment.strategy(),
            newAdmin,
            deployment.strategy().DEFAULT_ADMIN_ROLE(),
            true,
            "newAdmin has DEFAULT_ADMIN_ROLE"
        );
    }
}
