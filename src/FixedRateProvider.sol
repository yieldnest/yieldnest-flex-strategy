// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IProvider } from "@yieldnest-vault/interface/IProvider.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IAccountingToken } from "./AccountingToken.sol";

/**
 * Fixed rate provider that assumes 1:1 rate of added asset.
 */
contract FixedRateProvider is IProvider {
    address public immutable ASSET;
    uint8 public immutable DECIMALS;
    address public immutable ACCOUNTING_TOKEN;

    constructor(address accountingToken) {
        ASSET = IAccountingToken(accountingToken).TRACKED_ASSET();
        DECIMALS = IERC20Metadata(accountingToken).decimals();
        ACCOUNTING_TOKEN = accountingToken;
    }

    error UnsupportedAsset(address asset);

    function getRate(address asset) external view returns (uint256 rate) {
        if (asset == ASSET) {
            return 10 ** DECIMALS;
        }

        if (asset == ACCOUNTING_TOKEN) {
            return 10 ** DECIMALS;
        }

        revert UnsupportedAsset(asset);
    }
}
