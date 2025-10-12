// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import { IValidator } from "@yieldnest-vault/interface/IVault.sol";
import { SafeRules, IVault } from "@yieldnest-vault-script/rules/SafeRules.sol";

library FlexStrategyRules {
    function getDepositRule(address contractAddress) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({ paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0) });

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({ isActive: true, paramRules: paramRules, validator: IValidator(address(0)) });

        return SafeRules.RuleParams({ contractAddress: contractAddress, funcSig: funcSig, rule: rule });
    }

    function getWithdrawRule(
        address contractAddress,
        address receiver
    )
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({ paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0) });

        address[] memory allowList = new address[](1);
        allowList[0] = address(receiver);

        paramRules[1] = IVault.ParamRule({ paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList });

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({ isActive: true, paramRules: paramRules, validator: IValidator(address(0)) });

        return SafeRules.RuleParams({ contractAddress: contractAddress, funcSig: funcSig, rule: rule });
    }
}
