// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {StakingManagerStorage} from "src/libraries/storage/StakingManagerStorage.sol";
import {Errors} from "src/libraries/Errors.sol";

// interfaces
import {IKvcmStakingFacet} from "src/interfaces/StakingManager/IKvcmStakingFacet.sol";
import {IIncentivesRetirementFacet} from "src/interfaces/StakingManager/IIncentivesRetirementFacet.sol";
import {IKvcmIncentivesCurveFacet} from "src/interfaces/RewardManager/IKvcmIncentivesCurveFacet.sol";
import {IRetirementAggregator} from "src/interfaces/IRetirementAggregator.sol";
import {IQuoterRouterFacet} from "src/interfaces/AssetManager/IQuoterRouterFacet.sol";
import {ICarbonClassVault} from "src/interfaces/ICarbonClassVault.sol";
import {KvcmStakingLib} from "src/libraries/staking-manager/KvcmStakingLib.sol";

/// @dev Same-diamond entrypoints: `msg.sender` is preserved for `IKvcmStakingFacet` owner checks (no operator approval).
contract IncentivesRetirementFacet is IIncentivesRetirementFacet, ReentrancyGuard {
    using SafeERC20 for IERC20;

    modifier whenNotPaused() {
        if (
            StakingManagerStorage.managerPauseLayout().systemPaused
                || StakingManagerStorage.managerPauseLayout().kvcmStakingPaused
        ) {
            revert Errors.KvcmStakingPaused();
        }
        _;
    }

    /// @inheritdoc IIncentivesRetirementFacet
    function retireKvcmIncentivesActiveLock(uint256 lockId, RetireParams calldata p)
        external
        whenNotPaused
        nonReentrant
    {
        if (p.maxKvcmIn == 0) revert Errors.AmountCannotBeZero();

        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        address kvcmToken = sConfig.kvcmToken;
        address retirementAggregator = sConfig.retirementAggregator;
        if (retirementAggregator == address(0)) revert Errors.RetirementAggregatorNotSet();

        IKvcmStakingFacet.KvcmLockInfo memory lockInfo = IKvcmStakingFacet(address(this)).getKvcmLockInfo(lockId);
        if (lockInfo.status != IKvcmStakingFacet.KvcmLockStatus.OPEN) revert Errors.KvcmLockIsClosed();
        if (IKvcmStakingFacet(address(this)).isKvcmLockMatured(lockId)) revert Errors.KvcmLockMatured();
        if (!IKvcmStakingFacet(address(this)).isKvcmLockOwned(lockId, msg.sender)) revert Errors.KvcmLockNotOwned();

        address lockOwner = lockInfo.lockOwner;

        uint256 kvcmPreWithdraw = IERC20(kvcmToken).balanceOf(address(this));

        // get exact quote to minimize dust burns
        (uint256 tonnesQuote, uint256 tokenAmountQuote, uint256 kvcmRetirementPrice,,) = IQuoterRouterFacet(sConfig.aam)
            .getRetirementQuoteForKvcmIn(
                p.carbonClass,
                p.creditToken,
                p.tokenId,
                p.maxKvcmIn,
                ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
            );

        if (kvcmRetirementPrice == 0) revert Errors.ZeroAmount();
        if (tonnesQuote == 0) revert Errors.ZeroAmount();

        // this should never happen because of the quote method above, but just in case
        if (kvcmRetirementPrice > p.maxKvcmIn) {
            revert Errors.KvcmRetireAmountExceedsBalance(p.maxKvcmIn, kvcmRetirementPrice);
        }
        /**
         * we pass the retirement price from above in the case that the kvcm in will empty the vault.
         * // in this case, the retirement price will be lower than the maxKvcmIn
         */
        IKvcmIncentivesCurveFacet(sConfig.rewardManager)
            .routeYieldForActiveMaturityRetire(lockId, kvcmRetirementPrice, address(this));

        uint256 kvcmPostWithdraw = IERC20(kvcmToken).balanceOf(address(this));
        if (kvcmPostWithdraw < kvcmPreWithdraw + kvcmRetirementPrice) {
            revert Errors.KvcmYieldClaimProceedsShortfall(kvcmPreWithdraw + kvcmRetirementPrice, kvcmPostWithdraw);
        }

        // Measure actual RA spend to enforce that ALL claimed incentives are retired.
        uint256 kvcmBeforeRetire = IERC20(kvcmToken).balanceOf(address(this));
        _retireViaRA(retirementAggregator, p, kvcmRetirementPrice, tokenAmountQuote);
        uint256 actualRetired = kvcmBeforeRetire - IERC20(kvcmToken).balanceOf(address(this));

        if (actualRetired != kvcmRetirementPrice) {
            revert Errors.KvcmYieldNotFullyRetired(kvcmRetirementPrice, actualRetired);
        }

        emit IncentivesRetiredFromActiveLock(
            lockOwner, lockId, lockInfo.maturityId, kvcmToken, actualRetired, address(this)
        );
    }

    /// @inheritdoc IIncentivesRetirementFacet
    function unlockAndRetire(uint256 lockId, RetireParams calldata p) external whenNotPaused nonReentrant {
        if (p.maxKvcmIn == 0) revert Errors.AmountCannotBeZero();

        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        address kvcmToken = sConfig.kvcmToken;
        address retirementAggregator = sConfig.retirementAggregator;
        if (retirementAggregator == address(0)) revert Errors.RetirementAggregatorNotSet();

        if (!IKvcmStakingFacet(address(this)).isKvcmLockOwned(lockId, msg.sender)) revert Errors.KvcmLockNotOwned();

        IKvcmStakingFacet.KvcmLockInfo memory lockInfo = IKvcmStakingFacet(address(this)).getKvcmLockInfo(lockId);

        // settle principal back to the user, yield into the diamond to fund retirement.
        (, uint256 incentivesOut) = KvcmStakingLib.unlock(lockId, msg.sender, address(this), msg.sender);

        (uint256 tonnesQuote, uint256 tokenAmountQuote, uint256 kvcmRetirementPrice,,) = IQuoterRouterFacet(sConfig.aam)
            .getRetirementQuoteForKvcmIn(
                p.carbonClass,
                p.creditToken,
                p.tokenId,
                p.maxKvcmIn,
                ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
            );

        if (kvcmRetirementPrice == 0) revert Errors.ZeroAmount();
        if (tonnesQuote == 0) revert Errors.ZeroAmount();

        // this should never happen, but just in case
        if (kvcmRetirementPrice > p.maxKvcmIn) {
            revert Errors.KvcmRetireAmountExceedsBalance(p.maxKvcmIn, kvcmRetirementPrice);
        }
        if (kvcmRetirementPrice > incentivesOut) {
            revert Errors.KvcmRetireAmountExceedsBalance(kvcmRetirementPrice, incentivesOut);
        }

        uint256 kvcmBeforeRetire = IERC20(kvcmToken).balanceOf(address(this));
        _retireViaRA(retirementAggregator, p, kvcmRetirementPrice, tokenAmountQuote);
        uint256 actualRetired = kvcmBeforeRetire - IERC20(kvcmToken).balanceOf(address(this));
        // Return any incentives not consumed by the retirement.
        uint256 returnedIncentives = incentivesOut - actualRetired;
        if (returnedIncentives > 0) IERC20(kvcmToken).safeTransfer(msg.sender, returnedIncentives);

        emit IncentivesRetiredOnUnlock(
            lockInfo.lockOwner, lockId, lockInfo.maturityId, kvcmToken, incentivesOut, actualRetired, returnedIncentives
        );
    }

    /// @inheritdoc IIncentivesRetirementFacet
    function retireRemainingIncentives(uint256 lockId, RetireParams calldata p) external whenNotPaused nonReentrant {
        if (p.maxKvcmIn == 0) revert Errors.AmountCannotBeZero();

        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        address kvcmToken = sConfig.kvcmToken;
        address retirementAggregator = sConfig.retirementAggregator;
        if (retirementAggregator == address(0)) revert Errors.RetirementAggregatorNotSet();

        IKvcmStakingFacet.KvcmLockInfo memory lockInfo = IKvcmStakingFacet(address(this)).getKvcmLockInfo(lockId);
        if (lockInfo.status != IKvcmStakingFacet.KvcmLockStatus.PARTIAL_CLAIMED) {
            revert Errors.KvcmLockNotPartialClaimed();
        }
        if (lockInfo.lockOwner != msg.sender) revert Errors.KvcmLockNotOwned();

        //  pull remaining yield into the diamond so it can fund the retirement;
        (uint256 incentivesOut,) = KvcmStakingLib.claimRemaining(lockId, address(this), msg.sender);
        if (incentivesOut == 0) revert Errors.NoIncentivesToClaim();

        (uint256 tonnesQuote, uint256 tokenAmountQuote, uint256 kvcmRetirementPrice,,) = IQuoterRouterFacet(sConfig.aam)
            .getRetirementQuoteForKvcmIn(
                p.carbonClass,
                p.creditToken,
                p.tokenId,
                p.maxKvcmIn,
                ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
            );

        if (kvcmRetirementPrice == 0) revert Errors.ZeroAmount();
        if (tonnesQuote == 0) revert Errors.ZeroAmount();

        // this should never happen, but just in case
        if (kvcmRetirementPrice > p.maxKvcmIn) {
            revert Errors.KvcmRetireAmountExceedsBalance(p.maxKvcmIn, kvcmRetirementPrice);
        }
        // revert to expose error vs clamping to incentivesOut
        if (kvcmRetirementPrice > incentivesOut) {
            revert Errors.KvcmRetireAmountExceedsBalance(kvcmRetirementPrice, incentivesOut);
        }

        uint256 kvcmBeforeRetire = IERC20(kvcmToken).balanceOf(address(this));
        _retireViaRA(retirementAggregator, p, kvcmRetirementPrice, tokenAmountQuote);
        uint256 actualRetired = kvcmBeforeRetire - IERC20(kvcmToken).balanceOf(address(this));
        // Post-claim: incentives are rightfully the user's. Refund anything not retired —
        // both the quote-cap remainder (incentivesOut - kvcmRetirementPrice) and any RA undershoot.
        uint256 returned = incentivesOut - actualRetired;
        if (returned > 0) IERC20(kvcmToken).safeTransfer(msg.sender, returned);

        emit RemainingIncentivesRetired(
            lockInfo.lockOwner, lockId, lockInfo.maturityId, kvcmToken, incentivesOut, actualRetired, returned
        );
    }

    function _retireViaRA(
        address retirementAggregator,
        RetireParams calldata p,
        uint256 kvcmRetirementPrice,
        uint256 creditTokenAmount
    ) internal {
        StakingManagerStorage.StakingManagerConfigLayout storage c = StakingManagerStorage.configLayout();
        address kvcm = c.kvcmToken;
        address spender = c.aam;
        if (kvcm == address(0) || spender == address(0)) revert Errors.ZeroAddressNotAllowed();

        IERC20(kvcm).forceApprove(spender, kvcmRetirementPrice);

        IRetirementAggregator(retirementAggregator)
            .retireCreditViaKlima(
                p.creditToken,
                p.tokenId,
                p.batchId,
                creditTokenAmount,
                kvcm,
                p.carbonClass,
                kvcmRetirementPrice,
                0,
                IRetirementAggregator.RetireDetails({
                retiringAddress: address(this),
                retiringEntityString: "",
                beneficiaryAddress: p.beneficiaryAddress == address(0) ? msg.sender : p.beneficiaryAddress,
                beneficiaryString: p.beneficiaryString,
                retirementMessage: p.retirementMessage,
                beneficiaryLocation: p.beneficiaryLocation,
                consumptionCountryCode: p.consumptionCountryCode,
                consumptionPeriodStart: p.consumptionPeriodStart,
                consumptionPeriodEnd: p.consumptionPeriodEnd
            })
            );

        IERC20(kvcm).forceApprove(spender, 0);
    }
}
