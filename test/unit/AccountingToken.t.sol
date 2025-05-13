// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";

contract AccountingTokenTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);

    MockERC20 public mockErc20;
    MockERC20 public mockErc20e6;
    AccountingToken public accountingToken;

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);
        mockErc20e6 = new MockERC20("MOCK", "MOCK", 6);
        accountingToken = new AccountingToken("NAME", "SYMBOL", address(mockErc20), ADMIN);
    }

    function test_setupSuccess() public view {
        assertEq(accountingToken.name(), "NAME");
        assertEq(accountingToken.symbol(), "SYMBOL");
        assertEq(accountingToken.decimals(), 18);
    }

    function test_accountingToken_decimal_inherit_baseAsset() public {
        accountingToken = new AccountingToken("NAME6", "SYMBOL6", address(mockErc20e6), ADMIN);
        assertEq(accountingToken.name(), "NAME6");
        assertEq(accountingToken.symbol(), "SYMBOL6");
        assertEq(accountingToken.decimals(), 6);
    }

    function test_mintTo_revertIfNotAccounting() public {
        vm.expectRevert(AccountingToken.Unauthorized.selector);
        accountingToken.mintTo(ADMIN, 1e18);
    }

    function test_mintTo_happyPath() public {
        vm.prank(ADMIN);
        accountingToken.mintTo(ADMIN, 1e18);
        assertEq(accountingToken.balanceOf(ADMIN), 1e18);
    }

    function test_burnFrom_revertIfNotAccounting() public {
        vm.prank(ADMIN);
        accountingToken.mintTo(ADMIN, 1e18);
        vm.stopPrank();
        vm.expectRevert(AccountingToken.Unauthorized.selector);
        accountingToken.burnFrom(ADMIN, 1e18);
    }

    function test_burnFrom_happyPath() public {
        vm.startPrank(ADMIN);
        accountingToken.mintTo(ADMIN, 1e18);
        accountingToken.burnFrom(ADMIN, 1e18);
        assertEq(accountingToken.balanceOf(ADMIN), 0);
    }

    function test_transferFrom_revert() public {
        vm.startPrank(ADMIN);
        accountingToken.mintTo(ADMIN, 1e18);
        vm.expectRevert(AccountingToken.NotAllowed.selector);
        accountingToken.transferFrom(ADMIN, BOB, 1e18);
    }

    function test_transfer_revert() public {
        vm.startPrank(ADMIN);
        accountingToken.mintTo(ADMIN, 1e18);
        vm.expectRevert(AccountingToken.NotAllowed.selector);
        accountingToken.transfer(BOB, 1e18);
    }
}
