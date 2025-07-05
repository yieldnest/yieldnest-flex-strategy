// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IAccountingModule } from "./AccountingModule.sol";

interface IAccountingToken is IERC20, IERC20Metadata {
    function burnFrom(address burnAddress, uint256 burnAmount) external;
    function mintTo(address mintAddress, uint256 mintAmount) external;

    function TRACKED_ASSET() external view returns (address);
}

/**
 * @notice Storage struct for AccountingToken
 */
struct AccountingTokenStorage {
    address accountingModule;
}

/**
 * Accounting token that keeps track of baseAsset amount transferred to safe.
 */
contract AccountingToken is Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    error Unauthorized();
    error NotAllowed();
    error ZeroAddress();
    error AccountingTokenMismatch();

    event AccountingModuleUpdated(address newValue, address oldValue);

    address public immutable TRACKED_ASSET;

    /// @notice Storage slot for AccountingToken data
    bytes32 private constant ACCOUNTING_TOKEN_STORAGE_SLOT = keccak256("yieldnest.storage.accountingToken");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trackedAsset) {
        _disableInitializers();
        TRACKED_ASSET = trackedAsset;
    }

    /**
     * @notice Get the storage struct
     */
    function _getAccountingTokenStorage() internal pure returns (AccountingTokenStorage storage s) {
        bytes32 slot = ACCOUNTING_TOKEN_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /**
     * @param admin The address of the admin.
     * @param name_ The name of the accountingToken.
     * @param symbol_ The symbol of accountingToken.
     */
    function initialize(address admin, string memory name_, string memory symbol_) external virtual initializer {
        if (admin == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    modifier onlyAccounting() {
        if (msg.sender != _getAccountingTokenStorage().accountingModule) revert Unauthorized();
        _;
    }

    /**
     * @dev See {IERC20Metadata-decimals}.
     */
    function decimals() public view virtual override returns (uint8) {
        return IERC20Metadata(TRACKED_ASSET).decimals();
    }

    /**
     * @notice burn `burnAmount` from `burnAddress`
     * @param burnAddress address to burn from
     * @param burnAmount amount to burn
     */
    function burnFrom(address burnAddress, uint256 burnAmount) external onlyAccounting {
        _burn(burnAddress, burnAmount);
    }

    /**
     * @notice mints `mintAmount` to `mintAddress`
     * @param mintAddress address to mint to
     * @param mintAmount amount to mint
     */
    function mintTo(address mintAddress, uint256 mintAmount) external onlyAccounting {
        _mint(mintAddress, mintAmount);
    }

    /**
     * @dev should not ordinarily be transferred
     */
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert NotAllowed();
    }

    /**
     * @dev should not ordinarily be transferred
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert NotAllowed();
    }

    /**
     * Update accounting module address
     * @param accountingModule_ new accounting module address
     */
    function setAccountingModule(address accountingModule_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (accountingModule_ == address(0)) revert ZeroAddress();
        AccountingTokenStorage storage s = _getAccountingTokenStorage();
        emit AccountingModuleUpdated(accountingModule_, s.accountingModule);

        if (address(IAccountingModule(accountingModule_).accountingToken()) != address(this)) {
            revert AccountingTokenMismatch();
        }

        s.accountingModule = accountingModule_;
    }

    /// VIEWS ///

    function accountingModule() public view returns (address) {
        return _getAccountingTokenStorage().accountingModule;
    }
}
