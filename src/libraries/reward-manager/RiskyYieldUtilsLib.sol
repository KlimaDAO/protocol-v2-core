// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

library RiskyYieldUtilsLib {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /**
     * @notice Calculates and books rewards for all completed daily periods up to the last keeper run.
     * @dev Reads from the immutable midnight index for a specific LP/maturity pair.
     *      It settles rewards for full days only.
     */
    function _settleYieldForLP(address lpToken, uint256 maturityId, address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage position = r.lpRYieldPosition[lpToken][maturityId][user];
        RewardManagerStorage.GlobalRewardsState storage globalState = r.lpRYieldGlobal[lpToken][maturityId];

        // Allow settlement for users who have withdrawn (shares == 0) but still have pending entries.
        if (position.shares == 0 && position.entriesDeque.empty()) {
            return;
        }

        uint256 yieldAccrued;
        uint256 lastKeeperUpdate = globalState.lastKeeperUpdate;
        uint256 globalAccumulator = globalState.globalAccumulator;

        while (!position.entriesDeque.empty()) {
            uint256 currentIdx = uint256(position.entriesDeque.front());

            // if the keeper has not yet reached the current entry, no point in continuing
            if (lastKeeperUpdate < currentIdx) {
                break;
            }

            RewardManagerStorage.Entry storage positionEntry = position.entryRecords[currentIdx];

            uint256 accPosLastSettled =
                r.lpRYieldAccSnapshot[lpToken][maturityId][positionEntry.settledMidnightIndex].midnightAccumulator;

            // Check if there is a next entry in the deque
            if (position.entriesDeque.length() > 1) {
                uint256 nextIdx = uint256(position.entriesDeque.at(1));

                if (lastKeeperUpdate >= nextIdx) {
                    // Settle rewards up to the next entry
                    uint256 accNextEntry = r.lpRYieldAccSnapshot[lpToken][maturityId][nextIdx].midnightAccumulator;
                    uint256 deltaAcc = accNextEntry - accPosLastSettled;
                    uint256 reward = Math.mulDiv(positionEntry.shares, deltaAcc, 1e18);
                    yieldAccrued += reward;
                    position.entriesDeque.popFront();
                    delete position.entryRecords[currentIdx];
                } else {
                    // Settle rewards up to the last keeper update and then stop
                    uint256 deltaAcc = globalAccumulator - accPosLastSettled;
                    uint256 reward = Math.mulDiv(positionEntry.shares, deltaAcc, 1e18);
                    yieldAccrued += reward;
                    positionEntry.settledMidnightIndex = lastKeeperUpdate;
                    break;
                }
            } else {
                // This is the last entry. Settle up to the last keeper update.
                uint256 deltaAcc = globalAccumulator - accPosLastSettled;
                uint256 reward = Math.mulDiv(positionEntry.shares, deltaAcc, 1e18);
                yieldAccrued += reward;

                // For a withdrawn user, this is a final claim, so the entry must be cleared.
                // For an active user, the entry remains for the next settlement period, so we only update its day ID.
                if (position.shares == 0) {
                    position.entriesDeque.popFront();
                    delete position.entryRecords[currentIdx];
                } else {
                    positionEntry.settledMidnightIndex = lastKeeperUpdate;
                }

                // In both cases, we cannot process any further, so we break.
                break;
            }
        }

        if (yieldAccrued > 0) {
            position.pendingYield += yieldAccrued;
        }
    }

    // LP Stakers are issues shares based on amount of time left for the maturity to expire
    // This is done so that LP stakers can't enter just before the daily rewards are distributed
    // and get rewards for the day.
    function _calcSharesForLPDeposit(uint256 maturityId, uint256 amount) internal view returns (uint256 shares) {
        shares = amount;
    }

    function _calcSharesForK2StakersDeposit(uint256 amount) internal pure returns (uint256 shares) {
        shares = amount;
    }

    /// @param user The user address
    /// @param categorizeActiveAsClaimable If true, yield for the current active period is treated as claimable (burn). If false, it is treated as pending (mint).
    function _settleK2StakerYield(address user, bool categorizeActiveAsClaimable) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage position = r.k2RYPositions[user];
        RewardManagerStorage.GlobalRewardsState storage globalState = r.k2StakersRYGlobal;

        uint256 lastKeeperUpdate = globalState.lastKeeperUpdate;
        uint256 globalAccumulator = globalState.globalAccumulator;

        // Process all historical (non-active) entries first
        while (position.entriesDeque.length() > 1) {
            uint256 currentIdx = uint256(position.entriesDeque.front());
            uint256 nextIdx = uint256(position.entriesDeque.at(1));

            // If the keeper hasn't reached the end of this historical period, we cannot process it yet.
            // We can only process history up to the point the keeper has run.
            if (lastKeeperUpdate < nextIdx) {
                break;
            }

            RewardManagerStorage.Entry storage currentEntry = position.entryRecords[currentIdx];

            // Safety check: only process if there's a time gap to account for.
            if (nextIdx > currentEntry.settledMidnightIndex) {
                uint256 accPosLastSettled = r.k2RYieldAccSnapshot[currentEntry.settledMidnightIndex].midnightAccumulator;
                uint256 accNextEntry = r.k2RYieldAccSnapshot[nextIdx].midnightAccumulator;
                uint256 yieldAccrued = Math.mulDiv(currentEntry.shares, (accNextEntry - accPosLastSettled), 1e18);

                RewardManagerStorage.Entry storage nextEntry = position.entryRecords[nextIdx];
                if (nextEntry.shares < currentEntry.shares) {
                    position.claimableYield += yieldAccrued;
                } else {
                    position.pendingYield += yieldAccrued;
                }
            }

            // This historical entry is now fully processed. Pop it.
            position.entriesDeque.popFront();
            delete position.entryRecords[currentIdx];
        }

        // Process the final, active entry
        if (!position.entriesDeque.empty()) {
            uint256 currentIdx = uint256(position.entriesDeque.front());
            RewardManagerStorage.Entry storage currentEntry = position.entryRecords[currentIdx];

            if (lastKeeperUpdate > currentEntry.settledMidnightIndex) {
                uint256 accPosLastSettled = r.k2RYieldAccSnapshot[currentEntry.settledMidnightIndex].midnightAccumulator;
                uint256 yieldAccrued = Math.mulDiv(currentEntry.shares, (globalAccumulator - accPosLastSettled), 1e18);

                // Rewards on the current active stake are categorized by the caller.
                if (categorizeActiveAsClaimable) {
                    position.claimableYield += yieldAccrued;
                } else {
                    position.pendingYield += yieldAccrued;
                }
                currentEntry.settledMidnightIndex = lastKeeperUpdate;
            }
        }
    }
}
