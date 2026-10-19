// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../interfaces/StakingManager/IKvcmStakingFacet.sol";
import "../../interfaces/StakingManager/IK2StakingFacet.sol";
import "../../interfaces/StakingManager/IKvcmLPStakingFacet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

/**
 * @title StakingManagerStorage
 * @dev Provides isolated storage structures for different staking mechanisms
 * Each component has its own storage slot to prevent collisions
 */
library StakingManagerStorage {
    // Storage positions - each component gets a unique storage slot
    // Reference: https://eips.ethereum.org/EIPS/eip-7201

    bytes32 constant STAKING_MANAGER_PAUSE =
        keccak256(abi.encode(uint256(keccak256("staking-manager.pause.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant STAKING_MANAGER_CONFIG =
        keccak256(abi.encode(uint256(keccak256("staking-manager.config.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant KVCM_STAKING_POSITION =
        keccak256(abi.encode(uint256(keccak256("staking-manager.kvcm.staking.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant K2_STAKING_POSITION =
        keccak256(abi.encode(uint256(keccak256("staking-manager.k2.staking.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant LP_STAKING_POSITION =
        keccak256(abi.encode(uint256(keccak256("staking-manager.lp.staking.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant INTEGRATION_CONFIG_POSITION = keccak256(
        abi.encode(uint256(keccak256("staking-manager.integration.config.storage")) - 1)
    ) & ~bytes32(uint256(0xff));

    // Global configuration
    // @custom:storage-location erc7201:staking-manager.pause.storage
    struct StakingManagerPauseLayout {
        bool systemPaused;
        bool kvcmStakingPaused;
        bool k2StakingPaused;
        bool lpStakingPaused;
        uint256[50] _gap;
    }

    struct IntegrationConfig {
        address zkMeCooperator;
        address zkMeVerify;
        bool zkMeRequired;
    }

    struct IntegrationConfigLayout {
        address zkMeCooperator;
        address zkMeVerify;
        bool zkMeRequired;
        uint256[50] _gap;
    }

    struct StakingManagerConfig {
        address accessManager;
        address aam;
        address kvcmToken;
        address k2Token;
        address rewardManager;
        address maturityManager;
        address carbonLedger;
        address kvcmLocks;
        address kvcmLocksManager;
        address k2YieldToken;
        address retirementAggregator;
    }

    // @custom:storage-location erc7201:staking-manager.config.storage
    struct StakingManagerConfigLayout {
        address accessManager;
        address aam;
        address kvcmToken;
        address k2Token;
        address rewardManager;
        address maturityManager;
        address carbonLedger;
        address kvcmLocks;
        address kvcmLocksManager;
        address k2YieldToken;
        address zkMeCooperator; // deprecated, use integrationConfig instead
        address zkMeVerify; // deprecated, use integrationConfig instead
        bool zkMeRequired; // deprecated, use integrationConfig instead
        address retirementAggregator;
        uint256[49] _gap;
    }

    // @custom:storage-location erc7201:staking-manager.kvcm.staking.storage
    struct KvcmStakingLayout {
        mapping(address user => mapping(uint128 maturityId => uint256 lockId)) userKvcmLockIds;
        mapping(uint256 lockId => IKvcmStakingFacet.KvcmLockInfo) kvcmLocks;
        mapping(uint128 maturityId => uint256 totalKvcmLocked) lockByMaturity;
        mapping(uint256 lockId => EnumerableMap.AddressToUintMap lockAllocations) lockAllocations;
        mapping(address carbonClass => uint256 totalAllocations) allocationsByCarbonClass;
        //////////////////////////////////////////////////////////////////////////////
        // This mapping is required to track the price allocations for a maturity.
        // At midnight we will need to reset allocations for all carbonClasses once the maturity is over.
        mapping(uint128 maturityId => EnumerableMap.AddressToUintMap classToAllocationMap) priceAllocationsByMaturity;
        //////////////////////////////////////////////////////////////////////////////
        uint256 _nextLockId;
        uint128 minKvcmLockAmount;
        uint256 totalKvcmLocked;
        uint256[50] _gap;
    }

    // @custom:note we only need one k2 lock per user.
    // @dev If a user adds to a position, we calculate their reward from RM, add to amount and then set startTimestamp
    // @dev claimTimestamp is initialized empty and set on claim request by user

    struct K2StakingLayout {
        uint128 minLockPeriod; // default 1 days
        uint128 maxLockId;
        uint128 minLockAmount;
        uint128 maxLockAmount;
        uint256 totalK2Locked;
        uint256 totalK2Allocations;
        mapping(address user => IK2StakingFacet.K2LockInfo) userK2Locks;
        mapping(address carbonClass => uint256 totalAllocations) allocationsByCarbonClass;
        uint256[50] _gap;
    }

    /**
     * @dev Information about a specific LP staking pair
     */
    struct LPStakingPairInfo {
        uint256 totalStaked;
        address token0;
        address token1;
        bool isActive;
        uint256[50] _gap;
    }

    /**
     * @dev Main storage layout for LP staking functionality
     */
    struct LPStakingLayout {
        EnumerableMap.AddressToUintMap lpToLatestStakeId;
        mapping(
            address lpToken => mapping(uint256 maturityId => mapping(address user => IKvcmLPStakingFacet.LpStakeInfo))
        ) userStakeMapping;
        // Pair configuration and totals
        mapping(address lpToken => mapping(uint256 maturityId => uint256 totalLpStaked)) pairMaturityTotalStaked; // this is used
        mapping(address lpToken => address facet) pairModules;
        mapping(address lpToken => LPStakingPairInfo pairInfo) pairs;
        mapping(address lpToken => bool isAuthorized) authorizedLPTokens;
        // Global totals for reward calculations
        uint256 totalLockedKvcm;
        uint256 totalLockedK2;
        uint256[50] _gap;
    }

    function configLayout() internal pure returns (StakingManagerConfigLayout storage l) {
        bytes32 position = STAKING_MANAGER_CONFIG;
        assembly {
            l.slot := position
        }
    }

    function integrationConfigLayout() internal pure returns (IntegrationConfigLayout storage l) {
        bytes32 position = INTEGRATION_CONFIG_POSITION;
        assembly {
            l.slot := position
        }
    }

    function managerPauseLayout() internal pure returns (StakingManagerPauseLayout storage l) {
        bytes32 position = STAKING_MANAGER_PAUSE;
        assembly {
            l.slot := position
        }
    }

    function kvcmStakingLayout() internal pure returns (KvcmStakingLayout storage l) {
        bytes32 position = KVCM_STAKING_POSITION;
        assembly {
            l.slot := position
        }
    }

    function k2StakingLayout() internal pure returns (K2StakingLayout storage l) {
        bytes32 position = K2_STAKING_POSITION;
        assembly {
            l.slot := position
        }
    }

    function lpStakingLayout() internal pure returns (LPStakingLayout storage l) {
        bytes32 position = LP_STAKING_POSITION;
        assembly {
            l.slot := position
        }
    }
}
