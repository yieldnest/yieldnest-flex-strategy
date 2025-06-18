// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountingModule } from "../AccountingModule.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
/**
 * @title RewardsSweeper
 * @notice Contract to sweep rewards from a strategy and process them through the accounting module
 */
contract RewardsSweeper is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant REWARDS_SWEEPER_ROLE = keccak256("REWARDS_SWEEPER_ROLE");

    IAccountingModule public accountingModule;

    error Unauthorized();
    error TransferFailed();
    error CannotSweepRewards();

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



    function sweepRewardsUpToAPRMax() public {

        // Calculate max rewards based on current TVL and target APY
        uint256 totalAssets = IERC4626(accountingModule.STRATEGY()).totalAssets();

        uint256 timeElapsed = block.timestamp - accountingModule.nextUpdateWindow();
        uint256 maxRewards = (totalAssets * accountingModule.targetApy() * timeElapsed) 
            / (365 days * accountingModule.DIVISOR());

        // Get current balance and use the minimum of maxRewards and balance
        uint256 currentBalance = IERC20(accountingModule.BASE_ASSET()).balanceOf(address(this));
        uint256 amountToSweep = maxRewards < currentBalance ? maxRewards : currentBalance;

        if (amountToSweep > 0) {
            sweepRewards(amountToSweep);
        }
    }

    /**
     * @notice Sweeps rewards from the strategy and processes them through the accounting module
     * @param amount Amount of rewards to sweep
     */
    function sweepRewards(uint256 amount) public onlyRole(REWARDS_SWEEPER_ROLE) {
        if (!canSweepRewards()) revert CannotSweepRewards();
        // Transfer rewards to safe
        IERC20(accountingModule.BASE_ASSET()).safeTransfer(accountingModule.safe(), amount);

        // Process rewards through accounting module
        accountingModule.processRewards(amount);

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
