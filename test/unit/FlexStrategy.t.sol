// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { FlexStrategy } from "../../src/FlexStrategy.sol";

contract FlexStrategyTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);

    MockERC20 public mockErc20;
    FlexStrategy public flexStrategy;

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);

        FlexStrategy implementation = new FlexStrategy();
        bytes memory initData =
            abi.encodeWithSelector(FlexStrategy.initialize.selector, ADMIN, "FlexStrategy", "FLEX", mockErc20);

        TransparentUpgradeableProxy tu = new TransparentUpgradeableProxy(address(implementation), ADMIN, initData);

        flexStrategy = FlexStrategy(payable(address(tu)));

        vm.startPrank(ADMIN);
        flexStrategy.grantRole(flexStrategy.ASSET_MANAGER_ROLE(), ADMIN);
        flexStrategy.addAsset(address(mockErc20), true, true); // base asset
    }

    function test_setup_success() public view {
        assertEq(flexStrategy.name(), "FlexStrategy");
        assertEq(flexStrategy.symbol(), "FLEX");
    }

    function test_setAccountingModule_revertIfZeroAddress() public view { }

    function test_setAccountingModule_setRelevantApprovals() public view { }
    function test_setAccountingModule_revokeRelevantApprovals() public view { }

    function test_deposit_revertIfNotBaseAsset() public view { }
    function test_deposit_revertIfNoAccountingModule() public view { }

    function test_withdraw_revertIfNotBaseAsset() public view { }
    function test_withdraw_revertIfNoAccountingModule() public view { }
}
