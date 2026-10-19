// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

library K2YieldUtilsLib {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    // LP Stakers Utils Funcs

    // Settle Rewards is used to settle rewards for a user for a given lpToken and maturityId
    // => This will bring forward the index of users position & make the rewards claimable
    function _settleLPK2Yield(address lpToken, uint256 maturityId, address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage position = r.lpK2YieldPosition[lpToken][maturityId][user];
        RewardManagerStorage.GlobalRewardsState storage globalState = r.lpK2YieldGlobal[lpToken][maturityId];

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
                r.lpK2YieldAccSnapshot[lpToken][maturityId][positionEntry.settledMidnightIndex].midnightAccumulator;

            // Check if there is a next entry in the deque
            if (position.entriesDeque.length() > 1) {
                uint256 nextIdx = uint256(position.entriesDeque.at(1));
                if (lastKeeperUpdate >= nextIdx) {
                    // Settle rewards up to the next entry
                    uint256 accNextEntry = r.lpK2YieldAccSnapshot[lpToken][maturityId][nextIdx].midnightAccumulator;
                    yieldAccrued += Math.mulDiv(positionEntry.shares, (accNextEntry - accPosLastSettled), 1e18);
                    position.entriesDeque.popFront();
                    delete position.entryRecords[currentIdx];
                } else {
                    // Settle rewards up to the last keeper update and then stop
                    yieldAccrued += Math.mulDiv(positionEntry.shares, (globalAccumulator - accPosLastSettled), 1e18);
                    positionEntry.settledMidnightIndex = lastKeeperUpdate;
                    break;
                }
            } else {
                // This is the last entry. Settle up to the last keeper update.
                yieldAccrued += Math.mulDiv(positionEntry.shares, (globalAccumulator - accPosLastSettled), 1e18);

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

    // Settle Rewards for KVCM stakers K2 yield
    // => This will bring forward the index of users position & make the rewards claimable
    function _settleKVCMK2Yield(uint256 maturityId, address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage position = r.kvcmK2YieldPosition[maturityId][user];
        RewardManagerStorage.GlobalRewardsState storage globalState = r.kvcmK2YieldGlobal[maturityId];

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
                r.kvcmK2YieldAccSnapshot[maturityId][positionEntry.settledMidnightIndex].midnightAccumulator;

            // Check if there is a next entry in the deque
            if (position.entriesDeque.length() > 1) {
                uint256 nextIdx = uint256(position.entriesDeque.at(1));
                if (lastKeeperUpdate >= nextIdx) {
                    // Settle rewards up to the next entry
                    uint256 accNextEntry = r.kvcmK2YieldAccSnapshot[maturityId][nextIdx].midnightAccumulator;
                    yieldAccrued += Math.mulDiv(positionEntry.shares, (accNextEntry - accPosLastSettled), 1e18);
                    position.entriesDeque.popFront();
                    delete position.entryRecords[currentIdx];
                } else {
                    // Settle rewards up to the last keeper update and then stop
                    yieldAccrued += Math.mulDiv(positionEntry.shares, (globalAccumulator - accPosLastSettled), 1e18);
                    positionEntry.settledMidnightIndex = lastKeeperUpdate;
                    break;
                }
            } else {
                // This is the last entry. Settle up to the last keeper update.
                yieldAccrued += Math.mulDiv(positionEntry.shares, (globalAccumulator - accPosLastSettled), 1e18);

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

    function _calcLPStakersShares(uint256 depositAmount_) internal view returns (uint256 shares) {
        shares = depositAmount_;
    }

    function _calcK2StakersShares(uint256 depositAmount_) internal pure returns (uint256 shares) {
        shares = depositAmount_;
    }

    function _calcKVCMStakersShares(uint256 depositAmount_) internal pure returns (uint256 shares) {
        shares = depositAmount_;
    }

    /// @param user The user address
    /// @param categorizeActiveAsClaimable If true, yield for the current active period is treated as claimable (burn). If false, it is treated as pending (mint).
    function _settleK2StakerK2Yield(address user, bool categorizeActiveAsClaimable) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage position = r.k2YieldPosition[user];
        RewardManagerStorage.GlobalRewardsState storage globalState = r.k2StakersK2YieldGlobal;

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
                uint256 accPosLastSettled =
                    r.k2K2YieldAccSnapshot[currentEntry.settledMidnightIndex].midnightAccumulator;
                uint256 accNextEntry = r.k2K2YieldAccSnapshot[nextIdx].midnightAccumulator;
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
                uint256 accPosLastSettled =
                    r.k2K2YieldAccSnapshot[currentEntry.settledMidnightIndex].midnightAccumulator;
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
