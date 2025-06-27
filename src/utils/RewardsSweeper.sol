// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountingModule } from "../AccountingModule.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { console } from "forge-std/console.sol";

/**
 * @title RewardsSweeper
 * @notice Contract to sweep rewards from a strategy and process them through the accounting module
 */
contract RewardsSweeper is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant REWARDS_SWEEPER_ROLE = keccak256("REWARDS_SWEEPER_ROLE");

    IAccountingModule public accountingModule;

    error CannotSweepRewards();
    error SnapshotIndexOutOfBounds(uint256 index);
    error PreviousTimestampGreaterThanCurrentTimestamp(uint256 currentTimestamp, uint256 previousTimestamp);

    event RewardsSwept(uint256 amount);
    event AccountingModuleUpdated(address newModule, address oldModule);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param admin The address of the admin
     * @param accountingModule_ The address of the accounting module
     */
    function initialize(address admin, address accountingModule_) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        accountingModule = IAccountingModule(accountingModule_);
    }

    /**
     * @notice Sweeps rewards up to the maximum allowable APR.
     * @dev This function calls the overloaded version with the latest snapshot index.
     * @return The amount of rewards swept.
     */
    function sweepRewardsUpToAPRMax() public onlyRole(REWARDS_SWEEPER_ROLE) returns (uint256) {
        return sweepRewardsUpToAPRMax(accountingModule.snapshotsLength() - 1);
    }

    /**
     * @notice Sweeps rewards up to the maximum allowable APR for a specific snapshot index.
     * @param snapshotIndex The index of the snapshot to consider for sweeping rewards.
     * @return The amount of rewards swept.
     */
    function sweepRewardsUpToAPRMax(uint256 snapshotIndex) public onlyRole(REWARDS_SWEEPER_ROLE) returns (uint256) {
        uint256 amountToSweep = previewSweepRewardsUpToAPRMax(snapshotIndex);

        if (amountToSweep > 0) {
            sweepRewards(amountToSweep, snapshotIndex);
        }

        return amountToSweep;
    }

    /**
     * @notice Previews the amount of rewards that can be swept up to the maximum allowable APR for a specific snapshot
     * index.
     * @param snapshotIndex The index of the snapshot to consider for previewing rewards.
     * @return The amount of rewards that can be swept.
     */
    function previewSweepRewardsUpToAPRMax(uint256 snapshotIndex) public view returns (uint256) {
        // Calculate max rewards based on price per share at snapshot
        IAccountingModule.StrategySnapshot memory snapshot = accountingModule.snapshots(snapshotIndex);
        uint256 pricePerShareAtSnapshot = snapshot.pricePerShare;

        IERC4626 strategy = IERC4626(accountingModule.STRATEGY());

        uint256 maxRewards = calculateMaxRewards(
            pricePerShareAtSnapshot,
            snapshot.timestamp,
            block.timestamp,
            accountingModule.targetApy(),
            strategy.totalSupply(),
            strategy.totalAssets(),
            strategy.decimals(),
            accountingModule.YEAR(),
            accountingModule.DIVISOR()
        );

        // Get current balance and use the minimum of maxRewards and balance
        uint256 currentBalance = IERC20(accountingModule.BASE_ASSET()).balanceOf(address(this));
        uint256 amountToSweep = maxRewards < currentBalance ? maxRewards : currentBalance;

        return amountToSweep;
    }

    function calculateMaxRewards(
        uint256 previousPricePerShare,
        uint256 previousTimestamp,
        uint256 currentTimestamp,
        uint256 targetApy,
        uint256 currentSupply,
        uint256 currentAssets,
        uint256 sharesDecimals,
        uint256 YEAR,
        uint256 DIVISOR
    )
        public
        pure
        returns (uint256)
    {
        if (currentTimestamp <= previousTimestamp) {
            revert PreviousTimestampGreaterThanCurrentTimestamp(currentTimestamp, previousTimestamp);
        }

        // How to calculate targetApy:
        // uint256 targetApy = (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
        //     / (currentTimestamp - previousTimestamp);

        uint256 pricePerShareWithMaxTargetApy = previousPricePerShare
            + (targetApy * previousPricePerShare * (currentTimestamp - previousTimestamp)) / (YEAR * DIVISOR);

        uint256 totalAssetsWithMaxTargetApy = (pricePerShareWithMaxTargetApy * currentSupply / (10 ** sharesDecimals));

        if (totalAssetsWithMaxTargetApy > currentAssets) {
            return totalAssetsWithMaxTargetApy - currentAssets;
        }

        return 0;
    }

    /**
     * @notice Sweeps rewards from the strategy and processes them through the accounting module
     * @param amount Amount of rewards to sweep
     */
    function sweepRewards(uint256 amount) public onlyRole(REWARDS_SWEEPER_ROLE) {
        sweepRewards(amount, accountingModule.snapshotsLength() - 1);
    }

    /**
     * @notice Sweeps rewards from the strategy and processes them through the accounting module with specific snapshot
     * index
     * @param amount Amount of rewards to sweep
     * @param snapshotIndex Index of the snapshot to compare against
     */
    function sweepRewards(uint256 amount, uint256 snapshotIndex) public onlyRole(REWARDS_SWEEPER_ROLE) {
        if (!canSweepRewards()) revert CannotSweepRewards();

        if (snapshotIndex >= accountingModule.snapshotsLength()) revert SnapshotIndexOutOfBounds(snapshotIndex);

        // Transfer rewards to safe
        IERC20(accountingModule.BASE_ASSET()).safeTransfer(accountingModule.safe(), amount);

        // Process rewards through accounting module with specific snapshot index
        accountingModule.processRewards(amount, snapshotIndex);

        emit RewardsSwept(amount);
    }
    /**
     * @notice Checks if rewards can be swept based on cooldown period and base asset balance
     * @return bool True if rewards can be swept, false otherwise
     */

    function canSweepRewards() public view returns (bool) {
        return block.timestamp >= accountingModule.nextUpdateWindow()
            && IERC20(accountingModule.BASE_ASSET()).balanceOf(address(this)) > 0;
    }
    /**
     * @notice Updates the accounting module address
     * @param accountingModule_ New accounting module address
     */

    function setAccountingModule(address accountingModule_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit AccountingModuleUpdated(accountingModule_, address(accountingModule));
        accountingModule = IAccountingModule(accountingModule_);
    }
}
