// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";
import { RebasingAccountingToken } from "../../src/RebasingAccountingToken.sol";
import { MockAccountingModule } from "../mocks/MockAccountingModule.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract RebasingAccountingTokenTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public APR_MANAGER = address(0xa91);
    address public ALICE = address(0xa11ce);
    address public BOB = address(0xb0b);

    MockERC20 public mockErc20;
    MockAccountingModule public accountingModule;
    RebasingAccountingToken public accountingToken;

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);
        accountingModule = new MockAccountingModule(address(mockErc20));

        RebasingAccountingToken implementation = new RebasingAccountingToken(address(mockErc20));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            ADMIN,
            abi.encodeWithSelector(AccountingToken.initialize.selector, ADMIN, ADMIN, "NAME", "SYMBOL")
        );
        accountingToken = RebasingAccountingToken(payable(address(proxy)));

        accountingModule.setAccountingToken(address(accountingToken));

        vm.startPrank(ADMIN);
        accountingToken.setAccountingModule(address(accountingModule));
        accountingToken.grantRole(accountingToken.APR_MANAGER_ROLE(), APR_MANAGER);
        vm.stopPrank();
    }

    function test_setup_success() public view {
        assertEq(accountingToken.name(), "NAME");
        assertEq(accountingToken.symbol(), "SYMBOL");
        assertEq(accountingToken.decimals(), 18);
        assertEq(accountingToken.accountingModule(), address(accountingModule));
    }

    function test_setApr_revertIfNotAprManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, accountingToken.APR_MANAGER_ROLE()
            )
        );
        vm.prank(BOB);
        accountingToken.setApr(0.1e18);
    }

    function test_balanceAndSupplyAccrueSmoothlyAtFixedApr() public {
        vm.prank(address(accountingModule));
        accountingToken.mintTo(ALICE, 100e18);

        vm.prank(APR_MANAGER);
        accountingToken.setApr(0.1e18);

        vm.warp(block.timestamp + accountingToken.YEAR() / 2);

        assertEq(accountingToken.balanceOf(ALICE), 105e18);
        assertEq(accountingToken.totalSupply(), 105e18);
        assertEq(accountingToken.sharesOf(ALICE), 100e18);
        assertEq(accountingToken.totalShares(), 100e18);

        vm.warp(block.timestamp + accountingToken.YEAR() / 2);

        assertEq(accountingToken.balanceOf(ALICE), 110e18);
        assertEq(accountingToken.totalSupply(), 110e18);
        assertEq(accountingToken.sharesOf(ALICE), 100e18);
        assertEq(accountingToken.totalShares(), 100e18);
    }

    function test_setApr_checkpointsAccruedSupplyBeforeRateChange() public {
        vm.prank(address(accountingModule));
        accountingToken.mintTo(ALICE, 100e18);

        vm.prank(APR_MANAGER);
        accountingToken.setApr(0.1e18);

        vm.warp(block.timestamp + accountingToken.YEAR());

        vm.prank(APR_MANAGER);
        accountingToken.setApr(0.2e18);

        vm.warp(block.timestamp + accountingToken.YEAR() / 2);

        assertEq(accountingToken.totalSupply(), 121e18);
        assertEq(accountingToken.balanceOf(ALICE), 121e18);
    }

    function test_mintAfterAccrualMintsProportionalShares() public {
        vm.prank(address(accountingModule));
        accountingToken.mintTo(ALICE, 100e18);

        vm.prank(APR_MANAGER);
        accountingToken.setApr(0.1e18);

        vm.warp(block.timestamp + accountingToken.YEAR());

        vm.prank(address(accountingModule));
        accountingToken.mintTo(BOB, 110e18);

        assertEq(accountingToken.sharesOf(ALICE), 100e18);
        assertEq(accountingToken.sharesOf(BOB), 100e18);
        assertEq(accountingToken.totalShares(), 200e18);
        assertEq(accountingToken.balanceOf(ALICE), 110e18);
        assertEq(accountingToken.balanceOf(BOB), 110e18);
        assertEq(accountingToken.totalSupply(), 220e18);
    }

    function test_burnAfterAccrualBurnsProportionalShares() public {
        vm.startPrank(address(accountingModule));
        accountingToken.mintTo(ALICE, 100e18);
        accountingToken.mintTo(BOB, 100e18);
        vm.stopPrank();

        vm.prank(APR_MANAGER);
        accountingToken.setApr(0.1e18);

        vm.warp(block.timestamp + accountingToken.YEAR());

        vm.prank(address(accountingModule));
        accountingToken.burnFrom(BOB, 55e18);

        assertEq(accountingToken.totalSupply(), 165e18);
        assertEq(accountingToken.totalShares(), 150e18);
        assertEq(accountingToken.sharesOf(ALICE), 100e18);
        assertEq(accountingToken.sharesOf(BOB), 50e18);
        assertEq(accountingToken.balanceOf(ALICE), 110e18);
        assertEq(accountingToken.balanceOf(BOB), 55e18);
    }

    function test_mintTo_revertIfNotAccounting() public {
        vm.expectRevert(AccountingToken.Unauthorized.selector);
        accountingToken.mintTo(ALICE, 1e18);
    }

    function test_transfer_revert() public {
        vm.prank(address(accountingModule));
        accountingToken.mintTo(ALICE, 1e18);

        vm.prank(ALICE);
        (bool success, bytes memory revertData) =
            address(accountingToken).call(abi.encodeWithSelector(accountingToken.transfer.selector, BOB, 1e18));

        assertFalse(success);
        assertEq(keccak256(revertData), keccak256(abi.encodeWithSelector(AccountingToken.NotAllowed.selector)));
    }
}
