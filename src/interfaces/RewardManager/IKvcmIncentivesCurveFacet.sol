// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICommonEvents} from "../ICommonEvents.sol";

interface IKvcmIncentivesCurveFacet is ICommonEvents {
    /**
     * @notice Lock updated event.
     * @param user The user.
     * @param lockId The lock id.
     * @param maturityId The maturity id.
     * @param deltaAmount The delta amount.
     * @param totalProcessedShares The total processed shares.
     * @param midnightIndexStart The midnight index start.
     */
    event LockUpdated(
        address indexed user,
        uint256 indexed lockId,
        uint256 indexed maturityId,
        uint256 deltaAmount,
        uint256 totalProcessedShares,
        uint256 midnightIndexStart
    );

    /**
     * @notice Lock claimed event.
     * @param lockOwner The lock owner.
     * @param maturityId The maturity id.
     * @param lockId The lock id.
     * @param to The address to transfer the yield to.
     * @param yieldAmount The yield amount.
     */
    event LockClaimed(
        address lockOwner, uint256 indexed maturityId, uint256 indexed lockId, address indexed to, uint256 yieldAmount
    );

    /**
     * @notice Incentive routed for retirement event.
     * @param lockId The lock id.
     * @param to The address to transfer the incentives to.
     * @param amount The amount of incentives to transfer.
     */

    event IncentiveRoutedForRetirement(uint256 indexed lockId, address indexed to, uint256 amount);

    /**
     * @notice getFullCurveValues helper structs
     */

    /**
     * @notice Handle lock update
     * @dev Only callable by the staking manager. Updates a lock's RewardManager state.
     * @param user The user.
     * @param lockId The lock id.
     * @param deltaAmount The delta amount of the update (only positive values)
     * @param maturityId The maturity id.
     */
    function handleActiveLockUpdate(address user, uint256 lockId, uint256 deltaAmount, uint256 maturityId) external;

    /**
     * @notice Handle unlock and claim
     * @dev Only callable by the staking manager in unlock(). Unlocks a lock and claims the accrued yield.
     * @param lockOwner The lock owner.
     * @param lockId The lock id.
     * @param to The address to claim the yield to.
     * @return accruedYield The accrued yield.
     * @return lockClosed Whether the lock was fully closed (all deposits processed).
     */
    function handleUnlockAndClaim(address lockOwner, uint256 lockId, address to)
        external
        returns (uint256 accruedYield, bool lockClosed);

    /**
     * @notice Claim KVCM yield before maturity; updates yieldDistributed before transfer
     * @dev Only callable by the staking manager
     */
    function routeYieldForActiveMaturityRetire(uint256 lockId, uint256 amount, address to) external;

    // Getters

    /**
     * @notice Get the yield of a lock at current time. Slightly more expensive than below as we need get the amount from storage.
     * @dev potentially more expensive if there are many unprocessed intervals
     * @param lockId The lock id.
     * @return lockYield The yield of the lock.
     */
    function getKvcmLockYield(uint256 lockId) external view returns (uint256 lockYield);

    /**
     * @notice Get the yield of a lock at current time. Slightly more expensive than below as we need get the amount from storage.
     * @param lockId The lock id.
     * @param midnightIndex The midnight index.
     * @return lockYield The yield of the lock.
     */
    function getKvcmLockYield(uint256 lockId, uint256 midnightIndex) external view returns (uint256 lockYield);

    /**
     * @notice Get the maximum number of unprocessed days for lock deposits.
     * @return The maximum number of unprocessed days for lock deposits.
     */
    function getMaxUnprocessedDaysForLockDeposits() external view returns (uint256);
}
