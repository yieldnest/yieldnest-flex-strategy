// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { FixedAPYAccrual } from "src/yield/FixedAPYAccrual.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/// @dev Implements only the accounting calls used by the accrual module. Reports mint to the
/// strategy, while configurable rejection/callbacks exercise atomicity and reentrancy.
contract AccrualAccountingMock {
    uint256 public YEAR = 365.25 days;
    MockERC20 public accountingToken;
    address public strategy = address(0x5151);
    uint256 public reports;
    uint256 public totalRewards;
    bool public rejectReports;
    bytes public callback;

    error ReportRejected();

    constructor(MockERC20 token) {
        accountingToken = token;
    }

    function setYear(uint256 year) external {
        YEAR = year;
    }

    function setRejectReports(bool reject) external {
        rejectReports = reject;
    }

    function setCallback(bytes calldata data) external {
        callback = data;
    }

    function processRewards(uint256 rewards) external {
        if (rejectReports) revert ReportRejected();
        ++reports;
        totalRewards += rewards;
        if (callback.length != 0) {
            (bool success, bytes memory reason) = msg.sender.call(callback);
            if (!success) {
                assembly {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
        accountingToken.mint(strategy, rewards);
    }
}

contract FixedAPYAccrualTest is Test {
    uint256 internal constant YEAR = 365.25 days;
    uint256 internal constant START = 1_000_000;
    uint256 internal constant BALANCE = 1000e18;
    address internal constant ADMIN = address(0xAD);
    address internal constant CALLER = address(0xCA);

    FixedAPYAccrual internal implementation;
    FixedAPYAccrual internal accrual;
    AccrualAccountingMock internal accounting;
    MockERC20 internal token;

    event APYUpdated(uint256 oldAPY, uint256 newAPY);
    event YieldAccrued(uint256 fromTimestamp, uint256 toTimestamp, uint256 balance, uint256 rewards);

    function setUp() public {
        vm.warp(START);
        token = new MockERC20("Accounting", "ACC", 18);
        accounting = new AccrualAccountingMock(token);
        token.mint(accounting.strategy(), BALANCE);
        implementation = new FixedAPYAccrual();
        accrual = _newProxy();
        accrual.initialize(ADMIN, address(accounting), 0.1e18, START);
    }

    function _newProxy() internal returns (FixedAPYAccrual) {
        return FixedAPYAccrual(address(new TransparentUpgradeableProxy(address(implementation), ADMIN, "")));
    }

    function test_initialize_setsConfigurationRolesAndEvent() public {
        FixedAPYAccrual fresh = _newProxy();
        accounting.setYear(360 days);
        vm.expectEmit(false, false, false, true, address(fresh));
        emit APYUpdated(0, 0.11e18);
        fresh.initialize(ADMIN, address(accounting), 0.11e18, START + 1 days);
        assertEq(address(fresh.accountingModule()), address(accounting));
        assertEq(fresh.YEAR(), 360 days);
        assertEq(fresh.apy(), 0.11e18);
        assertEq(fresh.lastAccrual(), START + 1 days);
        assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), ADMIN));
        assertTrue(fresh.hasRole(fresh.APY_MANAGER_ROLE(), ADMIN));
        assertFalse(fresh.hasRole(fresh.APY_MANAGER_ROLE(), address(this)));
        // The year is cached at initialization.
        accounting.setYear(365 days);
        assertEq(fresh.YEAR(), 360 days);
    }

    function test_initialize_acceptsZeroAndMaximumAPY() public {
        FixedAPYAccrual zero = _newProxy();
        zero.initialize(ADMIN, address(accounting), 0, START);
        assertEq(zero.apy(), 0);
        FixedAPYAccrual maximum = _newProxy();
        maximum.initialize(ADMIN, address(accounting), 100e18, START);
        assertEq(maximum.apy(), maximum.MAX_APY());
    }

    function test_initialize_rejectsZeroAdmin() public {
        FixedAPYAccrual fresh = _newProxy();
        vm.expectRevert(FixedAPYAccrual.ZeroAddress.selector);
        fresh.initialize(address(0), address(accounting), 0.1e18, START);
    }

    function test_initialize_rejectsZeroAccountingModule() public {
        FixedAPYAccrual fresh = _newProxy();
        vm.expectRevert(FixedAPYAccrual.ZeroAddress.selector);
        fresh.initialize(ADMIN, address(0), 0.1e18, START);
    }

    function test_initialize_rejectsExcessiveAPY() public {
        FixedAPYAccrual fresh = _newProxy();
        vm.expectRevert(abi.encodeWithSelector(FixedAPYAccrual.InvalidAPY.selector, 100e18 + 1));
        fresh.initialize(ADMIN, address(accounting), 100e18 + 1, START);
    }

    function test_initialize_rejectsPastStart() public {
        FixedAPYAccrual fresh = _newProxy();
        vm.expectRevert(abi.encodeWithSelector(FixedAPYAccrual.StartInPast.selector, START - 1));
        fresh.initialize(ADMIN, address(accounting), 0.1e18, START - 1);
    }

    function test_initialize_rejectsZeroYear() public {
        FixedAPYAccrual fresh = _newProxy();
        accounting.setYear(0);
        vm.expectRevert(FixedAPYAccrual.InvalidYear.selector);
        fresh.initialize(ADMIN, address(accounting), 0.1e18, START);
    }

    function test_initialize_cannotReinitializeProxyOrImplementation() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        accrual.initialize(ADMIN, address(accounting), 0.1e18, START);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(ADMIN, address(accounting), 0.1e18, START);
    }

    function test_accrue_beforeAndAtScheduledStartIsNoOp() public {
        FixedAPYAccrual future = _newProxy();
        future.initialize(ADMIN, address(accounting), 0.1e18, START + 1 days);
        vm.recordLogs();
        assertEq(future.previewAccrual(), 0);
        assertEq(future.accrue(), 0);
        vm.warp(START + 1 days);
        assertEq(future.previewAccrual(), 0);
        assertEq(future.accrue(), 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(future.lastAccrual(), START + 1 days);
        assertEq(accounting.reports(), 0);
        vm.warp(START + 1 days + YEAR);
        assertApproxEqAbs(future.accrue(), 100e18, 100_000);
    }

    function test_preview_isReadOnlyAndAccrueIsPermissionless() public {
        vm.warp(START + YEAR);
        uint256 preview = accrual.previewAccrual();
        assertApproxEqAbs(preview, 100e18, 100_000);
        assertEq(accrual.previewAccrual(), preview);
        assertEq(accrual.lastAccrual(), START);
        assertEq(accounting.reports(), 0);
        assertEq(token.balanceOf(accounting.strategy()), BALANCE);

        vm.expectEmit(false, false, false, true, address(accrual));
        emit YieldAccrued(START, START + YEAR, BALANCE, preview);
        vm.prank(CALLER);
        assertEq(accrual.accrue(), preview);
        assertEq(accrual.lastAccrual(), START + YEAR);
        assertEq(accounting.reports(), 1);
        assertEq(accounting.totalRewards(), preview);
        assertEq(token.balanceOf(accounting.strategy()), BALANCE + preview);

        vm.recordLogs();
        assertEq(accrual.previewAccrual(), 0);
        assertEq(accrual.accrue(), 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(accounting.reports(), 1);
    }

    function test_accrue_compoundsPreviouslyReportedRewards() public {
        vm.warp(START + YEAR);
        assertApproxEqAbs(accrual.accrue(), 100e18, 100_000);
        vm.warp(START + 2 * YEAR);
        assertApproxEqAbs(accrual.accrue(), 110e18, 100_000);
        assertApproxEqAbs(accounting.totalRewards(), 210e18, 200_000);
        assertEq(accounting.reports(), 2);
    }

    function test_accrue_emptyBalancePreservesTimestamp() public {
        vm.prank(accounting.strategy());
        token.transfer(CALLER, BALANCE);
        vm.warp(START + YEAR);
        vm.recordLogs();
        assertEq(accrual.accrue(), 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(accrual.lastAccrual(), START);
        assertEq(accounting.reports(), 0);
    }

    function test_accrue_zeroAPYPreservesTimestamp() public {
        vm.prank(ADMIN);
        accrual.setAPY(0);
        vm.warp(START + YEAR);
        vm.recordLogs();
        assertEq(accrual.accrue(), 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(accrual.lastAccrual(), START);
        assertEq(accounting.reports(), 0);
    }

    function test_accrue_dustPreservesIntervalUntilRewardsAccumulate() public {
        vm.prank(accounting.strategy());
        token.transfer(CALLER, BALANCE - 1e6);
        vm.recordLogs();
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(START + i * 12);
            assertEq(accrual.accrue(), 0);
            assertEq(accrual.lastAccrual(), START);
        }
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(accounting.reports(), 0);
        vm.warp(START + 1 days);
        uint256 expected = accrual.calculateRewards(1e6, 1 days, 0.1e18, YEAR);
        assertGt(expected, 0);
        assertEq(accrual.accrue(), expected);
        assertEq(accounting.totalRewards(), expected);
        assertEq(accrual.lastAccrual(), block.timestamp);
    }

    function test_accrue_rejectedReportRollsBackAndCanBeRetried() public {
        accounting.setRejectReports(true);
        vm.warp(START + YEAR);
        uint256 preview = accrual.previewAccrual();
        vm.expectRevert(AccrualAccountingMock.ReportRejected.selector);
        accrual.accrue();
        _assertUnsettled();
        assertEq(accrual.previewAccrual(), preview);
        accounting.setRejectReports(false);
        assertEq(accrual.accrue(), preview);
        assertEq(accrual.lastAccrual(), START + YEAR);
    }

    function test_setAPY_settlesOldRateBeforeApplyingNewRate() public {
        vm.warp(START + YEAR);
        uint256 preview = accrual.previewAccrual();
        vm.expectEmit(false, false, false, true, address(accrual));
        emit YieldAccrued(START, START + YEAR, BALANCE, preview);
        vm.expectEmit(false, false, false, true, address(accrual));
        emit APYUpdated(0.1e18, 0.05e18);
        vm.prank(ADMIN);
        accrual.setAPY(0.05e18);
        assertEq(accrual.apy(), 0.05e18);
        assertEq(accounting.totalRewards(), preview);
        assertEq(accrual.lastAccrual(), START + YEAR);
        vm.warp(START + 2 * YEAR);
        assertApproxEqAbs(accrual.accrue(), 55e18, 100_000);
    }

    function test_setAPY_beforeScheduledStartPreservesStart() public {
        FixedAPYAccrual future = _newProxy();
        future.initialize(ADMIN, address(accounting), 0.1e18, START + YEAR);
        vm.prank(ADMIN);
        future.setAPY(0.05e18);
        assertEq(future.lastAccrual(), START + YEAR);
        assertEq(future.apy(), 0.05e18);
        assertEq(accounting.reports(), 0);
        vm.warp(START + 2 * YEAR);
        assertApproxEqAbs(future.accrue(), 50e18, 100_000);
    }

    function test_setAPY_acceptsMaximum() public {
        vm.prank(ADMIN);
        accrual.setAPY(100e18);
        assertEq(accrual.apy(), 100e18);
    }

    function test_setAPY_rejectsExcessiveRateBeforeSettlement() public {
        vm.warp(START + YEAR);
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(FixedAPYAccrual.InvalidAPY.selector, 100e18 + 1));
        accrual.setAPY(100e18 + 1);
        _assertUnsettled();
    }

    function test_setAPY_requiresManagerRole() public {
        bytes32 role = accrual.APY_MANAGER_ROLE();
        vm.prank(CALLER);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, CALLER, role));
        accrual.setAPY(0.05e18);
        vm.prank(ADMIN);
        accrual.grantRole(role, CALLER);
        vm.prank(CALLER);
        accrual.setAPY(0.05e18);
        assertEq(accrual.apy(), 0.05e18);
    }

    function test_setAPY_rejectedReportRollsBackRateAndCheckpoint() public {
        accounting.setRejectReports(true);
        vm.warp(START + YEAR);
        vm.prank(ADMIN);
        vm.expectRevert(AccrualAccountingMock.ReportRejected.selector);
        accrual.setAPY(0.05e18);
        _assertUnsettled();
    }

    function test_accrue_blocksReentrantAccrue() public {
        accounting.setCallback(abi.encodeCall(FixedAPYAccrual.accrue, ()));
        vm.warp(START + YEAR);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        accrual.accrue();
        _assertUnsettled();
    }

    function test_accrue_blocksReentrantSetAPYEvenWithManagerRole() public {
        bytes32 role = accrual.APY_MANAGER_ROLE();
        vm.prank(ADMIN);
        accrual.grantRole(role, address(accounting));
        accounting.setCallback(abi.encodeCall(FixedAPYAccrual.setAPY, (0.05e18)));
        vm.warp(START + YEAR);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        accrual.accrue();
        _assertUnsettled();
    }

    function test_setAPY_blocksReentrantAccrue() public {
        accounting.setCallback(abi.encodeCall(FixedAPYAccrual.accrue, ()));
        vm.warp(START + YEAR);
        vm.prank(ADMIN);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        accrual.setAPY(0.05e18);
        _assertUnsettled();
    }

    function _assertUnsettled() internal view {
        assertEq(accrual.lastAccrual(), START);
        assertEq(accrual.apy(), 0.1e18);
        assertEq(accounting.reports(), 0);
        assertEq(accounting.totalRewards(), 0);
        assertEq(token.balanceOf(accounting.strategy()), BALANCE);
    }
}
