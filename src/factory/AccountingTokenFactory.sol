// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { AccountingToken } from "../AccountingToken.sol";

/**
 * @notice Factory for deploying AccountingToken implementations bound to a tracked asset.
 */
contract AccountingTokenFactory {
    event AccountingTokenImplementationDeployed(address indexed trackedAsset, address implementation);

    function deployAccountingTokenImplementation(address trackedAsset) external returns (AccountingToken) {
        AccountingToken implementation = new AccountingToken(trackedAsset);
        emit AccountingTokenImplementationDeployed(trackedAsset, address(implementation));
        return implementation;
    }
}
