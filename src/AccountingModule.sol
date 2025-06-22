// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountingToken } from "./AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IAccountingModule {
    struct StrategySnapshot {
        uint64 timestamp;
        uint256 pricePerShare;
        uint256 totalSupply;
        uint256 totalAssets;
    }

    event LowerBoundUpdated(uint256 newValue, uint256 oldValue);
    event TargetApyUpdated(uint256 newValue, uint256 oldValue);
    event CooldownSecondsUpdated(uint16 newValue, uint16 oldValue);
    event SafeUpdated(address newValue, address oldValue);

    error ZeroAddress();
    error TooEarly();
    error NotStrategy();
    error AccountingLimitsExceeded(uint256 aprSinceLastSnapshot, uint256 targetApr);
    error LossLimitsExceeded(uint256 amount, uint256 lowerBoundAmount);
    error InvariantViolation();
    error TvlTooLow();
    error CurrentTimestampBeforePreviousTimestamp();
    error SnapshotIndexOutOfBounds(uint256 index);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount, address recipient) external;
    function processRewards(uint256 amount) external;
    function processRewards(uint256 amount, uint256 snapshotIndex) external;
    function processLosses(uint256 amount) external;

    function BASE_ASSET() external view returns (address);
    function DIVISOR() external view returns (uint256);
    function accountingToken() external view returns (IAccountingToken);
    function safe() external view returns (address);
    function nextUpdateWindow() external view returns (uint64);
    function targetApy() external view returns (uint256);
    function lowerBound() external view returns (uint256);
    function cooldownSeconds() external view returns (uint16);
    function STRATEGY() external view returns (address);
    function SAFE_MANAGER_ROLE() external view returns (bytes32);
    function REWARDS_PROCESSOR_ROLE() external view returns (bytes32);
    function LOSS_PROCESSOR_ROLE() external view returns (bytes32);

    function calculateApr(
        uint256 previousPricePerShare,
        uint256 previousTimestamp,
        uint256 currentPricePerShare,
        uint256 currentTimestamp
    )
        external
        view
        returns (uint256 apr);

    function snapshotsLength() external view returns (uint256);
    function snapshots(uint256 index) external view returns (StrategySnapshot memory);
    function lastSnapshot() external view returns (StrategySnapshot memory);
}

/**
 * @notice Storage struct for AccountingModule
 */
struct AccountingModuleStorage {
    IAccountingToken accountingToken;
    address safe;
    uint64 nextUpdateWindow;
    uint16 cooldownSeconds;
    uint256 targetApy; // in bips;
    uint256 lowerBound; // in bips; % of tvl
    IAccountingModule.StrategySnapshot[] _snapshots;
}

/**
 * Module to configure strategy params,
 *  and mint/burn IOU tokens to represent value accrual/loss.
 */
contract AccountingModule is IAccountingModule, Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Role for safe manager permissions
    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");

    /// @notice Role for processing rewards/losses
    bytes32 public constant REWARDS_PROCESSOR_ROLE = keccak256("REWARDS_PROCESSOR_ROLE");
    bytes32 public constant LOSS_PROCESSOR_ROLE = keccak256("LOSS_PROCESSOR_ROLE");

    uint256 public constant YEAR = 365.25 days;
    uint256 public constant DIVISOR = 1e18;
    uint256 public constant MAX_LOWER_BOUND = DIVISOR / 2;

    address public immutable BASE_ASSET;
    address public immutable STRATEGY;

    /// @notice Storage slot for AccountingModule data
    bytes32 private constant ACCOUNTING_MODULE_STORAGE_SLOT = keccak256("yieldnest.storage.accountingModule");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address strategy, address baseAsset) {
        _disableInitializers();
        BASE_ASSET = baseAsset;
        STRATEGY = strategy;
    }

    /**
     * @notice Get the storage struct
     */
    function _getAccountingModuleStorage() internal pure returns (AccountingModuleStorage storage s) {
        bytes32 slot = ACCOUNTING_MODULE_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param safe_ The safe associated with the module.
     * @param accountingToken_ The accountingToken associated with the module.
     * @param targetApy_ The target APY of the strategy.
     * @param lowerBound_ The lower bound of losses of the strategy(as % of TVL).
     */
    function initialize(
        address admin,
        address safe_,
        IAccountingToken accountingToken_,
        uint256 targetApy_,
        uint256 lowerBound_
    )
        external
        virtual
        initializer
    {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        s.safe = safe_;
        s.accountingToken = accountingToken_;
        s.targetApy = targetApy_;
        s.lowerBound = lowerBound_;
        s.cooldownSeconds = 3600;

        createStrategySnapshot();
    }

    modifier checkAndResetCooldown() {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        if (block.timestamp < s.nextUpdateWindow) revert TooEarly();
        s.nextUpdateWindow = (uint64(block.timestamp) + s.cooldownSeconds);
        _;
    }

    modifier onlyStrategy() {
        if (msg.sender != STRATEGY) revert NotStrategy();
        _;
    }

    /// DEPOSIT/WITHDRAW ///

    /**
     * @notice Proxies deposit of base assets from caller to associated SAFE,
     * and mints an equiv amount of accounting tokens
     * @param amount amount to deposit
     */
    function deposit(uint256 amount) external onlyStrategy {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        IERC20(BASE_ASSET).safeTransferFrom(STRATEGY, s.safe, amount);
        s.accountingToken.mintTo(STRATEGY, amount);
    }

    /**
     * @notice Proxies withdraw of base assets from associated SAFE to caller,
     * and burns an equiv amount of accounting tokens
     * @param amount amount to deposit
     * @param recipient address to receive the base assets
     */
    function withdraw(uint256 amount, address recipient) external onlyStrategy {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        s.accountingToken.burnFrom(STRATEGY, amount);
        IERC20(BASE_ASSET).safeTransferFrom(s.safe, recipient, amount);
    }

    /// REWARDS ///

    /**
     * @notice Process rewards by minting accounting tokens
     * @param amount profits to mint
     */
    function processRewards(uint256 amount) external onlyRole(REWARDS_PROCESSOR_ROLE) checkAndResetCooldown {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        _processRewards(amount, s._snapshots.length - 1);
    }

    /**
     * @notice Process rewards by minting accounting tokens with specific snapshot index
     * @param amount profits to mint
     * @param snapshotIndex index of the snapshot to compare against
     */
    function processRewards(
        uint256 amount,
        uint256 snapshotIndex
    )
        external
        onlyRole(REWARDS_PROCESSOR_ROLE)
        checkAndResetCooldown
    {
        _processRewards(amount, snapshotIndex);
    }

    /**
     * @notice Internal function to process rewards with snapshot validation
     * @param amount profits to mint
     * @param snapshotIndex index of the snapshot to compare against
     *
     * @dev This function validates rewards by comparing current PPS against a historical snapshot.
     * Using a past snapshot (rather than the most recent) helps prevent APR manipulation
     * by smoothing out reward distribution over time.
     *
     *
     * Example with daily processRewards calls:
     *
     * Day 0: PPS = 100  [snapshot 0]
     * Day 1: PPS = 101  [snapshot 1]
     * Day 2: PPS = 102  [snapshot 2]
     * Day 3: PPS = 107  [snapshot 3] ← Big jump due to delayed rewards
     *
     * If we only compared Day 2→3 (102→107):
     *   Daily return: 4.9% → ~720% APR (exceeds cap)
     *
     * Instead, compare Day 0→3 (100→107):
     *   Daily return: ~2.3% → ~240% APR (within sustainable range)
     *
     * This approach provides flexibility by allowing irregular reward distributions
     * while still enforcing APR limits. By comparing against historical snapshots,
     * the system can accommodate delayed or lump-sum rewards without triggering
     * false positives, while maintaining protection against actual APR manipulation.
     */
    function _processRewards(uint256 amount, uint256 snapshotIndex) internal {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        // check if snapshot index is valid
        if (snapshotIndex >= s._snapshots.length) revert SnapshotIndexOutOfBounds(snapshotIndex);

        uint256 totalSupply = s.accountingToken.totalSupply();
        if (totalSupply < 10 ** s.accountingToken.decimals()) revert TvlTooLow();

        IVault strategy = IVault(STRATEGY);

        s.accountingToken.mintTo(STRATEGY, amount);
        strategy.processAccounting();

        // check if apr is within acceptable bounds

        StrategySnapshot memory previousSnapshot = s._snapshots[snapshotIndex];

        uint256 currentPricePerShare = createStrategySnapshot().pricePerShare;

        // Check if APR is within acceptable bounds
        uint256 aprSinceLastSnapshot = calculateApr(
            previousSnapshot.pricePerShare, previousSnapshot.timestamp, currentPricePerShare, block.timestamp
        );

        if (aprSinceLastSnapshot > s.targetApy) revert AccountingLimitsExceeded(aprSinceLastSnapshot, s.targetApy);
    }

    function createStrategySnapshot() internal returns (StrategySnapshot memory) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        IVault strategy = IVault(STRATEGY);

        // Take snapshot of current state
        uint256 currentPricePerShare = strategy.convertToAssets(10 ** strategy.decimals());

        StrategySnapshot memory snapshot = StrategySnapshot({
            timestamp: uint64(block.timestamp),
            pricePerShare: currentPricePerShare,
            totalSupply: strategy.totalSupply(),
            totalAssets: strategy.totalAssets()
        });

        s._snapshots.push(snapshot);

        return snapshot;
    }

    /**
     * @notice Calculate APR based on price per share changes over time
     * @param previousPricePerShare The price per share at the start of the period
     * @param previousTimestamp The timestamp at the start of the period
     * @param currentPricePerShare The price per share at the end of the period
     * @param currentTimestamp The timestamp at the end of the period
     * @return apr The calculated APR in basis points
     */
    function calculateApr(
        uint256 previousPricePerShare,
        uint256 previousTimestamp,
        uint256 currentPricePerShare,
        uint256 currentTimestamp
    )
        public
        pure
        returns (uint256 apr)
    {
        /*
        ppsStart - Price per share at the start of the period
        ppsEnd - Price per share at the end of the period
        t - Time period in years*
        Formula: (ppsEnd - ppsStart) / (ppsStart * t)
        */

        // Ensure timestamps are ordered (current should be after previous)
        if (currentTimestamp <= previousTimestamp) revert CurrentTimestampBeforePreviousTimestamp();

        // Prevent division by zero
        if (previousPricePerShare == 0) revert InvariantViolation();

        return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
            / (currentTimestamp - previousTimestamp);
    }

    /// LOSS ///

    /**
     * @notice Process losses by burning accounting tokens
     * @param amount losses to burn
     */
    function processLosses(uint256 amount) external onlyRole(LOSS_PROCESSOR_ROLE) checkAndResetCooldown {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        uint256 totalSupply = s.accountingToken.totalSupply();
        if (totalSupply < 10 ** s.accountingToken.decimals()) revert TvlTooLow();

        // check bound on losses
        if (amount > totalSupply * s.lowerBound / DIVISOR) {
            revert LossLimitsExceeded(amount, totalSupply * s.lowerBound / DIVISOR);
        }

        s.accountingToken.burnFrom(STRATEGY, amount);
        IVault(STRATEGY).processAccounting();

        createStrategySnapshot();
    }

    /// ADMIN ///

    /**
     * @notice Set target APY to determine upper bound. e.g. 1000 = 10% APY
     * @param targetApyInBips in bips
     * @dev hard max of 100% targetApy
     */
    function setTargetApy(uint256 targetApyInBips) external onlyRole(SAFE_MANAGER_ROLE) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        if (targetApyInBips > DIVISOR) revert InvariantViolation();

        emit TargetApyUpdated(targetApyInBips, s.targetApy);
        s.targetApy = targetApyInBips;
    }

    /**
     * @notice Set lower bound as a function of tvl for losses. e.g. 1000 = 10% of tvl
     * @param _lowerBound in bips, as a function of % of tvl
     * @dev hard max of 50% of tvl
     */
    function setLowerBound(uint256 _lowerBound) external onlyRole(SAFE_MANAGER_ROLE) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        if (_lowerBound > (MAX_LOWER_BOUND)) revert InvariantViolation();

        emit LowerBoundUpdated(_lowerBound, s.lowerBound);
        s.lowerBound = _lowerBound;
    }

    /**
     * @notice Set cooldown in seconds between every processing of rewards/losses
     * @param cooldownSeconds_ new cooldown seconds
     */
    function setCooldownSeconds(uint16 cooldownSeconds_) external onlyRole(SAFE_MANAGER_ROLE) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        emit CooldownSecondsUpdated(cooldownSeconds_, s.cooldownSeconds);
        s.cooldownSeconds = cooldownSeconds_;
    }

    /**
     * @notice Set a new safe address
     * @param newSafe new safe address
     */
    function setSafeAddress(address newSafe) external virtual onlyRole(SAFE_MANAGER_ROLE) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        if (newSafe == address(0)) revert ZeroAddress();
        emit SafeUpdated(newSafe, s.safe);
        s.safe = newSafe;
    }

    /// VIEWS ///

    function accountingToken() external view returns (IAccountingToken) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s.accountingToken;
    }

    function cooldownSeconds() external view returns (uint16) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s.cooldownSeconds;
    }

    function lowerBound() external view returns (uint256) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s.lowerBound;
    }

    function nextUpdateWindow() external view returns (uint64) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s.nextUpdateWindow;
    }

    function safe() external view returns (address) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s.safe;
    }

    function targetApy() external view returns (uint256) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s.targetApy;
    }

    function snapshotsLength() external view returns (uint256) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s._snapshots.length;
    }

    function snapshots(uint256 index) external view returns (StrategySnapshot memory) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s._snapshots[index];
    }

    function lastSnapshot() external view returns (StrategySnapshot memory) {
        AccountingModuleStorage storage s = _getAccountingModuleStorage();
        return s._snapshots[s._snapshots.length - 1];
    }
}
