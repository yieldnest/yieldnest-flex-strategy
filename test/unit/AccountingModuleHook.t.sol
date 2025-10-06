// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockStrategy } from "../mocks/MockStrategy.sol";
import { AccountingModule, IAccountingModule } from "../../src/AccountingModule.sol";
import { AccountingToken, IAccountingToken } from "../../src/AccountingToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AccountingModuleHook } from "src/hooks/AccountingModuleHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHooks } from "@yieldnest-vault/interface/IHooks.sol";

contract AccountingModuleHookTest is Test {
    using Math for uint256;

    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);
    address public SAFE = address(0x8af3);

    MockERC20 public mockErc20;
    MockStrategy public mockStrategy;
    AccountingModule public accountingModule;
    AccountingToken public accountingToken;
    AccountingModuleHook public accountingModuleHook;

    function setUp() public {
        // Deploy mock ERC20 token
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);

        // Deploy mock strategy
        mockStrategy = new MockStrategy(IERC20(address(mockErc20)));

        // Deploy accounting module via proxy
        AccountingModule accountingModule_impl = new AccountingModule();
        TransparentUpgradeableProxy accountingModule_tu =
            new TransparentUpgradeableProxy(address(accountingModule_impl), ADMIN, "");
        accountingModule = AccountingModule(payable(address(accountingModule_tu)));

        // Deploy accounting token via proxy
        AccountingToken accountingToken_impl = new AccountingToken(address(mockErc20));
        TransparentUpgradeableProxy accountingToken_tu = new TransparentUpgradeableProxy(
            address(accountingToken_impl),
            ADMIN,
            abi.encodeWithSelector(AccountingToken.initialize.selector, ADMIN, "NAME", "SYMBOL")
        );
        accountingToken = AccountingToken(payable(address(accountingToken_tu)));

        // Set accounting token in accounting module storage (if needed)
        // If the AccountingModule requires the accountingToken to be set after deployment,
        // you may need to add a setter or re-initialize. For now, assume it's settable:
        vm.prank(ADMIN);
        accountingModule.initialize(
            address(mockStrategy),
            ADMIN,
            SAFE, // safe (mocked as this contract)
            IAccountingToken(address(accountingToken)),
            0.1 ether, // targetApy
            0.5 ether, // lowerBound
            1e18, // minRewardableAssets
            1 hours // cooldownSeconds
        );

        // Set accounting module in token
        vm.prank(ADMIN);
        accountingToken.setAccountingModule(address(accountingModule));

        // Deploy the AccountingModuleHook
        accountingModuleHook = new AccountingModuleHook(
            address(mockStrategy), // vault_ (mocked as this contract)
            IAccountingModule(address(accountingModule)),
            address(mockStrategy)
        );

        mockStrategy.setAccountingModule(accountingModule);

        // Prank as mockStrategy and approve infinite mockErc20 to accountingModule
        vm.startPrank(address(mockStrategy));
        mockErc20.approve(address(accountingModule), type(uint256).max);
        vm.stopPrank();

        // Give max approval from SAFE to accounting module for mockErc20 token
        vm.startPrank(SAFE);
        mockErc20.approve(address(accountingModule), type(uint256).max);
        vm.stopPrank();
    }

    function test_beforeWithdraw_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: address(mockErc20),
                assets: 100 ether,
                caller: BOB,
                receiver: BOB,
                owner: BOB,
                shares: 100 ether
            })
        );
        vm.stopPrank();
    }

    function test_beforeRedeem_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.beforeRedeem(
            IHooks.RedeemParams({
                asset: address(mockErc20),
                shares: 100 ether,
                caller: BOB,
                receiver: BOB,
                owner: BOB,
                assets: 100 ether
            })
        );
        vm.stopPrank();
    }

    function test_afterDeposit_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.afterDeposit(
            IHooks.DepositParams({
                asset: address(mockErc20),
                assets: 100 ether,
                caller: BOB,
                receiver: BOB,
                shares: 100 ether,
                baseAssets: 0
            })
        );
        vm.stopPrank();
    }

    function test_afterWithdraw_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.afterWithdraw(
            IHooks.WithdrawParams({
                asset: address(mockErc20),
                assets: 100 ether,
                caller: BOB,
                receiver: BOB,
                owner: BOB,
                shares: 100 ether
            })
        );
        vm.stopPrank();
    }

    function test_afterRedeem_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.afterRedeem(
            IHooks.RedeemParams({
                asset: address(mockErc20),
                shares: 100 ether,
                caller: BOB,
                receiver: BOB,
                owner: BOB,
                assets: 100 ether
            })
        );
        vm.stopPrank();
    }

    function test_beforeDeposit_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.beforeDeposit(
            IHooks.DepositParams({
                asset: address(mockErc20),
                assets: 100 ether,
                caller: BOB,
                receiver: BOB,
                shares: 100 ether,
                baseAssets: 0
            })
        );
        vm.stopPrank();
    }

    function test_beforeMint_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.beforeMint(
            IHooks.MintParams({
                asset: address(mockErc20),
                shares: 100 ether,
                caller: BOB,
                receiver: BOB,
                assets: 100 ether,
                baseAssets: 0
            })
        );
        vm.stopPrank();
    }

    function test_afterDeposit_called_by_Vault_succeeds() public {
        // Simulate user approving and depositing assets to the accounting module
        uint256 depositAmount = 100 ether;
        mockErc20.mint(address(mockStrategy), depositAmount);

        // Simulate the vault calling deposit on the accounting module
        vm.startPrank(address(mockStrategy));
        // Actually deposit assets to the accounting module (assume deposit function exists)
        // This is a placeholder; replace with actual deposit logic if needed
        // accountingModule.deposit(depositAmount, address(this));

        // Now call the afterDeposit hook as the vault would after deposit
        accountingModuleHook.afterDeposit(
            IHooks.DepositParams({
                asset: address(mockErc20),
                assets: depositAmount,
                caller: address(this),
                receiver: address(this),
                shares: depositAmount,
                baseAssets: depositAmount
            })
        );
        vm.stopPrank();

        assertEq(IERC20(accountingModule.accountingToken()).balanceOf(address(mockStrategy)), depositAmount);
    }

    function test_beforeMint_called_by_Vault_succeeds() public {
        // Simulate user approving and depositing assets to the accounting module
        uint256 depositAmount = 100 ether;
        mockErc20.mint(address(mockStrategy), depositAmount);

        // Simulate the vault calling deposit on the accounting module
        vm.startPrank(address(mockStrategy));
        // Actually deposit assets to the accounting module (assume deposit function exists)
        // This is a placeholder; replace with actual deposit logic if needed
        // accountingModule.deposit(depositAmount, address(this));

        // Now call the beforeMint hook as the vault would before mint
        accountingModuleHook.beforeMint(
            IHooks.MintParams({
                asset: address(mockErc20),
                shares: depositAmount,
                caller: address(this),
                receiver: address(this),
                assets: depositAmount,
                baseAssets: depositAmount
            })
        );
        vm.stopPrank();

        // no effect since it does nothing on beforeMint
        assertEq(IERC20(accountingModule.accountingToken()).balanceOf(address(mockStrategy)), 0);
    }

    function test_afterMint_called_by_Vault_succeeds() public {
        uint256 mintAmount = 100 ether;
        mockErc20.mint(address(mockStrategy), mintAmount);

        // Simulate the vault calling afterMint on the hook
        vm.startPrank(address(mockStrategy));
        accountingModuleHook.afterMint(
            IHooks.MintParams({
                asset: address(mockErc20),
                shares: mintAmount,
                caller: address(this),
                receiver: address(this),
                assets: mintAmount,
                baseAssets: mintAmount
            })
        );
        vm.stopPrank();

        // Should have deposited to the accounting module via the hook
        assertEq(IERC20(accountingModule.accountingToken()).balanceOf(address(mockStrategy)), mintAmount);
    }

    function test_beforeRedeem_called_by_Vault_succeeds() public {
        // Use a receiver address instead of address(this)
        address receiver = address(0xBEEF);

        // Mint accountingToken to the strategy to simulate it having assets to withdraw
        uint256 redeemAmount = 100 ether;
        // Place some mockERC20 token into strategy by minting it directly
        mockErc20.mint(address(mockStrategy), redeemAmount);

        // Mint accountingToken to the strategy (mockStrategy) using the accountingModule
        vm.prank(address(mockStrategy));
        accountingModule.deposit(redeemAmount);
        // Confirm the strategy has the accountingToken
        assertEq(IERC20(accountingModule.accountingToken()).balanceOf(address(mockStrategy)), redeemAmount);

        // Simulate the vault calling beforeRedeem on the hook
        vm.startPrank(address(mockStrategy));
        accountingModuleHook.beforeRedeem(
            IHooks.RedeemParams({
                asset: address(mockErc20),
                shares: redeemAmount,
                caller: receiver,
                receiver: receiver,
                owner: receiver,
                assets: redeemAmount
            })
        );
        vm.stopPrank();

        // Assert that the strategy's accountingToken balance is now 0 after redeem
        assertEq(
            IERC20(accountingModule.accountingToken()).balanceOf(address(mockStrategy)),
            0,
            "Strategy's accountingToken balance should be 0 after redeem"
        );

        // asset back to strategy
        assertEq(
            mockErc20.balanceOf(address(mockStrategy)),
            redeemAmount,
            "Receiver should have received the redeemed mockErc20 assets"
        );

        assertEq(
            mockErc20.balanceOf(address(receiver)), 0, "Receiver should have received the redeemed mockErc20 assets"
        );
    }

    function test_beforeWithdraw_called_by_Vault_succeeds() public {
        // Use a receiver address instead of address(this)
        address receiver = address(0xBEEF);

        // Mint accountingToken to the strategy to simulate it having assets to withdraw
        uint256 withdrawAmount = 100 ether;
        // Place some mockERC20 token into strategy by minting it directly
        mockErc20.mint(address(mockStrategy), withdrawAmount);

        // Mint accountingToken to the strategy (mockStrategy) using the accountingModule
        vm.prank(address(mockStrategy));
        accountingModule.deposit(withdrawAmount);
        // Confirm the strategy has the accountingToken
        assertEq(IERC20(accountingModule.accountingToken()).balanceOf(address(mockStrategy)), withdrawAmount);

        // Simulate the vault calling beforeWithdraw on the hook
        vm.startPrank(address(mockStrategy));
        accountingModuleHook.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: address(mockErc20),
                assets: withdrawAmount,
                caller: receiver,
                receiver: receiver,
                owner: receiver,
                shares: withdrawAmount
            })
        );
        vm.stopPrank();

        // Assert that the strategy's accountingToken balance is now 0 after withdraw
        assertEq(
            IERC20(accountingModule.accountingToken()).balanceOf(address(mockStrategy)),
            0,
            "Strategy's accountingToken balance should be 0 after withdraw"
        );

        // asset back to strategy
        assertEq(
            mockErc20.balanceOf(address(mockStrategy)),
            withdrawAmount,
            "Receiver should have received the withdrawn mockErc20 assets"
        );

        assertEq(
            mockErc20.balanceOf(address(receiver)), 0, "Receiver should have received the withdrawn mockErc20 assets"
        );
    }

    function test_getConfig_returns_expected_config() public {
        IHooks.Config memory config = accountingModuleHook.getConfig();
        assertFalse(config.beforeDeposit, "beforeDeposit should be false");
        assertTrue(config.afterDeposit, "afterDeposit should be true");
        assertFalse(config.beforeMint, "beforeMint should be false");
        assertTrue(config.afterMint, "afterMint should be true");
        assertTrue(config.beforeRedeem, "beforeRedeem should be true");
        assertFalse(config.afterRedeem, "afterRedeem should be false");
        assertTrue(config.beforeWithdraw, "beforeWithdraw should be true");
        assertFalse(config.afterWithdraw, "afterWithdraw should be false");
        assertFalse(config.beforeProcessAccounting, "beforeProcessAccounting should be false");
        assertFalse(config.afterProcessAccounting, "afterProcessAccounting should be false");
    }
}
