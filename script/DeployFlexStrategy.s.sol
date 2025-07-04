// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {
    BaseScript,
    TransparentUpgradeableProxy,
    FlexStrategy,
    AccountingModule,
    AccountingToken,
    IActors,
    IProvider
} from "script/BaseScript.sol";
import { BaseRoles } from "script/roles/BaseRoles.sol";
import { FixedRateProvider } from "src/FixedRateProvider.sol";
import { console } from "forge-std/console.sol";
import { FlexStrategyRules } from "script/rules/FlexStrategyRules.sol";
import { SafeRules, IVault } from "@yieldnest-vault-script/rules/SafeRules.sol";
import { FlexStrategyDeployer } from "script/FlexStrategyDeployer.sol";
import { ProxyUtils } from "lib/yieldnest-vault/script/ProxyUtils.sol";

// forge script DeployFlexStrategy --rpc-url <MAINNET_RPC_URL>  --slow --broadcast --account
// <CAST_WALLET_ACCOUNT>  --sender <SENDER_ADDRESS>  --verify --etherscan-api-key <ETHERSCAN_API_KEY>  -vvv
contract DeployFlexStrategy is BaseScript {
    error InvalidRules();
    error InvalidRateProvider();
    error InvalidDeploymentParams(string);

    function symbol() public view override returns (string memory) {
        return symbol_;
    }

    function deployRateProvider() internal {
        rateProvider = IProvider(address(new FixedRateProvider(address(accountingToken))));
    }

    function _verifySetup() public view override {
        super._verifySetup();
    }

    function run() public virtual {
        deployer = msg.sender;

        vm.startBroadcast(deployer);

        _setup();
        assignDeploymentParameters();
        _verifyDeploymentParams();

        FlexStrategyDeployer strategyDeployer = new FlexStrategyDeployer(
            FlexStrategyDeployer.DeploymentParams({
                name: name,
                symbol: symbol_,
                accountTokenName: accountTokenName,
                accountTokenSymbol: accountTokenSymbol,
                decimals: decimals,
                allocator: allocator,
                baseAsset: baseAsset,
                targetApy: targetApy,
                lowerBound: lowerBound,
                safe: safe,
                accountingProcessor: accountingProcessor,
                minRewardableAssets: minRewardableAssets,
                alwaysComputeTotalAssets: alwaysComputeTotalAssets,
                paused: paused,
                actors: actors,
                minDelay: minDelay
        }));

        strategyDeployer.deploy();


        strategy = strategyDeployer.strategy();
        strategyImplementation = FlexStrategy(payable(ProxyUtils.getImplementation(address(strategy))));
        accountingModule = strategyDeployer.accountingModule();
        accountingModuleImplementation = AccountingModule(payable(ProxyUtils.getImplementation(address(accountingModule))));
        accountingToken = strategyDeployer.accountingToken();
        accountingTokenImplementation = AccountingToken(payable(ProxyUtils.getImplementation(address(accountingToken))));
        rateProvider = strategyDeployer.rateProvider();
        timelock = strategyDeployer.timelock();

        _verifySetup();

        _saveDeployment(deploymentEnv);

        vm.stopBroadcast();
    }

    function assignDeploymentParameters() internal virtual {
        if (decimals > 0) {
            console.log("Already configured. skipping default settings.");
            return;
        }

        name = "YieldNest Flex Strategy";
        symbol_ = "ynFlexEth";
        accountTokenName = "YieldNest Flex Strategy IOU";
        accountTokenSymbol = "ynFlex_iou";
        decimals = 18;
        paused = true;
        allocator = contracts.YNETHX();
        baseAsset = IVault(allocator).asset();

        targetApy = 0.1 ether; // max rewards per year: 10% of tvl
        lowerBound = 0.1 ether; // max loss: 10% of tvl
        safe = 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64;
        accountingProcessor = safe;
        minRewardableAssets = 1e18;
        alwaysComputeTotalAssets = true;
    }

    function _verifyDeploymentParams() internal view virtual {
        if (bytes(name).length == 0) {
            revert InvalidDeploymentParams("strategy name not set");
        }

        if (bytes(symbol_).length == 0) {
            revert InvalidDeploymentParams("strategy symbol not set");
        }

        if (decimals == 0) {
            revert InvalidDeploymentParams("strategy decimals not set");
        }

        if (allocator == address(0)) {
            revert InvalidDeploymentParams("allocator is not set");
        }

        if (baseAsset == address(0)) {
            revert InvalidDeploymentParams("baseAsset is not set");
        }

        if (targetApy == 0) {
            revert InvalidDeploymentParams("targetApy is not set");
        }

        if (lowerBound == 0) {
            revert InvalidDeploymentParams("lowerBound is not set");
        }

        if (safe == address(0)) {
            revert InvalidDeploymentParams("safe is not set");
        }
    }

}
