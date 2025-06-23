// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseStrategy } from "@yieldnest-vault/strategy/BaseStrategy.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccountingModule } from "./AccountingModule.sol";
import { VaultLib } from "lib/yieldnest-vault/src/library/VaultLib.sol";

interface IFlexStrategy {
    error NoAccountingModule();
    error InvariantViolation();
    error AccountingTokenMismatch();

    event AccountingModuleUpdated(address newValue, address oldValue);
}

/**
 * @notice Storage struct for FlexStrategy
 */
struct FlexStrategyStorage {
    IAccountingModule accountingModule;
}

/**
 * Flex strategy that proxies the deposited base asset to an associated safe,
 * minting IOU accounting tokens in the process to represent transferred assets.
 */
contract FlexStrategy is IFlexStrategy, BaseStrategy {
    using SafeERC20 for IERC20;

    /// @notice The version of the flex strategy contract.
    string public constant FLEX_STRATEGY_VERSION = "0.1.0";

    /// @notice Storage slot for FlexStrategy data
    bytes32 private constant FLEX_STRATEGY_STORAGE_SLOT = keccak256("yieldnest.storage.flexStrategy");

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Get the storage struct
     */
    function _getFlexStrategyStorage() internal pure returns (FlexStrategyStorage storage s) {
        bytes32 slot = FLEX_STRATEGY_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param baseAsset The base asset of the vault.
     * @param paused_ Whether the vault should start in a paused state.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address baseAsset,
        address accountingToken,
        bool paused_,
        address provider
    )
        external
        virtual
        initializer
    {
        if (admin == address(0)) revert ZeroAddress();

        _initialize(
            admin,
            name,
            symbol,
            decimals_,
            paused_,
            false, // countNativeAsset. MUST be false. strategy is assumed to hold no native assets
            false, // alwaysComputeTotalAssets. MUST be false. totalAssets == total accounting tokens in strategy
            0 // defaultAssetIndex. MUST be 0. baseAsset is default, and only, asset
        );

        _addAsset(baseAsset, IERC20Metadata(baseAsset).decimals(), true);
        _addAsset(accountingToken, IERC20Metadata(accountingToken).decimals(), false);
        _setAssetWithdrawable(baseAsset, true);

        VaultLib.setProvider(provider);
    }

    modifier hasAccountingModule() {
        if (address(_getFlexStrategyStorage().accountingModule) == address(0)) revert NoAccountingModule();
        _;
    }

    modifier checkInvariantsAfter() {
        _;

        IERC20 asset = IERC20(asset());

        if (
            totalAssets()
                != IERC20(_getFlexStrategyStorage().accountingModule.accountingToken()).balanceOf(address(this))
        ) {
            revert InvariantViolation();
        }
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
        hasAccountingModule
        checkInvariantsAfter
    {
        // call the base strategy deposit function for accounting
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        // virtual accounting
        _getFlexStrategyStorage().accountingModule.deposit(assets);
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
        hasAccountingModule
        onlyAllocator
        checkInvariantsAfter
    {
        if (asset_ != asset()) {
            revert InvalidAsset(asset_);
        }

        // call the base strategy withdraw function for accounting
        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        // burn virtual tokens
        _getFlexStrategyStorage().accountingModule.withdraw(assets, receiver);
        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Sets the accounting module.
     * @param accountingModule_ address to check.
     * @dev Will revoke approvals for outgoing accounting module, and approve max for incoming accounting module.
     */
    function setAccountingModule(address accountingModule_) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (accountingModule_ == address(0)) revert ZeroAddress();

        FlexStrategyStorage storage flexStorage = _getFlexStrategyStorage();
        emit AccountingModuleUpdated(accountingModule_, address(flexStorage.accountingModule));

        IAccountingModule oldAccounting = flexStorage.accountingModule;

        if (address(oldAccounting) != address(0)) {
            IERC20(asset()).approve(address(oldAccounting), 0);

            if (IAccountingModule(accountingModule_).accountingToken() != oldAccounting.accountingToken()) {
                revert AccountingTokenMismatch();
            }
        }

        flexStorage.accountingModule = IAccountingModule(accountingModule_);
        IERC20(asset()).approve(accountingModule_, type(uint256).max);
    }

    /**
     * @notice Processes the accounting of the vault by calculating the total base balance.
     * @dev This function iterates through the list of assets, gets their balances and rates,
     *      and updates the total assets denominated in the base asset.
     */
    function processAccounting() public virtual override nonReentrant checkInvariantsAfter {
        _processAccounting();
    }

    /**
     * @notice Internal function to get the available amount of assets.
     * @param asset_ The address of the asset.
     * @return availableAssets The available amount of assets.
     * @dev Overriden. This function is used to calculate the available assets for a given asset,
     *      It returns the balance of the asset in the associated SAFE.
     */
    function _availableAssets(address asset_) internal view virtual override returns (uint256 availableAssets) {
        if (asset_ == asset()) {
            return IERC20(asset()).balanceOf(_getFlexStrategyStorage().accountingModule.safe());
        }

        return super._availableAssets(asset_);
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

    /// VIEWS ///

    function accountingModule() public view returns (IAccountingModule) {
        return _getFlexStrategyStorage().accountingModule;
    }
}
