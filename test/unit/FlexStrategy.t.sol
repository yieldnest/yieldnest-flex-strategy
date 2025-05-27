// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { FlexStrategy, IFlexStrategy } from "../../src/FlexStrategy.sol";
import { AccountingModule, IAccountingModule } from "../../src/AccountingModule.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { FixedRateProvider } from "../../src/FixedRateProvider.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FlexStrategyTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);
    address public SAFE = address(0x1111);
    address public SAFE_MANAGER = address(0x5afe);
    uint16 public constant TARGET_APY = 1000;
    uint16 public constant LOWER_BOUND = 1000;

    MockERC20 public mockErc20;
    FlexStrategy public flexStrategy;
    AccountingModule public accountingModule;
    AccountingModule public accountingModule2;
    AccountingToken public accountingToken;

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);

        FlexStrategy strat_impl = new FlexStrategy();
        TransparentUpgradeableProxy strat_tu = new TransparentUpgradeableProxy(
            address(strat_impl),
            ADMIN,
            abi.encodeWithSelector(FlexStrategy.initialize.selector, ADMIN, "FlexStrategy", "FLEX", 18, mockErc20, true)
        );
        flexStrategy = FlexStrategy(payable(address(strat_tu)));

        AccountingToken accountingToken_impl = new AccountingToken(address(mockErc20));
        TransparentUpgradeableProxy accountingToken_tu = new TransparentUpgradeableProxy(
            address(accountingToken_impl),
            ADMIN,
            abi.encodeWithSelector(AccountingToken.initialize.selector, ADMIN, "NAME", "SYMBOL")
        );
        accountingToken = AccountingToken(payable(address(accountingToken_tu)));

        bytes memory am_initData = abi.encodeWithSelector(
            AccountingModule.initialize.selector, ADMIN, SAFE, address(accountingToken), TARGET_APY, LOWER_BOUND
        );
        AccountingModule am_impl = new AccountingModule(address(flexStrategy), address(mockErc20));
        TransparentUpgradeableProxy am_tu = new TransparentUpgradeableProxy(address(am_impl), ADMIN, am_initData);

        TransparentUpgradeableProxy am_tu2 = new TransparentUpgradeableProxy(address(am_impl), ADMIN, am_initData);

        accountingModule = AccountingModule(payable(address(am_tu)));
        accountingModule2 = AccountingModule(payable(address(am_tu2)));

        FixedRateProvider provider = new FixedRateProvider(address(mockErc20));

        vm.startPrank(ADMIN);
        flexStrategy.grantRole(flexStrategy.PROVIDER_MANAGER_ROLE(), ADMIN);
        flexStrategy.setProvider(address(provider));
        flexStrategy.grantRole(flexStrategy.UNPAUSER_ROLE(), ADMIN);
        flexStrategy.unpause();
        flexStrategy.grantRole(flexStrategy.ALLOCATOR_MANAGER_ROLE(), ADMIN);
        flexStrategy.setHasAllocator(true);
        flexStrategy.grantRole(flexStrategy.ASSET_MANAGER_ROLE(), ADMIN);
        flexStrategy.grantRole(flexStrategy.ALLOCATOR_ROLE(), BOB);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), SAFE_MANAGER);

        accountingToken.setAccountingModule(address(accountingModule));
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.stopPrank();

        vm.prank(BOB);
        mockErc20.mint(100e18);

        vm.prank(SAFE);
        mockErc20.approve(address(accountingModule), type(uint256).max);
    }

    function test_setup_success() public view {
        assertEq(flexStrategy.name(), "FlexStrategy");
        assertEq(flexStrategy.symbol(), "FLEX");
        assertEq(flexStrategy.decimals(), 18);
        assertEq(flexStrategy.asset(), address(mockErc20));
        assertEq(flexStrategy.asset(), address(mockErc20));
    }

    function test_setAccountingModule_revertIfNoDefaultAdminRole() public {
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, flexStrategy.DEFAULT_ADMIN_ROLE()
            )
        );
        flexStrategy.setAccountingModule(address(accountingModule));
    }

    function test_setAccountingModule_revertIfZeroAddress() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(IVault.ZeroAddress.selector);
        flexStrategy.setAccountingModule(address(0));
    }

    function test_setAccountingModule_setRelevantApprovals() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        assertEq(
            IERC20(flexStrategy.asset()).allowance(address(flexStrategy), address(accountingModule)), type(uint256).max
        );
    }

    function test_setAccountingModule_revokeRelevantApprovals() public {
        vm.startPrank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));
        flexStrategy.setAccountingModule(address(accountingModule2));

        assertEq(
            IERC20(flexStrategy.asset()).allowance(address(flexStrategy), address(accountingModule2)), type(uint256).max
        );
        assertEq(IERC20(flexStrategy.asset()).allowance(address(flexStrategy), address(accountingModule)), 0);
    }

    function test_deposit_success() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        uint256 balanceBefore = mockErc20.balanceOf(BOB);
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0);
        assertEq(mockErc20.balanceOf(BOB), balanceBefore - 2e18);
    }

    function test_deposit_revertIfNotAllocator() public {
        vm.startPrank(ADMIN);
        flexStrategy.revokeRole(flexStrategy.ALLOCATOR_ROLE(), BOB);

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, flexStrategy.ALLOCATOR_ROLE()
            )
        );

        flexStrategy.deposit(2e18, BOB);
    }

    function test_processAccounting_success() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        uint256 deposit = 30e18;
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);
        vm.stopPrank();

        assertEq(accountingToken.balanceOf(address(flexStrategy)), deposit);
        assertEq(flexStrategy.computeTotalAssets(), deposit);
        assertEq(flexStrategy.totalAssets(), deposit);

        uint256 rewards = 1e5;
        vm.startPrank(SAFE_MANAGER);
        accountingModule.processRewards(rewards);

        assertEq(accountingToken.balanceOf(address(flexStrategy)), deposit + rewards);
        assertEq(flexStrategy.computeTotalAssets(), deposit + rewards);
        assertEq(flexStrategy.totalAssets(), deposit + rewards);
    }

    function test_withdraw_success() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        uint256 balanceBefore = mockErc20.balanceOf(BOB);
        flexStrategy.deposit(2e18, BOB);
        flexStrategy.withdraw(2e18, BOB, BOB);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0);
        assertEq(mockErc20.balanceOf(BOB), balanceBefore);
    }

    function test_withdraw_revertIfNotAllocator() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        vm.startPrank(ADMIN);
        flexStrategy.revokeRole(flexStrategy.ALLOCATOR_ROLE(), BOB);

        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, flexStrategy.ALLOCATOR_ROLE()
            )
        );
        flexStrategy.withdraw(2e18, BOB, BOB);
    }

    function test_setAlwaysComputeTotalAssets_revert() public {
        vm.prank(ADMIN);
        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.setAlwaysComputeTotalAssets(true);
    }

    function test_initialize_revertIfZeroAdmin() public {
        FlexStrategy implementation = new FlexStrategy();
        vm.expectRevert(IVault.ZeroAddress.selector);
        new TransparentUpgradeableProxy(
            address(implementation),
            ADMIN,
            abi.encodeWithSelector(
                FlexStrategy.initialize.selector, address(0), "FlexStrategy", "FLEX", 18, address(mockErc20), true
            )
        );
    }

    function test_initialize_revertIfZeroBaseAsset() public {
        FlexStrategy implementation = new FlexStrategy();
        vm.expectRevert();
        new TransparentUpgradeableProxy(
            address(implementation),
            ADMIN,
            abi.encodeWithSelector(
                FlexStrategy.initialize.selector, ADMIN, "FlexStrategy", "FLEX", 18, address(0), true
            )
        );
    }

    function test_deposit_revertIfNoAccountingModule() public {
        FlexStrategy implementation = new FlexStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            ADMIN,
            abi.encodeWithSelector(
                FlexStrategy.initialize.selector, ADMIN, "FlexStrategy", "FLEX", 18, address(mockErc20), false
            )
        );
        FlexStrategy strategy = FlexStrategy(payable(address(proxy)));

        vm.startPrank(BOB);
        mockErc20.approve(address(strategy), type(uint256).max);
        vm.expectRevert();
        strategy.deposit(1e18, BOB);
    }

    function test_availableAssets() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.prank(SAFE);
        mockErc20.mint(100e18);

        assertEq(flexStrategy.totalAssets(), 0);
        assertEq(flexStrategy.computeTotalAssets(), 0);
    }

    function test_processAccounting() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        assertEq(flexStrategy.totalAssets(), 2e18);
        flexStrategy.processAccounting();
        assertEq(flexStrategy.totalAssets(), 2e18);
    }

    function test_feeOnTotal() public view {
        assertEq(flexStrategy._feeOnTotal(100e18), 0);
    }

    function test_feeOnRaw() public view {
        assertEq(flexStrategy._feeOnRaw(100e18), 0);
    }

    function test_withdrawAsset_revertIfAssetNotWithdrawable() public {
        vm.startPrank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));
        flexStrategy.setAssetWithdrawable(address(mockErc20), false);

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxWithdraw.selector, BOB, 2e18, 0));
        flexStrategy.withdraw(2e18, BOB, BOB);
    }

    function test_deposit_revertIfInvariantViolation() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.prank(BOB);
        mockErc20.transfer(address(flexStrategy), 1e18);

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.deposit(2e18, BOB);
    }

    function test_deposit_revertIfBaseAssetBalanceNotZero() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.transfer(address(flexStrategy), 1e18);
        mockErc20.approve(address(flexStrategy), type(uint256).max);

        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.deposit(2e18, BOB);
    }

    function test_withdraw_revertIfBaseAssetBalanceNotZero() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        mockErc20.transfer(address(flexStrategy), 1e18);

        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.withdraw(1e18, BOB, BOB);
    }

    function test_withdraw_revertIfInvariantViolation() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(address(flexStrategy), 1e18);

        vm.startPrank(BOB);
        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.withdraw(2e18, BOB, BOB);
    }

    function test_processAccounting_revertIfInvariantViolation() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        mockErc20.transfer(address(flexStrategy), 1e18);

        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.processAccounting();
    }

    function test_invariant_afterRewards() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        vm.startPrank(SAFE_MANAGER);
        accountingModule.processRewards(1e6);

        assertEq(flexStrategy.totalAssets(), accountingToken.balanceOf(address(flexStrategy)));
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0);
    }

    function test_invariant_afterLosses() public {
        vm.prank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(2e18, BOB);

        vm.startPrank(SAFE_MANAGER);
        accountingModule.processLosses(1e6);

        assertEq(flexStrategy.totalAssets(), accountingToken.balanceOf(address(flexStrategy)));
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0);
    }

    function test_availableAssets_returnsSafeBalance() public {
        vm.startPrank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.startPrank(BOB);
        mockErc20.transfer(SAFE, 100e18);

        assertEq(flexStrategy.totalAssets(), 0);
        assertEq(mockErc20.balanceOf(SAFE), 100e18);
    }
}
