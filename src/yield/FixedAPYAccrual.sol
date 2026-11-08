// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "lib/solady/src/utils/FixedPointMathLib.sol";
import { IAccountingModule } from "../AccountingModule.sol";

/**
 * @notice Recognizes compounded fixed-APY yield on a strategy's accounting-token balance.
 * @dev Grant this contract REWARDS_PROCESSOR_ROLE on the accounting module. Integrations must
 *      accrue atomically before deposits/withdrawals are priced and before external rewards or losses
 *      change the accounting balance. This contract does not enforce that ordering on other contracts.
 *      Reporting yield recognizes a claim; it does not transfer underlying assets into the Safe.
 *      The accounting module's cooldown, minimum TVL, and snapshot APR checks still apply and may revert
 *      accrual. Configure those separately for the intended calling frequency and maximum accrual gap.
 */
contract FixedAPYAccrual is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    bytes32 public constant APY_MANAGER_ROLE = keccak256("APY_MANAGER_ROLE");

    uint256 public constant WAD = 1e18;
    /// @notice Maximum configurable effective annual yield: 10,000%.
    uint256 public constant MAX_APY = 100 * WAD;

    struct FixedAPYAccrualStorage {
        IAccountingModule accountingModule;
        uint256 year;
        uint256 apy;
        uint256 lastAccrual;
    }

    bytes32 private constant STORAGE_SLOT = keccak256("yieldnest.storage.fixedAPYAccrualModule");

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
     * @param accountingModule_ Accounting module whose strategy receives the accounting-token rewards.
     * @param apy_ Effective APY scaled by 1e18.
     * @param startTimestamp Accrual start, at or after the initialization timestamp. Backdating is disallowed
     *        because the current balance does not establish historical eligible balances.
     */
    function initialize(
        address admin,
        address accountingModule_,
        uint256 apy_,
        uint256 startTimestamp
    )
        external
        initializer
    {
        if (admin == address(0) || accountingModule_ == address(0)) revert ZeroAddress();
        if (apy_ > MAX_APY) revert InvalidAPY(apy_);
        if (startTimestamp < block.timestamp) revert StartInPast(startTimestamp);

        __AccessControl_init();
        __ReentrancyGuard_init();

        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        s.accountingModule = IAccountingModule(accountingModule_);
        uint256 year = IAccountingModule(accountingModule_).YEAR();
        if (year == 0) revert InvalidYear();
        s.year = year;
        s.apy = apy_;
        s.lastAccrual = startTimestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(APY_MANAGER_ROLE, admin);
        emit APYUpdated(0, apy_);
    }

    /// @notice Estimates rewards; does not guarantee that the accounting module will accept the report.
    function previewAccrual() public view returns (uint256 rewards) {
        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        if (block.timestamp <= s.lastAccrual || s.apy == 0) return 0;
        uint256 balance = s.accountingModule.accountingToken().balanceOf(s.accountingModule.strategy());
        return calculateRewards(balance, block.timestamp - s.lastAccrual, s.apy, s.year);
    }

    /// @notice Anyone can settle yield through now. Zero rewards leave the accrual timestamp unchanged.
    /// @dev An unsettled interval remains open across zero-balance or zero-APY calls. Integrations must
    ///      account for this before changing balances or rates to avoid retroactive yield.
    function accrue() external nonReentrant returns (uint256 rewards) {
        return _accrue();
    }

    /// @notice Settles the old APY before changing it. Before the scheduled start, preserves that start.
    /// @dev NOTE: If settlement reverts, the APY remains unchanged, even when newAPY is zero.
    ///      The accounting module compares simple annualized return against its targetApy cap;
    ///      compounded yield over a long accrual gap can exceed that cap even when both APY settings
    ///      are equal. Cooldown and minimum-TVL checks can also reject settlement. This function
    ///      cannot bypass those checks to lower or stop the rate; settlement must succeed first.
    function setAPY(uint256 newAPY) external onlyRole(APY_MANAGER_ROLE) nonReentrant {
        if (newAPY > MAX_APY) revert InvalidAPY(newAPY);
        _accrue();
        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        emit APYUpdated(s.apy, newAPY);
        s.apy = newAPY;
    }

    function _accrue() internal returns (uint256 rewards) {
        FixedAPYAccrualStorage storage s = _getFixedAPYAccrualStorage();
        uint256 previousAccrual = s.lastAccrual;
        if (block.timestamp <= previousAccrual) return 0;

        uint256 balance = s.accountingModule.accountingToken().balanceOf(s.accountingModule.strategy());
        rewards = calculateRewards(balance, block.timestamp - previousAccrual, s.apy, s.year);

        // Preserve the interval until rewards reach at least one token unit.
        if (rewards == 0) return 0;

        // A failed reward report rolls this checkpoint back.
        s.lastAccrual = block.timestamp;
        s.accountingModule.processRewards(rewards);

        emit YieldAccrued(previousAccrual, block.timestamp, balance, rewards);
    }

    /**
     * @notice Calculates compounded rewards without reading contract state.
     * @param balance Eligible accounting-token balance in token units.
     * @param elapsed Elapsed time in seconds.
     * @param apy_ Effective annual yield scaled by 1e18.
     * @param year Seconds per accounting year; must be nonzero.
     * @dev B * ((1 + APY) ** (elapsed / YEAR) - 1), using WAD fixed-point exponentiation.
     *      NOTE: Assumes `balance` was eligible for yield throughout the entire `elapsed` period,
     *      with no intervening deposits, withdrawals, external rewards, or losses. Integrations must
     *      atomically settle outstanding yield and update vault accounting before pricing deposit or
     *      withdrawal shares and before changing the eligible balance. Otherwise, newly added funds
     *      earn retroactive yield, while removed funds lose yield earned before their removal.
     *      This function does not track historical balances or enforce that settlement order.
     *      Fractional token units are discarded per settlement; no remainder is stored. Thus very
     *      frequent accrual can under-recognize yield, especially for small six-decimal balances.
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

    function accountingModule() public view returns (IAccountingModule) {
        return _getFixedAPYAccrualStorage().accountingModule;
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
