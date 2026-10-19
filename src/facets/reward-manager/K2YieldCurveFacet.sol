// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {wrap} from "@prb/math/sd59x18/Casting.sol";
import {add} from "@prb/math/sd59x18/Helpers.sol";
import {div, exp, ln} from "@prb/math/sd59x18/Math.sol";

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {IK2YieldCurveFacet} from "../../interfaces/RewardManager/IK2YieldCurveFacet.sol";
import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Constants} from "../../libraries/Constants.sol";

/**
 * @title K2YieldCurveFacet
 * @notice Manages the normalized logistic reward distribution for K2 Yield.
 * @dev The curve is defined by:
 *
 *   P(t)   = exp(xt) / (1 + exp(xt))
 *   xt     = x0 * (1 - t / T)
 *   x0     = ln(P0 / (1 - P0)), P0 in (0,1)
 *
 * Normalized fraction (using actual endpoint):
 *   P_end     = P(duration) = exp(x_end) / (1 + exp(x_end))
 *   P_norm(t) = (P(t) - P0) / (P_end - P0)  in [0, 1]
 *
 * This ensures P_norm(0) = 0 and P_norm(duration) = 1 exactly,
 * guaranteeing full rewardCap distribution.
 *
 * Cumulative tokens:
 *   C(t) = P_norm(t) * rewardCap
 *
 * Daily emission for midnightIndex (1-based):
 *   E_i = C(t_i) - C(t_{i-1}), where t_{i-1} = start + (i-1) * DAY, clamped to duration.
 */
contract K2YieldCurveFacet is IK2YieldCurveFacet {
    modifier onlyAdmin() {
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        (bool hasRole,) = IAccessManager(c.accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);
        if (!hasRole) {
            revert Errors.NotSystemAdmin();
        }
        _;
    }

    /**
     * @notice Initialize the K2 yield curve parameters.
     * @param _rewardCap Total reward pool for K2 Yield.
     * @param _start TGE timestamp for the curve.
     * @param _T Inflection point in seconds (e.g., 2*365 days).
     * @param _duration Clamp horizon in seconds (e.g., 8*365 days).
     * @param _P0_wad Initial fraction P0 in 1e18 (e.g., 0.07e18 for 7%).
     */
    function initK2YieldSchedule(uint256 _rewardCap, uint256 _start, uint256 _T, uint256 _duration, uint256 _P0_wad)
        external
        onlyAdmin
    {
        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();
        if (s.rewardCap != 0) revert Errors.AlreadyInitialized();
        if (_rewardCap == 0) revert Errors.ZeroAmount();
        if (_T == 0 || _duration == 0) revert Errors.InvalidAmountTooSmall(0);
        if (_P0_wad == 0) revert Errors.ZeroAmount();
        if (_P0_wad >= Constants.WAD) revert Errors.InvalidAmountTooLarge(_P0_wad);

        s.rewardCap = _rewardCap;
        s.start = _start;
        s.T = _T;
        s.duration = _duration;
        s.P0_wad = _P0_wad;

        // x0 = ln(P0 / (1 - P0))
        int256 P0 = int256(_P0_wad);
        int256 oneMinusP0 = int256(Constants.WAD - _P0_wad);
        s.x0 = (ln(wrap(P0)) - ln(wrap(oneMinusP0))).unwrap();

        // Compute P_end = P(duration) for normalization
        // x_end = x0 * (1 - duration/T)
        int256 oneMinusDurOverT = int256(Constants.WAD) - int256((_duration * 1e18) / _T);
        int256 x_end_raw = (s.x0 * oneMinusDurOverT) / int256(1e18); // Both values are in 1e18 scale
        SD59x18 x_end = wrap(x_end_raw);
        SD59x18 exp_x_end = exp(x_end);
        SD59x18 denom_end = add(exp_x_end, wrap(int256(Constants.WAD)));
        SD59x18 p_end = div(exp_x_end, denom_end);
        s.P_end_wad = uint256(p_end.unwrap());

        // Validate P_end > P0 for proper normalization
        if (s.P_end_wad <= s.P0_wad) revert Errors.InvalidAmountTooSmall(s.P_end_wad);

        emit ScheduleUpdated(s.start, s.T, s.duration, s.x0, s.P0_wad);
    }

    // ----------------- Admin -----------------

    /**
     * @notice Safely update schedule while preserving cumulative monotonicity.
     *         Captures current cumulative as offset, then starts a fresh curve
     *         that distributes only the remaining tokens (rewardCap - offset).
     * @param newStart    New start timestamp for the curve (must be >= block.timestamp).
     * @param newT        New inflection point in seconds.
     * @param newDuration New clamp duration in seconds.
     * @param newP0_wad   New P0 in 1e18 for the fresh curve (required, in (0, 1e18)).
     */
    function updateSchedule(uint256 newStart, uint256 newT, uint256 newDuration, uint256 newP0_wad) external onlyAdmin {
        if (newStart < block.timestamp) revert Errors.InvalidMaturityTimestamp(newStart);
        if (newT == 0 || newDuration == 0) revert Errors.InvalidAmountTooSmall(0);
        if (newP0_wad == 0) revert Errors.ZeroAmount();
        if (newP0_wad >= Constants.WAD) revert Errors.InvalidAmountTooLarge(newP0_wad);

        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();

        // Capture current cumulative BEFORE updating parameters to preserve monotonicity
        // This becomes the new baseline for all future calculations
        uint256 currentCumulative = cumulativeAllocatedAt(newStart);
        s.cumulativeOffset = currentCumulative;

        // Set new start at now
        s.start = newStart;
        s.T = newT;
        s.duration = newDuration;

        // Set the new P0 for the fresh curve
        s.P0_wad = newP0_wad;

        // Recompute x0 from chosen P0
        int256 P0 = int256(s.P0_wad);
        int256 oneMinusP0 = int256(Constants.WAD - s.P0_wad);
        s.x0 = (ln(wrap(P0)) - ln(wrap(oneMinusP0))).unwrap();

        // Recompute P_end = P(duration) with new parameters
        // x_end = x0 * (1 - duration/T)
        int256 oneMinusDurOverT = int256(Constants.WAD) - int256((newDuration * 1e18) / newT);
        int256 x_end_raw = (s.x0 * oneMinusDurOverT) / int256(1e18); // Both values are in 1e18 scale
        SD59x18 x_end = wrap(x_end_raw);
        SD59x18 exp_x_end = exp(x_end);
        SD59x18 denom_end = add(exp_x_end, wrap(int256(Constants.WAD)));
        SD59x18 p_end = div(exp_x_end, denom_end);
        s.P_end_wad = uint256(p_end.unwrap());

        // Validate P_end > P0 for proper normalization
        if (s.P_end_wad <= s.P0_wad) revert Errors.InvalidAmountTooSmall(s.P_end_wad);

        emit ScheduleUpdated(s.start, s.T, s.duration, s.x0, s.P0_wad);
    }

    // ----------------- Views -----------------

    /// @notice Cumulative tokens allocated at `ts` (normalized).
    /// @dev After schedule updates, returns offset + (normalized_progress * remaining_cap)
    ///      This ensures monotonicity: cumulative never decreases after updateSchedule().
    function cumulativeAllocatedAt(uint256 ts) public view returns (uint256) {
        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();
        uint256 f = _pNormAt(ts); // in 1e18

        // After schedule update, offset holds tokens already allocated
        // New curve only distributes the remaining tokens (rewardCap - offset)
        uint256 remainingCap = s.rewardCap - s.cumulativeOffset;
        return s.cumulativeOffset + (f * remainingCap) / Constants.WAD;
    }

    /// @notice Tokens unlocked during day `midnightIndex` (1-based).
    /// @dev MidnightIndex 1 covers [start, start+1*DAY), index 2 covers [start+1*DAY, start+2*DAY), etc.
    function dailyEmission(uint256 midnightIndex) public view returns (uint256) {
        if (midnightIndex == 0) return 0; // Invalid: 1-based indexing

        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();
        uint256 dayId = midnightIndex - 1; // Convert to 0-based internal indexing
        uint256 aTs = _clampedTs(s.start + dayId * 1 days);
        uint256 bTs = _clampedTs(s.start + (dayId + 1) * 1 days);

        if (bTs <= aTs) return 0; // beyond duration

        uint256 a = cumulativeAllocatedAt(aTs);
        uint256 b = cumulativeAllocatedAt(bTs);

        return b > a ? b - a : 0;
    }

    /// @notice Emission unlocked between two timestamps (normalized schedule).
    function emissionBetween(uint256 fromTs, uint256 toTs) external view returns (uint256) {
        if (toTs <= fromTs) return 0;
        uint256 a = cumulativeAllocatedAt(fromTs);
        uint256 b = cumulativeAllocatedAt(toTs);
        return b > a ? b - a : 0;
    }

    function getK2YieldCurveParams() external view returns (IK2YieldCurveFacet.K2YieldCurveParams memory params) {
        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();
        return IK2YieldCurveFacet.K2YieldCurveParams({
            rewardCap: s.rewardCap,
            start: s.start,
            T: s.T,
            duration: s.duration,
            x0: s.x0,
            P0_wad: s.P0_wad,
            P_end_wad: s.P_end_wad,
            cumulativeOffset: s.cumulativeOffset
        });
    }

    // ----------------- Internal helpers -----------------

    /// @dev Clamp timestamp to [start, start+duration]
    function _clampedTs(uint256 ts) internal view returns (uint256) {
        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();
        if (ts <= s.start) return s.start;

        uint256 end = s.start + s.duration;
        return ts >= end ? end : ts;
    }

    /// @dev Raw logistic P(t) in 1e18 (not normalized).
    function _pRawAt(uint256 ts) internal view returns (uint256) {
        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();
        // At/before start: return exact P0 based on x0
        if (ts <= s.start) {
            SD59x18 expx0 = exp(wrap(s.x0));
            SD59x18 denom_p0 = add(expx0, wrap(int256(Constants.WAD)));
            SD59x18 p0 = div(expx0, denom_p0);

            if (p0.unwrap() < 0) return 0;
            if (p0.unwrap() > int256(Constants.WAD)) return Constants.WAD;
            return uint256(p0.unwrap());
        }

        uint256 eff = _clampedTs(ts);
        uint256 t = eff - s.start;

        // xt = x0 * (1 - t/T)
        int256 oneMinusT = int256(Constants.WAD) - int256((t * 1e18) / s.T); // 1e18 - (t/T in 1e18)
        int256 xt_raw = (s.x0 * oneMinusT) / int256(1e18); // Both values are in 1e18 scale
        SD59x18 xt = wrap(xt_raw);

        SD59x18 e = exp(xt);
        SD59x18 denom = add(e, wrap(int256(Constants.WAD)));
        SD59x18 p = div(e, denom);

        if (p.unwrap() < 0) return 0;
        if (p.unwrap() > int256(Constants.WAD)) return Constants.WAD;
        return uint256(p.unwrap());
    }

    /// @dev Normalized fraction P_norm(t) in 1e18.
    /// Uses actual endpoint normalization: (P(t) - P0) / (P_end - P0)
    function _pNormAt(uint256 ts) internal view returns (uint256) {
        RewardManagerStorage.K2YieldCurveLayout storage s = RewardManagerStorage.k2YieldCurveLayout();
        uint256 p = _pRawAt(ts); // in [0,1e18]
        if (p <= s.P0_wad) return 0;

        // (p - P0) / (P_end - P0)
        uint256 num = p - s.P0_wad;
        uint256 denom = s.P_end_wad - s.P0_wad; // > 0 by validation check
        uint256 frac = (num * 1e18) / denom;

        return frac > 1e18 ? 1e18 : frac;
    }
}
