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
import { IContracts, L1Contracts } from "@yieldnest-vault-script/Contracts.sol";
import { FlexStrategyDeployer } from "script/FlexStrategyDeployer.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { IActors } from "@yieldnest-vault-script/Actors.sol";

contract DeployYnFlexEthStrategyWithoutRewardsSweeper is DeployFlexStrategy {
    function _setup() public virtual override {
        if (block.chainid == 1) {
            minDelay = 1 days;
            MainnetActors _actors = new MainnetActors();
            actors = IActors(_actors);
            contracts = IContracts(new L1Contracts());
        } else {
            revert UnsupportedChain();
        }

        address[] memory allocators = new address[](1);
        allocators[0] = contracts.YNETHX();
        setDeploymentParameters(
            BaseScript.DeploymentParameters({
                name: "YieldNest Flex Strategy",
                symbol_: "ynFlexEthNoSweeper",
                accountTokenName: "YieldNest Flex Strategy IOU",
                accountTokenSymbol: "ynFlex_iou",
                decimals: 18,
                paused: true,
                targetApy: 0.1 ether, // max rewards per year: 10% of tvl
                lowerBound: 0.1 ether, // max loss: 10% of tvl
                minRewardableAssets: 1e18,
                accountingProcessor: 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64,
                baseAsset: IVault(contracts.YNETHX()).asset(),
                allocators: allocators,
                safe: 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64,
                alwaysComputeTotalAssets: true,
                useRewardsSweeper: false
            })
        );
    }
}

contract FlexStrategyDeployment is BaseIntegrationTest {
    function test_verify_setup() public {
        VerifyFlexStrategy verify = new VerifyFlexStrategy();
        verify.setEnv(BaseScript.Env.TEST);

        IContracts contracts = IContracts(new L1Contracts());
        address[] memory allocators = new address[](1);
        allocators[0] = contracts.YNETHX();

        verify.setVerificationParameters(
            VerifyFlexStrategy.VerificationParameters({
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
                allocators: allocators,
                alwaysComputeTotalAssets: true
            })
        );
        verify.run();
    }

    function test_verify_setup_without_rewards_sweeper() public {
        DeployYnFlexEthStrategyWithoutRewardsSweeper deployment = new DeployYnFlexEthStrategyWithoutRewardsSweeper();
        deployment.setEnv(BaseScript.Env.TEST);
        deployment.run();

        FlexStrategy strategy = FlexStrategy(deployment.strategy());
        IAccountingModule _accountingModule = strategy.accountingModule();

        // Give safe permissions
        vm.startPrank(accountingModule.safe());
        IERC20(strategy.asset()).approve(address(_accountingModule), type(uint256).max);
        vm.stopPrank();

        {
            VerifyFlexStrategy verify = new VerifyFlexStrategy();
            verify.setEnv(BaseScript.Env.TEST);

            IContracts contracts = IContracts(new L1Contracts());
            address[] memory allocators = new address[](1);
            allocators[0] = contracts.YNETHX();

            verify.setVerificationParameters(
                VerifyFlexStrategy.VerificationParameters({
                    name: "YieldNest Flex Strategy",
                    symbol_: "ynFlexEthNoSweeper",
                    accountTokenName: "YieldNest Flex Strategy IOU",
                    accountTokenSymbol: "ynFlex_iou",
                    decimals: 18,
                    paused: true,
                    targetApy: 0.1 ether, // max rewards per year: 10% of tvl
                    lowerBound: 0.1 ether, // max loss: 10% of tvl
                    minRewardableAssets: 1e18,
                    accountingProcessor: 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64,
                    baseAsset: IVault(contracts.YNETHX()).asset(),
                    allocators: allocators,
                    alwaysComputeTotalAssets: true
                })
            );
            verify.run();
        }
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

    function test_deployer_deploy_reverts_if_deployed() public {
        FlexStrategyDeployer deployer = FlexStrategyDeployer(deployment.deployer());
        vm.expectRevert(FlexStrategyDeployer.DeploymentDone.selector);
        deployer.deploy();
    }
}
