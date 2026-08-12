// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

contract MockAccountingModule {
    address public accountingToken;
    address public baseAsset;
    address public strategy;
    address public safe;

    constructor(address _baseAsset) {
        baseAsset = _baseAsset;
    }

    function setAccountingToken(address _accountingToken) public {
        accountingToken = _accountingToken;
    }

    function setStrategy(address _strategy) public {
        strategy = _strategy;
    }

    function setSafe(address _safe) public {
        safe = _safe;
    }
}
