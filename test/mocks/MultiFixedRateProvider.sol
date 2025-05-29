// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IProvider } from "@yieldnest-vault/interface/IProvider.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/**
 * Fixed rate provider that assumes 1:1 rate of added asset.
 */
contract MultiFixedRateProvider is IProvider {
    mapping(address => uint8) public _decimals;
    mapping(address => bool) public isSupported;

    error UnsupportedAsset(address asset);

    function getRate(address asset) external view returns (uint256 rate) {
        if (isSupported[asset]) {
            return 10 ** _decimals[asset];
        }

        revert UnsupportedAsset(asset);
    }

    function addAsset(address asset) external {
        isSupported[asset] = true;
        _decimals[asset] = IERC20Metadata(asset).decimals();
    }
}
