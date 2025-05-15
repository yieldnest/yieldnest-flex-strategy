// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockStrategy } from "../mocks/MockStrategy.sol";
import { AccountingModule, IAccountingModule } from "../../src/AccountingModule.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";

contract AccountingModuleTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);
    address public SAFE = address(0x1111);
    MockERC20 public mockErc20;
    AccountingModule public accountingModule;
    AccountingToken public accountingToken;
    MockStrategy public mockStrategy;
    uint16 public constant TARGET_APY = 1000;
    uint16 public constant LOWER_BOUND = 1000;

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);
        mockStrategy = new MockStrategy();
        accountingModule = new AccountingModule(
            "NAME", "SYMBOL", address(mockStrategy), address(mockErc20), SAFE, TARGET_APY, LOWER_BOUND
        );
        accountingToken = accountingModule.ACCOUNTING_TOKEN();

        mockStrategy.setAccountingModule(accountingModule);
        vm.prank(BOB);
        mockErc20.mint(100e18);

        vm.prank(SAFE);
        mockErc20.approve(address(accountingModule), type(uint256).max);
    }

    function test_setup_success() public view {
        assertEq(accountingToken.name(), "NAME");
        assertEq(accountingToken.symbol(), "SYMBOL");
        assertEq(accountingToken.decimals(), 18);

        assertEq(accountingModule.targetApy(), TARGET_APY);
        assertEq(accountingModule.lowerBound(), LOWER_BOUND);
    }

    function test_deposit_revertIfNotStrategy() public {
        vm.expectRevert(IAccountingModule.NotStrategy.selector);
        vm.prank(BOB);
        accountingModule.deposit(20e18);
    }

    function test_deposit_success() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        assertEq(accountingToken.balanceOf(address(mockStrategy)), deposit);
    }

    function test_withdraw_revertIfNotStrategy() public {
        vm.expectRevert(IAccountingModule.NotStrategy.selector);
        vm.prank(BOB);
        accountingModule.withdraw(20e18);
    }

    function test_withdraw_success() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        uint256 bobBefore = mockErc20.balanceOf(BOB);
        uint256 withdraw = 10e18;
        mockStrategy.withdraw(withdraw);

        assertEq(accountingToken.balanceOf(address(mockStrategy)), withdraw);
        assertEq(mockErc20.balanceOf(BOB) - bobBefore, withdraw);
    }

    function test_processRewards_revertIfNotSafeManager() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(false);
        vm.expectRevert(IAccountingModule.NotSafeManager.selector);
        accountingModule.processRewards(1e6);
    }

    function test_processRewards_revertIfTvlTooLow() public {
        vm.startPrank(BOB);
        uint256 deposit = 1e6;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        vm.expectRevert(IAccountingModule.TvlTooLow.selector);
        accountingModule.processRewards(1e6);
    }

    function test_processRewards_revertIfUpperBoundExceed() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        vm.expectRevert(IAccountingModule.AccountingLimitsExceeded.selector);
        accountingModule.processRewards(deposit);
    }

    function test_processRewards_revertIfTooEarly() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        accountingModule.processRewards(1e6);

        vm.expectRevert(IAccountingModule.TooEarly.selector);
        accountingModule.processRewards(1e6);

        skip(3601);
        accountingModule.processRewards(1e6);
    }

    function test_processRewards_success() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        accountingModule.processRewards(1e6);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), 20e18 + 1e6);
    }

    function test_processLosses_revertIfNotSafeManager() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(false);
        vm.expectRevert(IAccountingModule.NotSafeManager.selector);
        accountingModule.processLosses(1e6);
    }

    function test_processLosses_revertIfTvlTooLow() public {
        vm.startPrank(BOB);
        uint256 deposit = 1e6;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        vm.expectRevert(IAccountingModule.TvlTooLow.selector);
        accountingModule.processLosses(1e6);
    }

    function test_processLosses_revertIfLowerBoundExceed() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        vm.expectRevert(IAccountingModule.AccountingLimitsExceeded.selector);
        accountingModule.processLosses(deposit);
    }

    function test_processLosses_revertIfTooEarly() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        accountingModule.processLosses(1e6);

        vm.expectRevert(IAccountingModule.TooEarly.selector);
        accountingModule.processLosses(1e6);

        skip(3601);
        accountingModule.processLosses(1e6);
    }

    function test_processLosses_success() public {
        vm.startPrank(BOB);
        uint256 deposit = 20e18;
        mockErc20.approve(address(mockStrategy), type(uint256).max);
        mockStrategy.deposit(deposit);

        mockStrategy.setSafeManager(true);
        accountingModule.processLosses(1e6);
        assertEq(accountingToken.balanceOf(address(mockStrategy)), 20e18 - 1e6);
    }

    function test_setTargetApy_revertIfNotSafeManager() public {
        mockStrategy.setSafeManager(false);
        vm.expectRevert(IAccountingModule.NotSafeManager.selector);
        accountingModule.setTargetApy(5000);
    }

    function test_setTargetApy_revertIfExceedDivisor() public {
        mockStrategy.setSafeManager(true);
        vm.expectRevert(IAccountingModule.InvariantViolation.selector);
        accountingModule.setTargetApy(1e4);
    }

    function test_setTargetApy_success() public {
        mockStrategy.setSafeManager(true);
        accountingModule.setTargetApy(2000);
        assertEq(accountingModule.targetApy(), 2000);
    }

    function test_setLowerBound_revertIfNotSafeManager() public {
        mockStrategy.setSafeManager(false);
        vm.expectRevert(IAccountingModule.NotSafeManager.selector);
        accountingModule.setLowerBound(5000);
    }

    function test_setLowerBound_revertIfExceedDivisor() public {
        mockStrategy.setSafeManager(true);
        vm.expectRevert(IAccountingModule.InvariantViolation.selector);
        accountingModule.setLowerBound(1e4);
    }

    function test_setLowerBound_success() public {
        mockStrategy.setSafeManager(true);
        accountingModule.setLowerBound(2000);
        assertEq(accountingModule.lowerBound(), 2000);
    }

    function test_setCooldownSeconds_revertIfNotSafeManager() public {
        mockStrategy.setSafeManager(false);
        vm.expectRevert(IAccountingModule.NotSafeManager.selector);
        accountingModule.setCoolDownSeconds(5000);
    }

    function test_setCooldownSeconds_success() public {
        mockStrategy.setSafeManager(true);
        accountingModule.setCoolDownSeconds(5000);
        assertEq(accountingModule.cooldownSeconds(), 5000);
    }

    function test_setSafeAddress_revertIfNotSafeManager() public {
        mockStrategy.setSafeManager(false);
        vm.expectRevert(IAccountingModule.NotSafeManager.selector);
        accountingModule.setSafeAddress(BOB);
    }

    function test_setSafeAddress_success() public {
        mockStrategy.setSafeManager(true);
        accountingModule.setSafeAddress(BOB);
        assertEq(accountingModule.safe(), BOB);
    }
}
