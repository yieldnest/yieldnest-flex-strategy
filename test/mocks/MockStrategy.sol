// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IAccountingModule } from "../../src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlexStrategy } from "../../src/FlexStrategy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockStrategy is IFlexStrategy {
    using Math for uint256;

    IAccountingModule am;

    uint256 rate;

    constructor() { }

    function setAccountingModule(IAccountingModule am_) public {
        am = am_;
        IERC20(am.BASE_ASSET()).approve(address(am), type(uint256).max);
        IERC20(am.accountingToken()).approve(address(am), type(uint256).max);
    }

    function deposit(uint256 amount) public {
        IERC20(am.BASE_ASSET()).transferFrom(msg.sender, address(this), amount);
        am.deposit(amount);
    }

    function withdraw(uint256 amount, address recipient) public {
        am.withdraw(amount, recipient);
    }

    function processAccounting() public { }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 assets = shares.mulDiv(rate, 1e18, Math.Rounding.Floor);
        return assets;
    }

    function setRate(uint256 rate_) public {
        rate = rate_;
    }
}
