// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { BaseScript } from "script/BaseScript.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
// import { BaseRoles } from "script/roles/BaseRoles.sol";
// import { FixedRateProvider } from "src/FixedRateProvider.sol";
// import { console } from "forge-std/console.sol";
// import { FlexStrategyRules } from "script/rules/FlexStrategyRules.sol";
// import { SafeRules, IVault } from "@yieldnest-vault-script/rules/SafeRules.sol";
// import { FlexStrategyDeployer } from "script/FlexStrategyDeployer.sol";
// import { ProxyUtils } from "lib/yieldnest-vault/script/ProxyUtils.sol";
// import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployYnFlexUSDCynRWAxSPV1 is DeployFlexStrategy {
    address public YNRWAX_PROCESSOR = 0x7e92AbC00F58Eb325C7fC95Ed52ACdf74584Be2c;

    constructor() {
        setDeploymentParameters(
            BaseScript.DeploymentParameters({
                name: "YieldNest USDC Flex Strategy - ynRWAx - SPV1",
                symbol_: "ynFlexUSDC-ynRWAx-SPV1",
                accountTokenName: "YieldNest Flex Strategy - ynRWAx - SPV1 Accounting Token",
                accountTokenSymbol: "ynFlexUSDC-ynRWAx-SPV1-Tok",
                decimals: 6, // 6 decimals for USDC
                paused: true,
                targetApy: 0.15 ether, // max 15% rewards per year
                lowerBound: 0.0 ether, // no use of marking losses
                minRewardableAssets: 1000e6, // min 1000 USDC
                accountingProcessor: YNRWAX_PROCESSOR,
                baseAsset: IVault(contracts.YNETHX()).asset(),
                allocator: contracts.YNETHX(),
                safe: address(0), // TODO: set safe
                alwaysComputeTotalAssets: true
            })
        );
    }
}
