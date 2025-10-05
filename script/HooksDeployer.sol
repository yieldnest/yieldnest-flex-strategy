pragma solidity ^0.8.28;

import { AccountingModuleHook } from "src/hooks/AccountingModuleHook.sol";
import { IAccountingModule } from "src/AccountingModule.sol";

contract HooksDeployer {
    function deployAccountingModuleHook(
        address vault,
        address accountingModule,
        address flexStrategy
    )
        public
        returns (AccountingModuleHook)
    {
        AccountingModuleHook accountingModuleHook =
            new AccountingModuleHook(vault, IAccountingModule(accountingModule), flexStrategy);
        return accountingModuleHook;
    }
}
