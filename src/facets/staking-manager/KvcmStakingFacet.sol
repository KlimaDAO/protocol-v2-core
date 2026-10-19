// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/* ─────────────────────── libraries ─────────────────────── */
import "../../libraries/LibDiamond.sol";
import "../../libraries/storage/StakingManagerStorage.sol";
import "../../libraries/Errors.sol";
import "../../libraries/IntegrationErrors.sol";
/* ─────────────────────── interfaces ─────────────────────── */
import "../../interfaces/IMaturityManager.sol";
import "../../interfaces/StakingManager/IKvcmStakingFacet.sol";
import "../../interfaces/StakingManager/IKvcmLock.sol";
import "../../interfaces/ICarbonLedger.sol";
import "../../interfaces/RewardManager/IRMKVCMStakers.sol";
import "../../interfaces/RewardManager/IKvcmIncentivesCurveFacet.sol";
import {IAssetManagerConfigFacet} from "../../interfaces/AssetManager/IAssetManagerConfigFacet.sol";
import {IRateLimiterFacet} from "../../interfaces/AssetManager/IRateLimiterFacet.sol";
import {IRiskyYieldFacet} from "../../interfaces/RewardManager/IRiskyYieldFacet.sol";
import {IRewardManagerViewFacet} from "../../interfaces/RewardManager/IRewardManagerViewFacet.sol";
/* ─────────────────────── openzeppelin ─────────────────────── */
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {ZkMeUtilsLib} from "./utils/zkMe.sol";
import {KvcmStakingLib} from "../../libraries/staking-manager/KvcmStakingLib.sol";

library KvcmStakingUtilsLib {
    function isKvcmLockMatured(uint256 lockId) internal view returns (bool) {
        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        IKvcmStakingFacet.KvcmLockInfo memory lockInfo = sKvcm.kvcmLocks[lockId];
        return lockInfo.maturityTimestamp <= block.timestamp;
    }

    function isKvcmLockOwned(uint256 lockId, address user) internal view returns (bool) {
        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        return sKvcm.kvcmLocks[lockId].lockOwner == user;
    }

    /**
     * @dev Validates amount and carbon class inputs for allocation operations
     * @param amount The amount to validate (must be > 0)
     * @param carbonClass The carbon class address to validate (must be registered)
     */
    function validateAmountAndCarbonClass(uint256 amount, address carbonClass) internal view {
        if (amount == 0) revert Errors.AmountCannotBeZero();
        if (carbonClass == address(0)) revert Errors.ZeroAddressNotAllowed();

        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        if (sConfig.carbonLedger == address(0)) revert Errors.ZeroAddressNotAllowed();

        ICarbonLedger(sConfig.carbonLedger).isClassRegistered(carbonClass, true);
    }
}

/**
 * @title KvcmStakingFacet
 * @dev This facet will be used to manage Kvcm Locking And PriceStaking
 */
contract KvcmStakingFacet is ReentrancyGuard, IKvcmStakingFacet {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyRewardManager() {
        if (msg.sender != StakingManagerStorage.configLayout().rewardManager) revert Errors.NotAuthorized();
        _;
    }

    modifier whenNotPaused() {
        if (
            StakingManagerStorage.managerPauseLayout().systemPaused
                || StakingManagerStorage.managerPauseLayout().kvcmStakingPaused
        ) {
            revert Errors.KvcmStakingPaused();
        }
        _;
    }

    modifier whenVerified(address user) {
        if (!ZkMeUtilsLib.hasApproved(user)) revert IntegrationErrors.ZkMeNotVerified(user);
        _;
    }

    // ============ EXTERNAL STATE-CHANGING FUNCTIONS ============

    /// @inheritdoc IKvcmStakingFacet
    function lockKvcm(uint256 amount, uint128 maturityId)
        external
        whenNotPaused
        whenVerified(msg.sender)
        nonReentrant
        returns (uint256 lockId)
    {
        return _lockKvcm(amount, maturityId, msg.sender);
    }

    /// @inheritdoc IKvcmStakingFacet
    function lockKvcmFor(uint256 amount, uint128 maturityId, address user_)
        external
        whenNotPaused
        whenVerified(user_)
        nonReentrant
        returns (uint256 lockId)
    {
        return _lockKvcm(amount, maturityId, user_);
    }

    /// @inheritdoc IKvcmStakingFacet
    function lockKvcmWithPermit(uint256 amount, uint128 maturityId, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        whenNotPaused
        whenVerified(msg.sender)
        nonReentrant
        returns (uint256 lockId)
    {
        return _lockKvcmWithPermit(amount, maturityId, msg.sender, deadline, v, r, s);
    }

    /// @inheritdoc IKvcmStakingFacet
    function lockKvcmForWithPermit(
        uint256 amount,
        uint128 maturityId,
        address user,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused whenVerified(user) nonReentrant returns (uint256 lockId) {
        return _lockKvcmWithPermit(amount, maturityId, user, deadline, v, r, s);
    }

    /// @inheritdoc IKvcmStakingFacet
    function unlockKvcm(uint256 lockId_)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 principal, uint256 accruedYield)
    {
        return KvcmStakingLib.unlock(lockId_, msg.sender, msg.sender, msg.sender);
    }

    /// @inheritdoc IKvcmStakingFacet
    function unlockKvcmTo(uint256 lockId_, address to)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 principal, uint256 accruedYield)
    {
        return KvcmStakingLib.unlock(lockId_, to, to, msg.sender);
    }

    /// @inheritdoc IKvcmStakingFacet
    function claimRemainingKvcmYield(uint256 lockId) external whenNotPaused nonReentrant {
        KvcmStakingLib.claimRemaining(lockId, msg.sender, msg.sender);
    }

    /// @inheritdoc IKvcmStakingFacet
    function claimRemainingKvcmYieldTo(uint256 lockId, address to) external whenNotPaused nonReentrant {
        KvcmStakingLib.claimRemaining(lockId, to, msg.sender);
    }

    /// @inheritdoc IKvcmStakingFacet
    function allocateKvcm(uint256 lockId, address carbonClass, uint256 amount)
        external
        whenNotPaused
        whenVerified(msg.sender)
        nonReentrant
    {
        KvcmStakingUtilsLib.validateAmountAndCarbonClass(amount, carbonClass);

        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        KvcmLockInfo storage lockInfo = sKvcm.kvcmLocks[lockId];

        if (KvcmStakingUtilsLib.isKvcmLockMatured(lockId)) revert Errors.KvcmLockMatured();
        if (!KvcmStakingUtilsLib.isKvcmLockOwned(lockId, msg.sender)) revert Errors.KvcmLockNotOwned();

        if (lockInfo.priceAllocations + amount > lockInfo.principal) {
            revert Errors.KvcmAllocationExceedsLock(amount, lockInfo.priceAllocations, lockInfo.principal);
        }

        sKvcm.kvcmLocks[lockId].priceAllocations += amount;

        uint256 classPreTxnAllocationAmount = sKvcm.allocationsByCarbonClass[carbonClass];

        // Will be read directly by the AAM for carbon_pricing
        sKvcm.allocationsByCarbonClass[carbonClass] += amount;

        uint256 existingLockAllocation = 0;
        if (sKvcm.lockAllocations[lockId].contains(carbonClass)) {
            existingLockAllocation = sKvcm.lockAllocations[lockId].get(carbonClass);
        }
        sKvcm.lockAllocations[lockId].set(carbonClass, existingLockAllocation + amount);

        // Get existing allocation for this maturity + carbon class, then add the new amount
        uint256 existingAggregateAllocation = 0;
        if (sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].contains(carbonClass)) {
            existingAggregateAllocation = sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].get(carbonClass);
        }

        sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].set(carbonClass, existingAggregateAllocation + amount);

        (,, uint256 nextMidnightIndex,) =
            IMaturityManager(sConfig.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightIndex == 0) revert Errors.InvalidMidnightTimestamp();
        uint64 nextDayId = SafeCast.toUint64(nextMidnightIndex);

        // Checkpoint lambdas FIRST with current parameters (elapsed time used OLD beta)
        // Read totalK2Allocations from K2 staking layout
        uint256 totalK2Allocations = StakingManagerStorage.k2StakingLayout().totalK2Allocations;
        IRiskyYieldFacet(sConfig.rewardManager).updateRewardsProportions(nextDayId, totalK2Allocations);
        // Then update beta for FUTURE periods
        IRiskyYieldFacet(sConfig.rewardManager).updateBetaSqForKvcmAllocation(amount, carbonClass, nextDayId);

        if (classPreTxnAllocationAmount > 0) {
            IRateLimiterFacet(sConfig.aam).updateKvcmAllocationRateLimiter(carbonClass, classPreTxnAllocationAmount, 0);
        } else {
            IRateLimiterFacet(sConfig.aam).updateKvcmAllocationRateLimiter(carbonClass, 0, amount);
        }
        emit KvcmLockAllocated(msg.sender, lockInfo.maturityId, carbonClass, amount);
    }

    /// @inheritdoc IKvcmStakingFacet
    function deallocateKvcm(uint256 lockId, address carbonClass, uint256 amount) external whenNotPaused nonReentrant {
        KvcmStakingUtilsLib.validateAmountAndCarbonClass(amount, carbonClass);

        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        KvcmLockInfo storage lockInfo = sKvcm.kvcmLocks[lockId];

        // Post Maturity it doesn't make sense to mess with Allocations
        if (!KvcmStakingUtilsLib.isKvcmLockOwned(lockId, msg.sender)) revert Errors.KvcmLockNotOwned();

        if (lockInfo.priceAllocations < amount) {
            revert Errors.DeallocationAmountExceedsLockPriceAllocations(lockInfo.priceAllocations, amount);
        }

        sKvcm.kvcmLocks[lockId].priceAllocations -= amount;

        (bool lockAllocationExists, uint256 existingLockAllocation) = sKvcm.lockAllocations[lockId].tryGet(carbonClass);

        if (!lockAllocationExists) {
            revert Errors.KvcmLockAllocationNotFound();
        }
        if (existingLockAllocation < amount) {
            revert Errors.DeallocationAmountExceedsAllocatedAmountForClass(carbonClass, existingLockAllocation);
        }

        if (existingLockAllocation == amount) {
            // This will refund gas!
            sKvcm.lockAllocations[lockId].remove(carbonClass);
        } else {
            sKvcm.lockAllocations[lockId].set(carbonClass, existingLockAllocation - amount);
        }

        (bool maturityAllocationExists, uint256 existingMaturityAllocation) =
            sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].tryGet(carbonClass);

        if (!maturityAllocationExists) {
            revert Errors.KvcmLockAllocationNotFound();
        }
        if (existingMaturityAllocation < amount) {
            revert Errors.DeallocationAmountExceedsAllocatedAmountForClass(carbonClass, existingMaturityAllocation);
        }

        if (existingMaturityAllocation == amount) {
            sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].remove(carbonClass);
        } else {
            sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].set(carbonClass, existingMaturityAllocation - amount);
        }

        sKvcm.allocationsByCarbonClass[carbonClass] -= amount;

        (,, uint256 nextMidnightIndex,) =
            IMaturityManager(sConfig.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightIndex == 0) revert Errors.InvalidMidnightTimestamp();
        uint64 nextDayId = SafeCast.toUint64(nextMidnightIndex);

        // Checkpoint lambdas FIRST with current parameters (elapsed time used OLD beta)
        // Read totalK2Allocations from K2 staking layout
        uint256 totalK2Allocations = StakingManagerStorage.k2StakingLayout().totalK2Allocations;
        IRiskyYieldFacet(sConfig.rewardManager).updateRewardsProportions(nextDayId, totalK2Allocations);
        // Then update beta for FUTURE periods
        IRiskyYieldFacet(sConfig.rewardManager).updateBetaSqForKvcmDeallocation(amount, carbonClass, nextDayId);

        emit KvcmLockDeallocated(msg.sender, lockInfo.maturityId, carbonClass, amount);
    }

    /// @inheritdoc IKvcmStakingFacet
    function reallocateKvcm(uint256 lockId, address fromCarbonClass, address toCarbonClass, uint256 amount)
        external
        whenNotPaused
        whenVerified(msg.sender)
        nonReentrant
    {
        KvcmStakingUtilsLib.validateAmountAndCarbonClass(amount, fromCarbonClass);
        KvcmStakingUtilsLib.validateAmountAndCarbonClass(amount, toCarbonClass);
        if (fromCarbonClass == toCarbonClass) revert Errors.InvalidAddress();

        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        KvcmLockInfo storage lockInfo = sKvcm.kvcmLocks[lockId];

        // Post Maturity it doesn't make sense to mess with Allocations
        if (KvcmStakingUtilsLib.isKvcmLockMatured(lockId)) revert Errors.KvcmLockMatured();
        if (!KvcmStakingUtilsLib.isKvcmLockOwned(lockId, msg.sender)) revert Errors.KvcmLockNotOwned();

        // Check if allocation exists in fromCarbonClass
        (bool lockAllocationExists, uint256 existingLockAllocation) =
            sKvcm.lockAllocations[lockId].tryGet(fromCarbonClass);

        if (!lockAllocationExists) {
            revert Errors.KvcmLockAllocationNotFound();
        }
        if (existingLockAllocation < amount) {
            revert Errors.DeallocationAmountExceedsAllocatedAmountForClass(fromCarbonClass, existingLockAllocation);
        }

        // Check maturity allocation exists in fromCarbonClass
        (bool maturityAllocationExists, uint256 existingMaturityAllocation) =
            sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].tryGet(fromCarbonClass);
        if (!maturityAllocationExists) {
            revert Errors.KvcmLockAllocationNotFound();
        }
        if (existingMaturityAllocation < amount) {
            revert Errors.DeallocationAmountExceedsAllocatedAmountForClass(fromCarbonClass, existingMaturityAllocation);
        }

        // Update fromCarbonClass allocations (decrease)
        // Update lock-level allocation
        if (existingLockAllocation == amount) {
            sKvcm.lockAllocations[lockId].remove(fromCarbonClass);
        } else {
            sKvcm.lockAllocations[lockId].set(fromCarbonClass, existingLockAllocation - amount);
        }

        // Update maturity-level aggregate allocation (separate condition)
        if (existingMaturityAllocation == amount) {
            sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].remove(fromCarbonClass);
        } else {
            sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].set(
                fromCarbonClass, existingMaturityAllocation - amount
            );
        }

        sKvcm.allocationsByCarbonClass[fromCarbonClass] -= amount;

        // Update toCarbonClass allocations (increase)
        uint256 existingToLockAllocation = 0;
        if (sKvcm.lockAllocations[lockId].contains(toCarbonClass)) {
            existingToLockAllocation = sKvcm.lockAllocations[lockId].get(toCarbonClass);
        }
        sKvcm.lockAllocations[lockId].set(toCarbonClass, existingToLockAllocation + amount);

        uint256 existingToMaturityAllocation = 0;
        if (sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].contains(toCarbonClass)) {
            existingToMaturityAllocation = sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].get(toCarbonClass);
        }
        sKvcm.priceAllocationsByMaturity[lockInfo.maturityId].set(toCarbonClass, existingToMaturityAllocation + amount);

        uint256 toClassPreTxnAllocationAmount = sKvcm.allocationsByCarbonClass[toCarbonClass];
        sKvcm.allocationsByCarbonClass[toCarbonClass] += amount;

        (,, uint256 nextMidnightIndex,) =
            IMaturityManager(sConfig.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightIndex == 0) revert Errors.InvalidMidnightTimestamp();
        uint64 nextDayId = SafeCast.toUint64(nextMidnightIndex);

        // Checkpoint lambdas FIRST with current parameters (elapsed time used OLD beta)
        // Read totalK2Allocations from K2 staking layout
        uint256 totalK2Allocations = StakingManagerStorage.k2StakingLayout().totalK2Allocations;
        IRiskyYieldFacet(sConfig.rewardManager).updateRewardsProportions(nextDayId, totalK2Allocations);
        // Then update beta for FUTURE periods (deallocation from one class, allocation to another)
        IRiskyYieldFacet(sConfig.rewardManager).updateBetaSqForKvcmDeallocation(amount, fromCarbonClass, nextDayId);
        IRiskyYieldFacet(sConfig.rewardManager).updateBetaSqForKvcmAllocation(amount, toCarbonClass, nextDayId);

        if (toClassPreTxnAllocationAmount > 0) {
            IRateLimiterFacet(sConfig.aam)
                .updateKvcmAllocationRateLimiter(toCarbonClass, toClassPreTxnAllocationAmount, 0);
        } else {
            IRateLimiterFacet(sConfig.aam).updateKvcmAllocationRateLimiter(toCarbonClass, 0, amount);
        }

        emit KvcmLockReallocated(msg.sender, lockInfo.maturityId, fromCarbonClass, toCarbonClass, amount);
    }

    // ============ EXTERNAL VIEW FUNCTIONS ============

    /// @inheritdoc IKvcmStakingFacet
    function getKvcmLockInfo(uint256 lockId) external view returns (IKvcmStakingFacet.KvcmLockInfo memory kb) {
        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        return sKvcm.kvcmLocks[lockId];
    }

    /// @inheritdoc IKvcmStakingFacet
    function getKvcmLockedForMaturity(uint128 maturityId) external view returns (uint256) {
        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        return sKvcm.lockByMaturity[maturityId];
    }

    /// @inheritdoc IKvcmStakingFacet
    function getKvcmLockedForMaturityRange(uint128 firstMaturityId, uint128 lastMaturityId)
        external
        view
        returns (uint256[] memory maturityTotalLocked, uint256 totalKvcmLocked)
    {
        if (lastMaturityId < firstMaturityId) revert Errors.InvalidMaturityRange(firstMaturityId, lastMaturityId);

        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();

        uint128 len = lastMaturityId - firstMaturityId + 1;

        uint256 sum;
        maturityTotalLocked = new uint256[](len);

        for (uint128 i = firstMaturityId; i <= lastMaturityId;) {
            uint128 index = i - firstMaturityId;
            uint256 amount = sKvcm.lockByMaturity[i];
            maturityTotalLocked[index] = amount;
            sum += amount;
            unchecked {
                ++i;
            }
        }
        totalKvcmLocked = sum;
    }

    /**
     * @dev This function is used to check if a Kvcm lock is matured
     * @param lockId The id of the lock to check
     * @return true if the lock is matured, false otherwise
     */
    function isKvcmLockMatured(uint256 lockId) external view returns (bool) {
        return KvcmStakingUtilsLib.isKvcmLockMatured(lockId);
    }

    /**
     * @dev This function is used to check if a Kvcm lock is owned by a user
     * @return totalKvcmLocked The total amount of Kvcm locked
     */
    function getTotalKvcmLocked() external view returns (uint256) {
        return StakingManagerStorage.kvcmStakingLayout().totalKvcmLocked;
    }

    /// @inheritdoc IKvcmStakingFacet
    function getKvcmAllocatedForCarbonClass(address carbonClass) external view returns (uint256) {
        return StakingManagerStorage.kvcmStakingLayout().allocationsByCarbonClass[carbonClass];
    }

    /// @inheritdoc IKvcmStakingFacet
    function getKvcmAllocationsForClasses(address[] calldata carbonClasses)
        external
        view
        returns (uint256[] memory allocations)
    {
        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        allocations = new uint256[](carbonClasses.length);
        for (uint256 i; i < carbonClasses.length; ++i) {
            allocations[i] = sKvcm.allocationsByCarbonClass[carbonClasses[i]];
        }
    }

    // ============ PUBLIC VIEW FUNCTIONS ============

    function isKvcmLockOwned(uint256 lockId, address user) public view returns (bool) {
        return KvcmStakingUtilsLib.isKvcmLockOwned(lockId, user);
    }

    // ============ EXTERNAL FUNCTIONS (CALLED BY OTHER CONTRACTS) ============

    /**
     * @notice Cleans up all KVCM allocations for an expired maturity
     * @dev Iterates through all carbon class allocations for the maturity,
     *      subtracts them from global totals, de-registers them from the
     *      risky-yield beta caches, and clears the maturity-specific map
     * @param maturityId The expired maturity ID to clean up
     */
    function cleanUpAllocationsForMaturity(uint256 maturityId) external onlyRewardManager {
        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();

        (uint256 start,) = IMaturityManager(sConfig.maturityManager).getActiveMaturityRange();

        // verify maturity is expired
        if (maturityId >= start) {
            revert Errors.MaturityIdNotExpired(maturityId);
        }

        EnumerableMap.AddressToUintMap storage maturityAllocations =
            sKvcm.priceAllocationsByMaturity[SafeCast.toUint128(maturityId)];

        uint256 length = maturityAllocations.length();
        if (length == 0) {
            return;
        }

        (,, uint256 nextMidnightIndex,) =
            IMaturityManager(sConfig.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightIndex == 0) revert Errors.InvalidMidnightTimestamp();
        uint64 nextDayId = SafeCast.toUint64(nextMidnightIndex);
        uint256 totalK2Allocations = StakingManagerStorage.k2StakingLayout().totalK2Allocations;
        IRiskyYieldFacet(sConfig.rewardManager).updateRewardsProportions(nextDayId, totalK2Allocations);

        // Iterate backwards to avoid index shifting issues when removing
        for (uint256 i = length; i > 0;) {
            unchecked {
                --i;
            }

            (address carbonClass, uint256 allocationAmount) = maturityAllocations.at(i);

            // Subtract from global allocations
            if (sKvcm.allocationsByCarbonClass[carbonClass] >= allocationAmount) {
                sKvcm.allocationsByCarbonClass[carbonClass] -= allocationAmount;
            } else {
                // if somehow allocation is greater, set to 0
                sKvcm.allocationsByCarbonClass[carbonClass] = 0;
            }

            uint256 cachedClassAllocation =
                IRiskyYieldFacet(sConfig.rewardManager).getRYBetaCache(carbonClass).kvcmAllocation;
            uint256 deallocationAmount =
                allocationAmount <= cachedClassAllocation ? allocationAmount : cachedClassAllocation;
            if (deallocationAmount > 0) {
                IRiskyYieldFacet(sConfig.rewardManager)
                    .updateBetaSqForKvcmDeallocation(deallocationAmount, carbonClass, nextDayId);
            }

            // Remove from maturity-specific map
            maturityAllocations.remove(carbonClass);
        }
    }

    // ============ INTERNAL FUNCTIONS ============
    function _lockKvcmWithPermit(
        uint256 amount,
        uint128 maturityId,
        address user,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (uint256 lockId) {
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        IERC20Permit(sConfig.kvcmToken).permit(msg.sender, address(this), amount, deadline, v, r, s);
        return _lockKvcm(amount, maturityId, user);
    }

    function _lockKvcm(uint256 amount, uint128 maturityId, address user) internal returns (uint256 lockId) {
        if (amount == 0) revert Errors.AmountCannotBeZero();
        if (user == address(0)) revert Errors.ZeroAddressNotAllowed();

        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();

        if (sConfig.kvcmToken == address(0)) revert Errors.KvcmTokenNotSet();
        if (sConfig.kvcmLocks == address(0)) revert Errors.KvcmLockNotSet();

        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();

        // validation scope
        {
            if (SafeCast.toUint128(amount) < sKvcm.minKvcmLockAmount) {
                revert Errors.KvcmLockAmountTooSmall(amount, sKvcm.minKvcmLockAmount);
            }

            (uint256 start, uint256 end) = IMaturityManager(sConfig.maturityManager).getActiveMaturityRange();

            if (maturityId < start || maturityId > end) {
                revert Errors.MaturityIdOutOfRange(maturityId, start, end);
            }
        }

        IERC20(sConfig.kvcmToken).safeTransferFrom(msg.sender, address(this), amount);

        // lock creation and update scope
        {
            bool lockExists = sKvcm.userKvcmLockIds[user][maturityId] != 0;

            if (!lockExists) {
                lockId = _createNewLock(sKvcm, sConfig, amount, maturityId, user);
            } else {
                lockId = _updateExistingLock(sKvcm, sConfig, amount, maturityId, user);
            }
        }

        // update global totals
        sKvcm.totalKvcmLocked += amount;
        IRMKVCMStakers(sConfig.rewardManager).mintSharesForKVCMStaker(maturityId, user, amount);
    }

    function _createNewLock(
        StakingManagerStorage.KvcmStakingLayout storage sKvcm,
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig,
        uint256 amount,
        uint128 maturityId,
        address user
    ) internal returns (uint256 newLockId) {
        newLockId = ++sKvcm._nextLockId;

        // build lock in storage (avoid stack too deep)
        KvcmLockInfo storage lockInfo = sKvcm.kvcmLocks[newLockId];
        lockInfo.lockOwner = user;
        lockInfo.lockId = newLockId;
        lockInfo.principal = amount;
        lockInfo.maturityId = maturityId;
        lockInfo.maturityTimestamp =
            SafeCast.toUint128(IMaturityManager(sConfig.maturityManager).getMaturityTimestamp(maturityId));
        lockInfo.startTimestamp = SafeCast.toUint128(block.timestamp);
        lockInfo.status = KvcmLockStatus.OPEN;
        lockInfo.priceAllocations = 0;

        // add lock to user and maturity
        sKvcm.userKvcmLockIds[user][maturityId] = lockInfo.lockId;
        sKvcm.lockByMaturity[maturityId] += amount;

        IKvcmIncentivesCurveFacet(sConfig.rewardManager)
            .handleActiveLockUpdate(user, lockInfo.lockId, amount, maturityId);

        IKvcmLock(sConfig.kvcmLocks).mint(user, lockInfo.lockId, "");

        emit KvcmLocked(user, lockInfo.lockId, lockInfo.principal, lockInfo.startTimestamp, lockInfo.maturityId);

        return lockInfo.lockId;
    }

    function _updateExistingLock(
        StakingManagerStorage.KvcmStakingLayout storage sKvcm,
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig,
        uint256 amount,
        uint128 maturityId,
        address user
    ) internal returns (uint256 newLockId) {
        KvcmLockInfo storage lockInfo = sKvcm.kvcmLocks[sKvcm.userKvcmLockIds[user][maturityId]];

        IKvcmIncentivesCurveFacet(sConfig.rewardManager)
            .handleActiveLockUpdate(user, sKvcm.userKvcmLockIds[user][maturityId], amount, maturityId);

        lockInfo.principal += amount;
        lockInfo.startTimestamp = SafeCast.toUint128(block.timestamp);

        // update existing lock with updated params
        sKvcm.kvcmLocks[lockInfo.lockId] = lockInfo;

        sKvcm.lockByMaturity[maturityId] += amount;

        emit KvcmLocked(user, lockInfo.lockId, lockInfo.principal, lockInfo.startTimestamp, lockInfo.maturityId);

        return lockInfo.lockId;
    }
}
