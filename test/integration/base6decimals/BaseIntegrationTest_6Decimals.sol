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
import { Contracts } from "./Contracts.sol";
import { MockERC4626 } from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BaseIntegrationTest_6Decimals is Test {
    DeployFlexStrategy public deployment;
    address DEPLOYER = address(0xd34db33f);

    FlexStrategy public strategy;
    IAccountingModule public accountingModule;
    IAccountingToken public accountingToken;

    address public accountingProcessor = address(0x1234567);
    address public safe = address(0x3afe);

    address public mockAllocator;

    function setUp() public virtual {
        mockAllocator = address(new MockERC4626(ERC20(Contracts.USDC), "Mock USDC", "mUSDC"));
        deployment = new DeployFlexStrategy();

        deployment.setDeploymentParameters(
            BaseScript.DeploymentParameters({
                name: "YieldNest Flex Strategy",
                symbol_: "YNFLEX",
                accountTokenName: "YieldNest Flex Token",
                accountTokenSymbol: "YNFLEX",
                decimals: 6,
                paused: true,
                targetApy: 0.1 ether,
                lowerBound: 0.5 ether,
                accountingProcessor: accountingProcessor,
                baseAsset: Contracts.USDC,
                allocator: mockAllocator,
                safe: safe
            })
        );
        deployment.setEnv(BaseScript.Env.TEST);
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
