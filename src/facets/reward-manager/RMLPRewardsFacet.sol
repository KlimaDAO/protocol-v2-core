// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {RiskyYieldUtilsLib} from "../../libraries/reward-manager/RiskyYieldUtilsLib.sol";
import {K2YieldUtilsLib} from "../../libraries/reward-manager/K2YieldUtilsLib.sol";
import {Errors} from "../../libraries/Errors.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

import {IRMLPRewardsFacet} from "../../interfaces/RewardManager/IRMLPRewardsFacet.sol";

/**
 * @title RMLPRewardsFacet
 * @dev Rewards Manager LP Rewards Facet for managing LP token rewards
 */
contract RMLPRewardsFacet is IRMLPRewardsFacet {
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
        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.rmConfig();
        return IMaturityManager(rmConfig.maturityManager).isValidMaturityId(maturityId);
    }

    /**
     * @dev Add LP stakes for a specific LP token and maturity, handling both new and top-up deposits.
     * @param lpToken The LP token address
     * @param maturityId The maturity ID
     * @param user The user address
     * @param capital the deposit capital amount
     */
    function mintShareToLP(address lpToken, uint256 maturityId, address user, uint256 capital)
        external
        onlyStakingManager
        whenNotPaused
    {
        if (capital == 0) return;
        if (lpToken == address(0)) revert Errors.ZeroAddress();
        if (!_isMaturityValid((maturityId))) revert Errors.InvalidMaturityId(maturityId);

        _handleRYieldShareMint(lpToken, maturityId, user, capital);
        _handleK2YieldShareMint(lpToken, maturityId, user, capital);
    }

    function _handleRYieldShareMint(address lpToken, uint256 maturityId, address user, uint256 capital)
        internal
        returns (uint256)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage position = r.lpRYieldPosition[lpToken][maturityId][user];

        RiskyYieldUtilsLib._settleYieldForLP(lpToken, maturityId, user);

        uint256 newShares = RiskyYieldUtilsLib._calcSharesForLPDeposit(maturityId, capital);

        if (newShares == 0) {
            return 0;
        }

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndex,,,) = IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        // issue new shares;
        position.shares += newShares;
        r.lpRYieldGlobal[lpToken][maturityId].totalShares += newShares;

        if (!position.entriesDeque.empty() && uint256(position.entriesDeque.back()) == currentMidnightIndex) {
            // top-up: update shares for the current day entry
            position.entryRecords[currentMidnightIndex].shares = position.shares;
        } else {
            // new day – append a fresh entry after guarding against deque overflow
            if (position.entriesDeque.length() == MAX_DEQUE_LENGTH) {
                revert Errors.LPRYieldQueueOverflow(lpToken, maturityId, user);
            }
            position.entriesDeque.pushBack(bytes32(currentMidnightIndex));
            position.entryRecords[currentMidnightIndex].shares = position.shares;
            position.entryRecords[currentMidnightIndex].settledMidnightIndex = currentMidnightIndex;
        }

        emit LPRYieldSharesMinted(lpToken, maturityId, user, currentMidnightIndex, position.pendingYield, newShares);

        return position.shares;
    }

    function _handleK2YieldShareMint(address lpToken, uint256 maturityId, address user, uint256 capital)
        internal
        returns (uint256)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage position = r.lpK2YieldPosition[lpToken][maturityId][user];

        K2YieldUtilsLib._settleLPK2Yield(lpToken, maturityId, user);

        uint256 newShares = K2YieldUtilsLib._calcLPStakersShares(capital);

        if (newShares == 0) {
            return 0;
        }

        // issue new shares;
        position.shares += newShares;
        r.lpK2YieldGlobal[lpToken][maturityId].totalShares += newShares;

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndex,,,) = IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        if (!position.entriesDeque.empty() && uint256(position.entriesDeque.back()) == currentMidnightIndex) {
            // top-up: update shares for the current day entry
            position.entryRecords[currentMidnightIndex].shares = position.shares;
        } else {
            // new day – append a fresh entry after guarding against deque overflow
            if (position.entriesDeque.length() == MAX_DEQUE_LENGTH) {
                revert Errors.LPRYieldQueueOverflow(lpToken, maturityId, user);
            }
            position.entriesDeque.pushBack(bytes32(currentMidnightIndex));
            position.entryRecords[currentMidnightIndex].shares = position.shares;
            position.entryRecords[currentMidnightIndex].settledMidnightIndex = currentMidnightIndex;
        }

        emit LPK2YieldSharesMinted(lpToken, maturityId, user, currentMidnightIndex, position.pendingYield, newShares);

        return position.shares;
    }

    function _handleRYieldShareBurn(address lpToken, uint256 maturityId, address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.GlobalRewardsState storage rYieldState = r.lpRYieldGlobal[lpToken][maturityId];
        RewardManagerStorage.LPRewardsPosition storage rmPos = r.lpRYieldPosition[lpToken][maturityId][user];

        RiskyYieldUtilsLib._settleYieldForLP(lpToken, maturityId, user);

        uint256 sharesToBurn = rmPos.shares;
        if (rYieldState.totalShares < sharesToBurn) {
            // This should not happen in a correctly functioning system.
            revert Errors.SharesToBurnGTSystem();
        }

        rYieldState.totalShares -= sharesToBurn;

        // Set user's active shares to 0 to prevent future accrual.
        // Their historical entries in the deque are preserved for their final rewards claim.
        rmPos.shares = 0;

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndex,,,) = IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        emit LPRYieldSharesBurned(lpToken, maturityId, user, currentMidnightIndex, rmPos.pendingYield, sharesToBurn);
    }

    function _handleK2YieldShareBurn(address lpToken, uint256 maturityId, address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage k2Pos = r.lpK2YieldPosition[lpToken][maturityId][user];
        RewardManagerStorage.GlobalRewardsState storage k2YieldLPState = r.lpK2YieldGlobal[lpToken][maturityId];

        K2YieldUtilsLib._settleLPK2Yield(lpToken, maturityId, user);

        uint256 sharesToBurn = k2Pos.shares;
        if (k2YieldLPState.totalShares < sharesToBurn) {
            // This should not happen in a correctly functioning system.
            revert Errors.SharesToBurnGTSystem();
        }

        k2YieldLPState.totalShares -= sharesToBurn;

        // Set user's active shares to 0 to prevent future accrual.
        // Their historical entries in the deque are preserved for their final rewards claim.
        k2Pos.shares = 0;

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndex,,,) = IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        emit LPK2YieldSharesBurned(lpToken, maturityId, user, currentMidnightIndex, k2Pos.pendingYield, sharesToBurn);
    }

    function _transferK2Yield(address lpToken, uint256 maturityId, address user) internal returns (uint256 yieldAmt) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage k2Pos = r.lpK2YieldPosition[lpToken][maturityId][user];
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        yieldAmt = k2Pos.pendingYield;

        if (yieldAmt > 0) {
            k2Pos.pendingYield = 0;
            IERC20(c.k2YieldToken).safeTransfer(user, yieldAmt);
            emit LPK2YieldTransferred(lpToken, maturityId, user, yieldAmt);
        }

        RewardManagerStorage.LPRewardsPosition storage ryPosition = r.lpRYieldPosition[lpToken][maturityId][user];
        if (ryPosition.pendingYield == 0) {
            return 0;
        }

        uint256 ryRewards = ryPosition.pendingYield;

        ryPosition.shares = 0;
        ryPosition.pendingYield = 0;

        IERC20(c.riskyYieldToken).safeTransfer(user, ryRewards);
        emit LPRYieldTransferred(lpToken, maturityId, user, ryRewards);
    }

    function _transferRYield(address lpToken, uint256 maturityId, address user) internal returns (uint256 yieldAmt) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage rPos = r.lpRYieldPosition[lpToken][maturityId][user];
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();
        yieldAmt = rPos.pendingYield;

        if (yieldAmt > 0) {
            rPos.pendingYield = 0;
            IERC20(c.riskyYieldToken).safeTransfer(user, yieldAmt);
            emit LPRYieldTransferred(lpToken, maturityId, user, yieldAmt);
        }
    }

    /**
     * @dev Remove LP stakes for a specific LP token and maturity
     * @param lpToken The LP token address
     * @param maturityId The maturity ID
     */
    function burnSharesFromLP(address lpToken, uint256 maturityId, address user)
        external
        onlyStakingManager
        whenNotPaused
    {
        if (lpToken == address(0)) revert Errors.ZeroAddress();

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.GlobalRewardsState storage riskyYieldRMState = r.lpRYieldGlobal[lpToken][maturityId];
        RewardManagerStorage.LPRewardsPosition storage position = r.lpRYieldPosition[lpToken][maturityId][user];
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        // settle -> burn_shares
        _handleRYieldShareBurn(lpToken, maturityId, user);
        _handleK2YieldShareBurn(lpToken, maturityId, user);

        // Transfer accrued yield
        _transferRYield(lpToken, maturityId, user);
        _transferK2Yield(lpToken, maturityId, user);
    }

    /**
     * @notice Allows a user to claim any outstanding rewards.
     * @dev This is particularly for users who have withdrawn their capital but still had rewards pending
     *      for an incomplete period. They can call this after the keeper has run for that period
     *      to claim their final rewards.
     * @param lpToken The LP token address
     * @param maturityId The maturity ID
     */
    function claimLPRewards(address lpToken, uint256 maturityId) external whenNotPaused {
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        // Settle any final rewards. This will process any entries left in the deque
        // after the user has withdrawn their capital.
        RiskyYieldUtilsLib._settleYieldForLP(lpToken, maturityId, msg.sender);
        K2YieldUtilsLib._settleLPK2Yield(lpToken, maturityId, msg.sender);

        uint256 ryRewards = _transferRYield(lpToken, maturityId, msg.sender);
        if (ryRewards > 0) {
            emit LPRYieldTransferred(lpToken, maturityId, msg.sender, ryRewards);
        }

        uint256 k2Rewards = _transferK2Yield(lpToken, maturityId, msg.sender);
        if (k2Rewards > 0) {
            emit LPK2YieldTransferred(lpToken, maturityId, msg.sender, k2Rewards);
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get LP stakers risky yield details
     * @param lpToken The LP token address
     * @param maturityId The maturity ID
     * @return global The global LP rewards data
     */
    function getLpStakersRYDetails(address lpToken, uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.GlobalRewardsState memory)
    {
        if (lpToken == address(0)) revert Errors.ZeroAddress();
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        return r.lpRYieldGlobal[lpToken][maturityId];
    }

    /**
     * @dev Get user LP position
     * @param lpToken The LP token address
     * @param maturityId The maturity ID
     * @param user The user address
     * @return position The user's LP rewards position
     */
    function getUserLPRYPosition(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.LPRewardsPositionView memory position)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage p = r.lpRYieldPosition[lpToken][maturityId][user];

        return RewardManagerStorage.LPRewardsPositionView(p.shares, p.pendingYield, p.lastSettlementMidnightIndex);
    }

    function getUnclaimedRYRewards(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (uint256 rewards)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage p = r.lpRYieldPosition[lpToken][maturityId][user];

        if (p.shares == 0) {
            return p.pendingYield;
        }

        // It's not safe to read `lastKeeperUpdate` in a view function as it may not be updated.
        // This function will now only show rewards settled up to the last interaction.
        // A more complex off-chain query would be needed to estimate live rewards.
        rewards = p.pendingYield;
    }

    /**
     * @dev Get global LP rewards
     * @param lpToken The LP token address
     * @param maturityId The maturity ID
     * @return global The global LP rewards data
     */
    function getGlobalLPRewards(address lpToken, uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.GlobalRewardsState memory global)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        return r.lpRYieldGlobal[lpToken][maturityId];
    }

    function getGlobalLPK2Rewards(address lpToken, uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.GlobalRewardsState memory global)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        return r.lpK2YieldGlobal[lpToken][maturityId];
    }

    function getUserLPK2Position(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.LPRewardsPositionView memory position)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage p = r.lpK2YieldPosition[lpToken][maturityId][user];

        return RewardManagerStorage.LPRewardsPositionView(p.shares, p.pendingYield, p.lastSettlementMidnightIndex);
    }

    function getUnclaimedK2YRewards(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (uint256 rewards)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage p = r.lpK2YieldPosition[lpToken][maturityId][user];

        if (p.shares == 0) {
            return p.pendingYield;
        }

        // It's not safe to read `lastKeeperUpdate` in a view function as it may not be updated.
        // This function will now only show rewards settled up to the last interaction.
        // A more complex off-chain query would be needed to estimate live rewards.
        rewards = p.pendingYield;
    }

    function getUserLPRYEntries(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.Entry[] memory entries)
    {
        RewardManagerStorage.LPRewardsPosition storage p =
            RewardManagerStorage.rmStorage().lpRYieldPosition[lpToken][maturityId][user];
        uint256 len = p.entriesDeque.length();
        entries = new RewardManagerStorage.Entry[](len);

        for (uint256 i = 0; i < len; i++) {
            bytes32 entryIndex = p.entriesDeque.at(i);
            entries[i] = p.entryRecords[uint256(entryIndex)];
        }
    }

    function getUserLPK2YEntries(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.Entry[] memory entries)
    {
        RewardManagerStorage.LPRewardsPosition storage p =
            RewardManagerStorage.rmStorage().lpK2YieldPosition[lpToken][maturityId][user];
        uint256 len = p.entriesDeque.length();
        entries = new RewardManagerStorage.Entry[](len);

        for (uint256 i = 0; i < len; i++) {
            bytes32 entryIndex = p.entriesDeque.at(i);
            entries[i] = p.entryRecords[uint256(entryIndex)];
        }
    }

    function previewClaimLPRewards(address lpToken, uint256 maturityId, address user)
        external
        returns (uint256 ryAmount, uint256 k2Amount)
    {
        RiskyYieldUtilsLib._settleYieldForLP(lpToken, maturityId, user);
        K2YieldUtilsLib._settleLPK2Yield(lpToken, maturityId, user);

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.LPRewardsPosition storage ryPos = r.lpRYieldPosition[lpToken][maturityId][user];
        RewardManagerStorage.LPRewardsPosition storage k2Pos = r.lpK2YieldPosition[lpToken][maturityId][user];

        ryAmount = ryPos.pendingYield;
        k2Amount = k2Pos.pendingYield;
    }
}
