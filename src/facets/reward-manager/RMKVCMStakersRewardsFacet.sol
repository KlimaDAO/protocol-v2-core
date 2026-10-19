// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {Errors} from "../../libraries/Errors.sol";
import {K2YieldUtilsLib} from "../../libraries/reward-manager/K2YieldUtilsLib.sol";
import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {IRMKVCMStakers} from "../../interfaces/RewardManager/IRMKVCMStakers.sol";

/**
 * @title RMKVCMStakersRewardsFacet
 * @dev Rewards Manager KVCM Stakers Rewards Facet for managing KVCM staker K2 yield rewards
 */
contract RMKVCMStakersRewardsFacet is IRMKVCMStakers {
    using SafeERC20 for IERC20;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint256 immutable MAX_DEQUE_LENGTH = 10;

    modifier onlyStakingManager() {
        if (msg.sender != RewardManagerStorage.configLayout().stakingManager) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    modifier whenNotPaused() {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }

    // =============================================================================
    // STATE MANAGEMENT FUNCTIONS
    // =============================================================================

    function _isMaturityValid(uint256 maturityId) internal view returns (bool) {
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();
        return IMaturityManager(c.maturityManager).isValidMaturityId(maturityId);
    }

    /**
     * @dev Mint K2 yield shares for KVCM stakers when KVCM is locked
     * @param maturityId The maturity ID
     * @param user The user address
     * @param amount The KVCM amount locked
     */
    function mintSharesForKVCMStaker(uint256 maturityId, address user, uint256 amount)
        external
        onlyStakingManager
        whenNotPaused
    {
        if (amount == 0) return;
        if (user == address(0)) revert Errors.ZeroAddress();
        if (!_isMaturityValid(maturityId)) revert Errors.InvalidMaturityId(maturityId);

        _handleKVCMK2YieldShareMint(maturityId, user, amount);
    }

    function _handleKVCMK2YieldShareMint(uint256 maturityId, address user, uint256 capital) internal returns (uint256) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage position = r.kvcmK2YieldPosition[maturityId][user];

        K2YieldUtilsLib._settleKVCMK2Yield(maturityId, user);

        uint256 newShares = K2YieldUtilsLib._calcKVCMStakersShares(capital);

        if (newShares == 0) {
            return 0;
        }

        // issue new shares;
        position.shares += newShares;
        r.kvcmK2YieldGlobal[maturityId].totalShares += newShares;

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndex,,,) = IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        if (!position.entriesDeque.empty() && uint256(position.entriesDeque.back()) == currentMidnightIndex) {
            // top-up: update shares for the current day entry
            position.entryRecords[currentMidnightIndex].shares = position.shares;
        } else {
            // new day – append a fresh entry after guarding against deque overflow
            if (position.entriesDeque.length() == MAX_DEQUE_LENGTH) {
                revert Errors.KVCMK2YQueueOverflow(maturityId, user);
            }
            position.entriesDeque.pushBack(bytes32(currentMidnightIndex));
            position.entryRecords[currentMidnightIndex].shares = position.shares;
            position.entryRecords[currentMidnightIndex].settledMidnightIndex = currentMidnightIndex;
        }

        emit KVCMK2YieldSharesMinted(maturityId, user, currentMidnightIndex, position.pendingYield, newShares);

        return position.shares;
    }

    function _handleKVCMK2YieldShareBurn(uint256 maturityId, address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage k2Pos = r.kvcmK2YieldPosition[maturityId][user];
        RewardManagerStorage.GlobalRewardsState storage k2YieldKVCMState = r.kvcmK2YieldGlobal[maturityId];

        K2YieldUtilsLib._settleKVCMK2Yield(maturityId, user);

        uint256 sharesToBurn = k2Pos.shares;
        if (k2YieldKVCMState.totalShares < sharesToBurn) {
            // This should not happen in a correctly functioning system.
            revert Errors.SharesToBurnGTSystem();
        }

        k2YieldKVCMState.totalShares -= sharesToBurn;

        // Set user's active shares to 0 to prevent future accrual.
        // Their historical entries in the deque are preserved for their final rewards claim.
        k2Pos.shares = 0;

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndex,,,) = IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        emit KVCMK2YieldSharesBurned(maturityId, user, currentMidnightIndex, k2Pos.pendingYield, sharesToBurn);
    }

    function _transferKVCMK2Yield(uint256 maturityId, address user) internal returns (uint256 yieldAmt) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage k2Pos = r.kvcmK2YieldPosition[maturityId][user];
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        yieldAmt = k2Pos.pendingYield;

        if (yieldAmt > 0) {
            k2Pos.pendingYield = 0;
            IERC20(c.k2YieldToken).safeTransfer(user, yieldAmt);
            emit KVCMK2YieldTransferred(maturityId, user, yieldAmt);
        }
    }

    function _transferKVCMK2YieldTo(uint256 maturityId, address user, address to) internal returns (uint256 yieldAmt) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage k2Pos = r.kvcmK2YieldPosition[maturityId][user];
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        yieldAmt = k2Pos.pendingYield;

        if (yieldAmt > 0) {
            k2Pos.pendingYield = 0;
            IERC20(c.k2YieldToken).safeTransfer(to, yieldAmt);
            emit KVCMK2YieldTransferred(maturityId, to, yieldAmt);
        }
    }

    /**
     * @dev Burn K2 yield shares for KVCM stakers when KVCM is unlocked
     * @param maturityId The maturity ID
     * @param user The user address
     * @param to The address to transfer the yield to
     */
    function burnSharesForKVCMStaker(uint256 maturityId, address user, address to)
        external
        onlyStakingManager
        whenNotPaused
    {
        if (user == address(0)) revert Errors.ZeroAddress();
        _handleKVCMK2YieldShareBurn(maturityId, user);
        _transferKVCMK2YieldTo(maturityId, user, to);
    }

    /**
     * @dev Burn K2 yield shares for KVCM stakers when KVCM is unlocked
     * @param maturityId The maturity ID
     * @param user The user address
     */
    function burnSharesForKVCMStaker(uint256 maturityId, address user) external onlyStakingManager whenNotPaused {
        if (user == address(0)) revert Errors.ZeroAddress();

        // settle -> burn_shares
        _handleKVCMK2YieldShareBurn(maturityId, user);

        // Transfer accrued yield
        _transferKVCMK2Yield(maturityId, user);
    }

    /**
     * @notice Allows a user to claim any outstanding KVCM K2 yield rewards.
     * @dev This is particularly for users who have withdrawn their KVCM but still had rewards pending
     *      for an incomplete period. They can call this after the keeper has run for that period
     *      to claim their final rewards.
     * @param maturityId The maturity ID
     */
    function claimKVCMK2Rewards(uint256 maturityId) external whenNotPaused {
        // Settle any final rewards. This will process any entries left in the deque
        // after the user has withdrawn their KVCM.
        K2YieldUtilsLib._settleKVCMK2Yield(maturityId, msg.sender);

        uint256 k2Rewards = _transferKVCMK2Yield(maturityId, msg.sender);
        if (k2Rewards > 0) {
            emit KVCMK2YieldTransferred(maturityId, msg.sender, k2Rewards);
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get KVCM staker K2 yield position
     * @param maturityId The maturity ID
     * @param user The user address
     * @return position The user's KVCM K2 yield position
     */
    function getKVCMK2YieldPosition(uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.KVCMStakersK2RewardsPositionView memory position)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage p = r.kvcmK2YieldPosition[maturityId][user];

        return
            RewardManagerStorage.KVCMStakersK2RewardsPositionView(
                p.shares, p.pendingYield, p.lastSettlementMidnightIndex
            );
    }

    /**
     * @dev Get KVCM stakers K2 yield global state
     * @param maturityId The maturity ID
     * @return global The global KVCM K2 yield state
     */
    function getKVCMK2YieldGlobalState(uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.GlobalRewardsState memory global)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        return r.kvcmK2YieldGlobal[maturityId];
    }

    function getUnclaimedKVCMK2Rewards(uint256 maturityId, address user) external view returns (uint256 rewards) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage p = r.kvcmK2YieldPosition[maturityId][user];

        if (p.shares == 0) {
            return p.pendingYield;
        }

        rewards = p.pendingYield;
    }

    function getKVCMK2YEntries(uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.Entry[] memory entries)
    {
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage p =
            RewardManagerStorage.rmStorage().kvcmK2YieldPosition[maturityId][user];
        uint256 len = p.entriesDeque.length();
        entries = new RewardManagerStorage.Entry[](len);

        for (uint256 i = 0; i < len; i++) {
            bytes32 entryIndex = p.entriesDeque.at(i);
            entries[i] = p.entryRecords[uint256(entryIndex)];
        }
    }

    function previewClaimKVCMK2Rewards(uint256 maturityId, address user) external returns (uint256 k2Amount) {
        K2YieldUtilsLib._settleKVCMK2Yield(maturityId, user);

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.KVCMStakersK2RewardsPosition storage k2Pos = r.kvcmK2YieldPosition[maturityId][user];

        k2Amount = k2Pos.pendingYield;
    }
}
