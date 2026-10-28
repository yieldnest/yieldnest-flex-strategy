// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test, stdError } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "lib/solady/src/utils/FixedPointMathLib.sol";
import { FixedAPYAccrual } from "src/yield/FixedAPYAccrual.sol";

contract CalculateRewardsTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_APY = 10e18;
    uint256 internal constant YEAR = 365.25 days;
    uint256 internal constant MAX_BALANCE = 1e36;

    FixedAPYAccrual internal accrual;

    function setUp() public {
        // The pure entry point needs neither a proxy nor an accounting module.
        accrual = new FixedAPYAccrual();
    }

    // Concrete examples use 1,000 tokens with 18 decimals. Expected values are rewards only.
    // Half-year expectations were independently calculated as 1,000 * (sqrt(1 + APY) - 1)
    // with 70-digit decimal precision, then floored to wei. Allow 100,000 wei (1e-13 tokens)
    // for the fixed-point log/exp approximation, including at the two-year horizon.
    function test_calculateRewards_tenPercentAPY() public view {
        assertApproxEqAbs(
            accrual.calculateRewards(1000e18, YEAR / 2, 0.1e18, YEAR), 48_808_848_170_151_546_991, 100_000
        );
        assertApproxEqAbs(accrual.calculateRewards(1000e18, YEAR, 0.1e18, YEAR), 100e18, 100_000);
        assertApproxEqAbs(accrual.calculateRewards(1000e18, 2 * YEAR, 0.1e18, YEAR), 210e18, 100_000);
    }

    function test_calculateRewards_elevenPercentAPY() public view {
        assertApproxEqAbs(
            accrual.calculateRewards(1000e18, YEAR / 2, 0.11e18, YEAR), 53_565_375_285_273_884_840, 100_000
        );
        assertApproxEqAbs(accrual.calculateRewards(1000e18, YEAR, 0.11e18, YEAR), 110e18, 100_000);
        assertApproxEqAbs(accrual.calculateRewards(1000e18, 2 * YEAR, 0.11e18, YEAR), 232.1e18, 100_000);
    }

    function test_calculateRewards_fivePercentAPY() public view {
        assertApproxEqAbs(
            accrual.calculateRewards(1000e18, YEAR / 2, 0.05e18, YEAR), 24_695_076_595_959_838_322, 100_000
        );
        assertApproxEqAbs(accrual.calculateRewards(1000e18, YEAR, 0.05e18, YEAR), 50e18, 100_000);
        assertApproxEqAbs(accrual.calculateRewards(1000e18, 2 * YEAR, 0.05e18, YEAR), 102.5e18, 100_000);
    }

    function test_calculateRewards_oneHundredPercentAPY() public view {
        assertApproxEqAbs(accrual.calculateRewards(1000e18, YEAR / 2, 1e18, YEAR), 414_213_562_373_095_048_801, 100_000);
        assertApproxEqAbs(accrual.calculateRewards(1000e18, YEAR, 1e18, YEAR), 1000e18, 100_000);
        assertApproxEqAbs(accrual.calculateRewards(1000e18, 2 * YEAR, 1e18, YEAR), 3000e18, 100_000);
    }

    function test_calculateRewards_pointOnePercentAPY() public view {
        assertApproxEqAbs(accrual.calculateRewards(1000e18, YEAR / 2, 0.001e18, YEAR), 499_875_062_460_964_823, 100_000);
        assertApproxEqAbs(accrual.calculateRewards(1000e18, YEAR, 0.001e18, YEAR), 1e18, 100_000);
        assertApproxEqAbs(accrual.calculateRewards(1000e18, 2 * YEAR, 0.001e18, YEAR), 2.001e18, 100_000);
    }

    function testFuzz_calculateRewards_zeroBalance(uint256 elapsed, uint256 apy, uint256 year) public view {
        assertEq(accrual.calculateRewards(0, elapsed, bound(apy, 0, MAX_APY), bound(year, 1, type(uint256).max)), 0);
    }

    function testFuzz_calculateRewards_zeroAPY(uint256 balance, uint256 elapsed, uint256 year) public view {
        assertEq(accrual.calculateRewards(balance, elapsed, 0, bound(year, 1, type(uint256).max)), 0);
    }

    function testFuzz_calculateRewards_zeroElapsed(uint256 balance, uint256 apy, uint256 year) public view {
        assertEq(accrual.calculateRewards(balance, 0, bound(apy, 0, MAX_APY), bound(year, 1, type(uint256).max)), 0);
    }

    function testFuzz_calculateRewards_invalidYear(uint256 balance, uint256 elapsed, uint256 apy) public {
        // Year validation precedes both APY validation and the zero-input shortcuts.
        vm.expectRevert(FixedAPYAccrual.InvalidYear.selector);
        accrual.calculateRewards(balance, elapsed, apy, 0);
        vm.expectRevert(FixedAPYAccrual.InvalidYear.selector);
        accrual.calculateRewards(0, 0, apy, 0);
    }

    function testFuzz_calculateRewards_invalidAPY(uint256 balance, uint256 elapsed, uint256 apy, uint256 year) public {
        apy = bound(apy, MAX_APY + 1, type(uint256).max);
        year = bound(year, 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(FixedAPYAccrual.InvalidAPY.selector, apy));
        accrual.calculateRewards(balance, elapsed, apy, year);
        vm.expectRevert(abi.encodeWithSelector(FixedAPYAccrual.InvalidAPY.selector, apy));
        accrual.calculateRewards(0, 0, apy, year);
    }

    function testFuzz_calculateRewards_oneYear(uint256 balance, uint256 apy, uint256 year) public view {
        balance = bound(balance, 1, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        year = bound(year, 1, type(uint256).max);
        uint256 expected = balance * apy / WAD;
        _assertRewardsClose(accrual.calculateRewards(balance, year, apy, year), expected, balance);
    }

    function testFuzz_calculateRewards_integerYears(uint256 balance, uint256 apy, uint256 yearsElapsed) public view {
        balance = bound(balance, 1, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        yearsElapsed = bound(yearsElapsed, 1, 10);
        // Independent oracle: repeated multiplication, without logarithms or powWad.
        uint256 growth = WAD;
        for (uint256 i; i < yearsElapsed; ++i) {
            growth = growth * (WAD + apy) / WAD;
        }
        uint256 expected = balance * (growth - WAD) / WAD;
        _assertRewardsClose(accrual.calculateRewards(balance, yearsElapsed * YEAR, apy, YEAR), expected, balance);
    }

    function testFuzz_calculateRewards_halfYear(uint256 balance, uint256 apy, uint256 halfYear) public view {
        balance = bound(balance, 1, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        halfYear = bound(halfYear, 1, type(uint256).max / 2);
        // sqrt((1 + APY) * WAD) gives the half-year growth in WAD without powWad.
        uint256 growth = Math.sqrt((WAD + apy) * WAD);
        uint256 expected = balance * (growth - WAD) / WAD;
        _assertRewardsClose(accrual.calculateRewards(balance, halfYear, apy, 2 * halfYear), expected, balance);
    }

    function testFuzz_calculateRewards_maxAPY(uint256 balance) public view {
        balance = bound(balance, 1, MAX_BALANCE);
        _assertRewardsClose(accrual.calculateRewards(balance, YEAR, MAX_APY, YEAR), 10 * balance, balance);
        _assertRewardsClose(accrual.calculateRewards(balance, 2 * YEAR, MAX_APY, YEAR), 120 * balance, balance);
    }

    function testFuzz_calculateRewards_monotonicBalance(
        uint256 low,
        uint256 high,
        uint256 apy,
        uint256 elapsed
    )
        public
        view
    {
        low = bound(low, 0, MAX_BALANCE);
        high = bound(high, low, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        elapsed = bound(elapsed, 0, 10 * YEAR);
        assertLe(accrual.calculateRewards(low, elapsed, apy, YEAR), accrual.calculateRewards(high, elapsed, apy, YEAR));
    }

    function testFuzz_calculateRewards_monotonicAPY(
        uint256 balance,
        uint256 low,
        uint256 high,
        uint256 elapsed
    )
        public
        view
    {
        balance = bound(balance, 0, MAX_BALANCE);
        low = bound(low, 0, MAX_APY);
        high = bound(high, low, MAX_APY);
        elapsed = bound(elapsed, 0, 10 * YEAR);
        assertLe(
            accrual.calculateRewards(balance, elapsed, low, YEAR),
            accrual.calculateRewards(balance, elapsed, high, YEAR)
        );
    }

    function testFuzz_calculateRewards_monotonicTime(
        uint256 balance,
        uint256 apy,
        uint256 low,
        uint256 high
    )
        public
        view
    {
        balance = bound(balance, 0, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        low = bound(low, 0, 10 * YEAR);
        high = bound(high, low, 10 * YEAR);
        assertLe(accrual.calculateRewards(balance, low, apy, YEAR), accrual.calculateRewards(balance, high, apy, YEAR));
    }

    function testFuzz_calculateRewards_timeScaleInvariant(
        uint256 balance,
        uint256 apy,
        uint256 elapsed,
        uint256 year,
        uint256 scale
    )
        public
        view
    {
        balance = bound(balance, 0, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        year = bound(year, 1, YEAR);
        elapsed = bound(elapsed, 0, 10 * year);
        scale = bound(scale, 1, type(uint256).max / Math.max(elapsed, year));
        assertEq(
            accrual.calculateRewards(balance, elapsed * scale, apy, year * scale),
            accrual.calculateRewards(balance, elapsed, apy, year)
        );
    }

    function testFuzz_calculateRewards_balanceAdditivity(
        uint256 a,
        uint256 b,
        uint256 apy,
        uint256 elapsed
    )
        public
        view
    {
        a = bound(a, 0, MAX_BALANCE);
        b = bound(b, 0, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        elapsed = bound(elapsed, 0, 10 * YEAR);
        uint256 separate =
            accrual.calculateRewards(a, elapsed, apy, YEAR) + accrual.calculateRewards(b, elapsed, apy, YEAR);
        uint256 combined = accrual.calculateRewards(a + b, elapsed, apy, YEAR);
        // floor(a*g) + floor(b*g) differs from floor((a+b)*g) by at most one token unit.
        assertGe(combined, separate);
        assertLe(combined - separate, 1);
    }

    function testFuzz_calculateRewards_fractionalYearBounds(uint256 balance, uint256 apy, uint256 elapsed) public view {
        balance = bound(balance, 1, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        elapsed = bound(elapsed, 0, YEAR);
        uint256 rewards = accrual.calculateRewards(balance, elapsed, apy, YEAR);
        // For t in [0,1], convexity gives exp(t*ln(1+a))-1 <= a*t.
        // exp(x)-1 >= x and ln(1+a) >= a/(1+a) give the lower bound a*t/(1+a).
        uint256 linear = (balance * apy / WAD) * elapsed / YEAR;
        uint256 lower = linear * WAD / (WAD + apy);
        uint256 tolerance = _tolerance(linear, balance);
        assertLe(rewards, linear + tolerance);
        assertGe(rewards + tolerance, lower);
    }

    function testFuzz_calculateRewards_splitCompounding(
        uint256 balance,
        uint256 apy,
        uint256 first,
        uint256 second
    )
        public
        view
    {
        balance = bound(balance, 1, MAX_BALANCE);
        apy = bound(apy, 0, MAX_APY);
        first = bound(first, 0, YEAR);
        second = bound(second, 0, YEAR);
        uint256 firstReward = accrual.calculateRewards(balance, first, apy, YEAR);
        uint256 split = firstReward + accrual.calculateRewards(balance + firstReward, second, apy, YEAR);
        uint256 single = accrual.calculateRewards(balance, first + second, apy, YEAR);
        // A discarded token unit in the first settlement can grow by up to 11x in the second.
        assertApproxEqAbs(split, single, _tolerance(single, balance) + 12);
    }

    function testFuzz_calculateRewards_sixDecimalDust(uint256 balance, uint256 apy, uint256 elapsed) public view {
        balance = bound(balance, 1, 1e6);
        apy = bound(apy, 1, WAD);
        elapsed = bound(elapsed, 1, 15);
        // Even at 100% APY, a one-token six-decimal balance earns less than one unit in 15 seconds.
        assertEq(accrual.calculateRewards(balance, elapsed, apy, YEAR), 0);
    }

    function testFuzz_calculateRewards_exponentRoundsToZero(uint256 balance, uint256 apy, uint256 elapsed) public view {
        elapsed = bound(elapsed, 1, type(uint256).max / WAD - 1);
        assertEq(accrual.calculateRewards(balance, elapsed, bound(apy, 1, MAX_APY), elapsed * WAD + 1), 0);
    }

    function testFuzz_calculateRewards_fullPrecisionBalance(uint256 balance) public view {
        // balance * growth exceeds uint256, but the final quotient fits.
        balance = bound(balance, type(uint256).max / WAD + 1, type(uint256).max / 2);
        uint256 rewards = accrual.calculateRewards(balance, YEAR, WAD / 2, YEAR);
        assertApproxEqAbs(rewards, balance / 2, balance / WAD * 100);
    }

    function testFuzz_calculateRewards_exponentMulDivOverflow(uint256 elapsed) public {
        elapsed = bound(elapsed, type(uint256).max / WAD + 1, type(uint256).max);
        vm.expectRevert(Math.MathOverflowedMulDiv.selector);
        accrual.calculateRewards(1, elapsed, 1, 1);
    }

    function testFuzz_calculateRewards_exponentCastOverflow(uint256 elapsed) public {
        elapsed = bound(elapsed, uint256(type(int256).max) + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintToInt.selector, elapsed));
        accrual.calculateRewards(1, elapsed, 1, WAD);
    }

    function testFuzz_calculateRewards_growthOverflow(uint256 balance, uint256 yearsElapsed) public {
        balance = bound(balance, 1, type(uint256).max);
        // ln(11) * 60 exceeds expWad's supported exponent; keep well below signed multiplication overflow.
        yearsElapsed = bound(yearsElapsed, 60, 1_000_000);
        vm.expectRevert(FixedPointMathLib.ExpOverflow.selector);
        accrual.calculateRewards(balance, yearsElapsed * YEAR, MAX_APY, YEAR);
    }

    function testFuzz_calculateRewards_logExponentProductOverflow(uint256 exponent) public {
        // The exponent fits int256, but multiplying it by ln(11) in powWad does not.
        exponent = bound(exponent, uint256(type(int256).max) / WAD + 1, uint256(type(int256).max));
        vm.expectRevert(stdError.arithmeticError);
        accrual.calculateRewards(1, exponent, MAX_APY, WAD);
    }

    function testFuzz_calculateRewards_rewardOverflow(uint256 balance) public {
        balance = bound(balance, type(uint256).max / 2, type(uint256).max);
        vm.expectRevert(Math.MathOverflowedMulDiv.selector);
        accrual.calculateRewards(balance, YEAR, MAX_APY, YEAR);
    }

    function _assertRewardsClose(uint256 actual, uint256 expected, uint256 balance) internal pure {
        assertApproxEqAbs(actual, expected, _tolerance(expected, balance));
    }

    function _tolerance(uint256 expected, uint256 balance) internal pure returns (uint256) {
        // 100 WAD ulps of principal plus 1e-15 of rewards covers log/exp approximation,
        // exponent truncation and repeated-multiplication rounding; one unit covers final flooring.
        return balance * 100 / WAD + expected / 1e15 + 1;
    }
}
