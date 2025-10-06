// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IAccountingModule } from "../../src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlexStrategy } from "../../src/FlexStrategy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockStrategy is IFlexStrategy, ERC20 {
    using Math for uint256;

    IAccountingModule am;
    IERC20 public baseAsset;

    uint256 rate;
    uint256 _totalAssets;

    constructor(IERC20 baseAsset_) ERC20("Mock Strategy", "MOCK") {
        baseAsset = baseAsset_;
    }

    function setAccountingModule(IAccountingModule am_) public {
        am = am_;
        baseAsset.approve(address(am), type(uint256).max);
        IERC20(am.accountingToken()).approve(address(am), type(uint256).max);
    }

    function deposit(uint256 amount) public {
        baseAsset.transferFrom(msg.sender, address(this), amount);
        am.deposit(amount);
        uint256 shares = amount.mulDiv(1e18, rate, Math.Rounding.Floor);
        _mint(msg.sender, shares);
        _totalAssets += amount;
    }

    function withdraw(uint256 amount, address recipient) public {
        am.withdraw(amount, recipient);
        uint256 shares = amount.mulDiv(1e18, rate, Math.Rounding.Floor);
        _burn(msg.sender, shares);
        _totalAssets -= amount;
    }

    function processor(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldata_
    )
        public
        returns (bytes[] memory)
    {
        if (targets.length != 1) {
            revert("MockStrategy: invalid number of targets");
        }

        if (targets[0] == address(am)) {
            (bool success,) = address(am).call(calldata_[0]);
            require(success, "MockStrategy: call to accounting module failed");
        } else {
            revert("MockStrategy: invalid target");
        }
    }

    function processAccounting() public { }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 assets = shares.mulDiv(rate, 1e18, Math.Rounding.Floor);
        return assets;
    }

    function setRate(uint256 rate_) public {
        rate = rate_;
    }

    function totalAssets() public view returns (uint256) {
        return _totalAssets;
    }

    function asset() public view returns (IERC20) {
        return baseAsset;
    }
}
