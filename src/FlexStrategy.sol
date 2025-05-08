// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseStrategy } from "@yieldnest-vault/strategy/BaseStrategy.sol";
import { SafeVerifierLib } from "./library/SafeVerifierLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeAccountingModule } from "./SafeAccountingModule.sol";

contract FlexStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable SAFE;
    SafeAccountingModule public safeAccounting;

    /**
     * constructor
     * @param strategySafe The safe that will custody strategy principal.
     */
    constructor(address strategySafe) {
        _disableInitializers();

        SafeVerifierLib.verify(strategySafe);
        SAFE = strategySafe;
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

        safeAccounting = new SafeAccountingModule(string.concat("v-", name), string.concat("v-", name), address(this));

        // todo:  set fixed rate provider for 1:1 tokens
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
        // call the base strategy deposit function for accounting
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        // mint virtual tokens
        safeAccounting.deposit(assets);

        // transfer assets to safe
        IERC20(asset_).safeTransfer(SAFE, assets);
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

        // uint256 vaultBalance = IERC20(asset_).balanceOf(address(this));

        // burn virtual tokens
        safeAccounting.withdraw(assets);

        // transfer assets from SAFE to receiver
        // TODO: maybe dangerous. do more research
        SafeERC20.safeTransferFrom(IERC20(asset_), SAFE, receiver, assets);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    // TODO
    function _feeOnTotal(uint256) public view virtual override returns (uint256) {
        return 0;
    }

    // TODO
    function _feeOnRaw(uint256) public view virtual override returns (uint256) {
        return 0;
    }
}
