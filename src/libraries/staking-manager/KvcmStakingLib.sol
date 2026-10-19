// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StakingManagerStorage} from "../storage/StakingManagerStorage.sol";
import {Errors} from "../Errors.sol";
import {IKvcmStakingFacet} from "../../interfaces/StakingManager/IKvcmStakingFacet.sol";
import {IKvcmIncentivesCurveFacet} from "../../interfaces/RewardManager/IKvcmIncentivesCurveFacet.sol";
import {IKvcmLock} from "../../interfaces/StakingManager/IKvcmLock.sol";
import {IRMKVCMStakers} from "../../interfaces/RewardManager/IRMKVCMStakers.sol";

/// @title KvcmStakingLib
/// @notice Shared internal logic for KVCM staking flows that needs to be reachable
///         from multiple facets without an external `this.f()` hop.
library KvcmStakingLib {
    using SafeERC20 for IERC20;

    /// @notice Unlock a matured KVCM lock; transfers principal to `principalTo` and yield to `yieldTo`.
    /// @dev Lock ownership is checked against `lockOwner` which reduces complexity against routing principal and yield
    /// @param lockId Lock to unlock.
    /// @param principalTo Recipient of the locked KVCM principal.
    /// @param yieldTo Recipient of the accrued KVCM yield.
    /// @param lockOwner Address that must own the lock; authorizes the unlock.
    function unlock(uint256 lockId, address principalTo, address yieldTo, address lockOwner)
        internal
        returns (uint256 principal, uint256 accruedYield)
    {
        if (principalTo == address(0) || yieldTo == address(0)) revert Errors.ZeroAddressNotAllowed();

        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        IKvcmStakingFacet.KvcmLockInfo storage lockInfo = sKvcm.kvcmLocks[lockId];

        // Inclusive boundary (matured at exactly maturityTimestamp) — the same
        // convention as KvcmStakingUtilsLib.isKvcmLockMatured, LP unstake and
        // K2 claim.
        if (lockInfo.maturityTimestamp > block.timestamp) revert Errors.KvcmLockNotMatured();
        if (lockInfo.lockOwner != lockOwner) revert Errors.KvcmLockNotOwned();
        if (lockInfo.status != IKvcmStakingFacet.KvcmLockStatus.OPEN) revert Errors.KvcmLockIsClosed();

        uint128 maturityId = lockInfo.maturityId;
        principal = lockInfo.principal;

        bool lockClosed;
        (accruedYield, lockClosed) =
            IKvcmIncentivesCurveFacet(sConfig.rewardManager).handleUnlockAndClaim(lockOwner, lockId, yieldTo);

        sKvcm.kvcmLocks[lockId].status =
            lockClosed ? IKvcmStakingFacet.KvcmLockStatus.REDEEMED : IKvcmStakingFacet.KvcmLockStatus.PARTIAL_CLAIMED;
        sKvcm.userKvcmLockIds[lockOwner][maturityId] = 0;

        IKvcmLock(sConfig.kvcmLocks).burn(lockId);
        IERC20(sConfig.kvcmToken).safeTransfer(principalTo, principal);

        IRMKVCMStakers(sConfig.rewardManager).burnSharesForKVCMStaker(maturityId, lockOwner);

        sKvcm.lockByMaturity[maturityId] -= principal;
        sKvcm.totalKvcmLocked -= principal;

        if (lockClosed) {
            emit IKvcmStakingFacet.KvcmUnlocked(lockOwner, lockId, maturityId, principal, accruedYield, 0);
        } else {
            emit IKvcmStakingFacet.KvcmPartialClaim(lockOwner, lockId, maturityId, principal, accruedYield);
        }
    }

    /// @notice Settle remaining yield for a PARTIAL_CLAIMED lock, sending it to `to`.
    /// @dev Authorizes ownership against `claimer` rather than `msg.sender` so it can
    ///      be invoked from a sibling facet that has already verified the caller.
    ///      Inlined into the calling facet
    function claimRemaining(uint256 lockId, address to, address claimer)
        internal
        returns (uint256 yieldOut, bool lockClosed)
    {
        if (to == address(0)) revert Errors.ZeroAddressNotAllowed();

        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        IKvcmStakingFacet.KvcmLockInfo storage lockInfo = sKvcm.kvcmLocks[lockId];

        if (lockInfo.status != IKvcmStakingFacet.KvcmLockStatus.PARTIAL_CLAIMED) {
            revert Errors.KvcmLockNotPartialClaimed();
        }
        if (lockInfo.lockOwner != claimer) revert Errors.KvcmLockNotOwned();

        (yieldOut, lockClosed) =
            IKvcmIncentivesCurveFacet(sConfig.rewardManager).handleUnlockAndClaim(lockInfo.lockOwner, lockId, to);

        if (lockClosed) {
            sKvcm.kvcmLocks[lockId].status = IKvcmStakingFacet.KvcmLockStatus.REDEEMED;
            emit IKvcmStakingFacet.KvcmUnlocked(lockInfo.lockOwner, lockId, lockInfo.maturityId, 0, yieldOut, 0);
        } else {
            emit IKvcmStakingFacet.KvcmPartialClaim(lockInfo.lockOwner, lockId, lockInfo.maturityId, 0, yieldOut);
        }
    }
}
