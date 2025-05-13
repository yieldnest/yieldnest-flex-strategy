// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { AccountingModule } from "../../src/AccountingModule.sol";
import { AccountingToken } from "../../src/AccountingToken.sol";

contract AccountingModuleTest is Test {
    address public ADMIN = address(0xd34db33f);
    address public BOB = address(0x0b0b);
    address public SAFE = address(0x1111);
    MockERC20 public mockErc20;
    AccountingModule public accountingModule;
    AccountingToken public accountingToken;
    uint16 public constant TARGET_APY = 1000;
    uint16 public constant LOWER_BOUND = 1000;

    function setUp() public {
        mockErc20 = new MockERC20("MOCK", "MOCK", 18);
        accountingModule =
            new AccountingModule("NAME", "SYMBOL", ADMIN, address(mockErc20), SAFE, TARGET_APY, LOWER_BOUND);
        accountingToken = accountingModule.ACCOUNTING_TOKEN();
    }

    function test_setupSuccess() public view {
        assertEq(accountingToken.name(), "NAME");
        assertEq(accountingToken.symbol(), "SYMBOL");
        assertEq(accountingToken.decimals(), 18);

        assertEq(accountingModule.targetApy(), TARGET_APY);
        assertEq(accountingModule.lowerBound(), LOWER_BOUND);
    }

    function test_deposit_revertIfNotStrategy() public { }
    function test_deposit_happyPath() public { }

    function test_withdraw_revertIfNotStrategy() public { }
    function test_withdraw_happyPath() public { }

    function test_processRewards_revertIfNotSafeManager() public { }
    function test_processRewards_revertIfTvlTooLow() public { }
    function test_processRewards_revertIfUpperBoundExceed() public { }
    function test_processRewards_revertIfTooEarly() public { }
    function test_processRewards_happyPath() public { }

    function test_processLosses_revertIfNotSafeManager() public { }
    function test_processLosses_revertIfTvlTooLow() public { }
    function test_processLosses_revertIfLowerBoundExceed() public { }
    function test_processLosses_revertIfTooEarly() public { }
    function test_processLosses_happyPath() public { }

    function test_setTargetApy_revertIfNotSafeManager() public { }
    function test_setTargetApy_happyPath() public { }

    function test_setLowerBound_revertIfNotSafeManager() public { }
    function test_setLowerBound_happyPath() public { }

    function test_setCooldownSeconds_revertIfNotSafeManager() public { }
    function test_setCooldownSeconds_happyPath() public { }
}
