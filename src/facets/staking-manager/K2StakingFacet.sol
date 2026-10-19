// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// libraries
import "../../libraries/Errors.sol";
import "../../libraries/storage/StakingManagerStorage.sol";

// interfaces
import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {IRateLimiterFacet} from "../../interfaces/AssetManager/IRateLimiterFacet.sol";
import {IRiskyYieldFacet} from "../../interfaces/RewardManager/IRiskyYieldFacet.sol";
import {ICarbonLedger} from "../../interfaces/ICarbonLedger.sol";
// openzeppelin
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

// interfaces
import {IK2StakingFacet} from "../../interfaces/StakingManager/IK2StakingFacet.sol";
import {IRewardManager} from "src/interfaces/RewardManager/IRewardManager.sol";
import "../../libraries/IntegrationErrors.sol";
import {ZkMeUtilsLib} from "./utils/zkMe.sol";

/**
 * @title K2StakingFacet
 * @dev This facet will be used to manager K2 Locking And PriceStaking
 */
contract K2StakingFacet is ReentrancyGuard, IK2StakingFacet {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    modifier whenNotPaused() {
        StakingManagerStorage.StakingManagerPauseLayout storage s = StakingManagerStorage.managerPauseLayout();

        if (s.systemPaused || s.k2StakingPaused) {
            revert Errors.K2StakingPaused();
        }
        _;
    }

    modifier whenVerified(address user) {
        if (!ZkMeUtilsLib.hasApproved(user)) revert IntegrationErrors.ZkMeNotVerified(user);
        _;
    }

    /*////////////////////////////////////////////////////
                            EXTERNAL
    ////////////////////////////////////////////////////*/

    /// @inheritdoc IK2StakingFacet
    function lockK2(uint256 amount) external whenNotPaused whenVerified(msg.sender) nonReentrant {
        _lockK2(amount, msg.sender);
    }

    /// @inheritdoc IK2StakingFacet
    function lockK2WithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        whenNotPaused
        whenVerified(msg.sender)
        nonReentrant
    {
        _lockK2WithPermit(amount, msg.sender, deadline, v, r, s);
    }

    /// @inheritdoc IK2StakingFacet
    function lockK2For(uint256 amount, address user_) external whenNotPaused whenVerified(user_) nonReentrant {
        if (user_ == address(0)) revert Errors.ZeroAddress();
        _lockK2(amount, user_);
    }

    /// @inheritdoc IK2StakingFacet
    function lockK2ForWithPermit(uint256 amount, address user, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        whenNotPaused
        whenVerified(user)
        nonReentrant
    {
        if (user == address(0)) revert Errors.ZeroAddress();
        _lockK2WithPermit(amount, user, deadline, v, r, s);
    }

    /// @inheritdoc IK2StakingFacet
    function unlockK2(uint256 amount) external whenNotPaused nonReentrant {
        _unlockK2(amount, msg.sender);
    }

    /// @inheritdoc IK2StakingFacet
    function claimK2() external whenNotPaused nonReentrant returns (uint256 claimAmount) {
        claimAmount = _claimK2(msg.sender);
    }

    /// @inheritdoc IK2StakingFacet
    function claimK2For(address user_) external whenNotPaused nonReentrant returns (uint256 claimAmount) {
        claimAmount = _claimK2(user_);
    }

    // ALLOCATION

    /// @inheritdoc IK2StakingFacet
    function allocateK2(uint256 newAllocationAmount, address carbonClass)
        external
        nonReentrant
        whenNotPaused
        whenVerified(msg.sender)
    {
        _allocateK2(newAllocationAmount, carbonClass);
    }

    /// @inheritdoc IK2StakingFacet
    function deallocateK2(uint256 unstakeAmount, address carbonClass) external nonReentrant whenNotPaused {
        _deallocateK2(msg.sender, unstakeAmount, carbonClass);
    }

    /// @inheritdoc IK2StakingFacet
    function reallocateK2(uint256 amount, address fromCarbonClass, address toCarbonClass)
        external
        nonReentrant
        whenNotPaused
        whenVerified(msg.sender)
    {
        _reallocateK2(msg.sender, amount, fromCarbonClass, toCarbonClass);
    }

    /// @inheritdoc IK2StakingFacet
    function batchAllocateK2(AllocationInfo[] calldata allocations)
        external
        nonReentrant
        whenNotPaused
        whenVerified(msg.sender)
    {
        if (allocations.length == 0 || allocations.length > 50) revert Errors.InvalidAllocationsLength();
        for (uint256 i = 0; i < allocations.length; i++) {
            _allocateK2(allocations[i].amount, allocations[i].carbonClass);
        }
    }

    /// @inheritdoc IK2StakingFacet
    function batchDeallocateK2(AllocationInfo[] calldata allocations) external nonReentrant whenNotPaused {
        if (allocations.length == 0 || allocations.length > 50) revert Errors.InvalidAllocationsLength();
        for (uint256 i = 0; i < allocations.length; i++) {
            _deallocateK2(msg.sender, allocations[i].amount, allocations[i].carbonClass);
        }
    }

    /*////////////////////////////////////////////////////
                            INTERNAL
    ////////////////////////////////////////////////////*/

    // LOCKING

    /**
     * @notice Internal function to lock K2 tokens to the staking manager
     * @param amount The amount of K2 tokens to lock
     * @param user_ The user to lock the K2 tokens to
     */
    function _lockK2(uint256 amount, address user_) internal returns (uint256 lockId) {
        validateAmount(amount);

        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        K2LockInfo storage userLock = l.userK2Locks[user_];

        // @dev advance escrowed principal info to unlocked principal storage if initial lock period has passed
        _advanceEscrowedPrincipalInfo(userLock);

        uint256 targetUnlock = _getTargetUnlockTimestamp(l);

        // init to max
        uint256 matchIndex = type(uint256).max;
        uint256 emptyIndex = type(uint256).max;
        uint256 len = userLock.escrowedPrincipalInfo.length;

        for (uint256 i = 0; i < len; ++i) {
            uint256 unlockTimestamp = userLock.escrowedPrincipalInfo[i].unlockTimestamp;

            if (targetUnlock == unlockTimestamp) {
                matchIndex = i;
                break;
            }

            if (unlockTimestamp == 0 && emptyIndex == type(uint256).max) {
                emptyIndex = i;
            }
        }

        /**
         * @notice We use two escrow slots to track up to two distinct unlock timestamps.
         * For example, with a 24h minLockPeriod:
         *  - user locks at noon Tuesday → nextMidnight is Tue->Wed, unlock = Thu midnight,
         *  - user locks again at noon Wednesday → nextMidnight is Wed->Thu, unlock = Fri midnight.
         *
         * The first lock is still escrowed when the second lock is created, so we need a second
         * slot to represent the second unlock time. Multiple locks within the same period are
         * accumulated into the same slot (matchIndex).
         *
         * If configuration ever required more than two overlapping unlock periods (e.g. a much
         * longer minLockPeriod), this fixed-size array would need to be revisited.
         */

        // @dev if matchIndex is not type(uint256).max, then the amount is added to the escrow of the upcoming midnight slot. Scenario: multiple locks within one lock period.
        if (matchIndex != type(uint256).max) {
            userLock.escrowedPrincipalInfo[matchIndex].amount += SafeCast.toUint128(amount);
        } else {
            // @dev no prior lock in this lock period --> create new escrow record for this lock period
            if (emptyIndex == type(uint256).max) revert Errors.LockedSlotsFull(); // if thrown, logic error in contract
            EscrowedPrincipalInfo storage emptyLockedStake = userLock.escrowedPrincipalInfo[emptyIndex];
            emptyLockedStake.amount = SafeCast.toUint128(amount);
            emptyLockedStake.unlockTimestamp = SafeCast.toUint128(targetUnlock);
        }

        // all lock timestamps are uint128
        userLock.startTimestamp = SafeCast.toUint128(block.timestamp);
        if (userLock.status != K2LockStatus.UNLOCK_REQUESTED) {
            userLock.status = K2LockStatus.LOCKED;
        }

        // assign or keep lockId
        if (!userLock.initialized) {
            userLock.initialized = true;
            userLock.lockId = ++l.maxLockId;
        }

        lockId = userLock.lockId;

        // update totalK2Locked
        l.totalK2Locked += amount;

        SafeERC20.safeTransferFrom(
            IERC20(StakingManagerStorage.configLayout().k2Token), msg.sender, address(this), amount
        );

        IRewardManager(StakingManagerStorage.configLayout().rewardManager).mintSharesForK2Staker(user_, amount);
        emit K2Locked(user_, amount, targetUnlock, lockId);
        return lockId;
    }

    /**
     * @notice Internal function to lock K2 tokens to the staking manager with a permit
     * @param amount The amount of K2 tokens to lock
     * @param user_ The user to lock the K2 tokens to
     * @param deadline The deadline for the permit
     * @param v The v parameter of the permit
     * @param r The r parameter of the permit
     * @param s The s parameter of the permit
     */
    function _lockK2WithPermit(uint256 amount, address user_, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        internal
    {
        StakingManagerStorage.StakingManagerConfigLayout storage config = StakingManagerStorage.configLayout();
        IERC20Permit(config.k2Token).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _lockK2(amount, user_);
    }

    // UNLOCKING

    /**
     * @notice Internal function to unlock K2 tokens from the staking manager
     * @param amount The amount of K2 tokens to unlock
     * @param user_ The user to unlock the K2 tokens from
     */
    function _unlockK2(uint256 amount, address user_) internal {
        if (amount == 0) revert Errors.ZeroAmount();

        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        K2LockInfo storage userLock = l.userK2Locks[user_];

        // @dev advance matured escrowed principal info to unlocked principal storage if initial lock period has passed
        _advanceEscrowedPrincipalInfo(userLock);

        // @dev escrowed principal amount is the amount of K2 tokens that are still locked in the escrow, via not passing min bond period.
        (uint256 escrowedPrincipalAmount,) = _splitEscrowAmounts(userLock.escrowedPrincipalInfo);
        uint256 unlockedPrincipal = userLock.unlockedPrincipal;
        uint256 totalPrincipal = unlockedPrincipal + escrowedPrincipalAmount;

        if (userLock.startTimestamp == 0 || totalPrincipal == 0) {
            revert Errors.NoK2Locked();
        }

        if (amount > unlockedPrincipal) revert Errors.InsufficientK2UnlockedPrincipal(unlockedPrincipal, amount);

        uint256 newUnlockedPrincipal = unlockedPrincipal > amount ? unlockedPrincipal - amount : 0;

        uint256 allowedAllocationAmount = newUnlockedPrincipal + escrowedPrincipalAmount;

        // @dev total allocations are based on their locked amount. If totalAllocations exceed new principal, the user must deallocate to < new total principal.
        if (allowedAllocationAmount < userLock.totalAllocated) {
            revert Errors.AllocationsExceedsLockedAmount(userLock.totalAllocated, allowedAllocationAmount);
        }

        StakingManagerStorage.StakingManagerConfigLayout storage config = StakingManagerStorage.configLayout();

        (,,, uint256 upcomingMidnightTimestamp) =
            IMaturityManager(config.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        if (upcomingMidnightTimestamp == 0) {
            revert Errors.InvalidMidnightTimestamp();
        }

        userLock.unlockedPrincipal = newUnlockedPrincipal;

        if (userLock.status == K2LockStatus.UNLOCK_REQUESTED) {
            // Same claim window → accumulate claim escrow
            if (userLock.claimTimestamp == upcomingMidnightTimestamp) {
                userLock.claimEscrow += amount;
            } else {
                // Don't allow claims to accumulate for different midnights. Claim and then allow more unlock requests.
                revert Errors.ClaimRequired();
            }
        } else {
            userLock.status = K2LockStatus.UNLOCK_REQUESTED;
            userLock.claimTimestamp = SafeCast.toUint128(upcomingMidnightTimestamp);
            userLock.claimEscrow = amount;
        }
        // update totalK2Locked
        l.totalK2Locked -= amount;

        IRewardManager(StakingManagerStorage.configLayout().rewardManager).burnSharesForK2Staker(user_, amount);

        emit K2UnlockRequested(user_, amount, userLock.claimTimestamp);
    }

    // CLAIMING

    /**
     * @notice Claim K2 rewards.
     * @dev Claiming K2 is only allowed after the claimTimestamp has passed.
     *      This is to prevent users from claiming rewards before the lock is fully matured.
     */
    function _claimK2(address user_) internal whenNotPaused returns (uint256 claimAmount) {
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        K2LockInfo storage userLock = l.userK2Locks[user_];

        _advanceEscrowedPrincipalInfo(userLock);

        // if no unlock request then claim is automatically invalid
        if (userLock.status != IK2StakingFacet.K2LockStatus.UNLOCK_REQUESTED) {
            revert Errors.NoUnlockRequested();
        }

        // is there is an unlock request, check to see if the claimTimestamp has passed
        if (block.timestamp < userLock.claimTimestamp) revert Errors.ClaimNotAllowed();

        claimAmount = userLock.claimEscrow;

        if (claimAmount == 0) revert Errors.NoK2ClaimEscrow();

        StakingManagerStorage.StakingManagerConfigLayout storage config = StakingManagerStorage.configLayout();

        // update user lock. resets lock for future use.
        userLock.claimEscrow = 0;
        userLock.claimTimestamp = 0;

        if (
            userLock.unlockedPrincipal == 0 && userLock.escrowedPrincipalInfo[0].amount == 0
                && userLock.escrowedPrincipalInfo[1].amount == 0
        ) {
            userLock.startTimestamp = 0;
            userLock.status = IK2StakingFacet.K2LockStatus.INACTIVE;
        } else {
            userLock.status = IK2StakingFacet.K2LockStatus.LOCKED;
        }

        IERC20(config.k2Token).safeTransfer(user_, claimAmount);
        IRewardManager(config.rewardManager).claimK2StakersRewards(user_);
        emit K2Claimed(user_, claimAmount);
    }

    // ALLOCATIONS

    /**
     * @notice Internal function to allocate K2 tokens to a carbon class
     * @param newAllocationAmount The amount of K2 tokens to allocate
     * @param carbonClass The carbon class to allocate the K2 tokens to
     */
    function _allocateK2(uint256 newAllocationAmount, address carbonClass) internal {
        if (newAllocationAmount == 0) revert Errors.ZeroAmount();
        if (carbonClass == address(0)) revert Errors.InvalidAddress();
        if (!ICarbonLedger(StakingManagerStorage.configLayout().carbonLedger).isClassRegistered(carbonClass, true)) {
            revert Errors.ClassNotRegistered(carbonClass);
        }

        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage config = StakingManagerStorage.configLayout();
        K2LockInfo storage userLock = l.userK2Locks[msg.sender];

        (uint256 escrowedPrincipalAmount, uint256 maturedInEscrowAmount) =
            _splitEscrowAmounts(userLock.escrowedPrincipalInfo);

        uint256 totalAmountinEscrow = escrowedPrincipalAmount + maturedInEscrowAmount;
        if (userLock.totalAllocated + newAllocationAmount > userLock.unlockedPrincipal + totalAmountinEscrow) {
            revert Errors.InsufficientK2UnlockedPrincipal(
                userLock.unlockedPrincipal + totalAmountinEscrow, userLock.totalAllocated + newAllocationAmount
            );
        }

        uint256 existingAllocationAmount =
            userLock.allocations.contains(carbonClass) ? userLock.allocations.get(carbonClass) : 0;
        userLock.allocations.set(carbonClass, existingAllocationAmount + newAllocationAmount);

        userLock.totalAllocated += newAllocationAmount;

        uint256 classPreTxnAllocationAmount = l.allocationsByCarbonClass[carbonClass];

        // Store old total for lambda checkpoint before any state changes
        uint256 oldTotalK2Allocations = l.totalK2Allocations;

        // Calculate new total BEFORE updating storage
        uint256 newTotalK2Allocations = oldTotalK2Allocations + newAllocationAmount;

        // Now update storage
        l.allocationsByCarbonClass[carbonClass] += newAllocationAmount;
        l.totalK2Allocations = newTotalK2Allocations;

        (,, uint256 nextMidnightIndex,) =
            IMaturityManager(config.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightIndex == 0) revert Errors.InvalidMidnightTimestamp();
        uint64 nextDayId = SafeCast.toUint64(nextMidnightIndex);

        // Checkpoint lambdas FIRST with OLD parameters (elapsed time used OLD beta/allocations)
        IRiskyYieldFacet(config.rewardManager).updateRewardsProportions(nextDayId, oldTotalK2Allocations);
        // Then update beta for FUTURE periods
        IRiskyYieldFacet(config.rewardManager).updateBetaSqForK2Allocation(newAllocationAmount, carbonClass, nextDayId);

        if (classPreTxnAllocationAmount > 0) {
            IRateLimiterFacet(config.aam).updateK2AllocationRateLimiter(carbonClass, classPreTxnAllocationAmount, 0);
        } else {
            IRateLimiterFacet(config.aam).updateK2AllocationRateLimiter(carbonClass, 0, newAllocationAmount);
        }

        emit K2Allocated(msg.sender, newAllocationAmount, carbonClass);
    }

    /**
     * @notice Internal function to deallocate K2 tokens from a carbon class
     * @param user The user to deallocate the K2 tokens from
     * @param deallocateAmount The amount of K2 tokens to deallocate
     * @param carbonClass The carbon class to deallocate the K2 tokens from
     */
    function _deallocateK2(address user, uint256 deallocateAmount, address carbonClass) internal {
        if (deallocateAmount == 0) revert Errors.ZeroAmount();
        if (carbonClass == address(0)) revert Errors.InvalidAddress();
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage config = StakingManagerStorage.configLayout();
        K2LockInfo storage userLock = l.userK2Locks[user];

        (uint256 escrowedPrincipalAmount, uint256 maturedInEscrowAmount) =
            _splitEscrowAmounts(userLock.escrowedPrincipalInfo);
        uint256 totalAmountinEscrow = escrowedPrincipalAmount + maturedInEscrowAmount;

        if (userLock.unlockedPrincipal + totalAmountinEscrow == 0) revert Errors.NoK2Locked();

        (bool exists, uint256 existingAllocationAmount) = userLock.allocations.tryGet(carbonClass);
        if (!exists) revert Errors.NoK2Allocated();

        if (deallocateAmount > existingAllocationAmount) {
            revert Errors.UnstakeExceedsExistingAllocation(deallocateAmount, existingAllocationAmount);
        }

        // update existing allocation
        uint256 newAllocationAmount = existingAllocationAmount - deallocateAmount;

        if (newAllocationAmount == 0) {
            userLock.allocations.remove(carbonClass);
        } else {
            userLock.allocations.set(carbonClass, newAllocationAmount);
        }
        // update total price staked
        userLock.totalAllocated -= deallocateAmount;

        // Store old total for lambda checkpoint before any state changes
        uint256 oldTotalK2Allocations = l.totalK2Allocations;

        // Calculate new total BEFORE updating storage
        uint256 newTotalK2Allocations = oldTotalK2Allocations - deallocateAmount;

        (,, uint256 nextMidnightIndex,) =
            IMaturityManager(config.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightIndex == 0) revert Errors.InvalidMidnightTimestamp();
        uint64 nextDayId = SafeCast.toUint64(nextMidnightIndex);

        // Checkpoint lambdas FIRST with OLD parameters (elapsed time used OLD beta/allocations)
        IRiskyYieldFacet(config.rewardManager).updateRewardsProportions(nextDayId, oldTotalK2Allocations);
        // Then update beta for FUTURE periods
        IRiskyYieldFacet(config.rewardManager).updateBetaSqForK2Deallocation(deallocateAmount, carbonClass, nextDayId);

        // update storage
        l.allocationsByCarbonClass[carbonClass] -= deallocateAmount;
        l.totalK2Allocations = newTotalK2Allocations;

        emit K2Deallocated(user, deallocateAmount, carbonClass);
    }

    /**
     * @notice Internal function to reallocate K2 tokens from one carbon class to another
     * @param user The user to reallocate the K2 tokens from
     * @param amount The amount of K2 tokens to reallocate
     * @param fromCarbonClass The carbon class to reallocate the K2 tokens from
     * @param toCarbonClass The carbon class to reallocate the K2 tokens to
     */
    function _reallocateK2(address user, uint256 amount, address fromCarbonClass, address toCarbonClass) internal {
        if (amount == 0) revert Errors.ZeroAmount();
        if (fromCarbonClass == address(0) || toCarbonClass == address(0)) revert Errors.InvalidAddress();
        if (fromCarbonClass == toCarbonClass) revert Errors.InvalidAddress();
        if (!ICarbonLedger(StakingManagerStorage.configLayout().carbonLedger).isClassRegistered(fromCarbonClass, true))
        {
            revert Errors.ClassNotRegistered(fromCarbonClass);
        }
        if (!ICarbonLedger(StakingManagerStorage.configLayout().carbonLedger).isClassRegistered(toCarbonClass, true)) {
            revert Errors.ClassNotRegistered(toCarbonClass);
        }
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage config = StakingManagerStorage.configLayout();
        K2LockInfo storage userLock = l.userK2Locks[user];

        (bool fromAllocationExists, uint256 fromAllocationAmount) = userLock.allocations.tryGet(fromCarbonClass);
        if (!fromAllocationExists) revert Errors.NoK2Allocated();

        (bool toAllocationExists, uint256 toAllocationAmount) = userLock.allocations.tryGet(toCarbonClass);

        if (fromAllocationAmount < amount) {
            revert Errors.DeallocationAmountExceedsAllocatedAmountForClass(fromCarbonClass, fromAllocationAmount);
        }

        uint256 newFromAllocationAmount = fromAllocationAmount >= amount ? fromAllocationAmount - amount : 0;

        userLock.allocations.set(toCarbonClass, toAllocationAmount + amount);

        if (newFromAllocationAmount == 0) {
            userLock.allocations.remove(fromCarbonClass);
        } else {
            userLock.allocations.set(fromCarbonClass, newFromAllocationAmount);
        }
        // update totalPriceStakedByClass
        uint256 toClassPreTxnAllocationAmount = l.allocationsByCarbonClass[toCarbonClass];
        l.allocationsByCarbonClass[toCarbonClass] += amount;

        uint256 fromClassPreTxnAllocationAmount = l.allocationsByCarbonClass[fromCarbonClass];
        l.allocationsByCarbonClass[fromCarbonClass] =
            fromClassPreTxnAllocationAmount >= amount ? fromClassPreTxnAllocationAmount - amount : 0;

        (,, uint256 nextMidnightIndex,) =
            IMaturityManager(config.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightIndex == 0) revert Errors.InvalidMidnightTimestamp();
        uint64 nextDayId = SafeCast.toUint64(nextMidnightIndex);

        // Checkpoint lambdas FIRST with current parameters (elapsed time used OLD beta)
        // Note: totalK2Allocations is unchanged during reallocation
        IRiskyYieldFacet(config.rewardManager).updateRewardsProportions(nextDayId, l.totalK2Allocations);
        // Then update beta for FUTURE periods (deallocation from one class, allocation to another)
        IRiskyYieldFacet(config.rewardManager).updateBetaSqForK2Deallocation(amount, fromCarbonClass, nextDayId);
        IRiskyYieldFacet(config.rewardManager).updateBetaSqForK2Allocation(amount, toCarbonClass, nextDayId);

        if (toClassPreTxnAllocationAmount > 0) {
            IRateLimiterFacet(config.aam).updateK2AllocationRateLimiter(toCarbonClass, toClassPreTxnAllocationAmount, 0);
        } else {
            IRateLimiterFacet(config.aam).updateK2AllocationRateLimiter(toCarbonClass, 0, amount);
        }

        emit K2Reallocated(user, amount, fromCarbonClass, toCarbonClass);
    }

    ////////////////////////////////////////////////////
    // VIEW
    ////////////////////////////////////////////////////

    function getTotalK2Allocations() external view returns (uint256) {
        return StakingManagerStorage.k2StakingLayout().totalK2Allocations;
    }

    /**
     * @notice Get the K2 lock info
     * @param user The user to get the K2 lock info for
     */
    function getK2LockInfo(address user)
        external
        view
        returns (K2LockView memory lock, AllocationInfo[] memory allocations)
    {
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        K2LockInfo storage b = l.userK2Locks[user];
        (uint256 escrowedPrincipalAmount, uint256 maturedInEscrowAmount) = _splitEscrowAmounts(b.escrowedPrincipalInfo);

        lock = K2LockView(
            b.unlockedPrincipal + maturedInEscrowAmount,
            escrowedPrincipalAmount,
            b.claimEscrow,
            b.startTimestamp,
            b.claimTimestamp,
            b.totalAllocated,
            b.status
        );

        uint256 len = b.allocations.length();
        allocations = new AllocationInfo[](len);
        for (uint256 i; i < len; ++i) {
            (address class, uint256 amount) = b.allocations.at(i);
            allocations[i] = AllocationInfo(class, amount);
        }
        return (lock, allocations);
    }

    /**
     * @notice Get the K2 allocated for a carbon class
     * @param carbonClass The carbon class to get the K2 allocated for
     */
    function getK2AllocatedForCarbonClass(address carbonClass) external view returns (uint256) {
        return StakingManagerStorage.k2StakingLayout().allocationsByCarbonClass[carbonClass];
    }

    /**
     * @notice Get the K2 locked principal lock status
     * @param user The user to get the K2 locked principal lock status for
     */
    function getK2LockedPrincipalLockStatus(address user)
        external
        view
        returns (uint256 unlockedPrincipal, uint256 escrowedPrincipal)
    {
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        K2LockInfo storage b = l.userK2Locks[user];
        unlockedPrincipal = b.unlockedPrincipal;
        escrowedPrincipal = 0;

        for (uint256 i = 0; i < b.escrowedPrincipalInfo.length; ++i) {
            if (b.escrowedPrincipalInfo[i].unlockTimestamp > block.timestamp) {
                escrowedPrincipal += b.escrowedPrincipalInfo[i].amount;
            } else {
                unlockedPrincipal += b.escrowedPrincipalInfo[i].amount;
            }
        }

        return (unlockedPrincipal, escrowedPrincipal);
    }

    /**
     * @notice Get the K2 locked total principal
     * @param user The user to get the K2 locked total principal for
     */
    function getK2LockedTotalPrincipal(address user) external view returns (uint256 totalPrincipal) {
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        K2LockInfo storage b = l.userK2Locks[user];

        totalPrincipal = b.unlockedPrincipal;

        for (uint256 i = 0; i < b.escrowedPrincipalInfo.length; ++i) {
            totalPrincipal += b.escrowedPrincipalInfo[i].amount;
        }

        return totalPrincipal;
    }

    /**
     * @notice Get the raw K2 lock info for a user
     * @param user The address of the user to get the lock info for
     * @return lockId The lock ID
     * @return unlockedPrincipal The amount of K2 tokens unlocked
     * @return escrowedPrincipalInfo The escrowed principal info
     * @return claimEscrow The amount of K2 tokens claimed
     * @return startTimestamp The start timestamp
     * @return claimTimestamp The claim timestamp
     * @return totalAllocated The total amount of K2 tokens allocated
     * @return status The status of the lock
     */
    function getRawK2LockInfo(address user)
        external
        view
        returns (
            uint256 lockId,
            uint256 unlockedPrincipal,
            EscrowedPrincipalInfo[2] memory escrowedPrincipalInfo,
            uint256 claimEscrow,
            uint128 startTimestamp,
            uint128 claimTimestamp,
            uint256 totalAllocated,
            K2LockStatus status
        )
    {
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        K2LockInfo storage b = l.userK2Locks[user];

        return (
            b.lockId,
            b.unlockedPrincipal,
            b.escrowedPrincipalInfo,
            b.claimEscrow,
            b.startTimestamp,
            b.claimTimestamp,
            b.totalAllocated,
            b.status
        );
    }

    /**
     * @notice Get the total amount of K2 tokens staked
     * @return The total amount of K2 tokens staked
     */
    function getTotalK2Staked() external view returns (uint256) {
        return StakingManagerStorage.k2StakingLayout().totalK2Locked;
    }

    /// @inheritdoc IK2StakingFacet
    function getK2AllocationsForClasses(address[] calldata carbonClasses)
        external
        view
        returns (uint256[] memory allocations)
    {
        StakingManagerStorage.K2StakingLayout storage l = StakingManagerStorage.k2StakingLayout();
        allocations = new uint256[](carbonClasses.length);
        for (uint256 i; i < carbonClasses.length; ++i) {
            allocations[i] = l.allocationsByCarbonClass[carbonClasses[i]];
        }
    }

    /*////////////////////////////////////////////////////
                            CHECKS
    ////////////////////////////////////////////////////*/

    /**
     * @notice Validate the amount of K2 tokens to lock
     * @param amount The amount of K2 tokens to lock
     */
    function validateAmount(uint256 amount) internal view {
        if (amount < StakingManagerStorage.k2StakingLayout().minLockAmount) {
            revert Errors.InvalidAmountTooSmall(amount);
        }
        if (amount > StakingManagerStorage.k2StakingLayout().maxLockAmount) {
            revert Errors.InvalidAmountTooLarge(amount);
        }
    }

    /*////////////////////////////////////////////////////
                            LOCKED STAKE HELPERS
    ////////////////////////////////////////////////////*/

    /**
     * @notice Advance the locked principal info to storage if initial lock period has passed
     * @param b The K2 lock info
     */
    function _advanceEscrowedPrincipalInfo(K2LockInfo storage b) internal returns (uint256 maturedEscrowedPrincipal) {
        unchecked {
            for (uint256 i; i < 2; ++i) {
                if (
                    b.escrowedPrincipalInfo[i].unlockTimestamp != 0
                        && b.escrowedPrincipalInfo[i].unlockTimestamp <= block.timestamp
                        && b.escrowedPrincipalInfo[i].amount != 0
                ) {
                    maturedEscrowedPrincipal += b.escrowedPrincipalInfo[i].amount;
                    b.escrowedPrincipalInfo[i].amount = 0;
                    b.escrowedPrincipalInfo[i].unlockTimestamp = 0;
                }
            }
        }
        if (maturedEscrowedPrincipal != 0) b.unlockedPrincipal += maturedEscrowedPrincipal;
    }

    /**
     * @notice Split principal tracked in escrow slots into:
     *  - escrowedPrincipalAmount: slots with unlockTimestamp > now (still locked)
     *  - maturedInEscrowAmount:   slots with unlockTimestamp != 0 and <= now
     * @param a The escrowed principal info
     */
    function _splitEscrowAmounts(EscrowedPrincipalInfo[2] storage a)
        internal
        view
        returns (uint256 escrowedPrincipalAmount, uint256 maturedInEscrowAmount)
    {
        unchecked {
            for (uint256 i; i < 2; ++i) {
                if (a[i].unlockTimestamp > block.timestamp) {
                    escrowedPrincipalAmount += a[i].amount;
                } else {
                    maturedInEscrowAmount += a[i].amount;
                }
            }
        }

        return (escrowedPrincipalAmount, maturedInEscrowAmount);
    }

    /**
     * @notice Get the target unlock timestamp. k2 locks must be locked a MINIMUM of minLockPeriod (24 hrs). Practically this means upcoming midnight to upcoming midnight + 24 hrs.
     * @param l The staking manager layout
     */
    function _getTargetUnlockTimestamp(StakingManagerStorage.K2StakingLayout storage l)
        internal
        view
        returns (uint256 targetUnlock)
    {
        (,,, uint256 nextMidnightTimestamp) = IMaturityManager(StakingManagerStorage.configLayout().maturityManager)
            .getAdjacentMidnightInfo(block.timestamp);
        if (nextMidnightTimestamp == 0) revert Errors.InvalidMidnightTimestamp();

        if (l.minLockPeriod == 0) revert Errors.InvalidMinK2LockPeriod();
        targetUnlock = nextMidnightTimestamp + l.minLockPeriod;
    }
}
