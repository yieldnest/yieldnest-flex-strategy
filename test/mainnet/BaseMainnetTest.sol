// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { AccountingToken, IAccountingToken } from "src/AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseScript } from "script/BaseScript.sol";
import { UpgradeUtils } from "script/UpgradeUtils.sol";
import { MainnetActors } from "@yieldnest-vault-script/Actors.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";
import { RolesVerification } from "script/verification/RolesVerification.sol";
import { DeployYnFlexUSDCynRWAxSPV1 } from "script/instances/DeployYnFlexUSDCynRWAxSPV1.s.sol";

contract BaseMainnetTest is Test {
    DeployYnFlexUSDCynRWAxSPV1 public spv1Deployment;
    address DEPLOYER = address(0xd34db33f);

    FlexStrategy[] public strategies;
    DeployFlexStrategy[] public deployments;

    function setUp() public virtual {
        {
            spv1Deployment = new DeployYnFlexUSDCynRWAxSPV1();
            spv1Deployment.setEnv(BaseScript.Env.TEST);

            deployments.push(spv1Deployment);

            spv1Deployment.run();

            FlexStrategy strategy = FlexStrategy(spv1Deployment.strategy());
            strategies.push(strategy);
            IAccountingModule accountingModule = strategy.accountingModule();

            // Give safe permissions
            vm.startPrank(accountingModule.safe());
            IERC20(strategy.asset()).approve(address(accountingModule), type(uint256).max);
            vm.stopPrank();
        }
    }
}
