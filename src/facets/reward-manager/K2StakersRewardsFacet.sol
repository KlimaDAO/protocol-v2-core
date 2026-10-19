// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {IK2StakersRewardsFacet} from "../../interfaces/RewardManager/IK2StakersRewardsFacet.sol";
import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {RiskyYieldUtilsLib} from "../../libraries/reward-manager/RiskyYieldUtilsLib.sol";
import {K2YieldUtilsLib} from "../../libraries/reward-manager/K2YieldUtilsLib.sol";
import {Errors} from "../../libraries/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title K2StakersRewardsFacet
 * @dev  Facet for managing K2 Stakers rewards
 */
contract K2StakersRewardsFacet is IK2StakersRewardsFacet {
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

    function _settleRewards(address user, bool isBurn) internal {
        RiskyYieldUtilsLib._settleK2StakerYield(user, isBurn);
        K2YieldUtilsLib._settleK2StakerK2Yield(user, isBurn);
    }

    /**
     * @dev Add k2 stakers stakes. This settles rewards and adds a new entry to the deque.
     * @param user The user address
     * @param amount the deposit amount
     */
    function mintSharesForK2Staker(address user, uint256 amount) external onlyStakingManager whenNotPaused {
        // A mint action does not make active rewards claimable.
        _settleRewards(user, false);

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndexUint,,,) =
            IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);
        uint64 currentMidnightIndex = SafeCast.toUint64(currentMidnightIndexUint);

        _handleK2StakerRYieldShareMint(user, amount, currentMidnightIndex);
        _handleK2StakerK2YieldShareMint(user, amount, currentMidnightIndex);
    }

    function _handleK2StakerRYieldShareMint(address user, uint256 amount, uint64 currentMidnightIndex) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage ryPosition = r.k2RYPositions[user];

        uint256 ryShares = RiskyYieldUtilsLib._calcSharesForK2StakersDeposit(amount);

        if (ryShares > 0) {
            ryPosition.shares += ryShares;
            r.k2StakersRYGlobal.totalShares += ryShares;
        }

        _updateEntries(user, ryPosition, currentMidnightIndex);

        emit K2StakersRYSharesMinted(user, currentMidnightIndex, ryPosition.pendingYield, ryShares);
    }

    function _handleK2StakerK2YieldShareMint(address user, uint256 amount, uint64 currentMidnightIndex) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage k2Position = r.k2YieldPosition[user];

        uint256 k2Shares = K2YieldUtilsLib._calcK2StakersShares(amount);

        if (k2Shares > 0) {
            k2Position.shares += k2Shares;
            r.k2StakersK2YieldGlobal.totalShares += k2Shares;
        }

        _updateEntries(user, k2Position, currentMidnightIndex);

        emit K2StakersK2YSharesMinted(user, currentMidnightIndex, k2Position.pendingYield, k2Shares);
    }

    /**
     * @dev Remove K2 Stakes. This settles rewards and adds a new entry to the deque.
     */
    function burnSharesForK2Staker(address user, uint256 amount) external onlyStakingManager whenNotPaused {
        // A burn action makes active rewards claimable.
        _settleRewards(user, true);

        RewardManagerStorage.RMConfigLayout memory c = RewardManagerStorage.rmConfig();
        (uint256 currentMidnightIndex,,,) = IMaturityManager(c.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        _handleK2StakerRYieldShareBurn(user, amount, SafeCast.toUint64(currentMidnightIndex));
        _handleK2StakerK2YieldShareBurn(user, amount, SafeCast.toUint64(currentMidnightIndex));
    }

    function _handleK2StakerRYieldShareBurn(address user, uint256 amount, uint64 currentMidnightIndex) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage ryPosition = r.k2RYPositions[user];

        uint256 ryShares = RiskyYieldUtilsLib._calcSharesForK2StakersDeposit(amount);

        if (ryShares > 0) {
            if (ryPosition.shares < ryShares) {
                revert Errors.BurnMoreRYSharesThanMinted();
            }
            ryPosition.shares -= ryShares;
            r.k2StakersRYGlobal.totalShares -= ryShares;
        }

        _updateEntries(user, ryPosition, currentMidnightIndex);

        emit K2StakersRYSharesBurned(user, currentMidnightIndex, ryPosition.pendingYield, ryShares);
    }

    function _handleK2StakerK2YieldShareBurn(address user, uint256 amount, uint64 currentMidnightIndex) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage k2Position = r.k2YieldPosition[user];

        uint256 k2Shares = K2YieldUtilsLib._calcK2StakersShares(amount);

        if (k2Shares > 0) {
            if (k2Position.shares < k2Shares) {
                revert Errors.BurnMoreK2SharesThanMinted();
            }
            k2Position.shares -= k2Shares;
            r.k2StakersK2YieldGlobal.totalShares -= k2Shares;
        }

        _updateEntries(user, k2Position, currentMidnightIndex);

        emit K2StakersK2YSharesBurned(user, currentMidnightIndex, k2Position.pendingYield, k2Shares);
    }

    function _updateEntries(
        address user,
        RewardManagerStorage.K2StakerPosition storage position,
        uint64 currentMidnightIndex
    ) internal {
        if (!position.entriesDeque.empty() && uint256(position.entriesDeque.back()) == currentMidnightIndex) {
            position.entryRecords[currentMidnightIndex].shares = position.shares;
        } else {
            if (position.entriesDeque.length() == MAX_DEQUE_LENGTH) {
                revert Errors.K2StakersPositionsOverflow(user);
            }
            position.entriesDeque.pushBack(bytes32(uint256(currentMidnightIndex)));
            position.entryRecords[currentMidnightIndex].shares = position.shares;
            position.entryRecords[currentMidnightIndex].settledMidnightIndex = currentMidnightIndex;
        }
    }

    /**
     * @notice Claims rewards that were finalized from past withdrawals.
     * @dev Also performs a "final sweep" of pending rewards if the user has fully withdrawn.
     */
    function claimK2StakersRewards(address user) external whenNotPaused {
        // A claim action does not make active rewards claimable. It only processes the gap for past withdrawals.
        _settleRewards(user, false);
        _transferRYield(user);
        _transferK2Yield(user);
    }

    function _transferRYield(address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage ryPosition = r.k2RYPositions[user];
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        uint256 amountToPay = ryPosition.claimableYield;

        // Final Sweep Logic: If shares are zero, any remaining pending yield is also claimable
        if (ryPosition.shares == 0) {
            amountToPay += ryPosition.pendingYield;
            ryPosition.pendingYield = 0;
        }

        if (amountToPay > 0) {
            ryPosition.claimableYield = 0;
            IERC20(c.riskyYieldToken).safeTransfer(user, amountToPay);
            emit K2StakersRYRewardsTransferred(user, amountToPay);
        }
    }

    function _transferK2Yield(address user) internal {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage k2Position = r.k2YieldPosition[user];
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        uint256 k2AmountToPay = k2Position.claimableYield;

        if (k2Position.shares == 0) {
            k2AmountToPay += k2Position.pendingYield;
            k2Position.pendingYield = 0;
        }

        if (k2AmountToPay > 0) {
            k2Position.claimableYield = 0;
            IERC20(c.k2YieldToken).safeTransfer(user, k2AmountToPay);
            emit K2StakersK2RewardsTransferred(user, k2AmountToPay);
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get k2 stakers risky yield position
     * @param user The user address
     */
    function getK2StakersRYPosition(address user)
        external
        view
        returns (RewardManagerStorage.K2StakerPositionView memory position)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        return RewardManagerStorage.K2StakerPositionView(
            r.k2RYPositions[user].shares, r.k2RYPositions[user].pendingYield, r.k2RYPositions[user].claimableYield
        );
    }

    function getK2StakersK2YieldPosition(address user)
        external
        view
        returns (RewardManagerStorage.K2StakerPositionView memory position)
    {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        return RewardManagerStorage.K2StakerPositionView(
            r.k2YieldPosition[user].shares, r.k2YieldPosition[user].pendingYield, r.k2YieldPosition[user].claimableYield
        );
    }

    function getK2StakersRYGlobalState() external view returns (RewardManagerStorage.GlobalRewardsState memory) {
        return RewardManagerStorage.rmStorage().k2StakersRYGlobal;
    }

    function getK2StakersK2YieldGlobalState() external view returns (RewardManagerStorage.GlobalRewardsState memory) {
        return RewardManagerStorage.rmStorage().k2StakersK2YieldGlobal;
    }

    function getK2StakerRYEntries(address user) external view returns (RewardManagerStorage.Entry[] memory entries) {
        RewardManagerStorage.K2StakerPosition storage position = RewardManagerStorage.rmStorage().k2RYPositions[user];
        uint256 len = position.entriesDeque.length();
        entries = new RewardManagerStorage.Entry[](len);

        for (uint256 i = 0; i < len; i++) {
            bytes32 entryIndex = position.entriesDeque.at(i);
            entries[i] = position.entryRecords[uint256(entryIndex)];
        }
    }

    function getK2StakerK2YEntries(address user) external view returns (RewardManagerStorage.Entry[] memory entries) {
        RewardManagerStorage.K2StakerPosition storage position = RewardManagerStorage.rmStorage().k2YieldPosition[user];
        uint256 len = position.entriesDeque.length();
        entries = new RewardManagerStorage.Entry[](len);

        for (uint256 i = 0; i < len; i++) {
            bytes32 entryIndex = position.entriesDeque.at(i);
            entries[i] = position.entryRecords[uint256(entryIndex)];
        }
    }

    function previewClaimK2StakersRewards(address user) external returns (uint256 ryAmount, uint256 k2Amount) {
        _settleRewards(user, false);

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.K2StakerPosition storage ryPosition = r.k2RYPositions[user];
        RewardManagerStorage.K2StakerPosition storage k2Position = r.k2YieldPosition[user];

        ryAmount = ryPosition.claimableYield;
        if (ryPosition.shares == 0) {
            ryAmount += ryPosition.pendingYield;
        }

        k2Amount = k2Position.claimableYield;
        if (k2Position.shares == 0) {
            k2Amount += k2Position.pendingYield;
        }
    }
}
