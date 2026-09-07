// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AccountingToken } from "./AccountingToken.sol";

/**
 * @notice Accounting token variant that smoothly rebases balances at a fixed APR.
 * @dev APR is 18-decimal scaled. A value of 0.1e18 accrues 10% simple interest per year.
 */
contract RebasingAccountingToken is AccountingToken {
    bytes32 public constant APR_MANAGER_ROLE = keccak256("APR_MANAGER_ROLE");

    uint256 public constant DIVISOR = 1e18;
    uint256 public constant YEAR = 365.25 days;

    struct RebasingAccountingTokenStorage {
        mapping(address account => uint256) shares;
        uint256 totalShares;
        uint256 lastPooledAssets;
        uint256 apr;
        uint64 lastAccrualTimestamp;
    }

    bytes32 private constant REBASING_ACCOUNTING_TOKEN_STORAGE_SLOT =
        keccak256("yieldnest.storage.rebasingAccountingToken");

    event AprUpdated(uint256 newApr, uint256 oldApr);
    event AccrualCheckpoint(uint256 pooledAssets, uint64 timestamp);

    error ZeroShares();

    constructor(address trackedAsset) AccountingToken(trackedAsset) { }

    function _getRebasingAccountingTokenStorage() internal pure returns (RebasingAccountingTokenStorage storage s) {
        bytes32 slot = REBASING_ACCOUNTING_TOKEN_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /**
     * @notice Sets the fixed APR used for smooth rebasing.
     * @dev Checkpoints accrued supply before updating the APR, so historical accrual keeps the old rate.
     */
    function setApr(uint256 apr_) external onlyRole(APR_MANAGER_ROLE) {
        RebasingAccountingTokenStorage storage s = _getRebasingAccountingTokenStorage();
        _checkpointAccrual(s);

        emit AprUpdated(apr_, s.apr);
        s.apr = apr_;
    }

    function mintTo(address mintAddress, uint256 mintAmount) external override onlyAccounting {
        RebasingAccountingTokenStorage storage s = _getRebasingAccountingTokenStorage();
        _checkpointAccrual(s);

        uint256 shares = _assetsToShares(mintAmount, Math.Rounding.Floor);
        if (shares == 0 && mintAmount != 0) revert ZeroShares();

        s.lastPooledAssets += mintAmount;
        s.totalShares += shares;
        s.shares[mintAddress] += shares;

        emit Transfer(address(0), mintAddress, mintAmount);
    }

    function burnFrom(address burnAddress, uint256 burnAmount) external override onlyAccounting {
        RebasingAccountingTokenStorage storage s = _getRebasingAccountingTokenStorage();
        _checkpointAccrual(s);

        uint256 shares = _assetsToShares(burnAmount, Math.Rounding.Ceil);

        s.shares[burnAddress] -= shares;
        s.totalShares -= shares;
        s.lastPooledAssets -= burnAmount;

        emit Transfer(burnAddress, address(0), burnAmount);
    }

    function totalSupply() public view override returns (uint256) {
        return _currentPooledAssets(_getRebasingAccountingTokenStorage());
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _sharesToAssets(_getRebasingAccountingTokenStorage().shares[account], Math.Rounding.Floor);
    }

    function apr() external view returns (uint256) {
        return _getRebasingAccountingTokenStorage().apr;
    }

    function sharesOf(address account) external view returns (uint256) {
        return _getRebasingAccountingTokenStorage().shares[account];
    }

    function totalShares() external view returns (uint256) {
        return _getRebasingAccountingTokenStorage().totalShares;
    }

    function lastAccrualTimestamp() external view returns (uint64) {
        return _getRebasingAccountingTokenStorage().lastAccrualTimestamp;
    }

    function _checkpointAccrual(RebasingAccountingTokenStorage storage s) internal {
        uint256 currentPooledAssets = _currentPooledAssets(s);
        uint64 now_ = uint64(block.timestamp);

        s.lastPooledAssets = currentPooledAssets;
        s.lastAccrualTimestamp = now_;

        emit AccrualCheckpoint(currentPooledAssets, now_);
    }

    function _assetsToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        RebasingAccountingTokenStorage storage s = _getRebasingAccountingTokenStorage();
        uint256 pooledAssets = _currentPooledAssets(s);
        if (s.totalShares == 0 || pooledAssets == 0) {
            return assets;
        }

        return Math.mulDiv(assets, s.totalShares, pooledAssets, rounding);
    }

    function _sharesToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        RebasingAccountingTokenStorage storage s = _getRebasingAccountingTokenStorage();
        if (s.totalShares == 0) {
            return 0;
        }

        return Math.mulDiv(shares, _currentPooledAssets(s), s.totalShares, rounding);
    }

    function _currentPooledAssets(RebasingAccountingTokenStorage storage s) internal view returns (uint256) {
        uint256 lastPooledAssets = s.lastPooledAssets;
        if (lastPooledAssets == 0 || s.apr == 0) {
            return lastPooledAssets;
        }

        uint256 elapsed = block.timestamp - s.lastAccrualTimestamp;
        uint256 annualYield = Math.mulDiv(lastPooledAssets, s.apr, DIVISOR, Math.Rounding.Floor);
        return lastPooledAssets + Math.mulDiv(annualYield, elapsed, YEAR, Math.Rounding.Floor);
    }
}
