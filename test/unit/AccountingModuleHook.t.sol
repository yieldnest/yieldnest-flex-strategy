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
            address(this), // safe (mocked as this contract)
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
            address(this), // vault_ (mocked as this contract)
            IAccountingModule(address(accountingModule)),
            address(mockStrategy)
        );
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

    function test_afterMint_called_by_RandomAddress_reverts() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        accountingModuleHook.afterMint(
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
}
