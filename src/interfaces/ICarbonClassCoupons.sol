// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ICarbonClassCoupons
 * @dev Interface for the Carbon Class Coupons system that allows creation and
 * management of coupon tokens representing carbon tonnes in a CarbonClassVault.
 */
interface ICarbonClassCoupons {
    // Events
    event CouponsIssued(address indexed account, uint256 tonnes);
    event CouponsBurned(address indexed account, uint256 tonnes);

    // Core coupon functions
    function issueCoupons(address account, uint256 tonnes) external;
    function burnCoupons(address account, uint256 tonnes) external;
}
