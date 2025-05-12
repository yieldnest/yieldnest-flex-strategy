// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeVerifierLib } from "./library/SafeVerifierLib.sol";
import { AccountingToken } from "./AccountingToken.sol";
import { IFlexStrategy } from "./FlexStrategy.sol";

interface IAccountingModule {
    event LowerBoundUpdated(uint16 newValue, uint16 oldValue);
    event TargetApyUpdated(uint16 newValue, uint16 oldValue);

    error TooEarly();
    error Unauthorized();
    error InvariantViolation();
    error TvlTooLow();
}

contract AccountingModule is IAccountingModule {
    using SafeERC20 for IERC20;

    uint256 public constant YEAR = 365.25 days;
    uint256 public constant DIVISOR = 10_000;

    AccountingToken public immutable ACCOUNTING_TOKEN;
    address public immutable BASE_ASSET;
    address public immutable STRATEGY;

    address public SAFE;

    uint16 public cooldownSeconds = 3600;
    uint64 public nextRewardWindow;
    uint16 public targetApy; // in bips;
    uint16 public lowerBound; // in bips; % of tvl

    modifier checkAndResetCooldown() {
        if (block.timestamp < nextRewardWindow) revert TooEarly();
        nextRewardWindow = (uint64(block.timestamp) + cooldownSeconds);
        _;
    }

    modifier onlyStrategyAllocator() {
        if (IFlexStrategy(STRATEGY).isAllocator(msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlyStrategy() {
        if (msg.sender != STRATEGY) revert Unauthorized();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address strategy,
        address baseAsset,
        address safe,
        uint16 targetApy_,
        uint16 lowerBound_
    ) {
        ACCOUNTING_TOKEN = new AccountingToken(name_, symbol_, baseAsset, address(this));
        BASE_ASSET = baseAsset;
        STRATEGY = strategy;

        // will revert after having deployed if we proxify this - is there a better way to check?
        SafeVerifierLib.verify(safe);
        SAFE = safe;

        targetApy = targetApy_;
        lowerBound = lowerBound_;
    }

    /**
     * @notice Proxies deposit of base assets from caller to associated SAFE,
     * and mints an equiv amount of accounting tokens
     * @param amount amount to deposit
     */
    function deposit(uint256 amount) external onlyStrategy {
        IERC20(BASE_ASSET).safeTransferFrom(msg.sender, SAFE, amount);
        ACCOUNTING_TOKEN.mintTo(msg.sender, amount);
    }

    /**
     * @notice Proxies withdraw of base assets from associated SAFE to caller,
     * and burns an equiv amount of accounting tokens
     * @param amount amount to deposit
     */
    function withdraw(uint256 amount) external onlyStrategy {
        ACCOUNTING_TOKEN.burnFrom(msg.sender, amount);
        IERC20(BASE_ASSET).safeTransferFrom(SAFE, msg.sender, amount);
    }

    /**
     * @notice Process rewards by minting accounting tokens
     * @param amount profits to mint
     */
    function processRewards(uint256 amount) external onlyStrategyAllocator checkAndResetCooldown {
        uint256 totalSupply = ACCOUNTING_TOKEN.totalSupply();

        // sanity check: if token.totalSupply() > small amount to prevent rounding issues
        if (totalSupply < 1 ether) revert TvlTooLow();

        // check for upper bound
        // targetApy / year * token.totalsupply()
        if (amount > targetApy * totalSupply / DIVISOR / YEAR) revert InvariantViolation();

        ACCOUNTING_TOKEN.mintTo(STRATEGY, amount);
    }

    /**
     * @notice Process losses by burning accounting tokens
     * @param amount losses to burn
     */
    function processLosses(uint256 amount) external onlyStrategyAllocator checkAndResetCooldown {
        uint256 totalSupply = ACCOUNTING_TOKEN.totalSupply();

        // sanity check: if token.totalSupply() > small amount to prevent rounding issues
        if (totalSupply < 1 ether) revert TvlTooLow();

        // check lower bound - 10% of tvl (in bips)
        if (amount > totalSupply * 1000 / DIVISOR) revert InvariantViolation();

        ACCOUNTING_TOKEN.burnFrom(STRATEGY, amount);
    }

    /**
     * @notice Set target APY to determine upper bound. e.g. 1000 = 10% APY
     * @param targetApyInBips in bips
     */
    function setTargetApy(uint16 targetApyInBips) external onlyStrategyAllocator {
        emit TargetApyUpdated(targetApyInBips, targetApy);
        targetApy = targetApyInBips;
    }

    /**
     * @notice Set lower bound as a function of tvl for losses. e.g. 1000 = 10% of tvl
     * @param lb in bips, as a function of % of tvl
     */
    function setLowerBound(uint16 lb) external onlyStrategyAllocator {
        emit LowerBoundUpdated(lb, lowerBound);
        lowerBound = lb;
    }
}
