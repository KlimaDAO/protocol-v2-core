// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {DiscountFactorStorage64} from "./DiscountFactorStorage64.sol";

library RewardManagerStorage {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    // ============================================================================
    // Storage Position Constants (EIP-7201: Namespaced Storage Layout)
    // ============================================================================
    // Formula: keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff))
    // Reference: https://eips.ethereum.org/EIPS/eip-7201

    // Rewards Manager Core Storage
    // @custom:storage-location erc7201:reward-manager.storage
    bytes32 constant RM_STORAGE_POSITION =
        keccak256(abi.encode(uint256(keccak256("reward-manager.storage")) - 1)) & ~bytes32(uint256(0xff));

    // @custom:storage-location erc7201:reward-manager.config.storage
    bytes32 constant RM_CONFIG_POSITION =
        keccak256(abi.encode(uint256(keccak256("reward-manager.config.storage")) - 1)) & ~bytes32(uint256(0xff));

    // @custom:storage-location erc7201:reward-manager.pause.storage
    bytes32 constant REWARD_MANAGER_PAUSE =
        keccak256(abi.encode(uint256(keccak256("reward-manager.pause.storage")) - 1)) & ~bytes32(uint256(0xff));

    // Risky Yield Storage
    // @custom:storage-location erc7201:reward-manager.risky-yield.storage
    bytes32 constant RISKY_YIELD_POSITION =
        keccak256(abi.encode(uint256(keccak256("reward-manager.risky-yield.storage")) - 1)) & ~bytes32(uint256(0xff));

    // K2 Yield Storage
    // @custom:storage-location erc7201:reward-manager.k2.yield.storage
    bytes32 constant K2_YIELD_POSITION =
        keccak256(abi.encode(uint256(keccak256("reward-manager.k2.yield.storage")) - 1)) & ~bytes32(uint256(0xff));

    // @custom:storage-location erc7201:reward-manager.k2.yield.curve.storage
    bytes32 constant K2_YIELD_CURVE_POSITION = keccak256(
        abi.encode(uint256(keccak256("reward-manager.k2.yield.curve.storage")) - 1)
    ) & ~bytes32(uint256(0xff));

    // Kvcm Lock Storage
    // @custom:storage-location erc7201:reward-manager.kvcm.lock.yield.storage
    bytes32 constant KVCM_LOCK_YIELD_POSITION = keccak256(
        abi.encode(uint256(keccak256("reward-manager.kvcm.lock.yield.storage")) - 1)
    ) & ~bytes32(uint256(0xff));

    // @custom:storage-location erc7201:reward-manager.kvcm.lock.realtime.yield.curve.storage
    bytes32 constant KVCM_LOCK_REALTIME_YIELD_CURVE_POSITION = keccak256(
        abi.encode(uint256(keccak256("reward-manager.kvcm.lock.realtime.yield.curve.storage")) - 1)
    ) & ~bytes32(uint256(0xff));

    // @custom:storage-location erc7201:reward-manager.discount.factors.storage
    bytes32 constant DISCOUNT_FACTORS_POSITION = keccak256(
        abi.encode(uint256(keccak256("reward-manager.discount.factors.storage")) - 1)
    ) & ~bytes32(uint256(0xff));

    // Kvcm Lock Position
    // @custom:storage-location erc7201:reward-manager.locks.storage
    bytes32 constant LOCKS_POSITION =
        keccak256(abi.encode(uint256(keccak256("reward-manager.locks.storage")) - 1)) & ~bytes32(uint256(0xff));

    // @custom:storage-location erc7201:reward-manager.config.storage (duplicate reference)
    bytes32 constant REWARD_MANAGER_CONFIG =
        keccak256(abi.encode(uint256(keccak256("reward-manager.config.storage")) - 1)) & ~bytes32(uint256(0xff));

    // ============================================================================
    // Enums
    // ============================================================================

    enum LockStatus {
        UNINITIALIZED,
        INITIALIZED,
        OPEN,
        MATURED,
        PARTIAL_CLAIMED,
        CLAIMED
    }

    // ============================================================================
    // Core Configuration & Pause Structures
    // ============================================================================

    struct RMConfig {
        address aam;
        address accessManager;
        address protocolSupplyOracle;
        address protocolMinter;
        address stakingManager;
        address kvcmToken;
        address k2Token;
        address maturityManager;
        address kvcmK2LPToken;
        address kvcmQLPToken;
        address riskyYieldToken;
        address k2YieldToken;
        address protocolRewardsEscrow;
    }

    /// @custom:storage-location erc7201:reward-manager.config.storage
    struct RMConfigLayout {
        address aam;
        address accessManager;
        address protocolSupplyOracle;
        address protocolMinter;
        address stakingManager;
        address kvcmToken;
        address k2Token;
        address maturityManager;
        address kvcmK2LPToken;
        address kvcmQLPToken;
        address riskyYieldToken;
        address k2YieldToken;
        address protocolRewardsEscrow;
        uint256[50] _gap;
    }

    /// @notice Pause states for different reward manager features
    /// @custom:storage-location erc7201:reward-manager.pause.storage
    struct RewardManagerPauseLayout {
        bool systemPaused;
        bool kvcmLockPaused;
        bool k2LockPaused;
        bool riskyYieldPaused;
        uint256[50] _gap;
    }

    // ============================================================================
    // Shared/Common Structures
    // ============================================================================

    /// @notice Daily snapshot of accumulator values
    struct AccumulatorSnapshot {
        uint256 midnightAccumulator;
    }

    /// @notice Global rewards state for a reward pool
    /// @dev Used for both RiskyYield and K2InflationRewards
    struct GlobalRewardsState {
        uint256 totalRewards;
        uint256 totalShares;
        uint256 globalAccumulator;
        uint256 lastKeeperUpdate;
    }

    /// @notice Single day entry record for LP position
    struct Entry {
        uint256 shares; // Eligible shares for that particular day
        uint256 settledMidnightIndex;
    }

    struct DailyLambdaCache {
        uint256 tblambdaG; // time and beta weighted lambdaG
        uint256 tblambdaQ; // time and beta weighted lambdaQ
        uint256 tblambdaGG; // time and beta weigted lambdaGG
        uint64 lastLambdaUpdateTimestamp; // timestamp of last lambda update for this midnight
    }

    // ============================================================================
    // LP Rewards Structures
    // ============================================================================

    /// @notice Full LP rewards position with historical entries
    /// @dev Used for both RiskyYield and K2InflationRewards
    struct LPRewardsPosition {
        uint256 shares;
        uint256 pendingYield;
        uint64 lastSettlementMidnightIndex;
        DoubleEndedQueue.Bytes32Deque entriesDeque; // Stores entry midnightIndexes
        mapping(uint256 midnightIndex => Entry entry) entryRecords;
    }

    /// @notice View-only struct for LP rewards position
    struct LPRewardsPositionView {
        uint256 shares;
        uint256 pendingYield;
        uint64 lastSettlementMidnightIndex;
    }

    // ============================================================================
    // K2 Staker Structures
    // ============================================================================

    /// @notice Full K2 staker position with claimable yield from withdrawals
    struct K2StakerPosition {
        uint256 shares;
        uint256 pendingYield;
        uint256 claimableYield; // Rewards from burned shares, ready for claim
        DoubleEndedQueue.Bytes32Deque entriesDeque;
        mapping(uint256 midnightIndex => Entry entry) entryRecords;
    }

    /// @notice View-only struct for K2 staker position
    struct K2StakerPositionView {
        uint256 shares;
        uint256 pendingYield;
        uint256 claimableYield;
    }

    // ============================================================================
    // KVCM Staker K2 Rewards Structures
    // ============================================================================

    struct KVCMStakersK2RewardsPosition {
        uint256 shares;
        uint256 pendingYield;
        uint64 lastSettlementMidnightIndex;
        DoubleEndedQueue.Bytes32Deque entriesDeque; // Stores entry midnightIndexes
        mapping(uint256 midnightIndex => Entry entry) entryRecords;
    }

    struct KVCMStakersK2RewardsPositionView {
        uint256 shares;
        uint256 pendingYield;
        uint64 lastSettlementMidnightIndex;
    }

    // ============================================================================
    // KVCM Lock Structures
    // ============================================================================

    /// @custom:storage-location erc7201:reward-manager.kvcm.lock.yield.storage
    struct KvcmLockYieldLayout {
        // cadence
        uint128 yieldDistributionInterval;
        // rolls
        uint128 lastMidnightIndexYieldDistribution;
        // totals
        mapping(uint256 maturityId => MaturityTotals maturityTotals) currentMaturityTotals;
        mapping(uint256 midnightIndex => IntervalData intervalData) intervalData;
        // daily total locked, init at midnight timestamp (or index) key totalLocked for that day value
        mapping(uint256 midnightIndex => mapping(uint256 maturityId => MaturityIntervalData maturityIntervalData))
            maturityIntervalData;
        // discount factors
        // @dev a retire or swap operation will need to read this for the first op of the day
        // therefore, as retirements are more likely, use this separate mapping from above and pack for efficiency
        // currently uses 10 slots (maturityId <> discount factor)
        mapping(uint256 midnightIndex => DiscountFactorStorage64.PackedDiscountFactorsLayout) discountFactors;
    }

    /// @notice Maturity interval specific data for lock yield
    struct MaturityIntervalData {
        uint128 ppsAtRoll;
        uint128 totalSharesAtRoll; // totalSharesAtRoll * ppsAtRoll should equal totalEffectivePrincipalAtRoll
        uint128 yieldForCurrentInterval;
        uint256 depositsDuringInterval;
        uint256 totalEffectivePrincipalAtRoll; // Optional, used in getFullCurveValuesForInterval
        uint256[50] _gap;
    }

    /// @notice Interval-level data for lock yield distribution
    struct IntervalData {
        bool settled;
        uint128 rollTimestamp;
        uint128 discountParameterAtRoll; // Used: distribute <> calculate <> write curve values
        uint256 supplyAtRoll; // Written by distribute function
        uint256 kVCMYield; // Written by distribute function
    }

    /// @notice Maturity totals for lock yield tracking
    struct MaturityTotals {
        uint256 lastUpdateTimestamp;
        uint256 totalRawPrincipal;
        uint256 totalSharesForMaturity;
        uint256 totalMintedYieldRemaining;
        uint256[50] _gap;
    }

    /// @notice Individual Kvcm Lock storage
    struct KvcmLock {
        uint128 maturityId;
        uint128 midnightIndexStart;
        DoubleEndedQueue.Bytes32Deque unprocessedDeposits;
        uint256 rawPrincipal;
        uint256 shares; // = principal * 1e18 / pps[midnightIndexStart]
        uint256 yieldDistributed;
        LockStatus status;
        uint256[50] _gap;
    }

    /// @notice View-only struct for Kvcm Lock
    struct KvcmLockView {
        uint128 maturityId;
        uint128 midnightIndexStart;
        uint128[][] unprocessedDeposits;
        uint256 rawPrincipal;
        uint256 shares; // = principal * 1e18 / pps[midnightIndexStart]
        LockStatus status;
        uint256 yieldDistributed;
        uint256[50] _gap;
    }

    /// @notice Container for all Kvcm Locks
    /// @custom:storage-location erc7201:reward-manager.locks.storage
    struct KvcmLocksLayout {
        mapping(uint256 lockId => KvcmLock lock) kvcmLocks;
        uint256[50] _gap;
    }

    // ============================================================================
    // Risky Yield Structures
    // ============================================================================

    /// @notice Cache for Risky Yield beta calculations
    struct RYBetaCache {
        uint256 kvcmAllocation;
        uint256 k2Allocation;
    }

    /// @notice Risky Yield specific storage and calculations
    /// @custom:storage-location erc7201:reward-manager.risky-yield.storage
    struct RiskyYieldLayout {
        uint128 lastProcessedMidnightIndexK2; // Tracks the last midnight index for which K2 RY was distributed
        mapping(address lpToken => uint128 lastProcessed) lastProcessedMidnightIndexPerLP; // Tracks last midnight for each LP token
        mapping(address carbonClass => RYBetaCache betaCache) betaMappingForCarbonClass;
        uint256[50] _gap;
    }

    // ============================================================================
    // K2 Yield Structures
    // ============================================================================

    /// @notice K2 Yield specific storage and calculations
    /// @custom:storage-location erc7201:reward-manager.k2.yield.storage
    struct K2YieldLayout {
        // Tracks last midnight index for KVCM stakers K2 yield
        uint64 lastProcessedMidnightIndexKVCM;
        // Tracks last midnight index for K2 stakers K2 yield
        uint64 lastProcessedMidnightIndexK2Stakers;
        // Tracks last midnight index for treasury K2 yield
        uint64 lastProcessedMidnightIndexTreasury;
        mapping(address lpToken => uint128 lastProcessed) lastProcessedMidnightIndexPerLP; // Tracks last midnight for each LP token
        uint256[50] _gap;
    }

    /// @notice K2 Yield Curve specific storage and calculations
    /// @custom:storage-location erc7201:reward-manager.k2.yield.curve.storage
    struct K2YieldCurveLayout {
        // ----------------- Config (immutable-like) -----------------
        uint256 rewardCap; // total reward pool (e.g., 40M * 10^decimals)
        // ----------------- Schedule (mutable) -----------------
        uint256 start; // TGE timestamp
        uint256 T; // inflection point in seconds (e.g., 2*365 days)
        uint256 duration; // clamp horizon in seconds (e.g., 8*365 days)
        int256 x0; // log-odds in SD59x18
        uint256 P0_wad; // P0 in 1e18 (cached)
        uint256 P_end_wad; // P(duration) in 1e18 (cached)
        // ----------------- State -----------------
        uint256 cumulativeOffset; // tokens allocated before schedule updates (for monotonicity)
        uint256[50] _gap;
    }

    // ============================================================================
    // Main Rewards Manager Storage
    // ============================================================================

    /// @custom:storage-location erc7201:reward-manager.storage
    struct RMStorage {
        // --- LP Rewards ---

        // Risky Yield
        mapping(
            address lpToken => mapping(uint256 maturityId => mapping(address user => LPRewardsPosition position))
        ) lpRYieldPosition;
        mapping(address lpToken => mapping(uint256 maturityId => GlobalRewardsState global)) lpRYieldGlobal;
        mapping(
            address lpToken
                => mapping(uint256 maturityId => mapping(uint256 midnightIndex => AccumulatorSnapshot snapshot))
        ) lpRYieldAccSnapshot;
        // --- K2 Yield ---
        mapping(
            address lpToken => mapping(uint256 maturityId => mapping(address user => LPRewardsPosition position))
        ) lpK2YieldPosition;
        mapping(address lpToken => mapping(uint256 maturityId => GlobalRewardsState global)) lpK2YieldGlobal;
        mapping(
            address lpToken
                => mapping(uint256 maturityId => mapping(uint256 midnightIndex => AccumulatorSnapshot snapshot))
        ) lpK2YieldAccSnapshot;
        //-----
        // --- K2 Staker Rewards ---

        // Risky Yield
        mapping(address user => K2StakerPosition position) k2RYPositions;
        mapping(uint256 midnightIndex => AccumulatorSnapshot snapshot) k2RYieldAccSnapshot;
        // K2 Yield
        mapping(address user => K2StakerPosition position) k2YieldPosition;
        mapping(uint256 midnightIndex => AccumulatorSnapshot snapshot) k2K2YieldAccSnapshot;
        GlobalRewardsState k2StakersRYGlobal;
        GlobalRewardsState k2StakersK2YieldGlobal;
        //------

        // --- KVCM K2 Yield ---
        mapping(uint256 maturityId => GlobalRewardsState global) kvcmK2YieldGlobal;
        mapping(uint256 maturityId => mapping(uint256 midnightIndex => AccumulatorSnapshot snapshot))
            kvcmK2YieldAccSnapshot;
        mapping(uint256 maturityId => mapping(address user => KVCMStakersK2RewardsPosition position))
            kvcmK2YieldPosition;
        //------

        // --- Lambda Cache ---
        mapping(uint256 midnightIndex => DailyLambdaCache lambdaCache) dailyLambdaCache;
        // --- Beta Cache ---
        mapping(uint256 midnightIndex => uint256 betaSq) betaSqCache; // Stores betaSq (beta squared) per dayId (scale = 18)
        uint256 lastNonZeroBetaSqIndex; // Tracks the midnightIndex of the last non-zero betaSq for O(1) lookup
        uint256[50] _gap;
    }

    // ============================================================================
    // Storage Accessor Functions
    // ============================================================================

    // --- Core Rewards Manager Storage ---

    function rmStorage() internal pure returns (RMStorage storage s) {
        bytes32 position = RM_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function rmConfig() internal pure returns (RMConfigLayout storage c) {
        return configLayout();
    }

    function configLayout() internal pure returns (RMConfigLayout storage l) {
        bytes32 position = RM_CONFIG_POSITION;
        assembly {
            l.slot := position
        }
    }

    function managerPauseLayout() internal pure returns (RewardManagerPauseLayout storage l) {
        bytes32 position = REWARD_MANAGER_PAUSE;
        assembly {
            l.slot := position
        }
    }

    // --- Risky Yield Storage ---

    function riskyYieldLayout() internal pure returns (RiskyYieldLayout storage l) {
        bytes32 position = RISKY_YIELD_POSITION;
        assembly {
            l.slot := position
        }
    }

    // --- K2 Yield Storage ---

    function k2YieldLayout() internal pure returns (K2YieldLayout storage l) {
        bytes32 position = K2_YIELD_POSITION;
        assembly {
            l.slot := position
        }
    }

    function k2YieldCurveLayout() internal pure returns (K2YieldCurveLayout storage l) {
        bytes32 position = K2_YIELD_CURVE_POSITION;
        assembly {
            l.slot := position
        }
    }

    // --- Kvcm Lock Storage ---

    function kvcmLockYieldLayout() internal pure returns (KvcmLockYieldLayout storage l) {
        bytes32 position = KVCM_LOCK_YIELD_POSITION;
        assembly {
            l.slot := position
        }
    }

    function kvcmLocksLayout() internal pure returns (KvcmLocksLayout storage l) {
        bytes32 position = LOCKS_POSITION;
        assembly {
            l.slot := position
        }
    }

    function discountFactorsLayout()
        internal
        pure
        returns (DiscountFactorStorage64.PackedDiscountFactorsLayout storage l)
    {
        bytes32 position = DISCOUNT_FACTORS_POSITION;
        assembly {
            l.slot := position
        }
    }
}
