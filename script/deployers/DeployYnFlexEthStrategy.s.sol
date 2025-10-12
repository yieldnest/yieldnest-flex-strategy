// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "script/DeployFlexStrategy.s.sol";
import { L1Contracts } from "lib/yieldnest-vault/script/Contracts.sol";
import { IContracts } from "lib/yieldnest-vault/script/Contracts.sol";
import { IActors } from "lib/yieldnest-vault/script/Actors.sol";
import { console } from "forge-std/console.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyUtils } from "lib/yieldnest-vault/script/ProxyUtils.sol";
import { MainnetActors } from "lib/yieldnest-vault/script/Actors.sol";

contract DeployYnFlexEthStrategy is DeployFlexStrategy {
    function _setup() public virtual override {
        if (block.chainid == 1) {
            minDelay = 1 days;
            MainnetActors _actors = new MainnetActors();
            actors = IActors(_actors);
            contracts = IContracts(new L1Contracts());
        } else {
            revert UnsupportedChain();
        }

        address[] memory allocators = new address[](1);
        allocators[0] = contracts.YNETHX();
        setDeploymentParameters(
            BaseScript.DeploymentParameters({
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
                allocators: allocators,
                safe: 0xF080905b7AF7fA52952C0Bb0463F358F21c06a64,
                alwaysComputeTotalAssets: true,
                useRewardsSweeper: true
            })
        );
    }
}
