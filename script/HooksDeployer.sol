pragma solidity ^0.8.28;

import { AccountingModuleHook } from "src/hooks/AccountingModuleHook.sol";

contract HooksDeployer {
    function deployAccountingModuleHook(address vault, address flexStrategy) public returns (AccountingModuleHook) {
        AccountingModuleHook accountingModuleHook = new AccountingModuleHook(vault, flexStrategy);
        return accountingModuleHook;
    }
}
