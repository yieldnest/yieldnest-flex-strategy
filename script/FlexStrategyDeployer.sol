pragma solidity ^0.8.28;

import { TransparentUpgradeableProxy, FlexStrategy, AccountingToken, IProvider, IActors } from "script/BaseScript.sol";
import { FixedRateProvider } from "src/FixedRateProvider.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { BaseRoles } from "script/roles/BaseRoles.sol";
import { FlexStrategyRules } from "script/rules/FlexStrategyRules.sol";
import { SafeRules, IVault } from "@yieldnest-vault-script/rules/SafeRules.sol";

contract FlexStrategyDeployer {
    error InvalidDeploymentParams(string);

    struct DeploymentParams {
        string name;
        string symbol;
        string accountTokenName;
        string accountTokenSymbol;
        uint8 decimals;
        address allocator;
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
    }

    address public deployer;
    string public name;
    string public symbol_;
    string public accountTokenName;
    string public accountTokenSymbol;
    uint8 public decimals;
    address public allocator;
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
    IActors public actors;
    uint256 public minDelay;

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
        allocator = params.allocator;
        baseAsset = params.baseAsset;
        targetApy = params.targetApy;
        lowerBound = params.lowerBound;
        safe = params.safe;
        accountingProcessor = params.accountingProcessor;
        minRewardableAssets = params.minRewardableAssets;
        alwaysComputeTotalAssets = params.alwaysComputeTotalAssets;
        paused = params.paused;
    }

    function deploy() public virtual {
        address admin = address(this);

        _deployTimelockController();

        FlexStrategy strategyImplementation = new FlexStrategy();
        AccountingToken accountingTokenImplementation = new AccountingToken(address(baseAsset));

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

        AccountingModule accountingModuleImplementation = new AccountingModule(address(strategy), baseAsset);
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

    function configureStrategy() internal virtual {
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

    function _deployTimelockController() internal {
        address[] memory proposers = new address[](1);
        proposers[0] = actors.PROPOSER_1();

        address[] memory executors = new address[](1);
        executors[0] = actors.EXECUTOR_1();

        address admin = actors.ADMIN();

        timelock = new TimelockController(minDelay, proposers, executors, admin);
    }

    function deployRateProvider() internal {
        rateProvider = IProvider(address(new FixedRateProvider(address(accountingToken))));
    }
}
