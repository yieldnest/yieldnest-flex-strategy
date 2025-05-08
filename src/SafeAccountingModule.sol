// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { AccountingToken } from "./AccountingToken.sol";

contract SafeAccountingModule {
    error TooEarly();
    error Unauthorized();
    error BoundaryBreach();

    uint256 public YEAR = 365.25 days;
    AccountingToken public immutable TOKEN;
    address public immutable STRATEGY;

    uint16 public cooldownSeconds = 3600;
    uint64 public nextRewardWindow;

    modifier checkCooldown() {
        if (block.timestamp < nextRewardWindow) revert TooEarly();
        nextRewardWindow = (uint64(block.timestamp) + cooldownSeconds);
        _;
    }

    modifier onlyStrategy() {
        if (msg.sender != STRATEGY) revert Unauthorized();
        _;
    }

    constructor(string memory name_, string memory symbol_, address strategy) {
        TOKEN = new AccountingToken(name_, symbol_, address(this));
        STRATEGY = strategy;
    }

    // in bips
    function apy() public view returns (uint64) {
        // TODO: retrieve from strategy
        return 1000;
    }

    function deposit(uint256 amount) external onlyStrategy {
        TOKEN.mintTo(msg.sender, amount);
    }

    function withdraw(uint256 amount) external onlyStrategy {
        TOKEN.burnFrom(msg.sender, amount);
    }

    function processRewards(uint256 amount) external onlyStrategy checkCooldown {
        // TODO sanity check:
        // only process rewards if token.totalSupply() > some small amount to prevent big rounding errors.

        // check for upper bound
        // apy / year * token.totalsupply()
        if (amount > apy() * TOKEN.totalSupply() / YEAR) revert BoundaryBreach();

        TOKEN.mintTo(msg.sender, amount);
    }
}
