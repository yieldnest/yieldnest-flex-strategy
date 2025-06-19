// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { AccountingModule } from "src/AccountingModule.sol";

contract CalculateAprTest is Test {
    function testFuzz_calculateApr_success(uint256 depositAmount, uint256 rewardAmount, uint256 timePassed) public {
        AccountingModule accountingModule = new AccountingModule(address(this), address(this));
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);

        // asumed rewards are at least 1e12
        rewardAmount = bound(rewardAmount, 1e12, depositAmount);

        // cooldown time is 1 hour
        timePassed = bound(timePassed, 1 hours, 365 days);

        uint256 previousPricePerShare = 1e18;
        // Price per share after rewards = (deposit + rewards) / deposit * 1e18
        uint256 currentPricePerShare = (depositAmount + rewardAmount) * 1e18 / depositAmount;
        uint256 previousTimestamp = 1000;
        uint256 currentTimestamp = previousTimestamp + timePassed;

        uint256 calculatedApr = accountingModule.calculateApr(
            previousPricePerShare, previousTimestamp, currentPricePerShare, currentTimestamp
        );

        // Verify APR is positive since we added rewards
        assertGt(calculatedApr, 0, "APR should be positive when rewards are added");
        // Verify the calculation matches expected formula:
        // APR = (rewards / deposit) * YEAR / timePassed
        uint256 expectedApr = (rewardAmount * 365.25 days * accountingModule.DIVISOR()) / (depositAmount * timePassed);

        // max delta;  0.0001%
        assertApproxEqRel(calculatedApr, expectedApr, 1e12, "APR calculation should match expected formula");
    }
}
