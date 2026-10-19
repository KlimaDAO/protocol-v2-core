// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title AssetManagerStorage
 * @dev Provides isolated storage structures for the Asset Manager components
 * Each component has its own storage slot to prevent collisions
 */
library AssetManagerStorage {
    // Storage positions - each component gets a unique storage slot
    // Reference: https://eips.ethereum.org/EIPS/eip-7201
    bytes32 constant CONFIG_POSITION =
        keccak256(abi.encode(uint256(keccak256("asset-manager.config.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant ROUTER_POSITION =
        keccak256(abi.encode(uint256(keccak256("asset-manager.router.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant QUOTER_MANAGER_POSITION =
        keccak256(abi.encode(uint256(keccak256("asset-manager.quoter-manager.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant CLASS_QUOTER_POSITION =
        keccak256(abi.encode(uint256(keccak256("asset-manager.class-quoter.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant DISCOUNT_FACTORS_POSITION = keccak256(
        abi.encode(uint256(keccak256("asset-manager.discount-factors.storage")) - 1)
    ) & ~bytes32(uint256(0xff));

    // Struct to store quoter facet and selector
    struct QuoterInfo {
        address facetAddress;
        bytes4 functionSelector;
        bool isActive;
        uint256[50] _gap;
    }

    struct AssetManagerConfig {
        address accessManager;
        address kvcm;
        address protocolSupplyOracle;
        address protocolMinter;
        address maturityManager;
        address stakingManager;
        address rewardManager;
        address carbonLedger;
        address retirementAggregator;
    }

    // Global configuration
    struct AssetManagerConfigLayout {
        bool systemPaused;
        AssetManagerConfig aamConfig;
        bool initialized;
        uint256[50] _gap;
    }

    // Router storage
    struct RouterLayout {
        mapping(address => bool) authorizedCallers;
        uint256[50] _gap;
    }

    // Quoter Manager storage
    struct QuoterManagerLayout {
        // Maps carbon class to quoter info (facet address and function selector)
        mapping(address => QuoterInfo) classQuoters;
        // List of supported carbon classes
        address[] supportedClasses;
        uint256[50] _gap;
    }

    // Class Quoter Storage
    struct RateLimiter {
        uint128 snapshotValue; // last captured value
        uint64 lastUpdateTimestamp;
        uint64 rate; // kvcm rate == 1 / 24
    }

    // Allocation below which the limiter never binds; above it, effective allocation ramps at the limiter rate.
    struct MinEffectiveAllocation {
        uint128 kvcm;
        uint128 k2;
    }

    struct ClassQuoterData {
        address carbonClass;
        bool isActive;
        bool exists; // Flag to track if this quoter exists
        uint256 index; // Index in the quoterAddresses array
        uint256 lastUpdateTimestamp;
        RateLimiter liquidSupplyRateLimiter;
        RateLimiter kvcmAllocationRateLimiter;
        RateLimiter k2AllocationRateLimiter;
        uint256[50] _gap; // Adjusted gap
    }

    struct DiscountedForwardBalanceIndexRecord {
        bool discountForwardBalanceInitializedForDay;
        uint256 discountedForwardBalanceForCurrentMidnightIndex;
        uint256[50] _gap;
    }

    struct ClassQuoterLayout {
        // Maps quoter addresses to their data
        mapping(address => ClassQuoterData) quoters;
        // Maps quoter facet addresses to their supported carbon class
        mapping(address => address) quoterToClass;
        // Maps carbon class to its associated quoter
        mapping(address => address) classToQuoter;
        // Maps carbon class to its associated class selector
        mapping(address => bytes4) classToSelector;
        // List of all registered quoter addresses
        address[] quoterAddresses;
        // adjusted class forward balance for current midnight index
        mapping(uint256 midnightIndex => mapping(address carbonClass => DiscountedForwardBalanceIndexRecord))
            discountedForwardBalancesForCurrentMidnightIndex;
        // Rate limiting
        uint64 defaultKVCMRate;
        uint64 defaultK2Rate;
        uint256 fallbackK2AllocationSnapshotValue;
        mapping(address carbonClass => MinEffectiveAllocation) classMinEffectiveAllocation;
        uint256[49] _gap; // Adjusted gap
    }

    // Storage accessor functions - one for each component
    function configLayout() internal pure returns (AssetManagerConfigLayout storage l) {
        bytes32 position = CONFIG_POSITION;
        assembly {
            l.slot := position
        }
    }

    function routerLayout() internal pure returns (RouterLayout storage l) {
        bytes32 position = ROUTER_POSITION;
        assembly {
            l.slot := position
        }
    }

    function quoterManagerLayout() internal pure returns (QuoterManagerLayout storage l) {
        bytes32 position = QUOTER_MANAGER_POSITION;
        assembly {
            l.slot := position
        }
    }

    function classQuoterLayout() internal pure returns (ClassQuoterLayout storage l) {
        bytes32 position = CLASS_QUOTER_POSITION;
        assembly {
            l.slot := position
        }
    }
}
