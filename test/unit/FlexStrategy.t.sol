// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, stdStorage, StdStorage, console } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { FlexStrategy, IFlexStrategy } from "../../src/FlexStrategy.sol";
import { AccountingModule, IAccountingModule } from "../../src/AccountingModule.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { FixedRateProvider } from "../../src/FixedRateProvider.sol";
import { MultiFixedRateProvider } from "../mocks/MultiFixedRateProvider.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract FlexStrategyTest is Test {
    using stdStorage for StdStorage;

    address public ADMIN = address(0xd34db33f);
    address public ALLOCATOR = address(0x0b0b);
    address public YIELD_FARM = address(0x8888);
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

        FixedRateProvider provider = new FixedRateProvider(address(mockErc20));

        TransparentUpgradeableProxy strat_tu = new TransparentUpgradeableProxy(
            address(strat_impl),
            ADMIN,
            abi.encodeWithSelector(
                FlexStrategy.initialize.selector, ADMIN, "FlexStrategy", "FLEX", 18, mockErc20, true, address(provider)
            )
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

        vm.startPrank(ADMIN);
        flexStrategy.grantRole(flexStrategy.UNPAUSER_ROLE(), ADMIN);
        flexStrategy.unpause();
        flexStrategy.grantRole(flexStrategy.ALLOCATOR_MANAGER_ROLE(), ADMIN);
        flexStrategy.setHasAllocator(true);
        flexStrategy.grantRole(flexStrategy.ASSET_MANAGER_ROLE(), ADMIN);
        flexStrategy.grantRole(flexStrategy.ALLOCATOR_ROLE(), ALLOCATOR);
        flexStrategy.grantRole(flexStrategy.PROVIDER_MANAGER_ROLE(), ADMIN);
        accountingModule.grantRole(accountingModule.SAFE_MANAGER_ROLE(), SAFE_MANAGER);
        accountingModule.grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);
        accountingModule.grantRole(accountingModule.LOSS_PROCESSOR_ROLE(), ACCOUNTING_PROCESSOR);

        accountingToken.setAccountingModule(address(accountingModule));
        flexStrategy.setAccountingModule(address(accountingModule));
        vm.stopPrank();

        vm.startPrank(ALLOCATOR);
        mockErc20.mint(type(uint128).max);
        mockErc20.approve(address(flexStrategy), type(uint256).max);
        vm.stopPrank();

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
        vm.startPrank(ALLOCATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALLOCATOR, flexStrategy.DEFAULT_ADMIN_ROLE()
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

    function testFuzz_operations_revertWhenNotBaseAsset(uint128 deposit, uint128 withdraw) public {
        vm.assume(withdraw > 0 && withdraw < type(uint128).max / 2);
        vm.assume(deposit > 0 && deposit < type(uint128).max / 2);

        vm.prank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ADMIN);
        // break invariant via bad settings
        MockERC20 wrongAsset = new MockERC20("WRONG", "WRONG", 18);
        MultiFixedRateProvider provider2 = new MultiFixedRateProvider();
        provider2.addAsset(address(mockErc20));

        // we need the wrong asset to be in provider to break invariant
        provider2.addAsset(address(wrongAsset));
        flexStrategy.setProvider(address(provider2));

        vm.startPrank(ALLOCATOR);
        vm.expectRevert(IVault.AssetNotActive.selector);
        flexStrategy.depositAsset(address(wrongAsset), deposit, ALLOCATOR);

        // bad settings to break invariant on withdraw
        vm.startPrank(SAFE);
        wrongAsset.mint(10_000e18);

        vm.startPrank(ALLOCATOR);
        assertEq(flexStrategy.maxWithdrawAsset(address(wrongAsset), ALLOCATOR), 0);
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxWithdraw.selector, ALLOCATOR, withdraw, 0));
        flexStrategy.withdrawAsset(address(wrongAsset), withdraw, WITHDRAW_RECEIVER, ALLOCATOR);
    }

    function testFuzz_feeOnTotal_returnsZero(uint128 assets) public view {
        assertEq(flexStrategy._feeOnTotal(assets), 0, "Fee on total should always return 0");
    }

    function testFuzz_feeOnRaw_returnsZero(uint128 assets) public view {
        assertEq(flexStrategy._feeOnRaw(assets), 0, "Fee on raw should always return 0");
    }

    function testFuzz_addAsset_revertOnNewAsset(uint8 decimals, bool depositable, bool withdrawable) public {
        vm.assume(decimals > 0 && decimals < 50);

        MockERC20 mockErc20_2 = new MockERC20("MOCK2", "MOCK2", decimals);
        vm.startPrank(ADMIN);
        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.addAsset(address(mockErc20_2), depositable, withdrawable);

        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.addAsset(address(mockErc20_2), decimals, depositable, withdrawable);
    }

    function test_invariant_initialBalanceZero() public {
        vm.prank(ALLOCATOR);
        mockErc20.transfer(address(flexStrategy), 1e18);

        // Any operation should trigger the invariant check and transfer
        vm.prank(ALLOCATOR);
        flexStrategy.deposit(1e18, ALLOCATOR);

        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should have transferred initial balance");
        assertEq(mockErc20.balanceOf(SAFE), 2e18, "Safe should have received both deposit and initial balance");
    }

    // Deposit
    function testFuzz_deposit_success(uint128 deposit) public {
        uint256 balanceBefore = mockErc20.balanceOf(ALLOCATOR);
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after deposit");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            deposit,
            "Strategy should have correct accountingToken balance after deposit"
        );
        assertEq(
            mockErc20.balanceOf(ALLOCATOR),
            balanceBefore - deposit,
            "Allocator balance should decrease by deposit amount"
        );
        assertEq(
            IERC20(address(flexStrategy)).balanceOf(ALLOCATOR), deposit, "Allocator should have correct strategy shares"
        );
        assertEq(mockErc20.balanceOf(SAFE), deposit, "Safe should have correct deposit");
        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should match deposit");
        assertEq(flexStrategy.totalAssets(), deposit, "Total assets should match deposit");
    }

    function testFuzz_deposit_sequential_success(uint128 deposit, uint128 deposit2) public {
        vm.assume(deposit > 0 && deposit < type(uint128).max / 2);
        vm.assume(deposit2 > 0 && deposit2 < type(uint128).max / 2);

        uint256 balanceBefore = mockErc20.balanceOf(ALLOCATOR);
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after deposit");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            deposit,
            "Strategy should have correct accountingToken balance after deposit"
        );
        assertEq(
            mockErc20.balanceOf(ALLOCATOR),
            balanceBefore - deposit,
            "Allocator balance should decrease by deposit amount"
        );
        assertEq(
            IERC20(address(flexStrategy)).balanceOf(ALLOCATOR), deposit, "Allocator should have correct strategy shares"
        );
        assertEq(mockErc20.balanceOf(SAFE), deposit, "Safe should have correct deposit");
        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should match deposit");
        assertEq(flexStrategy.totalAssets(), deposit, "Total assets should match deposit");

        // sim transfer to farm
        vm.startPrank(SAFE);
        mockErc20.transfer(YIELD_FARM, deposit);

        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit2, ALLOCATOR);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after deposit");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            deposit + deposit2,
            "Strategy should have correct accountingToken balance after deposit"
        );
        assertEq(
            mockErc20.balanceOf(ALLOCATOR),
            balanceBefore - deposit - deposit2,
            "Allocator balance should decrease by deposit amount"
        );
        assertEq(
            IERC20(address(flexStrategy)).balanceOf(ALLOCATOR),
            deposit + deposit2,
            "Allocator should have correct strategy shares"
        );
        assertEq(mockErc20.balanceOf(SAFE), deposit2, "Safe should have correct deposit");
        assertEq(flexStrategy.computeTotalAssets(), deposit + deposit2, "Computed total assets should match deposit");
        assertEq(flexStrategy.totalAssets(), deposit + deposit2, "Total assets should match deposit");
    }

    function testFuzz_deposit_revertIfNotAllocator(uint128 deposit) public {
        vm.startPrank(ADMIN);
        flexStrategy.revokeRole(flexStrategy.ALLOCATOR_ROLE(), ALLOCATOR);

        vm.startPrank(ALLOCATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALLOCATOR, flexStrategy.ALLOCATOR_ROLE()
            )
        );

        flexStrategy.deposit(deposit, ALLOCATOR);
    }

    function test_deposit_revertWhenNoAccountingModule() public {
        // write zero address to accountingModule
        stdstore.target(address(flexStrategy)).sig("accountingModule()").checked_write(address(0));

        vm.startPrank(ALLOCATOR);
        vm.expectRevert(IFlexStrategy.NoAccountingModule.selector);
        flexStrategy.deposit(1e18, ALLOCATOR);
    }

    // ProcessAccounting

    function testFuzz_processAccounting_success(uint128 deposit) public {
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);
        uint256 sharePriceBefore = flexStrategy.convertToAssets(flexStrategy.balanceOf(ALLOCATOR));

        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should match deposit");
        assertEq(flexStrategy.totalAssets(), deposit, "Total assets should match deposit amount");
        flexStrategy.processAccounting();
        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should remain unchanged");
        assertEq(
            flexStrategy.totalAssets(), deposit, "Total assets should remain unchanged after processing accounting"
        );
        assertEq(
            flexStrategy.convertToAssets(flexStrategy.balanceOf(ALLOCATOR)),
            sharePriceBefore,
            "Share price should remain unchanged after processing accounting"
        );
    }

    function testFuzz_processAccounting_successWhenProcessingRewards(uint128 deposit) public {
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);

        uint128 maxRewards = uint128(
            uint256(accountingModule.targetApy()) * deposit / accountingModule.DIVISOR() / accountingModule.YEAR()
        );

        uint128 rewards = maxRewards;

        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        uint256 shares = flexStrategy.balanceOf(ALLOCATOR);
        uint256 sharePriceBefore = flexStrategy.convertToAssets(shares);
        accountingModule.processRewards(rewards);
        assertGt(flexStrategy.convertToAssets(shares), sharePriceBefore, "Share price should increase");
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

    function testFuzz_processAccounting_successWhenProcessingLosses(uint128 deposit) public {
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);

        uint128 maxLosses = uint128((deposit * uint256(accountingModule.lowerBound()) / accountingModule.DIVISOR()));
        uint128 losses = maxLosses;

        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        uint256 shares = flexStrategy.balanceOf(ALLOCATOR);
        uint256 sharePriceBefore = flexStrategy.convertToAssets(shares);
        accountingModule.processLosses(losses);
        assertLt(flexStrategy.convertToAssets(shares), sharePriceBefore, "Share price should decrease");
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

    function testFuzz_processAccounting_preventsRewardsExceedingTargetApy(uint128 deposit) public {
        /**
         * Issues:
         *         1. The stragegy has a cooldown set to 1 hour but it's always checking amount per day.
         *         You  can boostrap it to the right amount (1 day) but you still have thie issue that
         *         if set to a different value it messes up how much APY can accumulate.
         *         Example: if cooldown is 1 hour, i can call it 24 times each day, and exceed targetAPY by 24x,
         *                  so the limit is defeated.
         *
         *         2.  The DENOMINATOR is too low precision. say there's a target APY of 10% so 1000.
         *             The most forgiving interpretation here is that you calculate 1 targetAPY per day.
         *             1000 / 365 = 2.74. the uint256 division in solidity rounds down so you'l get 2.
         *             That's a 27% delta from the desired limit. A per/hour APY limit is not even representable
         *             with this precison.
         *
         *         3.  the Variable is called targetAPY but that's not what it is. it is actually APR.
         *             So assuming all the other issues are perfectly fixed, setting it to 15% (APR) means you're
         * capping at 16%+ APY per year.
         *
         *         4.  Assuming all other issues addressed, The approach can still be operationally difficult.
         *             Assume that you have  a per day targetAPY value. if rewards are not processed for multiple days
         * in a row,
         *             You've essentially missed slots, and you potentially can't reach targetAPY because it does not
         * factor
         *             in how much time passed since last processRewards.
         */
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);

        uint128 maxRewards = uint128(
            uint256(accountingModule.targetApy()) * deposit / accountingModule.DIVISOR() / accountingModule.YEAR()
        );

        uint128 rewards = maxRewards;

        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ACCOUNTING_PROCESSOR);
        uint256 shares = flexStrategy.balanceOf(ALLOCATOR);
        uint256 sharePriceBefore = flexStrategy.convertToAssets(shares);
        accountingModule.processRewards(rewards);
        assertGt(flexStrategy.convertToAssets(shares), sharePriceBefore, "Share price should increase");

        // Advance time by 2 hours to simulate time passing for APY calculations
        vm.warp(block.timestamp + 2 hours);

        // Try to process rewards again - should revert due to APY limit
        vm.expectRevert();
        accountingModule.processRewards(rewards);
    }

    // Withdraw
    function test_withdraw_invalidAsset() public {
        uint128 deposit = 100e18;
        vm.prank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ADMIN);
        // break invariant via bad settings
        MockERC20 wrongAsset = new MockERC20("WRONG", "WRONG", 18);
        MultiFixedRateProvider provider2 = new MultiFixedRateProvider();
        provider2.addAsset(address(mockErc20));

        // we need the wrong asset to be in provider to break invariant
        provider2.addAsset(address(wrongAsset));
        flexStrategy.setProvider(address(provider2));

        vm.startPrank(ALLOCATOR);
        vm.expectRevert(IVault.AssetNotActive.selector);
        flexStrategy.depositAsset(address(wrongAsset), 100, ALLOCATOR);

        // bad settings to break invariant on withdraw
        vm.startPrank(SAFE);
        wrongAsset.mint(10_000e18);

        vm.startPrank(ADMIN);
        assertEq(flexStrategy.maxWithdrawAsset(address(wrongAsset), ALLOCATOR), 0);
        flexStrategy.setAssetWithdrawable(address(wrongAsset), true);
        assertEq(flexStrategy.maxWithdrawAsset(address(wrongAsset), ALLOCATOR), 100);

        vm.startPrank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidAsset.selector, address(wrongAsset)));
        flexStrategy.withdrawAsset(address(wrongAsset), 100, WITHDRAW_RECEIVER, ALLOCATOR);
    }

    function testFuzz_withdraw_revertIfNotOwnerAndNoAllowance(uint128 deposit) public {
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);

        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(WITHDRAW_RECEIVER);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                WITHDRAW_RECEIVER,
                flexStrategy.ALLOCATOR_ROLE()
            )
        );
        flexStrategy.withdraw(deposit, WITHDRAW_RECEIVER, ALLOCATOR);

        vm.startPrank(ADMIN);
        flexStrategy.grantRole(flexStrategy.ALLOCATOR_ROLE(), WITHDRAW_RECEIVER);

        vm.startPrank(WITHDRAW_RECEIVER);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, WITHDRAW_RECEIVER, 0, deposit)
        );
        flexStrategy.withdraw(deposit, WITHDRAW_RECEIVER, ALLOCATOR);
    }

    function testFuzz_withdraw_revertIfAssetNotWithdrawable(uint128 deposit) public {
        vm.assume(deposit > 10 ** accountingToken.decimals() && deposit < type(uint128).max / 2);
        vm.startPrank(ADMIN);
        flexStrategy.setAssetWithdrawable(address(mockErc20), false);

        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxWithdraw.selector, ALLOCATOR, deposit, 0));
        flexStrategy.withdraw(deposit, ALLOCATOR, ALLOCATOR);
    }

    function testFuzz_withdraw_revertIfInvariantViolation(uint128 deposit) public {
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        // break invariant by minting some accountingTokens to strategy
        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(address(flexStrategy), 1e18);

        vm.startPrank(ALLOCATOR);
        vm.expectRevert(IFlexStrategy.InvariantViolation.selector);
        flexStrategy.withdraw(deposit, WITHDRAW_RECEIVER, ALLOCATOR);
    }

    function testFuzz_withdraw_whenFundsAreInSafe_success(uint128 deposit) public {
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ALLOCATOR);
        flexStrategy.withdraw(deposit, WITHDRAW_RECEIVER, ALLOCATOR);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after withdrawal");
        assertEq(mockErc20.balanceOf(WITHDRAW_RECEIVER), deposit, "Receiver balance should be correct after withdrawal");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            0,
            "Strategy accountingToken balance should be correct after withdrawal"
        );
        assertEq(IERC20(address(flexStrategy)).balanceOf(ALLOCATOR), 0, "Allocator should have correct strategy shares");
        assertEq(mockErc20.balanceOf(SAFE), 0, "Safe should have correct deposit");
    }

    function testFuzz_withdraw_whenFundsAreInFarm_success(uint128 deposit) public {
        vm.assume(deposit > 0 && deposit < type(uint128).max / 2);
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(SAFE);
        // sim yield farming
        uint128 depositAmountIntoFarm = uint128(deposit * uint256(9) / 10); // deposit 90% to yield farm
        uint128 someAmountOfYield = uint128(deposit / uint256(10_000)); // some rewards, 0.0001% of deposit
        mockErc20.transfer(YIELD_FARM, depositAmountIntoFarm);
        mockErc20.mint(someAmountOfYield);

        uint256 accountTokensBefore = accountingToken.balanceOf(address(flexStrategy));
        uint256 sharesBefore = IERC20(address(flexStrategy)).balanceOf(ALLOCATOR);
        vm.startPrank(ALLOCATOR);
        uint128 expectedMaxWithdraw = deposit - depositAmountIntoFarm + someAmountOfYield;
        uint128 actualMaxWithdraw = uint128(flexStrategy.maxWithdrawAsset(address(mockErc20), ALLOCATOR));
        assertEq(expectedMaxWithdraw, actualMaxWithdraw);

        uint256 withdrawAmount = actualMaxWithdraw;
        flexStrategy.withdraw(withdrawAmount, WITHDRAW_RECEIVER, ALLOCATOR);

        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after withdrawal");
        assertEq(
            mockErc20.balanceOf(WITHDRAW_RECEIVER),
            withdrawAmount,
            "Receiver balance should be correct after withdrawal"
        );
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            accountTokensBefore - withdrawAmount,
            "Strategy accountingToken balance should be correct after withdrawal"
        );
        assertEq(
            IERC20(address(flexStrategy)).balanceOf(ALLOCATOR),
            sharesBefore - flexStrategy.convertToShares(withdrawAmount),
            "Allocator should have correct strategy shares"
        );
        assertEq(mockErc20.balanceOf(SAFE), 0, "Safe should have correct deposit");
        assertEq(mockErc20.balanceOf(YIELD_FARM), depositAmountIntoFarm, "Yield farm should have correct deposit");
    }

    function testFuzz_withdraw_revertIfNotAllocator(uint128 deposit) public {
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ADMIN);
        flexStrategy.revokeRole(flexStrategy.ALLOCATOR_ROLE(), ALLOCATOR);

        vm.startPrank(ALLOCATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALLOCATOR, flexStrategy.ALLOCATOR_ROLE()
            )
        );
        flexStrategy.withdraw(deposit, ALLOCATOR, ALLOCATOR);
    }

    function testFuzz_availableAssets_returnsSafeBalance(uint128 assetBalance) public {
        vm.prank(SAFE);
        mockErc20.mint(assetBalance);

        assertEq(flexStrategy.totalAssets(), 0, "Total assets should be 0 when no deposits made");
        assertEq(flexStrategy.computeTotalAssets(), 0, "Computed total assets should be 0 when no deposits made");
    }

    function testFuzz_mint_success(uint128 deposit) public {
        uint256 balanceBefore = mockErc20.balanceOf(ALLOCATOR);
        vm.startPrank(ALLOCATOR);
        flexStrategy.mint(deposit, ALLOCATOR);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after deposit");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            deposit,
            "Strategy should have correct accountingToken balance after deposit"
        );
        assertEq(
            mockErc20.balanceOf(ALLOCATOR),
            balanceBefore - deposit,
            "Allocator balance should decrease by deposit amount"
        );
        assertEq(
            IERC20(address(flexStrategy)).balanceOf(ALLOCATOR), deposit, "Allocator should have correct strategy shares"
        );
        assertEq(mockErc20.balanceOf(SAFE), deposit, "Safe should have correct deposit");
        assertEq(flexStrategy.computeTotalAssets(), deposit, "Computed total assets should match deposit");
        assertEq(flexStrategy.totalAssets(), deposit, "Total assets should match deposit");
    }

    function testFuzz_redeem_whenFundsAreInSafe_success(uint128 deposit) public {
        vm.startPrank(ALLOCATOR);
        flexStrategy.deposit(deposit, ALLOCATOR);

        vm.startPrank(ALLOCATOR);
        flexStrategy.withdraw(deposit, WITHDRAW_RECEIVER, ALLOCATOR);
        assertEq(mockErc20.balanceOf(address(flexStrategy)), 0, "Strategy should not hold any assets after withdrawal");
        assertEq(mockErc20.balanceOf(WITHDRAW_RECEIVER), deposit, "Receiver balance should be correct after withdrawal");
        assertEq(
            accountingToken.balanceOf(address(flexStrategy)),
            0,
            "Strategy accountingToken balance should be correct after withdrawal"
        );
        assertEq(IERC20(address(flexStrategy)).balanceOf(ALLOCATOR), 0, "Allocator should have correct strategy shares");
        assertEq(mockErc20.balanceOf(SAFE), 0, "Safe should have correct deposit");
    }
}
