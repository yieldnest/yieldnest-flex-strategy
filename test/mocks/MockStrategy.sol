// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IAccountingModule } from "../../src/AccountingModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlexStrategy } from "../../src/FlexStrategy.sol";

contract MockStrategy is IFlexStrategy {
    IAccountingModule am;
    bool _hasRole;
    /// @notice Role for safe manager permissions
    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");

    /// @notice Role for processing rewards/losses
    bytes32 public constant ACCOUNTING_PROCESSOR_ROLE = keccak256("ACCOUNTING_PROCESSOR_ROLE");

    function setAccountingModule(IAccountingModule am_) public {
        am = am_;
        IERC20(am.BASE_ASSET()).approve(address(am), type(uint256).max);
        IERC20(am.ACCOUNTING_TOKEN()).approve(address(am), type(uint256).max);
    }

    function deposit(uint256 amount) public {
        IERC20(am.BASE_ASSET()).transferFrom(msg.sender, address(this), amount);
        am.deposit(amount);
    }

    function withdraw(uint256 amount) public {
        am.withdraw(amount);
        IERC20(am.BASE_ASSET()).transfer(msg.sender, amount);
    }

    function setHasRole(bool hr) public {
        _hasRole = hr;
    }

    function hasRole(bytes32, address) external view virtual returns (bool) {
        return _hasRole;
    }

    function processAccounting() public { }
}
