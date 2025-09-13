// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { BaseScript } from "script/BaseScript.sol";
import { MainnetActors } from "@yieldnest-vault-script/Actors.sol";
import { FlexStrategyDeployer } from "script/FlexStrategyDeployer.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { IContracts, L1Contracts } from "@yieldnest-vault-script/Contracts.sol";
import { IActors } from "@yieldnest-vault-script/Actors.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";

// forge script VerifyFlexStrategy --rpc-url <MAINNET_RPC_URL>
contract VerifyYnFlexEthStrategy is VerifyFlexStrategy {
    function _setup() public virtual override {
        contracts = IContracts(new L1Contracts());

        if (block.chainid == 1) {
            minDelay = 1 days;
            MainnetActors _actors = new MainnetActors();
            actors = IActors(_actors);
        }

        setVerificationParameters(
            VerifyFlexStrategy.VerificationParameters({
                name: "YieldNest Flex Strategy",
                symbol_: "ynFlexEth",
                accountTokenName: "YieldNest Flex Strategy IOU",
                accountTokenSymbol: "ynFlex_iou",
                decimals: 18,
                paused: true,
                targetApy: 0.1 ether, // max rewards per year: 10% of tvl
                lowerBound: 0.1 ether, // max loss: 10% of tvl
                minRewardableAssets: 1e18,
                accountingProcessor: 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64,
                baseAsset: IVault(contracts.YNETHX()).asset(),
                alwaysComputeTotalAssets: true
            })
        );
    }
}
