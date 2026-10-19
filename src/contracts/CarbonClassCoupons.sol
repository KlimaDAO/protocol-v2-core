// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
// Note: This comment indicates we're ensuring correct import for the non-upgradeable AccessManager
import "../interfaces/ICarbonClassCoupons.sol";
import "../libraries/CarbonVaultStorage.sol";
import "../libraries/CarbonTonnageLib.sol";
import "../libraries/Errors.sol";
import "../libraries/CommonStructs.sol";
import "../libraries/CarbonSystemRoleLib.sol";

/**
 * @title CarbonClassCoupons
 * @dev Implementation of carbon coupons that represent carbon tonnes in a CarbonClassVault.
 *      This contract uses the OpenZeppelin upgradeable pattern and is designed to be inherited by CarbonClassVault.
 *      It is not intended to be deployed as a standalone contract.
 *      Uses AccessManaged for role-based access control.
 */
contract CarbonClassCoupons is ICarbonClassCoupons, Initializable, ERC20Upgradeable {
    using CarbonVaultStorage for CarbonVaultStorage.CouponStorage;
    using CarbonVaultStorage for CarbonVaultStorage.VaultAccountingStorage;
    using CarbonTonnageLib for CommonStructs.ConversionConfig;

    // ============== Constructor and Initializers ==============

    /**
     * @dev Constructor - empty for upgradeable contracts
     * The real initialization happens in the initialize function
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Leave empty - initialization will happen in initialize function
    }

    function __CarbonClassCoupons_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init(name_, symbol_);
    }

    // ============== Modifier ==============
    modifier onlyCouponsIssuer() {
        address accessManager = CarbonVaultStorage.getVaultConfigStorage().accessManager;
        bool isAuthorized = false;

        // Check if caller has any of the authorized roles
        (bool hasIssuerRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_COUPONS_ISSUER, msg.sender);
        (bool hasAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);
        (bool hasLiquidityManagerRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_COUPONS_LIQUIDITY_MANAGER, msg.sender);

        isAuthorized = hasIssuerRole || hasAdminRole || hasLiquidityManagerRole;

        if (!isAuthorized) revert Errors.NotCouponsIssuer();
        _;
    }

    modifier onlyCouponsBurner() {
        address accessManager = CarbonVaultStorage.getVaultConfigStorage().accessManager;
        bool isAuthorized = false;

        // Check if caller has any of the authorized roles
        (bool hasAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);
        (bool hasLiquidityManagerRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_COUPONS_LIQUIDITY_MANAGER, msg.sender);

        isAuthorized = hasAdminRole || hasLiquidityManagerRole;

        if (!isAuthorized) revert Errors.NotCouponsLiquidityManager();
        _;
    }

    /**
     * @dev Issues coupons to an account (simple reserve function)
     * @param account The account to issue coupons to
     * @param tonnes The amount of tonnes to issue
     */
    function issueCoupons(address account, uint256 tonnes) external override onlyCouponsIssuer {
        _issueCoupons(account, tonnes);
    }

    /**
     * @dev Internal function to issue coupons
     * @param account The account to issue coupons to
     * @param tonnes The amount of tonnes to issue
     */
    function _issueCoupons(address account, uint256 tonnes) internal {
        if (account == address(0)) revert Errors.ZeroAddressForCoupons();
        if (tonnes == 0) revert Errors.ZeroAmountForCoupons();

        // Check available tonnes
        uint256 liquidTonnes = CarbonVaultStorage.getMaturityAccountingStorage().liquidTonnes;
        uint256 reservedTonnes = CarbonVaultStorage.getCouponStorage().reservedTonnes;
        if (liquidTonnes < reservedTonnes + tonnes) revert Errors.InsufficientAvailableTonnes();

        // Update reserved tonnes
        CarbonVaultStorage.getCouponStorage().reservedTonnes += tonnes;

        // Mint tokens
        _mint(account, tonnes);

        emit CouponsIssued(account, tonnes);
    }

    /**
     * @dev Burns coupons and releases reserved tonnes
     * @param account The account to burn from
     * @param tonnes The amount to burn
     */
    function burnCoupons(address account, uint256 tonnes) external override onlyCouponsBurner {
        _burnCoupons(account, tonnes);
    }

    /**
     * @dev Internal function to burn coupons
     * @param account The account to burn from
     * @param tonnes The amount to burn
     */
    function _burnCoupons(address account, uint256 tonnes) internal {
        if (tonnes == 0) revert Errors.ZeroAmountForCoupons();

        // Check sufficient balance
        if (_getCouponBalance(account) < tonnes) revert Errors.InsufficientCouponBalance();

        _burn(account, tonnes);

        // Update reserved tonnes
        CarbonVaultStorage.CouponStorage storage couponStorage = CarbonVaultStorage.getCouponStorage();
        if (couponStorage.reservedTonnes < tonnes) revert Errors.CannotReleaseMoreThanReserved();
        couponStorage.reservedTonnes -= tonnes;

        emit CouponsBurned(account, tonnes);
    }

    function _getCouponBalance(address account) internal view returns (uint256) {
        return balanceOf(account);
    }
}
