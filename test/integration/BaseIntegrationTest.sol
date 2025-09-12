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
import { IContracts, L1Contracts } from "@yieldnest-vault-script/Contracts.sol";

contract BaseIntegrationTest is Test {
    DeployFlexStrategy public deployment;
    address DEPLOYER = address(0xd34db33f);

    FlexStrategy public strategy;
    IAccountingModule public accountingModule;
    IAccountingToken public accountingToken;

    function setUp() public virtual {
        deployment = new DeployFlexStrategy();
        deployment.setEnv(BaseScript.Env.TEST);

        IContracts contracts = IContracts(new L1Contracts());

        deployment.setDeploymentParameters(
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
        deployment.run();

        strategy = FlexStrategy(deployment.strategy());
        accountingModule = strategy.accountingModule();
        accountingToken = accountingModule.accountingToken();

        // Give safe permissions
        vm.startPrank(accountingModule.safe());
        IERC20(strategy.asset()).approve(address(accountingModule), type(uint256).max);
        vm.stopPrank();
    }
}
