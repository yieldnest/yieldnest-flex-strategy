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

    function run() public {
        deployer = msg.sender;

        vm.startBroadcast(deployer);

        _setup();
        assignDeploymentParameters();
        _verifyDeploymentParams();

        _deployTimelockController();
        _verifySetup();

        deploy();
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

    function deploy() internal {
        address admin = msg.sender;
        strategyImplementation = new FlexStrategy();
        accountingTokenImplementation = new AccountingToken(address(baseAsset));

        accountingToken = AccountingToken(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(accountingTokenImplementation),
                        address(timelock),
                        abi.encodeWithSelector(
                            AccountingToken.initialize.selector, admin, accountTokenName, accountTokenSymbol
                        )
                    )
                )
            )
        );

        deployRateProvider();

        strategy = FlexStrategy(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(strategyImplementation),
                        address(timelock),
                        abi.encodeWithSelector(
                            FlexStrategy.initialize.selector,
                            admin,
                            name,
                            symbol_,
                            decimals,
                            baseAsset,
                            address(accountingToken),
                            paused,
                            address(rateProvider),
                            alwaysComputeTotalAssets
                        )
                    )
                )
            )
        );

        accountingModuleImplementation = new AccountingModule(address(strategy), baseAsset);
        accountingModule = AccountingModule(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(accountingModuleImplementation),
                        address(timelock),
                        abi.encodeWithSelector(
                            AccountingModule.initialize.selector,
                            admin,
                            safe,
                            address(accountingToken),
                            targetApy,
                            lowerBound,
                            minRewardableAssets
                        )
                    )
                )
            )
        );

        configureStrategy();
    }

    function configureStrategy() internal {
        BaseRoles.configureDefaultRolesStrategy(strategy, accountingModule, accountingToken, address(timelock), actors);
        BaseRoles.configureTemporaryRolesStrategy(strategy, accountingModule, accountingToken, deployer);

        // set has allocator
        strategy.setHasAllocator(true);
        // grant allocator roles
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), allocator);
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), IActors(address(actors)).BOOTSTRAPPER());

        // set accounting module for token
        accountingToken.setAccountingModule(address(accountingModule));

        // set accounting module for strategy
        strategy.setAccountingModule(address(accountingModule));

        // set accounting processor role
        accountingModule.grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), accountingProcessor);
        accountingModule.grantRole(accountingModule.LOSS_PROCESSOR_ROLE(), accountingProcessor);

        // Create an array to hold the rules
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);

        // Set deposit rule for accounting module
        rules[0] = FlexStrategyRules.getDepositRule(address(accountingModule));

        // Set withdrawal rule for accounting module
        rules[1] = FlexStrategyRules.getWithdrawRule(address(accountingModule), address(strategy));

        // Set processor rules using SafeRules
        SafeRules.setProcessorRules(IVault(address(strategy)), rules, true);

        strategy.unpause();

        BaseRoles.renounceTemporaryRolesStrategy(strategy, accountingModule, accountingToken, deployer);
    }
}
