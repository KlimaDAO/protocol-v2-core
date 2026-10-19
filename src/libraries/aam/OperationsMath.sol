// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {mul, div, exp, sub, ln, add, UD60x18, ud, unwrap} from "@prb/math/UD60x18.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
// interfaces
import {IAssetManagerConfigFacet} from "src/interfaces/AssetManager/IAssetManagerConfigFacet.sol";
// libraries
import {Constants} from "src/libraries/Constants.sol";
import {Errors} from "src/libraries/Errors.sol";

/// @title OperationsMath
/// @notice Gas-minimised maths used by the Kvcm Asset Manager.

library OperationsMath {
    using {mul, div, exp, sub, ln, add} for UD60x18;

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTANTS                                  */
    /* -------------------------------------------------------------------------- */

    UD60x18 private constant ONE = UD60x18.wrap(1e18);

    /* -------------------------------------------------------------------------- */
    /*                     ─── Swap ( C → A)  helpers ───                         */
    /* -------------------------------------------------------------------------- */

    /// @dev classDelta = discountedAmount / classBalance
    function _swapClassDelta(uint256 classBalance, uint256 discountedAmount) private pure returns (UD60x18) {
        return ud(Math.mulDiv(discountedAmount, 1e18, classBalance, Math.Rounding.Floor));
    }

    /// @dev 4-8 white-paper price formula — returns ΔA (as UD60x18)
    function _swapKvcmDelta(UD60x18 classDelta, uint256 kvcmStake, uint256 k2Stake) private pure returns (UD60x18) {
        UD60x18 A = ud(kvcmStake);
        UD60x18 G = ud(k2Stake);
        UD60x18 oneMinusG = ONE.sub(G); // 1 – G

        // A – A²(1–G)² / 2
        UD60x18 x = ONE.add(classDelta);
        UD60x18 rhs = A.sub(A.mul(A).mul(oneMinusG.mul(oneMinusG)).div(ud(2e18)));

        // ΔA = (1+ΔC) ** rhs – 1
        return x.pow(rhs).sub(ONE);
    }

    /* -------------------------------------------------------------------------- */
    /*                        Swap quote ( C → A)                                  */
    /* -------------------------------------------------------------------------- */

    function calculateSwapKvcmPrice(
        uint256 discountedVaultBalance,
        uint256 discountedDelta,
        uint256 kvcmStake,
        uint256 k2Stake,
        uint256 kvcmCirculatingSupply
    ) internal pure returns (uint256) {
        UD60x18 classDelta = _swapClassDelta(discountedVaultBalance, discountedDelta);
        UD60x18 deltaA = _swapKvcmDelta(classDelta, kvcmStake, k2Stake);

        // price = ΔA · circulatingSupply   (still 18-dec fixed)
        return unwrap(deltaA.mul(ud(kvcmCirculatingSupply)));
    }

    /* -------------------------------------------------------------------------- */
    /*               Zero Carbon Scenario                                         */
    /* -------------------------------------------------------------------------- */

    function calculateKvcmSwapDeltaZeroCarbonScenario(uint256 classDeltaRaw, uint256 kvcmStake, uint256 k2Stake)
        internal
        pure
        returns (uint256)
    {
        UD60x18 classDelta = ud(classDeltaRaw);
        UD60x18 A = ud(kvcmStake);
        UD60x18 oneMinusG = ONE.sub(ud(k2Stake));

        UD60x18 left = classDelta.div(ONE.add(classDelta)); // ΔC / (1+ΔC)
        UD60x18 inner = A.sub(A.mul(A).mul(oneMinusG.mul(oneMinusG)).div(ud(2e18))); // A – A²(1–G)²/2

        return unwrap(left.mul(inner.mul(inner))); // square “inner”
    }

    /* -------------------------------------------------------------------------- */
    /*                       Retirement quote ( A → C*)                          */
    /* -------------------------------------------------------------------------- */
    /// @dev Inverse of calculateKvcmRetirementQuote: given a kVCM budget, solve for the tonnes retired.
    /// Returns tonnes (18-dec). Reverts if the budget reaches or exceeds the circulating supply.
    function calculateTonnesRetirementFromKvcm(
        uint256 kvcmIn,
        uint256 kvcmStake,
        uint256 k2Stake,
        uint256 totalClassBalanceForQuote,
        uint256 kvcmCirculatingSupply
    ) internal pure returns (uint256) {
        if (kvcmIn == 0) return 0;
        if (kvcmIn >= kvcmCirculatingSupply) revert Errors.CannotRetireEntireKvcmSupply();

        // Forward: ΔA = (1 − ΔC)^(−rhs) − 1   with rhs = A + ½·A²·(1 − G)²
        // Inverse: ΔC = 1 − (1 + ΔA)^(−1/rhs)
        UD60x18 A = ud(kvcmStake);
        UD60x18 G = ud(k2Stake);

        UD60x18 deltaA = ud(kvcmIn).div(ud(kvcmCirculatingSupply));
        UD60x18 onePlusDeltaA = ONE.add(deltaA);

        UD60x18 oneMinusG = ONE.sub(G);
        UD60x18 rhs = A.add(A.mul(A).mul(oneMinusG.mul(oneMinusG)).div(ud(2e18)));

        // (1 + ΔA)^(−1/rhs) = 1/exp(ln(1 + ΔA)/rhs)
        UD60x18 exponent = onePlusDeltaA.ln().div(rhs);
        UD60x18 x = unwrap(exponent) > Constants.UD_EXP_MAX_INPUT ? ud(0) : ONE.div(exponent.exp());
        UD60x18 deltaC = ONE.sub(x); // 1 − (1 + ΔA)^(−1/rhs)

        return unwrap(deltaC.mul(ud(totalClassBalanceForQuote)));
    }

    function calculateKvcmRetirementQuote(
        uint256 amount,
        uint256 kvcmStake,
        uint256 k2Stake,
        uint256 totalClassBalanceForQuote,
        uint256 kvcmCirculatingSupply
    ) internal pure returns (uint256) {
        /**
         * @custom:note solve for A from white-paper formula
         * ΔA = (1 − ΔC)^(−rhs) − 1,   rhs = A + ½·A²·(1 − G)²
         *
         * Retiring the entire class balance (ΔC → 1) diverges (quote → ∞), so
         * ΔC ≥ 1 is rejected up front with the same CannotRetireEntireKvcmSupply
         * error the caller raises once the quote exceeds circulating supply.
         */
        if (amount >= totalClassBalanceForQuote) {
            revert Errors.CannotRetireEntireKvcmSupply();
        }

        UD60x18 A = ud(kvcmStake);
        UD60x18 G = ud(k2Stake);

        UD60x18 deltaC = ud(amount).div(ud(totalClassBalanceForQuote));

        // 1 − ΔC
        UD60x18 oneMinusDeltaC = ONE.sub(deltaC);

        UD60x18 oneMinusG = ONE.sub(G);
        UD60x18 rhs = A.add(A.mul(A).mul(oneMinusG.mul(oneMinusG)).div(ud(2e18)));

        // ΔA = (1 − ΔC)^(−rhs) − 1 = (1 / (1 − ΔC))^rhs − 1
        UD60x18 deltaA = ONE.div(oneMinusDeltaC).pow(rhs).sub(ONE);

        return unwrap(deltaA.mul(ud(kvcmCirculatingSupply)));
    }

    function _computeExponentialDecay(
        uint256 snapshotValue,
        uint256 snapshotTime,
        uint64 rate,
        uint256 currentTimestamp
    ) internal pure returns (uint256 limit) {
        validateRateLimitParamSet(rate);
        uint256 timeDelta = currentTimestamp > snapshotTime ? (currentTimestamp - snapshotTime) : 0;
        uint256 rateDelta = uint256(rate) * timeDelta;

        // @dev at this value input, decay is effectively 0. return 0 vs revert
        if (rateDelta > Constants.UD_EXP_MAX_INPUT) return 0;

        // exp(-x) = 1 / exp(x)
        UD60x18 decay = ud(Constants.WAD).div(ud(rateDelta).exp());
        limit = unwrap(ud(snapshotValue).mul(decay));
    }

    function _computeExponentialGrowth(
        uint256 snapshotValue,
        uint256 snapshotTime,
        uint64 rate,
        uint256 currentTimestamp
    ) internal pure returns (uint256 limit) {
        validateRateLimitParamSet(rate);
        uint256 timeDelta = currentTimestamp > snapshotTime ? (currentTimestamp - snapshotTime) : 0;
        uint256 rateDelta = uint256(rate) * timeDelta;

        /* @dev at this value input, cap at maximum exp input to avoid PRB revert.
        * We take the min() of the growth vs raw, so the worst case scenario is that this will limit a massive allocation's true weight. */
        if (rateDelta > Constants.UD_EXP_MAX_INPUT) {
            rateDelta = Constants.UD_EXP_MAX_INPUT;
        }

        UD60x18 growth = ud(rateDelta).exp();

        if (snapshotValue >= unwrap(ud(type(uint256).max).div(growth))) {
            return type(uint256).max;
        }

        limit = unwrap(ud(snapshotValue).mul(growth));
    }

    /* -------------------------------------------------------------------------- */
    /*                            Validation Helpers                              */
    /* -------------------------------------------------------------------------- */

    function validateRateLimitParamSet(uint64 rate) private pure {
        // @dev never allow non-rate limited swaps
        if (rate == 0) revert Errors.ZeroRate();
    }

    /* -------------------------------------------------------------------------- */
    /*                            Discount helpers                                */
    /* -------------------------------------------------------------------------- */

    function calculateDiscountedDelta(uint256 amount, uint256 discountFactor) internal pure returns (uint256) {
        if (discountFactor == 0) revert Errors.ZeroDiscountFactor();
        return _discount(amount, discountFactor);
    }

    function calculateDiscountedForwardTonnage(uint256 amount, uint256 discountFactor) internal pure returns (uint256) {
        return _discount(amount, discountFactor);
    }

    /// @dev amount · discountFactor / 1e18  (floor)
    function _discount(uint256 amount, uint256 discountFactor) private pure returns (uint256) {
        return Math.mulDiv(amount, discountFactor, 1e18);
    }
}
