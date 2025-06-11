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

contract BaseIntegrationTest is Test {
    DeployFlexStrategy public deployment;
    address DEPLOYER = address(0xd34db33f);

    FlexStrategy public strategy;
    IAccountingModule public accountingModule;
    IAccountingToken public accountingToken;

    function setUp() public {
        deployment = new DeployFlexStrategy();
        deployment.setEnv(BaseScript.Env.TEST);
        deployment.run();

        strategy = FlexStrategy(deployment.strategy());
        accountingModule = strategy.accountingModule();
        accountingToken = accountingModule.accountingToken();
    }
}
