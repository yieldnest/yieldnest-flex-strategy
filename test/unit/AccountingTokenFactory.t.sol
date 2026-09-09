// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { AccountingToken } from "src/AccountingToken.sol";
import { AccountingTokenFactory } from "src/factory/AccountingTokenFactory.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract AccountingTokenFactoryTest is Test {
    AccountingTokenFactory public factory;
    MockERC20 public asset;

    function setUp() public {
        factory = new AccountingTokenFactory();
        asset = new MockERC20("MOCK", "MOCK", 18);
    }

    function test_deployAccountingTokenImplementation_success() public {
        assertEq(factory.VERSION(), "0.2.0");

        AccountingToken implementation = factory.deployAccountingTokenImplementation(address(asset));

        assertEq(implementation.TRACKED_ASSET(), address(asset));
        assertEq(implementation.decimals(), asset.decimals());
        assertGt(address(implementation).code.length, 0);
    }
}
