// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import { IVault } from "lib/yieldnest-vault/src/interface/IVault.sol";
import { IHooks } from "lib/yieldnest-vault/src/interface/IHooks.sol";
import { IAccountingModule } from "../AccountingModule.sol";
import { IFlexStrategy } from "../FlexStrategy.sol";

/**
 * @title FeeHooks
 * @notice FeeHooks for the Vault
 * @dev This contract gets callback from the vault it's attached to
 */
contract AccountingModuleHook is IHooks {
    error NotSupported();

    /// @notice The vault contract that this hooks contract is attached to
    IVault public immutable VAULT;

    IVault public immutable flexStrategy;

    /**
     * @notice Constructor
     * @param vault_ The address of the Vault to which this hooks contract is attached
     */
    constructor(address vault_, IAccountingModule, address flexStrategy_) {
        VAULT = IVault(payable(vault_));
        flexStrategy = IVault(payable(flexStrategy_));
    }

    /// @inheritdoc IHooks
    function name() external pure override returns (string memory) {
        return "AccountingModuleHook";
    }

    /**
     * @notice Modifier to ensure that the caller is the Vault
     */
    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        _;
    }

    /**
     * @notice Set the config (unused)
     */
    function setConfig(Config memory) external pure {
        revert NotSupported();
    }

    /**
     * @notice Get the hooks config
     * @return The hooks config struct
     */
    function getConfig() external pure returns (Config memory) {
        return Config({
            beforeDeposit: false,
            afterDeposit: true,
            beforeMint: false,
            afterMint: true,
            beforeRedeem: true,
            afterRedeem: false,
            beforeWithdraw: true,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: false
        });
    }

    /**
     * @notice Get the current accounting module from the strategy.
     * @dev Accounting module rotation is not fully handled by this lookup alone.
     *      When the strategy accounting module changes, processor rules and the
     *      accounting token's accounting module pointer must be updated as well.
     */
    function accountingModule() public view returns (IAccountingModule) {
        return IFlexStrategy(address(flexStrategy)).accountingModule();
    }

    /**
     * @notice Deposit to the accounting module
     * @param asset The asset to deposit
     * @param amount The amount to deposit
     */
    function depositToAccountingModule(address asset, uint256 amount) internal {
        IAccountingModule currentAccountingModule = accountingModule();

        if (asset == currentAccountingModule.baseAsset()) {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldata_ = new bytes[](1);

            targets[0] = address(currentAccountingModule);
            values[0] = 0;
            calldata_[0] = abi.encodeWithSignature("deposit(uint256)", amount);

            flexStrategy.processor(targets, values, calldata_);
        }
    }

    /**
     * @notice Withdraw from the accounting module
     * @param asset The asset to withdraw
     * @param assets The amount to withdraw
     */
    function withdrawFromAccountingModule(address asset, uint256 assets) internal {
        IAccountingModule currentAccountingModule = accountingModule();

        if (asset == currentAccountingModule.baseAsset()) {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldata_ = new bytes[](1);

            targets[0] = address(currentAccountingModule);
            values[0] = 0;
            calldata_[0] = abi.encodeWithSignature("withdraw(uint256,address)", assets, address(flexStrategy));

            flexStrategy.processor(targets, values, calldata_);
        }
    }

    /**
     * @notice Before withdraw hook function
     * @dev This hook is called before the withdraw is processed
     * @dev This hook is called before the shares and assets are updated in the vault
     * @param params The withdraw parameters
     */
    function beforeWithdraw(WithdrawParams calldata params) external onlyVault {
        withdrawFromAccountingModule(params.asset, params.assets);
    }

    /**
     * @notice After redeem hook function
     * @dev This hook is called after the redeem is processed
     * @param params The redeem parameters
     */
    function afterRedeem(RedeemParams calldata params) external onlyVault { }

    /**
     * @notice Before deposit hook function
     * @dev This hook is called before the deposit is processed
     * @param params The deposit parameters
     */
    function beforeDeposit(DepositParams calldata params) external onlyVault { }

    /**
     * @notice After deposit hook function
     * @dev This hook is called after the deposit is processed
     * @param params The deposit parameters
     */
    function afterDeposit(DepositParams calldata params) external onlyVault {
        depositToAccountingModule(params.asset, params.assets);
    }

    /**
     * @notice Before mint hook function
     * @dev This hook is called before the mint is processed
     * @param params The mint parameters
     */
    function beforeMint(MintParams calldata params) external onlyVault { }

    /**
     * @notice After mint hook function
     * @dev This hook is called after the mint is processed
     * @param params The mint parameters
     */
    function afterMint(MintParams calldata params) external onlyVault {
        depositToAccountingModule(params.asset, params.assets);
    }

    /**
     * @notice Before redeem hook function
     * @dev This hook is called before the redeem is processed
     * @param params The redeem parameters
     */
    function beforeRedeem(RedeemParams calldata params) external onlyVault {
        withdrawFromAccountingModule(params.asset, params.assets);
    }

    /**
     * @notice After withdraw hook function
     * @dev This hook is called after the withdraw is processed
     * @param params The withdraw parameters
     */
    function afterWithdraw(WithdrawParams calldata params) external onlyVault { }

    /**
     * @notice Before process accounting hook function
     * @dev This hook is called before the accounting is processed
     * @param params The before process accounting parameters
     */
    function beforeProcessAccounting(BeforeProcessAccountingParams calldata params) external onlyVault { }

    /**
     * @notice After process accounting hook function
     * @dev This hook is called after the accounting is processed
     * @param params The after process accounting parameters
     */
    function afterProcessAccounting(AfterProcessAccountingParams calldata params) external onlyVault { }
}
