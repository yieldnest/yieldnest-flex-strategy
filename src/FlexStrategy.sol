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
    error AccountingModuleMismatch();

    event AccountingModuleUpdated(address newValue, address oldValue);

    function accountingModule() external view returns (IAccountingModule);
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

    bytes32 public constant ACCOUNTING_MODULE_MANAGER_ROLE = keccak256("ACCOUNTING_MODULE_MANAGER_ROLE");

    /// @notice The version of the flex strategy contract.
    string public constant FLEX_STRATEGY_VERSION = "0.2.0";

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
     * @param accountingModuleManager The address that can update the accounting module.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param baseAsset The base asset of the vault.
     * @param paused_ Whether the vault should start in a paused state.
     */
    function initialize(
        address admin,
        address accountingModuleManager,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address baseAsset,
        address accountingToken,
        bool paused_,
        address provider,
        bool alwaysComputeTotalAssets
    )
        external
        virtual
        initializer
    {
        if (admin == address(0)) revert ZeroAddress();
        if (accountingModuleManager == address(0)) revert ZeroAddress();

        _initialize(
            admin,
            name,
            symbol,
            decimals_,
            paused_,
            false, // countNativeAsset. MUST be false. strategy is assumed to hold no native assets
            alwaysComputeTotalAssets, // alwaysComputeTotalAssets
            0 // defaultAssetIndex. MUST be 0. baseAsset is default
        );

        _grantRole(ACCOUNTING_MODULE_MANAGER_ROLE, accountingModuleManager);

        _addAsset(baseAsset, IERC20Metadata(baseAsset).decimals(), true);
        _addAsset(accountingToken, IERC20Metadata(accountingToken).decimals(), false);
        _setAssetWithdrawable(baseAsset, true);
        // Permissioned by default
        _setHasAllocator(true);

        VaultLib.setProvider(provider);
    }

    modifier hasAccountingModule() {
        if (address(_getFlexStrategyStorage().accountingModule) == address(0)) revert NoAccountingModule();
        _;
    }

    /**
     * @notice Sets the accounting module.
     * @param accountingModule_ address to check.
     * @dev Will revoke approvals for outgoing accounting module, and approve max for incoming accounting module.
     */
    function setAccountingModule(address accountingModule_) external virtual onlyRole(ACCOUNTING_MODULE_MANAGER_ROLE) {
        if (accountingModule_ == address(0)) revert ZeroAddress();

        IAccountingModule newAccounting = IAccountingModule(accountingModule_);
        if (newAccounting.strategy() != address(this)) revert AccountingModuleMismatch();
        if (newAccounting.safe() == address(0)) revert ZeroAddress();

        FlexStrategyStorage storage flexStorage = _getFlexStrategyStorage();
        emit AccountingModuleUpdated(accountingModule_, address(flexStorage.accountingModule));

        IAccountingModule oldAccounting = flexStorage.accountingModule;

        if (address(oldAccounting) != address(0)) {
            IERC20(asset()).forceApprove(address(oldAccounting), 0);

            if (newAccounting.accountingToken() != oldAccounting.accountingToken()) {
                revert AccountingTokenMismatch();
            }
        }

        flexStorage.accountingModule = newAccounting;
        IERC20(asset()).forceApprove(accountingModule_, type(uint256).max);
    }

    /**
     * @notice Internal function to get the available amount of assets.
     * @param asset_ The address of the asset.
     * @return availableAssets The available amount of assets.
     * @dev Overriden. This function is used to calculate the available assets for a given asset,
     *      It returns the balance of the asset in the associated SAFE.
     *      This assumes the strategy only accepts the base asset and the non-depositable accounting token.
     *      If additional depositable assets are enabled, base-asset availability may exceed the strategy's
     *      accounting token balance and overstate what the accounting module can withdraw.
     */
    function _availableAssets(address asset_) internal view virtual override returns (uint256 availableAssets) {
        address baseAsset = asset();
        if (asset_ == baseAsset) {
            return IERC20(baseAsset).balanceOf(_getFlexStrategyStorage().accountingModule.safe());
        }

        return super._availableAssets(asset_);
    }

    /**
     * @notice Returns the fee on total amount.
     * @return 0 as this strategy does not charge any fee on total amount.
     */
    function _feeOnTotal(uint256, address) public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the fee on total amount.
     * @return 0 as this strategy does not charge any fee on total amount.
     */
    function _feeOnRaw(uint256, address) public view virtual override returns (uint256) {
        return 0;
    }

    /// VIEWS ///

    function accountingModule() public view returns (IAccountingModule) {
        return _getFlexStrategyStorage().accountingModule;
    }
}
