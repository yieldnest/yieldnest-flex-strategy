// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseScript } from "script/BaseScript.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingTokenFactory } from "src/factory/AccountingTokenFactory.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { HooksDeployer } from "script/HooksDeployer.sol";

contract DeployFlexStrategyImplementations is BaseScript {
    bytes32 internal constant FLEX_STRATEGY = keccak256("yieldnest.yieldnest-flex-strategy.contracts.src.FlexStrategy");
    bytes32 internal constant ACCOUNTING_TOKEN_FACTORY =
        keccak256("yieldnest.yieldnest-flex-strategy.contracts.src.AccountingTokenFactory");
    bytes32 internal constant ACCOUNTING_MODULE =
        keccak256("yieldnest.yieldnest-flex-strategy.contracts.src.AccountingModule");
    bytes32 internal constant REWARDS_SWEEPER =
        keccak256("yieldnest.yieldnest-flex-strategy.contracts.src.utils.RewardsSweeper");
    bytes32 internal constant HOOKS_DEPLOYER =
        keccak256("yieldnest.yieldnest-flex-strategy.contracts.script.HooksDeployer");

    HooksDeployer public hooksDeployerImplementation;
    AccountingTokenFactory public accountingTokenFactoryImplementation;

    function symbol() public pure override returns (string memory) {
        return "flexStrategyImplementations";
    }

    function run() public {
        vm.startBroadcast();

        _setup();
        deployer = tx.origin;

        strategyImplementation = new FlexStrategy();
        accountingTokenFactoryImplementation = new AccountingTokenFactory();
        accountingModuleImplementation = new AccountingModule();
        rewardsSweeperImplementation = new RewardsSweeper();
        hooksDeployerImplementation = new HooksDeployer();

        _verifySetup();
        _saveDeployment();

        vm.stopBroadcast();
    }

    function _verifySetup() public view override {
        if (address(strategyImplementation).code.length == 0) revert InvalidSetup("flex strategy not deployed");
        if (address(accountingTokenFactoryImplementation).code.length == 0) {
            revert InvalidSetup("accounting token factory not deployed");
        }
        if (address(accountingModuleImplementation).code.length == 0) {
            revert InvalidSetup("accounting module not deployed");
        }
        if (address(rewardsSweeperImplementation).code.length == 0) {
            revert InvalidSetup("rewards sweeper not deployed");
        }
        if (address(hooksDeployerImplementation).code.length == 0) revert InvalidSetup("hooks deployer not deployed");
    }

    function deploymentFilePath() public view returns (string memory) {
        return _deploymentFilePath(deploymentEnv);
    }

    function _saveDeployment() internal virtual {
        vm.serializeString(symbol(), "symbol", symbol());
        vm.serializeAddress(symbol(), "deployer", deployer);

        vm.serializeBytes32(symbol(), "FLEX_STRATEGY", FLEX_STRATEGY);
        vm.serializeBytes32(symbol(), "ACCOUNTING_TOKEN_FACTORY", ACCOUNTING_TOKEN_FACTORY);
        vm.serializeBytes32(symbol(), "ACCOUNTING_MODULE", ACCOUNTING_MODULE);
        vm.serializeBytes32(symbol(), "REWARDS_SWEEPER", REWARDS_SWEEPER);
        vm.serializeBytes32(symbol(), "HOOKS_DEPLOYER", HOOKS_DEPLOYER);

        vm.serializeAddress(symbol(), vm.toString(FLEX_STRATEGY), address(strategyImplementation));
        vm.serializeAddress(
            symbol(), vm.toString(ACCOUNTING_TOKEN_FACTORY), address(accountingTokenFactoryImplementation)
        );
        vm.serializeAddress(symbol(), vm.toString(ACCOUNTING_MODULE), address(accountingModuleImplementation));
        vm.serializeAddress(symbol(), vm.toString(REWARDS_SWEEPER), address(rewardsSweeperImplementation));
        vm.serializeAddress(symbol(), vm.toString(HOOKS_DEPLOYER), address(hooksDeployerImplementation));

        vm.serializeAddress(symbol(), "flexStrategyImplementation", address(strategyImplementation));
        vm.serializeAddress(
            symbol(), "accountingTokenFactoryImplementation", address(accountingTokenFactoryImplementation)
        );
        vm.serializeAddress(symbol(), "accountingModuleImplementation", address(accountingModuleImplementation));
        vm.serializeAddress(symbol(), "rewardsSweeperImplementation", address(rewardsSweeperImplementation));
        string memory jsonOutput =
            vm.serializeAddress(symbol(), "hooksDeployerImplementation", address(hooksDeployerImplementation));

        vm.writeJson(jsonOutput, deploymentFilePath());
    }
}
