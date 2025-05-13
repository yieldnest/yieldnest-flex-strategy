// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseStrategy } from "@yieldnest-vault/strategy/BaseStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccountingModule } from "./AccountingModule.sol";

interface IFlexStrategy {
    error OnlyBaseAsset();

    event SafeUpdated(address newValue, address oldValue);

    function isSafeManager(address maybeAllocator) external view returns (bool);
}

contract FlexStrategy is IFlexStrategy, BaseStrategy {
    using SafeERC20 for IERC20;

    /// @notice Role for safe manager permissions
    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");

    address public safe;
    AccountingModule public accountingModule;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param strategySafe The safe that will custody strategy principal.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        address strategySafe,
        address baseAsset
    )
        external
        virtual
        initializer
    {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        addAsset(baseAsset, true);

        accountingModule = new AccountingModule(
            string.concat("v-", name), string.concat("v-", symbol), address(this), baseAsset, strategySafe, 1000, 1000
        );

        // TODO: set fixed rate provider for 1:1 tokens
        // add provider here? 1 baseAsset === 1 accountingModule.ACCOUNTING_TOKEN()
        //  _getVaultStorage().provider = provider;

        IERC20(baseAsset).approve(address(accountingModule), type(uint256).max);
        IERC20(accountingModule.ACCOUNTING_TOKEN()).approve(address(accountingModule), type(uint256).max);

        // TODO: approve on safe: IERC20(baseAsset).approve(accountingModule, type(uint256).max);
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
     * @notice Checks if an address has the SAFE_MANAGER_ROLE
     * @param addr address to check
     * @return true if address has role
     */
    function isSafeManager(address addr) external view virtual override returns (bool) {
        return hasRole(SAFE_MANAGER_ROLE, addr);
    }

    /**
     * @notice Allows an address with the SAFE_MANAGER_ROLE to specify a new safe address
     * @param newSafe new address
     */
    function setSafeAddress(address newSafe) external virtual onlyRole("SAFE_MANAGER_ROLE") {
        emit SafeUpdated(newSafe, safe);
        safe = newSafe;
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
