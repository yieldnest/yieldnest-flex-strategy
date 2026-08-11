pragma solidity ^0.8.28;

import { TransparentUpgradeableProxy, FlexStrategy, AccountingToken, IProvider, IActors } from "script/BaseScript.sol";
import { FixedRateProvider } from "src/FixedRateProvider.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { BaseRoles } from "script/roles/BaseRoles.sol";
import { FlexStrategyRules } from "script/rules/FlexStrategyRules.sol";
import { SafeRules, IVault } from "@yieldnest-vault-script/rules/SafeRules.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { AccountingModuleHook } from "src/hooks/AccountingModuleHook.sol";
import { HooksDeployer } from "script/HooksDeployer.sol";

contract FlexStrategyDeployer {
    error InvalidDeploymentParams(string);
    error DeploymentDone();

    struct DeploymentParams {
        string name;
        string symbol;
        string accountTokenName;
        string accountTokenSymbol;
        uint8 decimals;
        address[] allocators;
        address baseAsset;
        uint256 targetApy;
        uint256 lowerBound;
        address safe;
        address accountingProcessor;
        uint256 minRewardableAssets;
        bool alwaysComputeTotalAssets;
        bool paused;
        IActors actors;
        uint256 minDelay;
        Implementations implementations;
    }

    address public deployer;
    string public name;
    string public symbol_;
    string public accountTokenName;
    string public accountTokenSymbol;
    uint8 public decimals;
    address[] public allocators;
    address public baseAsset;
    uint256 public targetApy;
    uint256 public lowerBound;
    address public safe;
    address public accountingProcessor;
    uint256 public minRewardableAssets;
    bool public alwaysComputeTotalAssets;
    bool public paused;
    AccountingToken public accountingToken;
    AccountingModule public accountingModule;
    FlexStrategy public strategy;
    IProvider public rateProvider;
    TimelockController public timelock;
    RewardsSweeper public rewardsSweeper;
    IActors public actors;
    uint256 public minDelay;

    bool public useRewardsSweeper;

    Implementations public implementations;

    bool public deploymentDone;

    constructor(DeploymentParams memory params) {
        // the contract is the deployer
        deployer = address(this);
        actors = params.actors;
        minDelay = params.minDelay;

        // Set deployment parameters
        name = params.name;
        symbol_ = params.symbol;
        accountTokenName = params.accountTokenName;
        accountTokenSymbol = params.accountTokenSymbol;
        decimals = params.decimals;
        allocators = params.allocators;
        baseAsset = params.baseAsset;
        targetApy = params.targetApy;
        lowerBound = params.lowerBound;
        safe = params.safe;
        accountingProcessor = params.accountingProcessor;
        minRewardableAssets = params.minRewardableAssets;
        alwaysComputeTotalAssets = params.alwaysComputeTotalAssets;
        paused = params.paused;
        implementations = params.implementations;
    }

    struct Implementations {
        FlexStrategy flexStrategyImplementation;
        AccountingToken accountingTokenImplementation;
        AccountingModule accountingModuleImplementation;
        TimelockController timelockController;
        RewardsSweeper rewardsSweeperImplementation;
        HooksDeployer hooksDeployer;
    }

    function deploy() public virtual {
        if (deploymentDone) {
            revert DeploymentDone();
        }
        deploymentDone = true;

        address admin = deployer;

        timelock = implementations.timelockController;

        if (address(implementations.rewardsSweeperImplementation) != address(0)) {
            useRewardsSweeper = true;
        }

        FlexStrategy strategyImplementation = implementations.flexStrategyImplementation;
        AccountingToken accountingTokenImplementation = implementations.accountingTokenImplementation;

        accountingToken = AccountingToken(
            payable(address(
                    new TransparentUpgradeableProxy(
                        address(accountingTokenImplementation),
                        address(timelock),
                        abi.encodeWithSelector(
                            AccountingToken.initialize.selector, admin, accountTokenName, accountTokenSymbol
                        )
                    )
                ))
        );

        deployRateProvider();

        strategy = FlexStrategy(
            payable(address(
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
                ))
        );

        AccountingModule accountingModuleImplementation =
            AccountingModule(address(implementations.accountingModuleImplementation));
        accountingModule = AccountingModule(
            payable(address(
                    new TransparentUpgradeableProxy(
                        address(accountingModuleImplementation),
                        address(timelock),
                        abi.encodeWithSelector(
                            AccountingModule.initialize.selector,
                            address(strategy),
                            admin,
                            safe,
                            address(accountingToken),
                            targetApy,
                            lowerBound,
                            minRewardableAssets,
                            1 hours
                        )
                    )
                ))
        );

        RewardsSweeper rewardsSweeperImplementation = implementations.rewardsSweeperImplementation;

        if (useRewardsSweeper) {
            rewardsSweeper = RewardsSweeper(
                payable(address(
                        new TransparentUpgradeableProxy(
                            address(rewardsSweeperImplementation),
                            address(timelock),
                            abi.encodeWithSelector(RewardsSweeper.initialize.selector, admin, address(accountingModule))
                        )
                    ))
            );
        }

        configureStrategy();
    }

    function configureStrategy() internal virtual {
        BaseRoles.configureDefaultRolesStrategy(strategy, accountingModule, accountingToken, address(timelock), actors);
        BaseRoles.configureTemporaryRolesStrategy(strategy, accountingModule, accountingToken, deployer);

        // set has allocator
        strategy.setHasAllocator(true);
        // grant allocator roles
        for (uint256 i = 0; i < allocators.length; i++) {
            strategy.grantRole(strategy.ALLOCATOR_ROLE(), allocators[i]);
        }
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), IActors(address(actors)).BOOTSTRAPPER());

        // set accounting module for token
        accountingToken.setAccountingModule(address(accountingModule));

        // set accounting module for strategy
        strategy.setAccountingModule(address(accountingModule));

        // set accounting processor role
        accountingModule.grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), accountingProcessor);
        accountingModule.grantRole(accountingModule.LOSS_PROCESSOR_ROLE(), safe);

        {
            AccountingModuleHook accountingModuleHook = implementations.hooksDeployer
                .deployAccountingModuleHook(address(strategy), address(accountingModule), address(strategy));
            // set hooks
            IVault(address(strategy)).setHooks(address(accountingModuleHook));

            // Grant PROCESSOR_ROLE to the accounting module hook
            strategy.grantRole(strategy.PROCESSOR_ROLE(), address(accountingModuleHook));

            // Create an array to hold the rules for the strategy
            SafeRules.RuleParams[] memory strategyRules = new SafeRules.RuleParams[](2);

            // Set deposit rule for accounting module on strategy
            strategyRules[0] = FlexStrategyRules.getDepositRule(address(accountingModule));

            // Set withdrawal rule for accounting module on strategy
            strategyRules[1] = FlexStrategyRules.getWithdrawRule(address(accountingModule), address(strategy));

            // Set processor rules for strategy using SafeRules
            SafeRules.setProcessorRules(IVault(address(strategy)), strategyRules, true);
        }

        {
            // Safe Rules

            // Create an array to hold the rules
            SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);

            // Set deposit rule for accounting module
            rules[0] = FlexStrategyRules.getDepositRule(address(accountingModule));

            // Set withdrawal rule for accounting module
            rules[1] = FlexStrategyRules.getWithdrawRule(address(accountingModule), address(strategy));

            // Set processor rules using SafeRules
            SafeRules.setProcessorRules(IVault(address(strategy)), rules, true);
        }

        if (useRewardsSweeper) {
            // RewardsSweeper
            rewardsSweeper.grantRole(rewardsSweeper.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
            rewardsSweeper.grantRole(rewardsSweeper.ACCOUNTING_MODULE_MANAGER_ROLE(), actors.ADMIN());
            rewardsSweeper.grantRole(rewardsSweeper.REWARDS_SWEEPER_ROLE(), actors.PROCESSOR());

            accountingModule.grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), address(rewardsSweeper));

            rewardsSweeper.renounceRole(rewardsSweeper.DEFAULT_ADMIN_ROLE(), deployer);
            rewardsSweeper.renounceRole(rewardsSweeper.ACCOUNTING_MODULE_MANAGER_ROLE(), deployer);
        }

        strategy.unpause();

        BaseRoles.renounceTemporaryRolesStrategy(strategy, accountingModule, accountingToken, deployer);
    }

    function deployRateProvider() internal {
        rateProvider = IProvider(address(new FixedRateProvider(address(accountingToken))));
    }
}
