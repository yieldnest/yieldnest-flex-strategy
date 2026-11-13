// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "lib/solady/src/utils/FixedPointMathLib.sol";
import { IAccountingModule } from "../AccountingModule.sol";
import { IFlexStrategy } from "../FlexStrategy.sol";

/**
 * @notice Recognizes compounded fixed-APY yield on a strategy's accounting-token balance.
 * @dev Integration requirements:
 *      - Grant this contract REWARDS_PROCESSOR_ROLE on the accounting module.
 *      - Configure the accounting module with cooldownSeconds = 0
 *      - For deposits and withdrawals into the strategy, atomically call accrue()
 *        before depositing/withdrawing
 *      - For processLosses(), atomically call accrue() first and apply the loss second.
 *      - This contract does not enforce that ordering on other contracts.
 *      - Accounting-module lookup follows strategy rotation. Rotation must preserve the accounting
 *        token and year convention, configure reward permissions and token authority, and settle
 *        before any eligible balance change. The cached year and retained remainder are preserved.
 *      - Raw processRewards() calls do not update lastAccrual and count as yield on top.
 *      - With zero cooldown, repeated accrue() calls at the same timestamp return zero after a
 *        successful settlement, while later timestamps can settle again. Other reporting paths can
 *        still create a same-timestamp snapshot and make a subsequent reward report revert. The
 *        minimum-TVL and snapshot APR checks, including the targetApy cap, remain enforced.
 *      - Accounting uses 18-decimal token amounts regardless of the token's decimals.
 *        Remainder carries over to the next accrual period.
 */
contract FixedAPYAccrual is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    bytes32 public constant APY_MANAGER_ROLE = keccak256("APY_MANAGER_ROLE");

    uint256 public constant WAD = 1e18;
    /// @notice Maximum configurable effective annual yield: 10,000%.
    uint256 public constant MAX_APY = 100 * WAD;

    struct FixedAPYAccrualStorage {
        IFlexStrategy strategy;
        uint256 year;
        uint256 apy;
        uint256 lastAccrual;
        uint256 remainder; // Unminted rewards in 18-decimal token units; appended for storage compatibility.
    }

    bytes32 private constant STORAGE_SLOT = keccak256("yieldnest.storage.fixedAPYAccrualModule");

    error UnsupportedDecimals(uint8 decimals);
    error ZeroAddress();
    error InvalidYear();
    error InvalidAPY(uint256 apy);
    error StartInPast(uint256 startTimestamp);

    event APYUpdated(uint256 oldAPY, uint256 newAPY);
    event YieldAccrued(uint256 fromTimestamp, uint256 toTimestamp, uint256 balance, uint256 rewards);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes a proxy instance. Upgrades are managed by the transparent proxy's admin.
     * @param admin Receives admin and APY-manager roles.
     * @param strategy_ Strategy whose current accounting module receives reward reports.
     * @param apy_ Effective APY scaled by 1e18.
     * @param startTimestamp Accrual start, at or after the initialization timestamp. Backdating is disallowed
     *        because the current balance does not establish historical eligible balances.
     */
    function initialize(address admin, address strategy_, uint256 apy_, uint256 startTimestamp) external initializer {
        if (admin == address(0) || strategy_ == address(0)) revert ZeroAddress();
        if (apy_ > MAX_APY) revert InvalidAPY(apy_);
        if (startTimestamp < block.timestamp) revert StartInPast(startTimestamp);

        __AccessControl_init();
        __ReentrancyGuard_init();

        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        s.strategy = IFlexStrategy(strategy_);
        uint256 year = accountingModule().YEAR();
        if (year == 0) revert InvalidYear();
        s.year = year;
        s.apy = apy_;
        s.lastAccrual = startTimestamp;
        _scale(s); // Validate accounting-token precision.

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(APY_MANAGER_ROLE, admin);
        emit APYUpdated(0, apy_);
    }

    /// @notice Estimates rewards; does not guarantee that the accounting module will accept the report.
    /// @return rewards Mintable rewards in accounting-token units.
    /// @return remainder_ Unminted rewards that would remain after accrual, in 18-decimal token units.
    function previewAccrual() public view returns (uint256 rewards, uint256 remainder_) {
        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        uint256 balance = accountingModule().accountingToken().balanceOf(address(s.strategy));
        uint256 elapsed = block.timestamp - Math.min(block.timestamp, s.lastAccrual);
        return _pendingRewards(s, balance, elapsed);
    }

    /// @notice Anyone can settle yield through now, retaining unmintable fractions at 18 decimals.
    /// @dev Checkpoints even zero rewards so subsequent balance/rate changes are not retroactive.
    function accrue() external nonReentrant returns (uint256 rewards) {
        return _accrue();
    }

    /// @notice Changes APY, optionally settling the old rate first.
    /// @param newAPY Effective annual yield scaled by 1e18.
    /// @param skipAccrue If true, changes the rate without settling or advancing lastAccrual.
    /// @dev NOTE: Skipping accrual applies the new APY to the entire unsettled interval since
    ///      lastAccrual, including time before this rate change. The retained remainder is unchanged.
    ///      If skipAccrue is false, a failed settlement reverts the rate change, even to zero.
    function setAPY(uint256 newAPY, bool skipAccrue) external onlyRole(APY_MANAGER_ROLE) nonReentrant {
        if (newAPY > MAX_APY) revert InvalidAPY(newAPY);
        if (!skipAccrue) _accrue();
        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        emit APYUpdated(s.apy, newAPY);
        s.apy = newAPY;
    }

    function _accrue() internal returns (uint256 rewards) {
        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        uint256 previousAccrual = s.lastAccrual;
        if (block.timestamp <= previousAccrual) return 0;

        uint256 balance = accountingModule().accountingToken().balanceOf(address(s.strategy));
        (rewards, s.remainder) = _pendingRewards(s, balance, block.timestamp - previousAccrual);

        s.lastAccrual = block.timestamp;
        if (rewards != 0) accountingModule().processRewards(rewards);

        emit YieldAccrued(previousAccrual, block.timestamp, balance, rewards);
    }

    function _scale(FixedAPYAccrualStorage storage s) internal view returns (uint256) {
        uint8 decimals = s.strategy.accountingModule().accountingToken().decimals();
        if (decimals > 18) revert UnsupportedDecimals(decimals);
        return 10 ** (18 - decimals);
    }

    function _pendingRewards(
        FixedAPYAccrualStorage storage s,
        uint256 balance,
        uint256 elapsed
    )
        internal
        view
        returns (uint256 rewards, uint256 remainder_)
    {
        uint256 scale = _scale(s);
        uint256 principal = balance * scale + s.remainder;
        uint256 pending = s.remainder + calculateRewards(principal, elapsed, s.apy, s.year);
        return (pending / scale, pending % scale);
    }

    /// @notice Unminted rewards in 18-decimal token units, included in subsequent compounding.
    function remainder() public view returns (uint256) {
        return _getFixedAPYAccrualStorage().remainder;
    }

    /**
     * @notice Calculates compounded rewards without reading contract state.
     * @param balance Eligible accounting-token balance in token units.
     * @param elapsed Elapsed time in seconds.
     * @param apy_ Effective annual yield scaled by 1e18.
     * @param year Seconds per accounting year; must be nonzero.
     * @dev B * ((1 + APY) ** (elapsed / YEAR) - 1), using WAD fixed-point exponentiation.
     *      NOTE: Assumes `balance` was eligible for yield throughout the entire `elapsed` period,
     *      with no intervening deposits, withdrawals, external rewards, or losses.
     */
    function calculateRewards(
        uint256 balance,
        uint256 elapsed,
        uint256 apy_,
        uint256 year
    )
        public
        pure
        returns (uint256)
    {
        if (year == 0) revert InvalidYear();
        if (apy_ > MAX_APY) revert InvalidAPY(apy_);
        if (balance == 0 || apy_ == 0 || elapsed == 0) return 0;

        // exponent = (elapsed / year) * 1e18 (exponent is scaled by 1e18 to be used in the powWad function)
        uint256 exponent = Math.mulDiv(elapsed, WAD, year);
        // growthFactor = (1 + apy_) ** exponent (growth factor is scaled by 1e18)
        int256 growthFactor = FixedPointMathLib.powWad(SafeCast.toInt256(WAD + apy_), SafeCast.toInt256(exponent));
        // growthFactory should always be GE to 1e18 since apy_ is always positive
        // if growthFactor is LE to 1e18, then the rewards are 0
        if (growthFactor <= SafeCast.toInt256(WAD)) return 0;

        // rewards = balance * (growthFactor - 1e18) / 1e18 (dividing by 1e18 since the growth factor is scaled)
        return Math.mulDiv(balance, SafeCast.toUint256(growthFactor) - WAD, WAD);
    }

    /// @notice Strategy whose current accounting module is resolved for each accrual.
    function strategy() public view returns (IFlexStrategy) {
        return _getFixedAPYAccrualStorage().strategy;
    }

    function accountingModule() public view returns (IAccountingModule) {
        return strategy().accountingModule();
    }

    /// @notice Year length in seconds, taken from the accounting module during initialization.
    function YEAR() public view returns (uint256) {
        return _getFixedAPYAccrualStorage().year;
    }

    /// @notice Effective annual yield scaled by 1e18: 0.1e18 means 10% APY.
    function apy() public view returns (uint256) {
        return _getFixedAPYAccrualStorage().apy;
    }

    /// @notice Scheduled start initially; thereafter the timestamp through which accrual is settled.
    function lastAccrual() public view returns (uint256) {
        return _getFixedAPYAccrualStorage().lastAccrual;
    }

    function _getFixedAPYAccrualStorage() internal pure returns (FixedAPYAccrualStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}
