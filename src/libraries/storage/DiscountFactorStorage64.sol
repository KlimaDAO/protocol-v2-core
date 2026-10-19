// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title DiscountFactorStorage64
 * @dev Packs four 64-bit discount factors into a single 256-bit slot automatically
 */
library DiscountFactorStorage64 {
    error DiscountFactorStorage64__ValueExceeds64Bits();

    /// @dev Each slot holds exactly 4 × 64-bit discount factors
    struct Slot {
        uint64[4] factors;
        uint256[50] _gap;
    }

    /// @dev Layout with a mapping from group index to packed Slot
    struct PackedDiscountFactorsLayout {
        mapping(uint256 => Slot) slots;
        uint256[50] _gap;
    }

    /**
     * @dev Sets the discount factor for a given `id`.
     * @param dfLayout The layout to set the discount factor for.
     * @param id     The maturity identifier.
     * @param value  The 64-bit discount factor to store.
     */
    function _set(PackedDiscountFactorsLayout storage dfLayout, uint256 id, uint64 value) internal {
        if (value > type(uint64).max) revert DiscountFactorStorage64__ValueExceeds64Bits();

        uint256 group = id / 4; // select packed slot
        uint256 lane = id % 4; // select index within slot

        dfLayout.slots[group].factors[lane] = value;
    }

    /**
     * @dev Retrieves the discount factor for a given `id`.
     * @param dfLayout The layout to retrieve the discount factor from.
     * @param id  The maturity identifier.
     * @return  discountFactor  The 64-bit discount factor.
     */
    function _get(PackedDiscountFactorsLayout storage dfLayout, uint256 id)
        internal
        view
        returns (uint64 discountFactor)
    {
        uint256 group = id / 4;
        uint256 lane = id % 4;

        discountFactor = dfLayout.slots[group].factors[lane];
    }

    /**
     * @dev Clears an entire packed slot (all 4 discount factors) for `group`.
     * @param group  The index of the slot to clear.
     */
    function _clearGroup(PackedDiscountFactorsLayout storage dfLayout, uint256 group) internal {
        delete dfLayout.slots[group];
    }

    /**
     * @dev Clears all discount factors by wiping specific groups.
     * @notice This is a simplified implementation that clears the first 100 groups.
     * In a production environment, consider tracking which groups are in use.
     */
    function _clearAll(PackedDiscountFactorsLayout storage dfLayout) internal {
        for (uint256 i = 0; i < 500; i++) {
            _clearGroup(dfLayout, i);
        }
    }
}
