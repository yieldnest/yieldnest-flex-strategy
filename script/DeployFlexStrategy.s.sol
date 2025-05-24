// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { IProvider } from "@yieldnest-vault/interface/IProvider.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { BaseRules, SafeRules } from "@yieldnest-vault-script/rules/BaseRules.sol";
import {
    BaseScript,
    TransparentUpgradeableProxy,
    FlexStrategy,
    AccountingModule,
    AccountingToken,
    MainnetActors
} from "script/BaseScript.sol";
import { BaseRoles } from "script/roles/BaseRoles.sol";
import { FixedRateProvider } from "src/FixedRateProvider.sol";

// forge script DeployFlexStrategy --rpc-url <MAINNET_RPC_URL>  --slow --broadcast --account
// <CAST_WALLET_ACCOUNT>  --sender <SENDER_ADDRESS>  --verify --etherscan-api-key <ETHERSCAN_API_KEY>  -vvv
contract DeployFlexStrategy is BaseScript {
    error InvalidRules();
    error InvalidRateProvider();

    function symbol() public pure override returns (string memory) {
        return "ynFlexEth";
    }

    function deployRateProvider() internal {
        rateProvider = IProvider(address(new FixedRateProvider(IVault(contracts.YNETHX()).asset())));
    }

    function _verifySetup() public view override {
        super._verifySetup();

        if (address(rateProvider) == address(0)) {
            revert InvalidRateProvider();
        }
    }

    function run() public {
        vm.startBroadcast();

        _setup();
        deployRateProvider();
        _deployTimelockController();
        _verifySetup();

        deploy();

        _saveDeployment();

        vm.stopBroadcast();
    }

    function deploy() internal {
        string memory name = "YieldNest Flex Strategy";
        string memory symbol_ = symbol();
        string memory accountTokenName = "YieldNest Flex Strategy IOU";
        string memory accountTokenSymbol = "ynFlex_iou";
        uint8 decimals = 18;
        bool paused = true;
        uint16 targetApy = 1000; // max rewards per day: 10% of tvl / 365.25
        uint16 lowerBound = 1000; // max loss: 10% of tvl
        safe = 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64;
        address accountingProcessor = safe;

        address baseAsset = IVault(contracts.YNETHX()).asset();
        address admin = msg.sender;
        strategyImplementation = new FlexStrategy();
        accountingTokenImplementation = new AccountingToken(address(baseAsset));
        accountingModuleImplementation = new AccountingModule(address(strategy), baseAsset);

        strategy = FlexStrategy(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(strategyImplementation),
                        address(timelock),
                        abi.encodeWithSelector(
                            FlexStrategy.initialize.selector, admin, name, symbol_, decimals, baseAsset, paused
                        )
                    )
                )
            )
        );

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
                            lowerBound
                        )
                    )
                )
            )
        );

        configureStrategy(accountingProcessor);
    }

    function configureStrategy(address accountingProcessor) internal {
        BaseRoles.configureDefaultRolesStrategy(strategy, accountingModule, accountingToken, address(timelock), actors);
        BaseRoles.configureTemporaryRolesStrategy(strategy, accountingModule, accountingToken, deployer);

        // set provider
        strategy.setProvider(address(rateProvider));

        // set has allocator
        strategy.setHasAllocator(true);
        // grant allocator roles
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), contracts.YNETHX());
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), MainnetActors(address(actors)).YnBootstrapper());

        // set accounting module for strategy
        strategy.setAccountingModule(address(accountingModule));

        // set accounting module for token
        accountingToken.setAccountingModule(address(accountingModule));

        // set accounting processor role
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), accountingProcessor);

        strategy.unpause();

        BaseRoles.renounceTemporaryRolesStrategy(strategy, accountingModule, accountingToken, deployer);
    }
}
