// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../libraries/CommonStructs.sol";

/**
 * @title CarbonLedgerStorage
 * @dev Library that manages namespaced storage layout for CarbonLedger
 */
library CarbonLedgerStorage {
    // Enums
    enum Status {
        Unregistered,
        Registered
    }

    // Storage namespaces
    struct ClassRegistryStorage {
        mapping(address => Status) carbonClassStatus;
        uint256[49] __gap;
    }

    struct CreditRegistryStorage {
        mapping(address classVault => mapping(address credit => Status)) creditStatusForClass;
        mapping(address classVault => mapping(address credit => mapping(uint256 tokenId => Status)))
            tokenIdStatusForClass;
        mapping(address creditToken => CommonStructs.CreditConfig creditConfig) creditConfigs;
        uint256[49] __gap;
    }

    struct LiquidityManagementStorage {
        mapping(address classVault => mapping(address credit => uint256)) dustRemovalTimestamps;
        uint256[49] __gap;
    }

    /**
     * @dev Stores configuration settings for the CarbonLedger contract
     * @custom:field accessManager The address of the access manager contract
     * @custom:field systemPaused The boolean flag to check if the system is paused
     * @custom:field maxTokenIdsPerMigration Maximum number of tokenIds allowed per migration
     * @custom:field maxTokenIdsPerUnregister Maximum number of tokenIds allowed per unregister call
     */
    struct ConfigStorage {
        address accessManager;
        bool systemPaused;
        uint256 maxTokenIdsPerMigration;
        uint256 maxTokenIdsPerUnregister;
        uint256[48] __gap;
    }

    // Storage slots - constant across all implementations
    bytes32 constant CLASS_REGISTRY_POSITION = keccak256("carbonledger.storage.classregistry");
    bytes32 constant CREDIT_REGISTRY_POSITION = keccak256("carbonledger.storage.creditregistry");
    bytes32 constant LIQUIDITY_MANAGEMENT_POSITION = keccak256("carbonledger.storage.liquiditymanagement");
    bytes32 constant CONFIG_POSITION = keccak256("carbonledger.storage.config");

    // Storage accessors
    function getClassRegistryStorage() internal pure returns (ClassRegistryStorage storage s) {
        bytes32 position = CLASS_REGISTRY_POSITION;
        assembly {
            s.slot := position
        }
    }

    function getCreditRegistryStorage() internal pure returns (CreditRegistryStorage storage s) {
        bytes32 position = CREDIT_REGISTRY_POSITION;
        assembly {
            s.slot := position
        }
    }

    function getLiquidityManagementStorage() internal pure returns (LiquidityManagementStorage storage s) {
        bytes32 position = LIQUIDITY_MANAGEMENT_POSITION;
        assembly {
            s.slot := position
        }
    }

    function getConfigStorage() internal pure returns (ConfigStorage storage s) {
        bytes32 position = CONFIG_POSITION;
        assembly {
            s.slot := position
        }
    }
}
