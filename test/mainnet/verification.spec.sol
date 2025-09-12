// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import { Test } from "lib/forge-std/src/Test.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { BaseMainnetTest } from "test/mainnet/BaseMainnetTest.sol";
import { UpgradeUtils } from "script/UpgradeUtils.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { ProxyUtils } from "@yieldnest-vault-script/ProxyUtils.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { BaseScript } from "script/BaseScript.sol";

contract MainnetVerificationTest is BaseMainnetTest {
    address public YNRWAX_PROCESSOR = 0x7e92AbC00F58Eb325C7fC95Ed52ACdf74584Be2c;

    address public SAFE = 0xb34E69c23Df216334496DFFd455618249E6bbFa9;

    address public YNRWAX = 0x01Ba69727E2860b37bc1a2bd56999c1aFb4C15D8;

    function setUp() public override {
        super.setUp();
    }

    function test_usdc_ynrwax_spv1_Verification() public {
        VerifyFlexStrategy verifyFlexStrategy = new VerifyFlexStrategy();
        verifyFlexStrategy.setEnv(BaseScript.Env.TEST);

        verifyFlexStrategy.setDeploymentParameters(
            BaseScript.DeploymentParameters({
                name: "YieldNest USDC Flex Strategy - ynRWAx - SPV1",
                symbol_: "ynFlex-USDC-ynRWAx-SPV1",
                accountTokenName: "YieldNest Flex Strategy - ynRWAx - SPV1 Accounting Token",
                accountTokenSymbol: "ynFlexUSDC-ynRWAx-SPV1-Tok",
                decimals: 6, // 6 decimals for USDC
                paused: true,
                targetApy: 0.15 ether, // max 15% rewards per year
                lowerBound: 0.0001 ether, // Ability to mark 0.01% of TVL as losses
                minRewardableAssets: 1000e6, // min 1000 USDC
                accountingProcessor: YNRWAX_PROCESSOR,
                baseAsset: IVault(YNRWAX).asset(),
                allocator: YNRWAX,
                safe: SAFE,
                alwaysComputeTotalAssets: true,
                useRewardsSweeper: false
            })
        );
        verifyFlexStrategy.run();
    }
}
