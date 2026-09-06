// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Script, stdJson } from "lib/forge-std/src/Script.sol";
import { IProvider } from "@yieldnest-vault/interface/IProvider.sol";
import { TimelockController, TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { Strings } from "openzeppelin-contracts/contracts/utils/Strings.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";
import { MainnetActors, IActors } from "@yieldnest-vault-script/Actors.sol";
import { IContracts, L1Contracts } from "@yieldnest-vault-script/Contracts.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { AccountingModuleHook } from "src/hooks/AccountingModuleHook.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { console } from "forge-std/console.sol";

abstract contract BaseScript is Script {
    using stdJson for string;

    enum Env {
        TEST,
        PROD
    }

    struct DeploymentParameters {
        string name;
        string symbol_;
        string accountTokenName;
        string accountTokenSymbol;
        uint8 decimals;
        bool paused;
        uint256 targetApy;
        uint256 lowerBound;
        uint256 minRewardableAssets;
        address accountingProcessor;
        address baseAsset;
        address[] allocators;
        address safe;
        bool alwaysComputeTotalAssets;
        bool useRewardsSweeper;
    }

    function setDeploymentParameters(DeploymentParameters memory params) public virtual {
        name = params.name;
        symbol_ = params.symbol_;
        accountTokenName = params.accountTokenName;
        accountTokenSymbol = params.accountTokenSymbol;
        decimals = params.decimals;
        paused = params.paused;
        targetApy = params.targetApy;
        lowerBound = params.lowerBound;
        minRewardableAssets = params.minRewardableAssets;
        accountingProcessor = params.accountingProcessor;
        baseAsset = params.baseAsset;
        allocators = params.allocators;
        safe = params.safe;
        alwaysComputeTotalAssets = params.alwaysComputeTotalAssets;
        useRewardsSweeper = params.useRewardsSweeper;
    }

    Env public deploymentEnv = Env.PROD;

    string public name;
    string public symbol_;
    string public accountTokenName;
    string public accountTokenSymbol;
    uint8 public decimals;
    bool public paused;
    uint256 public targetApy;
    uint256 public lowerBound;
    uint256 public minRewardableAssets;
    address public accountingProcessor;
    address public baseAsset;
    address[] public allocators;
    bool public alwaysComputeTotalAssets;

    uint256 public minDelay;
    IActors public actors;
    IContracts public contracts;

    address public deployer;
    TimelockController public timelock;
    IProvider public rateProvider;
    address public safe;

    FlexStrategy public strategy;
    FlexStrategy public strategyImplementation;
    address public strategyProxyAdmin;

    AccountingModule public accountingModule;
    AccountingModule public accountingModuleImplementation;
    address public accountingModuleProxyAdmin;

    AccountingToken public accountingToken;
    AccountingToken public accountingTokenImplementation;
    address public accountingTokenProxyAdmin;

    AccountingModuleHook public accountingModuleHook;

    bool public useRewardsSweeper;
    RewardsSweeper public rewardsSweeper;
    RewardsSweeper public rewardsSweeperImplementation;
    address public rewardsSweeperProxyAdmin;

    error UnsupportedChain();
    error InvalidSetup(string);

    // needs to be overridden by child script
    function symbol() public view virtual returns (string memory);

    function setEnv(Env env) public {
        deploymentEnv = env;
    }

    function _setup() public virtual {
        minDelay = 1 days;
        MainnetActors _actors = new MainnetActors();
        actors = IActors(_actors);
        contracts = IContracts(new L1Contracts());
    }

    function _verifySetup() public view virtual {
        if (address(actors) == address(0)) {
            revert InvalidSetup("actors not set");
        }
        if (address(contracts) == address(0)) {
            revert InvalidSetup("contracts not set");
        }
        if (address(timelock) == address(0)) {
            revert InvalidSetup("timelock not set");
        }
    }

    function _deployTimelockController() internal virtual {
        address[] memory proposers = new address[](1);
        proposers[0] = actors.PROPOSER_1();

        address[] memory executors = new address[](1);
        executors[0] = actors.EXECUTOR_1();

        address admin = actors.ADMIN();

        timelock = new TimelockController(minDelay, proposers, executors, admin);
    }

    function _loadDeployment(Env env) internal virtual {
        if (!vm.isFile(_deploymentFilePath(env))) {
            console.log("No deployment file found");
            return;
        }
        string memory jsonInput = vm.readFile(_deploymentFilePath(env));
        symbol_ = vm.parseJsonString(jsonInput, ".symbol");
        deployer = address(vm.parseJsonAddress(jsonInput, ".deployer"));
        timelock = TimelockController(payable(address(vm.parseJsonAddress(jsonInput, ".timelock"))));
        rateProvider = IProvider(payable(address(vm.parseJsonAddress(jsonInput, ".rateProvider"))));
        safe = vm.parseJsonAddress(jsonInput, ".safe");

        strategy =
            FlexStrategy(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxy")))));
        strategyImplementation = FlexStrategy(
            payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-implementation"))))
        );
        strategyProxyAdmin = address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxyAdmin")));

        accountingModule = AccountingModule(
            payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-accountingModule-proxy"))))
        );
        accountingModuleImplementation = AccountingModule(
            payable(address(
                    vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-accountingModule-implementation"))
                ))
        );
        accountingModuleProxyAdmin =
            address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-accountingModule-proxyAdmin")));

        accountingToken = AccountingToken(
            payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-accountingToken-proxy"))))
        );
        accountingTokenImplementation = AccountingToken(
            payable(address(
                    vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-accountingToken-implementation"))
                ))
        );
        accountingTokenProxyAdmin =
            address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-accountingToken-proxyAdmin")));

        accountingModuleHook =
            AccountingModuleHook(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-accountingModuleHook")));

        useRewardsSweeper = vm.parseJsonBool(jsonInput, string.concat(".useRewardsSweeper"));

        if (useRewardsSweeper) {
            rewardsSweeper = RewardsSweeper(
                payable(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-rewardsSweeper-proxy")))
            );
            rewardsSweeperImplementation = RewardsSweeper(
                payable(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-rewardsSweeper-implementation")))
            );
            rewardsSweeperProxyAdmin =
                address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-rewardsSweeper-proxyAdmin")));
        }
    }

    function _deploymentFilePath(Env env) internal view virtual returns (string memory) {
        if (env == Env.PROD) {
            return
                string.concat(
                    vm.projectRoot(), "/deployments/", symbol(), "-", Strings.toString(block.chainid), ".json"
                );
        }

        return string.concat(
            vm.projectRoot(), "/deployments/", "test-", symbol(), "-", Strings.toString(block.chainid), ".json"
        );
    }

    function _saveDeployment(Env env) internal virtual {
        vm.serializeString(symbol(), "symbol", symbol());
        vm.serializeAddress(symbol(), "deployer", deployer);
        vm.serializeAddress(symbol(), "admin", actors.ADMIN());
        vm.serializeAddress(symbol(), "timelock", address(timelock));
        vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));
        vm.serializeAddress(symbol(), "safe", address(safe));
        vm.serializeAddress(symbol(), "baseAsset", address(baseAsset));
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(strategy));
        vm.serializeAddress(
            symbol(), string.concat(symbol(), "-proxyAdmin"), ProxyUtils.getProxyAdmin(address(strategy))
        );
        vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(strategyImplementation));

        vm.serializeAddress(symbol(), string.concat(symbol(), "-accountingModule-proxy"), address(accountingModule));
        vm.serializeAddress(
            symbol(),
            string.concat(symbol(), "-accountingModule-proxyAdmin"),
            ProxyUtils.getProxyAdmin(address(accountingModule))
        );
        vm.serializeAddress(
            symbol(),
            string.concat(symbol(), "-accountingModule-implementation"),
            address(accountingModuleImplementation)
        );

        vm.serializeBool(symbol(), "useRewardsSweeper", useRewardsSweeper);

        if (useRewardsSweeper) {
            vm.serializeAddress(symbol(), string.concat(symbol(), "-rewardsSweeper-proxy"), address(rewardsSweeper));
            vm.serializeAddress(
                symbol(),
                string.concat(symbol(), "-rewardsSweeper-proxyAdmin"),
                ProxyUtils.getProxyAdmin(address(rewardsSweeper))
            );
            vm.serializeAddress(
                symbol(),
                string.concat(symbol(), "-rewardsSweeper-implementation"),
                address(rewardsSweeperImplementation)
            );
        }

        vm.serializeAddress(symbol(), string.concat(symbol(), "-accountingToken-proxy"), address(accountingToken));
        vm.serializeAddress(
            symbol(),
            string.concat(symbol(), "-accountingToken-proxyAdmin"),
            ProxyUtils.getProxyAdmin(address(accountingToken))
        );
        string memory jsonOutput = vm.serializeAddress(
            symbol(), string.concat(symbol(), "-accountingToken-implementation"), address(accountingTokenImplementation)
        );
        jsonOutput = vm.serializeAddress(
            symbol(), string.concat(symbol(), "-accountingModuleHook"), address(accountingModuleHook)
        );

        vm.writeJson(jsonOutput, _deploymentFilePath(env));
    }
}
