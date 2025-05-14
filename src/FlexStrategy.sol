// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseStrategy } from "@yieldnest-vault/strategy/BaseStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountingModule } from "./AccountingModule.sol";

interface IFlexStrategy {
    error OnlyBaseAsset();
    error NoAccountingModule();

    event AccountingModuleUpdated(address newValue, address oldValue);

    function isSafeManager(address addr) external view returns (bool);
}

contract FlexStrategy is IFlexStrategy, BaseStrategy {
    using SafeERC20 for IERC20;

    /// @notice Role for safe manager permissions
    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");

    IAccountingModule public accountingModule;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     */
    function initialize(address admin, string memory name, string memory symbol) external virtual initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset conversion of shares.
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    )
        internal
        virtual
        override
    {
        // only base asset is depositable into safe
        if (asset_ != accountingModule.BASE_ASSET()) revert OnlyBaseAsset();

        if (address(accountingModule) == address(0)) revert NoAccountingModule();

        // call the base strategy deposit function for accounting
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        // virtual accounting
        accountingModule.deposit(assets);
    }

    /**
     * @notice Internal function to handle withdrawals for base asset
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdrawAsset(
        address asset_,
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        virtual
        override
    {
        // only base asset is depositable into safe
        if (asset_ != accountingModule.BASE_ASSET()) revert OnlyBaseAsset();

        if (address(accountingModule) == address(0)) revert NoAccountingModule();

        // check if the asset is withdrawable
        if (!_getBaseStrategyStorage().isAssetWithdrawable[asset_]) {
            revert AssetNotWithdrawable();
        }

        // call the base strategy withdraw function for accounting
        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        // burn virtual tokens
        accountingModule.withdraw(assets);
        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Sets the accounting module.
     * @param accountingModule_ address to check.
     * @dev Will revoke approvals for outgoing accounting module, and approve max for incoming accounting module.
     */
    function setAccountingModule(address accountingModule_) external onlyRole("SAFE_MANAGER_ROLE") {
        if (accountingModule_ == address(0)) revert ZeroAddress();
        emit AccountingModuleUpdated(accountingModule_, address(accountingModule));

        IAccountingModule oldAccounting = accountingModule;

        if (address(oldAccounting) != address(0)) {
            IERC20(asset()).approve(address(oldAccounting), 0);
            IERC20(oldAccounting.ACCOUNTING_TOKEN()).approve(address(oldAccounting), 0);
        }

        accountingModule = IAccountingModule(accountingModule_);
        IERC20(asset()).approve(accountingModule_, type(uint256).max);
        IERC20(IAccountingModule(accountingModule_).ACCOUNTING_TOKEN()).approve(accountingModule_, type(uint256).max);
    }

    /**
     * @notice Checks if an address has the SAFE_MANAGER_ROLE
     * @param addr address to check
     * @return true if address has role
     */
    function isSafeManager(address addr) external view virtual override returns (bool) {
        return hasRole(SAFE_MANAGER_ROLE, addr);
    }

    /**
     * @notice Returns the fee on total amount.
     * @return 0 as this strategy does not charge any fee on total amount.
     */
    function _feeOnTotal(uint256) public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the fee on total amount.
     * @return 0 as this strategy does not charge any fee on total amount.
     */
    function _feeOnRaw(uint256) public view virtual override returns (uint256) {
        return 0;
    }
}
