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
    address public ACCOUNTING_PROCESSOR = address(0x1234);
    address public WITHDRAW_RECEIVER = address(0x2222);
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
        accountingModule.grantRole(accountingModule.ACCOUNTING_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        accountingToken.setAccountingModule(address(accountingModule));
        flexStrategy.setAccountingModule(address(accountingModule));

        vm.stopPrank();

        vm.prank(BOB);
        mockErc20.mint(type(uint128).max);

        vm.prank(SAFE);
        mockErc20.approve(address(accountingModule), type(uint256).max);
    }

    function test_setup_success() public view {
        assertEq(flexStrategy.name(), "FlexStrategy", "Strategy name should be set");
        assertEq(flexStrategy.symbol(), "FLEX", "Strategy symbol should be set");
        assertEq(flexStrategy.decimals(), 18, "Strategy decimals should be set");
        assertEq(address(flexStrategy.asset()), address(mockErc20), "Strategy asset should be set");
        assertEq(
            address(flexStrategy.accountingModule()),
            address(accountingModule),
            "Strategy accounting module should be set"
        );
    }

    // Initialization & param setting

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

    function test_setAccountingModule_revokeRelevantApprovals() public {
        vm.startPrank(ADMIN);
        flexStrategy.setAccountingModule(address(accountingModule2));

        assertEq(
            IERC20(flexStrategy.asset()).allowance(address(flexStrategy), address(accountingModule2)),
            type(uint256).max,
            "Strategy should approve max allowance of asset to new accountingModule"
        );
        assertEq(
            IERC20(flexStrategy.asset()).allowance(address(flexStrategy), address(accountingModule)),
            0,
            "Strategy should revoke allowance of asset from old accountingModule"
        );
    }

    function test_setAlwaysComputeTotalAssets_revert() public {
        vm.prank(ADMIN);
        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.setAlwaysComputeTotalAssets(true);
    }

    // Deposit

    function testFuzz_deposit_success(uint128 deposit) public {
        uint256 balanceBefore = mockErc20.balanceOf(BOB);
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after deposit");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            deposit,
            "Strategy should have correct accountingToken balance after deposit"
        );
        assertEq(
            mockErc20.balanceOf(BOB), balanceBefore - deposit, "Allocator balance should decrease by deposit amount"
        );
        assertEq(IERC20(address(flexStrategy)).balanceOf(BOB), deposit, "Allocator should have correct strategy shares");
        assertEq(mockErc20.balanceOf(SAFE), deposit, "Safe should have correct deposit");
        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should match deposit");
        assertEq(flexStrategy.totalAssets(), deposit, "Total assets should match deposit");
    }

    function testFuzz_deposit_revertIfNotAllocator(uint128 deposit) public {
        vm.startPrank(ADMIN);
        flexStrategy.revokeRole(flexStrategy.ALLOCATOR_ROLE(), BOB);

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, flexStrategy.ALLOCATOR_ROLE()
            )
        );

        flexStrategy.deposit(deposit, BOB);
    }

    // ProcessAccounting

    function testFuzz_processAccounting_success(uint128 deposit) public {
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);
        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should match deposit");
        assertEq(flexStrategy.totalAssets(), deposit, "Total assets should match deposit amount");
        flexStrategy.processAccounting();
        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should remain unchanged");
        assertEq(
            flexStrategy.totalAssets(), deposit, "Total assets should remain unchanged after processing accounting"
        );
    }

    function testFuzz_processAccounting_successWhenProcessingRewards(uint128 deposit, uint128 rewards) public {
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);

        uint256 maxRewards = (
            accountingModule.targetApy() * accountingToken.totalSupply() / accountingModule.DIVISOR()
                / accountingModule.YEAR()
        );

        vm.assume(rewards <= maxRewards);

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processRewards(rewards);
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            deposit + rewards,
            "Strategy should have correct accountingToken balance after processing rewards"
        );

        assertEq(flexStrategy.computeTotalAssets(), deposit + rewards, "Computed total assets should include rewards");
        assertEq(flexStrategy.totalAssets(), deposit + rewards, "Total assets should include rewards");
        assertEq(
            flexStrategy.totalAssets(),
            accountingToken.balanceOf(address(flexStrategy)),
            "Total assets should match accountingToken balance after processing rewards"
        );
        assertEq(
            mockErc20.balanceOf(address(flexStrategy)),
            0,
            "Strategy should not hold any tokens after processing rewards"
        );
    }

    function testFuzz_processAccounting_successWhenProcessingLosses(uint128 deposit, uint128 losses) public {
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);

        uint256 maxLosses = (accountingToken.totalSupply() * accountingModule.lowerBound() / accountingModule.DIVISOR());

        vm.assume(losses <= maxLosses);

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        accountingModule.processLosses(losses);
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            deposit - losses,
            "Strategy should have correct accountingToken balance after processing losses"
        );

        assertEq(flexStrategy.computeTotalAssets(), deposit - losses, "Computed total assets should include losses");
        assertEq(flexStrategy.totalAssets(), deposit - losses, "Total assets should include losses");
        assertEq(
            flexStrategy.totalAssets(),
            accountingToken.balanceOf(address(flexStrategy)),
            "Total assets should match accounting token balance after processing losses"
        );
        assertEq(
            mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any tokens after processing losses"
        );
    }

    // Withdraw

    function testFuzz_withdraw_revertIfAssetNotWithdrawable(uint128 deposit) public {
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);
        vm.startPrank(ADMIN);
        flexStrategy.setAssetWithdrawable(address(mockErc20), false);

        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxWithdraw.selector, BOB, deposit, 0));
        flexStrategy.withdraw(deposit, BOB, BOB);
    }

    function testFuzz_withdraw_revertIfInvariantViolation(uint128 deposit) public {
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);

        // break invariant by minting some accountingTokens to strategy
        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(address(flexStrategy), 1e18);

        vm.startPrank(BOB);
        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.withdraw(deposit, WITHDRAW_RECEIVER, BOB);
    }

    function testFuzz_withdraw_success(uint128 deposit) public {
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);

        flexStrategy.deposit(deposit, BOB);

        flexStrategy.withdraw(deposit, WITHDRAW_RECEIVER, BOB);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after withdrawal");
        assertEq(mockErc20.balanceOf(WITHDRAW_RECEIVER), deposit, "Receiver balance should be correct after withdrawal");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            0,
            "Strategy accountingToken balance should be correct after withdrawal"
        );
        assertEq(IERC20(address(flexStrategy)).balanceOf(BOB), 0, "Allocator should have correct strategy shares");
        assertEq(mockErc20.balanceOf(SAFE), 0, "Safe should have correct deposit");
    }

    function testFuzz_withdraw_revertIfNotAllocator(uint128 deposit) public {
        vm.startPrank(BOB);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        flexStrategy.deposit(deposit, BOB);

        vm.startPrank(ADMIN);
        flexStrategy.revokeRole(flexStrategy.ALLOCATOR_ROLE(), BOB);

        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, flexStrategy.ALLOCATOR_ROLE()
            )
        );
        flexStrategy.withdraw(deposit, BOB, BOB);
    }

    function testFuzz_availableAssets_returnsSafeBalance(uint128 assetBalance) public {
        vm.prank(SAFE);
        mockErc20.mint(assetBalance);

        assertEq(flexStrategy.totalAssets(), 0, "Total assets should be 0 when no deposits made");
        assertEq(flexStrategy.computeTotalAssets(), 0, "Computed total assets should be 0 when no deposits made");
    }
}
