// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IAccountingModule } from "./AccountingModule.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @notice Fixed rate dripper for FlexStrategy. Based on OUSD fixed rate dripper.
 * https://basescan.org/address/0xa3a4759df6687cd2573b1399b68118bb86eccdae#code
 */
contract FixedRateDripper is AccessControl {
    using SafeERC20 for IERC20;

    event DripRateUpdated(uint192 perSecond, uint192 oldPerSecond);

    /// @notice Role for processing drops
    bytes32 public constant DRIPPER_ROLE = keccak256("DRIPPER_ROLE");
    /// @notice Role for managing drip rate
    bytes32 public constant DRIP_RATE_MANAGER_ROLE = keccak256("DRIP_RATE_MANAGER_ROLE");

    struct Drip {
        uint64 lastCollect; // overflows 262 billion years after the sun dies
        uint192 perSecond; // drip rate per second
    }

    address immutable accountingModule; // FlexStrategy accounting module
    address immutable safe; // FlexStrategy safe
    address immutable token; // token to drip out
    Drip public drip; // active drip parameters

    constructor(address _admin, address _accountingModule, address _safe, address _token) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        accountingModule = _accountingModule;
        safe = _safe;
        token = _token;
    }

    /**
     * @notice How much funds have dripped out already and are currently
     *   available to be sent to the vault.
     * @return The amount that would be sent if a collect was called
     */
    function availableFunds() external view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        return _availableFunds(balance, drip);
    }

    /**
     * @notice Collect all dripped funds, send to vault, and calls processRewards on the accounting module.
     */
    function collectAndProcessRewards() external onlyRole(DRIPPER_ROLE) {
        uint256 amountToSend = _collect();
        IAccountingModule(accountingModule).processRewards(amountToSend);
    }

    /**
     * @dev Transfer out ERC20 tokens held by the contract. Admin only.
     * @param _asset ERC20 token address
     * @param _amount amount to transfer
     * @param _to address to transfer to
     */
    function transferToken(address _asset, uint256 _amount, address _to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_asset).safeTransfer(_to, _amount);
    }

    /**
     * @dev Calculate available funds by taking the lower of either the
     *  currently dripped out funds or the balance available.
     *  Uses passed in parameters to calculate with for gas savings.
     * @param _balance current balance in contract
     * @param _drip current drip parameters
     */
    function _availableFunds(uint256 _balance, Drip memory _drip) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - _drip.lastCollect;
        uint256 allowed = (elapsed * _drip.perSecond);
        return (allowed > _balance) ? _balance : allowed;
    }

    /**
     * @dev Sets the drip rate. Callable by drip rate manager.
     *      Can be set to zero to stop dripper.
     * @param _perSecond Rate of WETH to drip per second
     */
    function setDripRate(uint192 _perSecond) external onlyRole(DRIP_RATE_MANAGER_ROLE) {
        emit DripRateUpdated(_perSecond, drip.perSecond);

        /**
         * Note: It's important to call `_collect` before updating
         * the drip rate especially on a new proxy contract.
         * When `lastCollect` is not set/initialized, the elapsed
         * time would be calculated as `block.number` seconds,
         * resulting in a huge yield, if `collect` isn't called first.
         */
        // Collect at existing rate
        _collect();

        // Update rate
        drip.perSecond = _perSecond;
    }

    /**
     * @dev Sends the currently dripped funds to the safe, and updates lastCollect
     * @return amountToSend The amount of funds sent to the safe
     */
    function _collect() internal virtual returns (uint256 amountToSend) {
        // Calculate amount to send
        uint256 balance = IERC20(token).balanceOf(address(this));
        amountToSend = _availableFunds(balance, drip);

        // Update timestamp
        drip.lastCollect = uint64(block.timestamp);

        // Send funds
        IERC20(token).safeTransfer(safe, amountToSend);
    }
}
