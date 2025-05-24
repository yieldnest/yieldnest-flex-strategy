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

abstract contract BaseScript is Script {
    using stdJson for string;

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
    address public strategyImplementationProxyAdmin;

    AccountingModule public accountingModule;
    AccountingModule public accountingModuleImplementation;
    address public accountingModuleProxyAdmin;
    address public accountingModuleImplementationProxyAdmin;

    AccountingToken public accountingToken;
    AccountingToken public accountingTokenImplementation;
    address public accountingTokenProxyAdmin;
    address public accountingTokenImplementationProxyAdmin;

    error UnsupportedChain();
    error InvalidSetup();

    // needs to be overridden by child script
    function symbol() public view virtual returns (string memory);

    function _setup() public virtual {
        deployer = msg.sender;

        if (block.chainid == 1) {
            minDelay = 1 days;
            MainnetActors _actors = new MainnetActors();
            actors = IActors(_actors);
            contracts = IContracts(new L1Contracts());
        }
    }

    function _verifySetup() public view virtual {
        if (block.chainid != 1) {
            revert UnsupportedChain();
        }
        if (address(actors) == address(0) || address(contracts) == address(0) || address(timelock) == address(0)) {
            revert InvalidSetup();
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

    function _loadDeployment() internal virtual {
        if (!vm.isFile(_deploymentFilePath())) {
            return;
        }
        string memory jsonInput = vm.readFile(_deploymentFilePath());

        deployer = address(vm.parseJsonAddress(jsonInput, ".deployer"));
        timelock = TimelockController(payable(address(vm.parseJsonAddress(jsonInput, ".timelock"))));
        rateProvider = IProvider(payable(address(vm.parseJsonAddress(jsonInput, ".rateProvider"))));

        strategy =
            FlexStrategy(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxy")))));
        strategyImplementation = FlexStrategy(
            payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-implementation"))))
        );
        strategyProxyAdmin = address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxyAdmin")));
    }

    function _deploymentFilePath() internal view virtual returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", symbol(), "-", Strings.toString(block.chainid), ".json");
    }

    function _saveDeployment() internal virtual {
        vm.serializeString(symbol(), "symbol", symbol());
        vm.serializeAddress(symbol(), "deployer", deployer);
        vm.serializeAddress(symbol(), "admin", actors.ADMIN());
        vm.serializeAddress(symbol(), "timelock", address(timelock));
        vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));
        vm.serializeAddress(symbol(), "safe", address(safe));

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

        vm.serializeAddress(symbol(), string.concat(symbol(), "-accountingToken-proxy"), address(accountingToken));
        vm.serializeAddress(
            symbol(),
            string.concat(symbol(), "-accountingToken-proxyAdmin"),
            ProxyUtils.getProxyAdmin(address(accountingToken))
        );
        string memory jsonOutput = vm.serializeAddress(
            symbol(), string.concat(symbol(), "-accountingToken-implementation"), address(accountingTokenImplementation)
        );

        vm.writeJson(jsonOutput, _deploymentFilePath());
    }
}
