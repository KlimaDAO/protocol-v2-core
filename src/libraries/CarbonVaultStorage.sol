// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/ICarbonClassVault.sol";
import "../libraries/CommonStructs.sol";

/**
 * @title CarbonVaultStorage
 * @dev Library that manages storage layout for Carbon Class Vaults
 */
library CarbonVaultStorage {
    // Storage namespaces

    /// @dev Namespace for basic vault information
    struct VaultConfigStorage {
        string name; // vault name
        address carbonLedger;
        address maturityManager; // Added maturityManager address
        address accessManager; // Address of the access manager contract
        address registrationManager; // Address of the vault registration manager contract
        uint256 maxBatchSize; // Max tokens per batch operation (0 = unlimited)
        uint256[49] __gap;
    }

    /// @dev Namespace for carbon class coupons
    struct CouponStorage {
        uint256 reservedTonnes; // Tonnes reserved by coupons
        uint256[49] __gap;
    }

    struct RegisteredTokenConfig {
        uint256 index; // Index of the token in the registeredCarbonCredits array
        uint256[] tokenIds; // Array of token IDs for the token
    }

    /// @dev Namespace for token management
    struct TokenManagementStorage {
        mapping(address creditToken => CommonStructs.CreditConfig creditConfig) creditConfigs;
        mapping(address creditToken => RegisteredTokenConfig registeredTokenConfig) registeredCarbonCreditsMap;
        mapping(address creditToken => mapping(uint256 tokenId => uint256 index)) tokenIdIndexMap;
        address[] registeredERC20CarbonCredits;
        address[] registeredERC1155CarbonCredits;
        uint256[49] __gap;
    }

    /// @dev Namespace for tonnes accounting
    struct VaultAccountingStorage {
        uint256 totalTonnes; // Tracks total tonnes (scaled by precision)
        mapping(address tokenAddress => mapping(uint256 tokenId => uint256 amount)) carbonCreditDeposits;
        uint256[49] __gap;
    }

    /// @dev Namespace for maturity-based accounting
    struct MaturityAccountingStorage {
        // Track total tonnes by maturity ID
        mapping(uint256 maturityId => uint256 tonnes) maturityTonnes;
        // Track tonnes by maturity ID, token address, and token ID
        mapping(uint256 maturityId => mapping(address tokenAddress => mapping(uint256 tokenId => uint256 tonnes)))
            maturityTokenTonnes;
        // Track liquid carbon tonnes
        uint256 liquidTonnes; // Total tonnes that are currently liquid
        mapping(address tokenAddress => mapping(uint256 tokenId => uint256 tonnes)) liquidTokenTonnes;
        uint256[49] __gap;
    }

    // Storage slots - constant across all implementations
    bytes32 constant VAULT_CONFIG_POSITION = keccak256("carbonvault.storage.vaultconfig");
    bytes32 constant TOKEN_MANAGEMENT_POSITION = keccak256("carbonvault.storage.tokenmanagement");
    bytes32 constant VAULT_ACCOUNTING_POSITION = keccak256("carbonvault.storage.tonnesaccounting");
    bytes32 constant COUPON_STORAGE_POSITION = keccak256("carbonvault.storage.couponstorage");
    bytes32 constant MATURITY_ACCOUNTING_POSITION = keccak256("carbonvault.storage.maturityaccounting");

    // Storage accessors

    function getVaultConfigStorage() internal pure returns (VaultConfigStorage storage s) {
        bytes32 position = VAULT_CONFIG_POSITION;
        assembly {
            s.slot := position
        }
    }

    function getTokenManagementStorage() internal pure returns (TokenManagementStorage storage s) {
        bytes32 position = TOKEN_MANAGEMENT_POSITION;
        assembly {
            s.slot := position
        }
    }

    function getVaultAccountingStorage() internal pure returns (VaultAccountingStorage storage s) {
        bytes32 position = VAULT_ACCOUNTING_POSITION;
        assembly {
            s.slot := position
        }
    }

    function getCouponStorage() internal pure returns (CouponStorage storage s) {
        bytes32 position = COUPON_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function getMaturityAccountingStorage() internal pure returns (MaturityAccountingStorage storage s) {
        bytes32 position = MATURITY_ACCOUNTING_POSITION;
        assembly {
            s.slot := position
        }
    }
}
