// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { DeployFlexStrategy } from "script/DeployFlexStrategy.s.sol";
import { VerifyFlexStrategy } from "script/verification/VerifyFlexStrategy.s.sol";
import { FlexStrategy } from "src/FlexStrategy.sol";
import { AccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FlexStrategyDeployment is Test {
    DeployFlexStrategy public deployment;
    address DEPLOYER = address(0xd34db33f);

    function setUp() public {
        deployment = new DeployFlexStrategy();
        deployment.run();
    }

    function test_verify_setup() public {
        VerifyFlexStrategy verify = new VerifyFlexStrategy();
        verify.run();
    }
}
