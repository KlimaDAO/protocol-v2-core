// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title CarbonSystemRoleLib
 * @dev Library that defines the different roles in the Carbon system for use with AccessManager
 * Roles are ordered by privilege level (highest to lowest)
 */
library CarbonSystemRoleLib {
    /// @dev Role for system-wide administration, contract upgrades, highest privilege level
    uint64 constant CARBON_SYSTEM_ADMIN = 1;

    /// @dev Role for carbon ledger-specific administration, can manage classes and credits
    uint64 constant CARBON_LEDGER_ADMIN = 2;

    /// @dev Role for managing carbon vaults (can register/unregister carbon credits, etc.)
    uint64 constant CARBON_VAULT_MANAGER = 3;

    /// @dev Role for carbon ledger manager (register/unregister classes, etc.)
    uint64 constant CARBON_LEDGER_MANAGER = 4;

    /// @dev Role for carbon liquidity manager (add/remove liquidity)
    uint64 constant CARBON_LIQUIDITY_MANAGER = 5;

    /// @dev Role for managing carbon coupons liquidity and burning
    uint64 constant CARBON_COUPONS_LIQUIDITY_MANAGER = 6;

    /// @dev Role for issuing carbon coupons
    uint64 constant CARBON_COUPONS_ISSUER = 7;

    /// @dev Role for managing maturity manager
    uint64 constant CARBON_MATURITY_MANAGER = 8;

    /// @dev Role for managing staking manager
    uint64 constant KVCM_STAKING_MANAGER_ADMIN = 9;

    /// @dev Role for managing kvcm lock NFT
    uint64 constant KVCM_LOCK_NFT_OWNER = 10;

    /// @dev Role for managing kvcm lock NFT
    uint64 constant KVCM_LOCK_NFT_MANAGER = 11;

    /// @dev Role for managing risky yield state updater
    uint64 constant REWARDS_MANAGER_STATE_UPDATER = 12;

    /// @dev Role for managing protocol rewards escrow
    uint64 constant PROTOCOL_REWARDS_ESCROW_MANAGER = 13;

    /// @dev Role for managing protocol minter
    uint64 constant PROTOCOL_REWARDS_MINTER = 14;

    /// @dev Role for automated maturity execution operations (daily jobs)
    uint64 constant CARBON_MATURITY_EXECUTOR = 15;

    /// @dev Role for contracts allowed to update beta state in RewardManager
    uint64 constant BETA_UPDATER = 16;
}
