// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/interfaces/ICarbonClassVault.sol";

/**
 * @title CarbonVaultStorage
 * @dev Library that manages storage layout for Carbon Class Vaults
 */
library CarbonVaultStorage {
    // Storage namespaces

    /// @dev Namespace for basic vault information
    struct VaultConfigStorage {
        string name;
        address carbonLedger;
    }

    /// @dev Namespace for token management
    struct TokenManagementStorage {
        address[] registeredTokens;
        mapping(address => ICarbonClassVault.AssetConfig) assetConfigs;
        mapping(address => mapping(uint256 => uint256)) erc1155Deposits;
    }

    /// @dev Namespace for tonnes accounting
    struct TonnesAccountingStorage {
        uint256 totalTonnes; // Tracks total tonnes (scaled by precision)
    }

    // Storage slots - constant across all implementations
    bytes32 constant VAULT_CONFIG_POSITION = keccak256("carbonvault.storage.vaultconfig");
    bytes32 constant TOKEN_MANAGEMENT_POSITION = keccak256("carbonvault.storage.tokenmanagement");
    bytes32 constant TONNES_ACCOUNTING_POSITION = keccak256("carbonvault.storage.tonnesaccounting");

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

    function getTonnesAccountingStorage() internal pure returns (TonnesAccountingStorage storage s) {
        bytes32 position = TONNES_ACCOUNTING_POSITION;
        assembly {
            s.slot := position
        }
    }
}
