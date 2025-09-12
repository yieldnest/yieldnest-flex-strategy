// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { BaseScript } from "script/BaseScript.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";

contract DeployYnFlexUSDCynRWAxSPV1 is DeployFlexStrategy {
    address public YNRWAX_PROCESSOR = 0x7e92AbC00F58Eb325C7fC95Ed52ACdf74584Be2c;

    address public SAFE = 0xb34E69c23Df216334496DFFd455618249E6bbFa9;

    address public YNRWAX = 0x01Ba69727E2860b37bc1a2bd56999c1aFb4C15D8;

    function _setup() public virtual override {
        super._setup();
        setDeploymentParameters(
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
    }
}
