// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountingToken } from "./AccountingToken.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IAccountingModule {
    event LowerBoundUpdated(uint256 newValue, uint256 oldValue);
    event TargetApyUpdated(uint256 newValue, uint256 oldValue);
    event CooldownSecondsUpdated(uint16 newValue, uint16 oldValue);
    event SafeUpdated(address newValue, address oldValue);

    error TooEarly();
    error NotStrategy();
    error AccountingLimitsExceeded(uint256 aprSinceLastSnapshot, uint256 targetApr);
    error LossLimitExceeded(uint256 amount, uint256 lowerBoundAmount);
    error InvariantViolation();
    error TvlTooLow();
    error CurrentTimestampBeforePreviousTimestamp();

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount, address recipient) external;
    function processRewards(uint256 amount) external;
    function processLosses(uint256 amount) external;

    function BASE_ASSET() external view returns (address);
    function DIVISOR() external view returns (uint256);
    function accountingToken() external view returns (IAccountingToken);
    function safe() external view returns (address);
    function targetApy() external view returns (uint256);
    function lowerBound() external view returns (uint256);
    function cooldownSeconds() external view returns (uint16);
    function SAFE_MANAGER_ROLE() external view returns (bytes32);
    function REWARDS_PROCESSOR_ROLE() external view returns (bytes32);
    function LOSS_PROCESSOR_ROLE() external view returns (bytes32);
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
    address public immutable BASE_ASSET;
    address public immutable STRATEGY;
    uint256 constant MAX_LOWER_BOUND = DIVISOR / 2;

    IAccountingToken public accountingToken;
    address public safe;
    uint64 public nextUpdateWindow;
    uint16 public cooldownSeconds;
    uint256 public targetApy; // in bips;
    uint256 public lowerBound; // in bips; % of tvl

    StrategySnapshot[] public snapshots;

    struct StrategySnapshot {
        uint64 timestamp;
        uint256 pricePerShare;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address strategy, address baseAsset) {
        _disableInitializers();
        BASE_ASSET = baseAsset;
        STRATEGY = strategy;
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

        safe = safe_;
        accountingToken = accountingToken_;
        targetApy = targetApy_;
        lowerBound = lowerBound_;
        cooldownSeconds = 3600;

        createStrategySnapshot();
    }

    modifier checkAndResetCooldown() {
        if (block.timestamp < nextUpdateWindow) revert TooEarly();
        nextUpdateWindow = (uint64(block.timestamp) + cooldownSeconds);
        _;
    }

    modifier onlyStrategy() {
        if (msg.sender != STRATEGY) revert NotStrategy();
        _;
    }

    /**
     * @notice Proxies deposit of base assets from caller to associated SAFE,
     * and mints an equiv amount of accounting tokens
     * @param amount amount to deposit
     */
    function deposit(uint256 amount) external onlyStrategy {
        IERC20(BASE_ASSET).safeTransferFrom(STRATEGY, safe, amount);
        accountingToken.mintTo(STRATEGY, amount);
    }

    /**
     * @notice Proxies withdraw of base assets from associated SAFE to caller,
     * and burns an equiv amount of accounting tokens
     * @param amount amount to deposit
     * @param recipient address to receive the base assets
     */
    function withdraw(uint256 amount, address recipient) external onlyStrategy {
        accountingToken.burnFrom(STRATEGY, amount);
        IERC20(BASE_ASSET).safeTransferFrom(safe, recipient, amount);
    }

    /**
     * @notice Process rewards by minting accounting tokens
     * @param amount profits to mint
     */
    function processRewards(uint256 amount) external onlyRole(REWARDS_PROCESSOR_ROLE) checkAndResetCooldown {
        uint256 totalSupply = accountingToken.totalSupply();
        if (totalSupply < 10 ** accountingToken.decimals()) revert TvlTooLow();

        IVault strategy = IVault(STRATEGY);

        accountingToken.mintTo(STRATEGY, amount);
        strategy.processAccounting();

        StrategySnapshot memory previousSnapshot = snapshots[snapshots.length - 1];

        uint256 currentPricePerShare = createStrategySnapshot().pricePerShare;

        // Check if APR is within acceptable bounds
        uint256 aprSinceLastSnapshot = calculateApr(
            previousSnapshot.pricePerShare, previousSnapshot.timestamp, currentPricePerShare, block.timestamp
        );

        if (aprSinceLastSnapshot > targetApy) revert AccountingLimitsExceeded(aprSinceLastSnapshot, targetApy);
    }

    function createStrategySnapshot() internal returns (StrategySnapshot memory) {
        IVault strategy = IVault(STRATEGY);

        // Take snapshot of current state
        uint256 currentPricePerShare = strategy.convertToAssets(10 ** strategy.decimals());

        StrategySnapshot memory snapshot =
            StrategySnapshot({ timestamp: uint64(block.timestamp), pricePerShare: currentPricePerShare });

        snapshots.push(snapshot);

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

        return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
            / (currentTimestamp - previousTimestamp);
    }

    /**
     * @notice Process losses by burning accounting tokens
     * @param amount losses to burn
     */
    function processLosses(uint256 amount) external onlyRole(LOSS_PROCESSOR_ROLE) checkAndResetCooldown {
        uint256 totalSupply = accountingToken.totalSupply();
        if (totalSupply < 10 ** accountingToken.decimals()) revert TvlTooLow();

        // check lower bound - 10% of tvl (in bips)
        if (amount > totalSupply * lowerBound / DIVISOR) {
            revert LossLimitExceeded(amount, totalSupply * lowerBound / DIVISOR);
        }

        accountingToken.burnFrom(STRATEGY, amount);
        IVault(STRATEGY).processAccounting();

        createStrategySnapshot();
    }

    /**
     * @notice Set target APY to determine upper bound. e.g. 1000 = 10% APY
     * @param targetApyInBips in bips
     * @dev hard max of 100% targetApy
     */
    function setTargetApy(uint256 targetApyInBips) external onlyRole(SAFE_MANAGER_ROLE) {
        if (targetApyInBips > DIVISOR) revert InvariantViolation();

        emit TargetApyUpdated(targetApyInBips, targetApy);
        targetApy = targetApyInBips;
    }

    /**
     * @notice Set lower bound as a function of tvl for losses. e.g. 1000 = 10% of tvl
     * @param _lowerBound in bips, as a function of % of tvl
     * @dev hard max of 50% of tvl
     */
    function setLowerBound(uint256 _lowerBound) external onlyRole(SAFE_MANAGER_ROLE) {
        if (_lowerBound > (MAX_LOWER_BOUND)) revert InvariantViolation();

        emit LowerBoundUpdated(_lowerBound, lowerBound);
        lowerBound = _lowerBound;
    }

    /**
     * @notice Set cooldown in seconds between every processing of rewards/losses
     * @param cooldownSeconds_ new cooldown seconds
     */
    function setCooldownSeconds(uint16 cooldownSeconds_) external onlyRole(SAFE_MANAGER_ROLE) {
        emit CooldownSecondsUpdated(cooldownSeconds_, cooldownSeconds);
        cooldownSeconds = cooldownSeconds_;
    }

    /**
     * @notice Set a new safe address
     * @param newSafe new safe address
     */
    function setSafeAddress(address newSafe) external virtual onlyRole(SAFE_MANAGER_ROLE) {
        emit SafeUpdated(newSafe, safe);
        safe = newSafe;
    }
}
