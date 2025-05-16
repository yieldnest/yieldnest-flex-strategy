// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccountingToken } from "./AccountingToken.sol";
import { IFlexStrategy } from "./FlexStrategy.sol";
import { IVault } from "@yieldnest-vault/interface/IVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IAccountingModule {
    event LowerBoundUpdated(uint16 newValue, uint16 oldValue);
    event TargetApyUpdated(uint16 newValue, uint16 oldValue);
    event CooldownSecondsUpdated(uint16 newValue, uint16 oldValue);
    event SafeUpdated(address newValue, address oldValue);

    error TooEarly();
    error NotSafeManager();
    error NotAccountingProcessor();
    error NotStrategy();
    error AccountingLimitsExceeded();
    error InvariantViolation();
    error TvlTooLow();

    function BASE_ASSET() external view returns (address);
    function accountingToken() external view returns (AccountingToken);
    function safe() external view returns (address);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function processRewards(uint256 amount) external;
    function processLosses(uint256 amount) external;
}
/**
 * Module to configure strategy params,
 *  and mint/burn IOU tokens to represent value accrual/loss.
 */

contract AccountingModule is IAccountingModule, Initializable {
    using SafeERC20 for IERC20;

    uint256 public constant YEAR = 365.25 days;
    uint256 public constant DIVISOR = 10_000;
    address public immutable BASE_ASSET;
    address public immutable STRATEGY;

    AccountingToken public accountingToken;
    address public safe;
    uint64 public nextRewardWindow;
    uint16 public cooldownSeconds;
    uint16 public targetApy; // in bips;
    uint16 public lowerBound; // in bips; % of tvl

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address strategy, address baseAsset) {
        _disableInitializers();
        BASE_ASSET = baseAsset;
        STRATEGY = strategy;
    }

    /**
     * @notice Initializes the vault.
     * @param name_ The name of the accountingToken.
     * @param symbol_ The symbol of accountingToken.
     * @param safe_ The safe associated with the strategy.
     * @param targetApy_ The target APY of the strategy.
     * @param lowerBound_ The lower bound of losses of the strategy(as % of TVL).
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address safe_,
        uint16 targetApy_,
        uint16 lowerBound_
    )
        external
        virtual
        initializer
    {
        accountingToken = new AccountingToken(name_, symbol_, BASE_ASSET, address(this));
        safe = safe_;
        targetApy = targetApy_;
        lowerBound = lowerBound_;
        cooldownSeconds = 3600;
    }

    modifier checkAndResetCooldown() {
        if (block.timestamp < nextRewardWindow) revert TooEarly();
        nextRewardWindow = (uint64(block.timestamp) + cooldownSeconds);
        _;
    }

    modifier onlySafeManager() {
        if (IAccessControl(STRATEGY).hasRole(IFlexStrategy(STRATEGY).SAFE_MANAGER_ROLE(), msg.sender) == false) {
            revert NotSafeManager();
        }
        _;
    }

    modifier onlyAccountingProcessor() {
        if (IAccessControl(STRATEGY).hasRole(IFlexStrategy(STRATEGY).ACCOUNTING_PROCESSOR_ROLE(), msg.sender) == false)
        {
            revert NotAccountingProcessor();
        }
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
        IERC20(BASE_ASSET).safeTransferFrom(msg.sender, safe, amount);
        accountingToken.mintTo(msg.sender, amount);
    }

    /**
     * @notice Proxies withdraw of base assets from associated SAFE to caller,
     * and burns an equiv amount of accounting tokens
     * @param amount amount to deposit
     */
    function withdraw(uint256 amount) external onlyStrategy {
        accountingToken.burnFrom(msg.sender, amount);
        IERC20(BASE_ASSET).safeTransferFrom(safe, msg.sender, amount);
    }

    /**
     * @notice Process rewards by minting accounting tokens
     * @param amount profits to mint
     */
    function processRewards(uint256 amount) external onlyAccountingProcessor checkAndResetCooldown {
        uint256 totalSupply = accountingToken.totalSupply();
        if (totalSupply < 10 ** accountingToken.decimals()) revert TvlTooLow();

        // check for upper bound
        // targetApy / year * token.totalsupply()
        if (amount > targetApy * totalSupply / DIVISOR / YEAR) revert AccountingLimitsExceeded();

        accountingToken.mintTo(STRATEGY, amount);
        IVault(STRATEGY).processAccounting();
    }

    /**
     * @notice Process losses by burning accounting tokens
     * @param amount losses to burn
     */
    function processLosses(uint256 amount) external onlyAccountingProcessor checkAndResetCooldown {
        uint256 totalSupply = accountingToken.totalSupply();
        if (totalSupply < 10 ** accountingToken.decimals()) revert TvlTooLow();

        // check lower bound - 10% of tvl (in bips)
        if (amount > totalSupply * lowerBound / DIVISOR) revert AccountingLimitsExceeded();

        accountingToken.burnFrom(STRATEGY, amount);
        IVault(STRATEGY).processAccounting();
    }

    /**
     * @notice Set target APY to determine upper bound. e.g. 1000 = 10% APY
     * @param targetApyInBips in bips
     * @dev hard max of 100% targetApy
     */
    function setTargetApy(uint16 targetApyInBips) external onlySafeManager {
        if (targetApyInBips > DIVISOR) revert InvariantViolation();

        emit TargetApyUpdated(targetApyInBips, targetApy);
        targetApy = targetApyInBips;
    }

    /**
     * @notice Set lower bound as a function of tvl for losses. e.g. 1000 = 10% of tvl
     * @param _lowerBound in bips, as a function of % of tvl
     * @dev hard max of 50% of tvl
     */
    function setLowerBound(uint16 _lowerBound) external onlySafeManager {
        if (_lowerBound > (DIVISOR / 2)) revert InvariantViolation();

        emit LowerBoundUpdated(_lowerBound, lowerBound);
        lowerBound = _lowerBound;
    }

    /**
     * @notice Set cooldown in seconds between every processing of rewards/losses
     * @param cooldownSeconds_ new cooldown seconds
     */
    function setCooldownSeconds(uint16 cooldownSeconds_) external onlySafeManager {
        emit CooldownSecondsUpdated(cooldownSeconds_, cooldownSeconds);
        cooldownSeconds = cooldownSeconds_;
    }

    /**
     * @notice Set a new safe address
     * @param newSafe new safe address
     */
    function setSafeAddress(address newSafe) external virtual onlySafeManager {
        emit SafeUpdated(newSafe, safe);
        safe = newSafe;
    }
}
