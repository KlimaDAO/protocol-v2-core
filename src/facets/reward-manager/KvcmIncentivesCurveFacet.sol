// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
// interfaces

import "../../interfaces/RewardManager/IKvcmIncentivesCurveFacet.sol";
import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
// libraries
import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {KvcmIncentivesCurveMathLib} from "../../libraries/reward-manager/KvcmIncentivesCurveMathLib.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Constants} from "../../libraries/Constants.sol";
import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {LibUtils} from "../../libraries/LibUtils.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
// external
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract KvcmIncentivesCurveFacet is IKvcmIncentivesCurveFacet {
    uint256 constant MAX_UNPROCESSED_DAYS_FOR_LOCK_DEPOSITS = 10;

    using SafeERC20 for IERC20;
    using LibUtils for uint256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    modifier onlyStakingManager() {
        if (msg.sender != RewardManagerStorage.configLayout().stakingManager) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    /**
     * @dev Modifier to check if sender has admin role
     */
    modifier onlyAdmin() {
        address accessManager = RewardManagerStorage.configLayout().accessManager;

        (bool hasAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (!hasAdminRole) {
            revert Errors.CallerNotAdmin();
        }
        _;
    }

    modifier whenNotPaused() {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }

    /* ─────────────────────── EXTERNAL ─────────────────────── */

    /**
     * @notice Updates RewardManager state on lock creation or update.
     * @param user The user.
     * @param lockId The ID of the lock.
     * @param deltaAmount The amount of the lock.
     * @param maturityId The maturity ID of the lock.
     * @dev This should only be called by the staking manager.
     * @dev Updates the yield curve values for realtime forward pricing.
     * @dev Returns the lock incentives, retrieved before the update, so the staking manager can adjust principal.
     * @dev there are no lock maturity checks here, this is done in the staking manager
     */
    function handleActiveLockUpdate(address user, uint256 lockId, uint256 deltaAmount, uint256 maturityId)
        external
        onlyStakingManager
        whenNotPaused
    {
        _handleActiveLockUpdate(user, lockId, deltaAmount, maturityId);
    }

    /**
     * @notice Handles claim of user of matured lock. Transfers incentives to user.
     * @dev This should only be called by the staking manager.
     * @dev This does *not* verify the lock is matured. StakingManager verifies this.
     * @param lockOwner The lock owner.
     * @param lockId The ID of the lock.
     * @param to The address to claim the yield to.
     */
    function handleUnlockAndClaim(address lockOwner, uint256 lockId, address to)
        external
        onlyStakingManager
        whenNotPaused
        returns (uint256 accruedYield, bool lockClosed)
    {
        if (lockOwner == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (to == address(0)) {
            revert Errors.ZeroAddress();
        }

        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();
        RewardManagerStorage.KvcmLock storage lock = RewardManagerStorage.kvcmLocksLayout().kvcmLocks[lockId];

        IMaturityManager maturityManager = IMaturityManager(RewardManagerStorage.configLayout().maturityManager);

        if (lock.rawPrincipal == 0) {
            revert Errors.LockNotFound(lockId);
        }

        uint256 maturityTs = maturityManager.getMaturityTimestamp(lock.maturityId);

        if (maturityTs > block.timestamp) {
            revert Errors.LockNotYetMatured(lock.maturityId);
        }

        if (lock.unprocessedDeposits.length() > 0) {
            // loop through deposits and mint shares
            _processDeposits(lock, yieldLayout, lock.unprocessedDeposits);
        }

        uint256 maturityMidnightIndex = _getMaturityMidnightIndex(lock.maturityId);
        uint256 lastMidnightIndexYieldDistribution = yieldLayout.lastMidnightIndexYieldDistribution;

        // If PPS not yet set for the maturity index, partial-claim up to the last available index
        if (maturityMidnightIndex > lastMidnightIndexYieldDistribution) {
            if (lastMidnightIndexYieldDistribution == 0) {
                revert Errors.ZeroMidnightIndexYieldDistribution();
            }
            uint256 partialAccruedYield =
                _handleClaimToIndex(lock, lockId, lockOwner, to, lastMidnightIndexYieldDistribution);
            return (partialAccruedYield, false);
        }

        uint256 totalAtMaturity = _getLockClaimValueAtMidnightIndex(lockId, maturityMidnightIndex);

        if (totalAtMaturity < lock.yieldDistributed) {
            revert Errors.InvalidAccruedYield(totalAtMaturity, lock.yieldDistributed);
        }

        // This accounting encompasses any mid-maturity yield retirements
        accruedYield = totalAtMaturity - lock.yieldDistributed;

        _handleUnlockAndBurn(lock);

        _claimIncentives(to, accruedYield);

        emit LockClaimed(lockOwner, lock.maturityId, lockId, to, accruedYield);
        return (accruedYield, true);
    }

    /// @inheritdoc IKvcmIncentivesCurveFacet
    function routeYieldForActiveMaturityRetire(uint256 lockId, uint256 amount, address to)
        external
        onlyStakingManager
        whenNotPaused
    {
        RewardManagerStorage.KvcmLock storage lock = RewardManagerStorage.kvcmLocksLayout().kvcmLocks[lockId];

        if (lock.rawPrincipal == 0) revert Errors.LockNotFound(lockId);

        uint256 idx = RewardManagerStorage.kvcmLockYieldLayout().lastMidnightIndexYieldDistribution;
        uint256 maxIdx = _getMaximumLockMidnightIndex(lockId);
        if (idx > maxIdx) idx = maxIdx;

        uint256 grossYield = _getLockClaimValueAtMidnightIndex(lockId, idx);
        uint256 available = grossYield > lock.yieldDistributed ? grossYield - lock.yieldDistributed : 0;

        if (amount > available) {
            revert Errors.InsufficientKvcmYieldAvailable(available, amount);
        }

        lock.yieldDistributed += amount;

        _claimIncentives(to, amount);

        emit IncentiveRoutedForRetirement(lockId, to, amount);
    }

    /* ─────────────────────── EXTERNAL GETTERS ─────────────────────── */

    /**
     * @notice Get the kvcm lock yield at a given midnight index.
     * @param lockId The lock id.
     * @param midnightIndex The midnight index.
     * @return lockYield The lock yield.
     */
    function getKvcmLockYield(uint256 lockId, uint256 midnightIndex) external view returns (uint256 lockYield) {
        if (midnightIndex == 0) {
            return 0;
        }

        if (midnightIndex > _getMaximumLockMidnightIndex(lockId)) {
            revert Errors.InvalidMidnightIndex(midnightIndex);
        }
        return _getLockClaimValueAtMidnightIndex(lockId, midnightIndex);
    }

    /**
     * @notice Get the kvcm lock yield at the current midnight index.
     * @param lockId The lock id.
     * @return lockYield The lock yield.
     */
    function getKvcmLockYield(uint256 lockId) external view returns (uint256 lockYield) {
        uint256 idx = RewardManagerStorage.kvcmLockYieldLayout().lastMidnightIndexYieldDistribution;

        uint256 maximumLockMidnightIndex = _getMaximumLockMidnightIndex(lockId);
        if (idx > maximumLockMidnightIndex) {
            idx = maximumLockMidnightIndex;
        }

        return _getLockClaimValueAtMidnightIndex(lockId, idx);
    }

    /**
     * @notice Get the maximum valid midnight index for a lock.
     * @param lockId The lock id.
     * @return The maximum valid midnight index for a lock.
     */
    function _getMaximumLockMidnightIndex(uint256 lockId) internal view returns (uint256) {
        RewardManagerStorage.KvcmLock storage lock = RewardManagerStorage.kvcmLocksLayout().kvcmLocks[lockId];
        IMaturityManager maturityManager = IMaturityManager(RewardManagerStorage.configLayout().maturityManager);
        uint256 maturityTimestamp = maturityManager.getMaturityTimestamp(lock.maturityId);
        return maturityManager.getMidnightIndexForTimestamp(maturityTimestamp);
    }

    /**
     * @notice Get the maximum number of unprocessed days for lock deposits.
     * @return The maximum number of unprocessed days for lock deposits.
     */
    function getMaxUnprocessedDaysForLockDeposits() external view returns (uint256) {
        return MAX_UNPROCESSED_DAYS_FOR_LOCK_DEPOSITS;
    }

    /* ─────────────────────── INTERNAL ─────────────────────── */

    /**
     * @notice Handles the active lock update.
     * @param user The user.
     * @param lockId The ID of the lock.
     * @param deltaAmount The amount of the lock.
     * @param maturityId The maturity ID of the lock.
     */
    function _handleActiveLockUpdate(address user, uint256 lockId, uint256 deltaAmount, uint256 maturityId) internal {
        if (deltaAmount == 0) revert Errors.ZeroAmount();
        if (user == address(0)) {
            revert Errors.ZeroAddress();
        }

        (uint256 currentMidnightIndex,, uint256 nextMidnightIndex,) = IMaturityManager(
                RewardManagerStorage.configLayout().maturityManager
            ).getAdjacentMidnightInfo(block.timestamp);

        uint256 totalProcessedShares =
            _updateActiveLockRegistration(lockId, maturityId, currentMidnightIndex, deltaAmount);

        emit LockUpdated(user, lockId, maturityId, deltaAmount, totalProcessedShares, nextMidnightIndex);
    }

    /**
     * @notice Updates the lock registration.
     * @dev initializes the lock if it doesn't exist. Mints new shares based on deltaAmount.
     * @param lockId The ID of the lock.
     * @param maturityId The maturity ID of the lock.
     * @param deltaAmount The amount of the lock.
     */
    function _updateActiveLockRegistration(
        uint256 lockId,
        uint256 maturityId,
        uint256 currentMidnightIndex,
        uint256 deltaAmount
    ) internal returns (uint256 totalProcessedShares) {
        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();
        RewardManagerStorage.KvcmLock storage lock = RewardManagerStorage.kvcmLocksLayout().kvcmLocks[lockId];

        bool lockExists = lock.status != RewardManagerStorage.LockStatus.UNINITIALIZED;

        uint256 nextMidnightIndex = currentMidnightIndex + 1;

        // init lock's maturityId on initial call
        if (!lockExists) {
            lock.maturityId = maturityId.to128();
            lock.midnightIndexStart = nextMidnightIndex.to128();
        } else {
            // verify passed maturityId matches the lock's maturityId
            if (lock.maturityId != maturityId) {
                revert Errors.InvalidMaturityId(maturityId);
            }
        }

        // revert if less than one yield period until maturity
        _validateLockingInterval(maturityId);

        // update lock for share calculation based on deltaAmount. settle previous records if pps is now available
        totalProcessedShares = _updateSharesAndMidnightIndex(deltaAmount, nextMidnightIndex, lock, yieldLayout);

        // update raw principal totals for bookkeeping
        lock.rawPrincipal += deltaAmount;
        yieldLayout.currentMaturityTotals[maturityId].totalRawPrincipal += deltaAmount;

        // write deposit into the interval it happened, CURRENT, not next
        yieldLayout.maturityIntervalData[currentMidnightIndex][maturityId].depositsDuringInterval += deltaAmount;

        lock.status = RewardManagerStorage.LockStatus.OPEN;
    }

    /**
     * @notice Handles the unlock and burn.
     * @param lock The lock.
     */
    function _handleUnlockAndBurn(RewardManagerStorage.KvcmLock storage lock) internal {
        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();

        // if these totals are not already subtracted from global totals from partial claim, subtract them here
        if (lock.status != RewardManagerStorage.LockStatus.PARTIAL_CLAIMED) {
            uint256 ts = yieldLayout.currentMaturityTotals[lock.maturityId].totalSharesForMaturity;
            yieldLayout.currentMaturityTotals[lock.maturityId].totalSharesForMaturity =
                ts > lock.shares ? ts - lock.shares : 0;
            uint256 rp = yieldLayout.currentMaturityTotals[lock.maturityId].totalRawPrincipal;
            yieldLayout.currentMaturityTotals[lock.maturityId].totalRawPrincipal =
                rp > lock.rawPrincipal ? rp - lock.rawPrincipal : 0;
        }

        // zero out lock shares and raw principal
        lock.rawPrincipal = 0;
        lock.shares = 0;
        lock.status = RewardManagerStorage.LockStatus.CLAIMED;
    }

    /**
     * @notice Core partial-claim logic: claims yield up to a given midnight index.
     * @param lock The lock.
     * @param lockId The lock id.
     * @param lockOwner The lock owner.
     * @param to The address to claim the yield to.
     * @param targetMidnightIndex The midnight index to claim up to.
     * @return accruedYield The accrued yield.
     */
    function _handleClaimToIndex(
        RewardManagerStorage.KvcmLock storage lock,
        uint256 lockId,
        address lockOwner,
        address to,
        uint256 targetMidnightIndex
    ) internal returns (uint256 accruedYield) {
        uint256 totalAccruedYieldAtIndex = _getLockClaimValueAtMidnightIndex(lockId, targetMidnightIndex);

        if (totalAccruedYieldAtIndex < lock.yieldDistributed) {
            revert Errors.InvalidAccruedYield(totalAccruedYieldAtIndex, lock.yieldDistributed);
        }
        accruedYield = totalAccruedYieldAtIndex - lock.yieldDistributed;

        lock.yieldDistributed = totalAccruedYieldAtIndex;

        // if a new partial claim, subtract all shares and raw principal from maturity totals
        if (lock.status != RewardManagerStorage.LockStatus.PARTIAL_CLAIMED) {
            RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();

            uint256 ts = yieldLayout.currentMaturityTotals[lock.maturityId].totalSharesForMaturity;
            yieldLayout.currentMaturityTotals[lock.maturityId].totalSharesForMaturity =
                ts > lock.shares ? ts - lock.shares : 0;
            uint256 rp = yieldLayout.currentMaturityTotals[lock.maturityId].totalRawPrincipal;
            yieldLayout.currentMaturityTotals[lock.maturityId].totalRawPrincipal =
                rp > lock.rawPrincipal ? rp - lock.rawPrincipal : 0;
        }

        lock.status = RewardManagerStorage.LockStatus.PARTIAL_CLAIMED;
        _claimIncentives(to, accruedYield);
        emit LockClaimed(lockOwner, lock.maturityId, lockId, to, accruedYield);
        return accruedYield;
    }

    /**
     * @notice Processes the shares for a given amount.
     * @param amount The amount.
     * @param nextMidnightIndex The next midnight index.
     * @param lock The lock.
     * @param yieldLayout The yield layout.
     * @return totalProcessedShares The total processed shares.
     */
    function _updateSharesAndMidnightIndex(
        uint256 amount,
        uint256 nextMidnightIndex,
        RewardManagerStorage.KvcmLock storage lock,
        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout
    ) internal returns (uint256 totalProcessedShares) {
        if (amount > type(uint128).max) {
            revert Errors.ConversionExceedsUint128(amount);
        }
        if (nextMidnightIndex > type(uint128).max) revert Errors.ConversionExceedsUint128(nextMidnightIndex);

        DoubleEndedQueue.Bytes32Deque storage unprocessedDeposits = lock.unprocessedDeposits;

        // process existing deposits to shrink queue
        _processDeposits(lock, yieldLayout, unprocessedDeposits);

        // bring unprocessedShares to up to date
        _addDepositToQueueGuard(amount, nextMidnightIndex, unprocessedDeposits);

        // attempt to process new deposit
        totalProcessedShares = _processDeposits(lock, yieldLayout, unprocessedDeposits);
    }

    /**
     * @notice Processes the deposits.
     * @param lock The lock.
     * @param yieldLayout The yield layout.
     * @param unprocessedDeposits The unprocessed deposits.
     * @return totalProcessedShares The total processed shares.
     */
    function _processDeposits(
        RewardManagerStorage.KvcmLock storage lock,
        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout,
        DoubleEndedQueue.Bytes32Deque storage unprocessedDeposits
    ) internal returns (uint256 totalProcessedShares) {
        uint256 sharesDelta;
        uint256 lastProcessedMidnightIndex;

        while (unprocessedDeposits.length() > 0) {
            bytes32 depositRecord = unprocessedDeposits.front();

            (uint128 ppsMidnightIndex, uint128 depositAmount) = LibUtils._unpackUnprocessedDeposit(depositRecord);

            uint256 pps = yieldLayout.maturityIntervalData[ppsMidnightIndex][lock.maturityId].ppsAtRoll;

            // if the pps isn't available, this deposit cannot be processed and added to total shares
            if (pps == 0) {
                break;
            }
            uint256 newShares = _calculateShares(depositAmount, pps);

            sharesDelta += newShares;
            lastProcessedMidnightIndex = ppsMidnightIndex;

            unprocessedDeposits.popFront();
        }

        if (sharesDelta != 0) {
            lock.shares += sharesDelta;
            lock.midnightIndexStart = lastProcessedMidnightIndex.to128();
        }

        return lock.shares;
    }

    /**
     * @notice Adds the deposit to the deque
     * @param amount The amount.
     * @param nextMidnightIndex The next midnight index.
     * @param unprocessedDeposits The unprocessed deposits.
     */
    function _addDepositToQueueGuard(
        uint256 amount,
        uint256 nextMidnightIndex,
        DoubleEndedQueue.Bytes32Deque storage unprocessedDeposits
    ) internal {
        if (amount == 0) revert Errors.ZeroAmount();

        uint256 len = unprocessedDeposits.length();
        if (len == 0) {
            unprocessedDeposits.pushBack(LibUtils._packUnprocessedDeposit(nextMidnightIndex, amount));
            return;
        }

        bytes32 lastDepositRecord = unprocessedDeposits.at(len - 1);

        (uint128 lastIndex, uint128 lastAmount) = LibUtils._unpackUnprocessedDeposit(lastDepositRecord);

        // enforce non-decreasing order
        if (nextMidnightIndex < lastIndex) {
            revert Errors.InvalidQueueOrder(nextMidnightIndex, lastIndex);
        }

        if (nextMidnightIndex == lastIndex) {
            // aggregate same day. never counts towards unique day cap
            unprocessedDeposits.popBack();
            uint256 newAmt = uint256(lastAmount) + amount;
            if (newAmt > type(uint128).max) {
                revert Errors.ConversionExceedsUint128(newAmt);
            }
            unprocessedDeposits.pushBack(LibUtils._packUnprocessedDeposit(nextMidnightIndex, newAmt));
        } else {
            // New distinct day == enforce cap before pushing
            // len is the current number of distinct days; same-day entries are aggregated
            if (len >= MAX_UNPROCESSED_DAYS_FOR_LOCK_DEPOSITS) {
                revert Errors.TooManyUnprocessedDeposits();
            }
            // strictly later day
            unprocessedDeposits.pushBack(LibUtils._packUnprocessedDeposit(nextMidnightIndex, amount));
        }
    }

    /**
     * @notice Gets the lock claim value at a given midnight index.
     * @param lockId The lock id.
     * @param midnightIndex The midnight index.
     * @return claimValue The claim value.
     */
    function _getLockClaimValueAtMidnightIndex(uint256 lockId, uint256 midnightIndex)
        internal
        view
        returns (uint256 claimValue)
    {
        RewardManagerStorage.KvcmLock storage lock = RewardManagerStorage.kvcmLocksLayout().kvcmLocks[lockId];

        uint256 ppsAtMidnightIndex =
            KvcmIncentivesCurveMathLib.getPricePerShareAtMidnightIndex(midnightIndex, lock.maturityId);

        (uint256 effShares, uint256 unprocessedPrincipal) =
            _previewSharesAndUnprocessedPrincipal(midnightIndex, lock, RewardManagerStorage.kvcmLockYieldLayout());

        uint256 effectivePrincipalAtMidnightIndex = Math.mulDiv(effShares, ppsAtMidnightIndex, Constants.WAD);

        if (unprocessedPrincipal > lock.rawPrincipal) unprocessedPrincipal = lock.rawPrincipal;

        uint256 principalToSubtract = lock.rawPrincipal - unprocessedPrincipal;

        claimValue = effectivePrincipalAtMidnightIndex > principalToSubtract
            ? effectivePrincipalAtMidnightIndex - principalToSubtract
            : 0;
    }

    /**
     * @notice Preview the shares with the latest available pps.
     * @param lock The lock.
     * @param yl The yield layout.
     * @return effShares The effective shares.
     * @return unprocessedPrincipal The unprocessed principal.
     */
    function _previewSharesAndUnprocessedPrincipal(
        uint256 targetMidnightIndex,
        RewardManagerStorage.KvcmLock storage lock,
        RewardManagerStorage.KvcmLockYieldLayout storage yl
    ) internal view returns (uint256 effShares, uint256 unprocessedPrincipal) {
        effShares = lock.shares;

        uint256 n = lock.unprocessedDeposits.length();
        for (uint256 i = 0; i < n; ++i) {
            bytes32 rec = lock.unprocessedDeposits.at(i);
            (uint128 ppsIdx, uint128 amt) = LibUtils._unpackUnprocessedDeposit(rec);

            // Not eligible yet at target => not included in effShares
            if (uint256(ppsIdx) > targetMidnightIndex) {
                unprocessedPrincipal += uint256(amt);
                continue;
            }

            uint256 pps = yl.maturityIntervalData[ppsIdx][lock.maturityId].ppsAtRoll;

            // Eligible by time but PPS missing => also not included in effShares
            if (pps == 0) {
                unprocessedPrincipal += uint256(amt);
                continue;
            }

            effShares += _calculateShares(uint256(amt), pps);
        }
    }

    /**
     * @notice Claims the incentives.
     * @param to The address to claim the yield to.
     * @param yield The yield.
     */
    function _claimIncentives(address to, uint256 yield) private {
        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.configLayout();

        address kvcmToken = rmConfig.kvcmToken;

        if (kvcmToken == address(0) || to == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20(kvcmToken).safeTransfer(to, yield);
    }

    /**
     * @notice Gets the maturity midnight index.
     * @param maturityId The maturity id.
     * @return The maturity midnight index.
     */
    function _getMaturityMidnightIndex(uint256 maturityId) internal view returns (uint256) {
        IMaturityManager maturityManager = IMaturityManager(RewardManagerStorage.configLayout().maturityManager);
        uint256 maturityTimestamp = maturityManager.getMaturityTimestamp(maturityId);
        return maturityManager.getMidnightIndexForTimestamp(maturityTimestamp);
    }

    /**
     * @notice Checks if the lock is matured.
     * @param lockId The lock id.
     * @return bool The bool.
     */
    function isLockMatured(uint256 lockId) internal view returns (bool) {
        RewardManagerStorage.KvcmLock storage lock = RewardManagerStorage.kvcmLocksLayout().kvcmLocks[lockId];
        IMaturityManager maturityManager = IMaturityManager(RewardManagerStorage.configLayout().maturityManager);
        uint256 maturityTimestamp = maturityManager.getMaturityTimestamp(lock.maturityId);
        return block.timestamp >= maturityTimestamp;
    }

    /**
     * @notice Validates the locking interval.
     * @param maturityId The maturity id.
     */
    function _validateLockingInterval(uint256 maturityId) internal view {
        uint256 maturityTimestamp =
            IMaturityManager(RewardManagerStorage.configLayout().maturityManager).getMaturityTimestamp(maturityId);
        if (maturityTimestamp == 0) {
            revert Errors.InvalidMaturityId(maturityId);
        }

        uint256 yieldDistributionInterval = RewardManagerStorage.kvcmLockYieldLayout().yieldDistributionInterval;
        // block locks on last yield distribution interval before maturity
        if (maturityTimestamp < block.timestamp + yieldDistributionInterval) {
            revert Errors.InvalidLockingInterval(maturityId);
        }
        (uint256 start, uint256 end) =
            IMaturityManager(RewardManagerStorage.configLayout().maturityManager).getActiveMaturityRange();
        if (start > maturityId || end < maturityId) {
            revert Errors.InvalidLockingInterval(maturityId);
        }
    }

    /*////////////////////////////////////////////////////////////
                             Pure Helpers
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the shares.
     * @param amount The amount.
     * @param pps The pps.
     * @return shares The shares.
     */
    function _calculateShares(uint256 amount, uint256 pps) internal pure returns (uint256 shares) {
        return Math.mulDiv(amount, Constants.WAD, pps);
    }
}
