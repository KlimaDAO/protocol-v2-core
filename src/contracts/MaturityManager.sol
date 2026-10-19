// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/IMaturityManager.sol";
import "../libraries/CarbonSystemRoleLib.sol";
import "../libraries/Errors.sol";
import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title MaturityManager
 * @notice Manages lock maturities with deterministic mapping between timestamps and maturity IDs
 */

/**
 * General To-dos
 * Do we need to plan for a configurable matuirty period and altnerate timelines (MAturityMangager v2) before launch or can we handle after launch
 */
contract MaturityManager is IMaturityManager, UUPSUpgradeable, PausableUpgradeable {
    uint256 public constant NUM_ACTIVE_MATURITIES = 40;
    // Precision scaling factor for time calculations (1e18)
    uint256 public constant PRECISION = 1e18;

    address public accessManager;
    // The adjusted start timestamp, aligned to 12:00 am UTC (midnight)
    uint128 public adjustedStartTimestamp;
    uint128 public currentMaxMaturityId;

    uint256 public MATURITY_PERIOD;
    uint256 public MATURITY_DAYS;

    uint256[50] private __gap;

    /**
     * @dev Modifier to check if sender has admin or liquidity manager role
     */
    modifier onlyCarbonMaturityManager() {
        (bool hasCarbonMaturityManagerRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_MATURITY_MANAGER, msg.sender);

        if (!hasCarbonMaturityManagerRole) {
            revert Errors.NotCarbonMaturityManager();
        }
        _;
    }

    modifier onlySystemAdmin() {
        (bool hasCarbonSystemAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (!hasCarbonSystemAdminRole) {
            revert Errors.NotSystemAdmin();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _initialStartTimestamp, address _accessManager) public initializer {
        __Pausable_init();
        __UUPSUpgradeable_init();

        if (_accessManager == address(0)) {
            revert Errors.ZeroAddressNotAllowed();
        }

        accessManager = _accessManager;

        MATURITY_PERIOD = 90 days;

        MATURITY_DAYS = 90;

        // Align _initialStartTimestamp to the previous midnight (12:00 am UTC)
        adjustedStartTimestamp = SafeCast.toUint128(
            ((SafeCast.toUint128(_initialStartTimestamp) * PRECISION) / (1 days * PRECISION)) * 1 days
        );

        // 0 = liquid, 1-40 = active --> 41 total init maturities
        uint256 total_init_maturities = NUM_ACTIVE_MATURITIES + 1;

        uint256[] memory initial = new uint256[](total_init_maturities);
        for (uint256 i; i < total_init_maturities; ++i) {
            initial[i] = adjustedStartTimestamp + i * MATURITY_PERIOD;
            emit MaturityAdded(initial[i], i);
        }

        // @dev initialize to 200 years of maturities
        currentMaxMaturityId = SafeCast.toUint128(NUM_ACTIVE_MATURITIES * 20);

        emit MaxMaturityIdUpdated(getFirstActiveMaturityId(), currentMaxMaturityId);
    }

    //**********
    // ADMIN & CONFIG
    //**********

    /**
     * @notice Updates the maximum valid maturity ID
     * @param newMaxMaturityId The new maximum maturity ID
     * @dev possibly we also use this as check within other calls to ensure there are always 40 maturities
     */
    function updateMaxMaturityId(uint256 newMaxMaturityId) external onlyCarbonMaturityManager whenNotPaused {
        if (newMaxMaturityId <= currentMaxMaturityId) {
            revert Errors.InvalidMaturityId(newMaxMaturityId);
        }

        uint256 latestTimestamp = _timestampForMaturityId(currentMaxMaturityId);

        for (uint256 i = currentMaxMaturityId + 1; i <= newMaxMaturityId; i++) {
            uint256 newTimestamp = latestTimestamp + MATURITY_PERIOD;
            latestTimestamp = newTimestamp;
            emit MaturityAdded(newTimestamp, i);
        }

        currentMaxMaturityId = SafeCast.toUint128(newMaxMaturityId);

        emit MaxMaturityIdUpdated(getFirstActiveMaturityId(), currentMaxMaturityId);
    }

    function setAccessManager(address newAccessManager) external onlySystemAdmin {
        if (newAccessManager == address(0)) {
            revert Errors.ZeroAddressNotAllowed();
        }

        accessManager = newAccessManager;

        emit AccessManagerUpdated(newAccessManager);
    }

    function pause() external onlySystemAdmin {
        _pause();
    }

    function unpause() external onlySystemAdmin {
        _unpause();
    }

    function setMaturityPeriod(uint256 newMaturityPeriod) external onlySystemAdmin {
        if (newMaturityPeriod == 0) {
            revert Errors.ZeroAmount();
        }

        if (newMaturityPeriod % 1 days != 0) revert Errors.InvalidMaturityPeriod(newMaturityPeriod);

        MATURITY_PERIOD = newMaturityPeriod;
        MATURITY_DAYS = newMaturityPeriod / (1 days);

        emit MaturityPeriodUpdated(newMaturityPeriod);
    }

    //**********
    // GETTERS
    //**********

    function getNumMaturities() external view returns (uint256) {
        return NUM_ACTIVE_MATURITIES;
    }

    function getMaturityPeriod() external view returns (uint256) {
        return MATURITY_PERIOD;
    }

    /**
     * @notice Computes the start of the timestamp of the CURRENT (liquid) window.
     * If the current time has advanced by whole 90-day periods, the window shifts accordingly.
     * @return The effective start timestamp for the active maturity window.
     */
    function currentWindowStartTimestamp() public view returns (uint256) {
        if (block.timestamp < adjustedStartTimestamp) return adjustedStartTimestamp;
        uint256 periods = (block.timestamp - adjustedStartTimestamp) / MATURITY_PERIOD;
        return adjustedStartTimestamp + periods * MATURITY_PERIOD;
    }

    /**
     * @notice The timestamp when the *active* window begins (i.e. the next boundary)
     * @return The timestamp when the *active* window begins
     */
    function firstActiveBoundary() public view returns (uint256) {
        return currentWindowStartTimestamp() + MATURITY_PERIOD;
    }

    /**
     * @notice Returns the current active maturity IDs
     * @return ids An array of active maturity IDs
     */
    function getActiveMaturities() public view returns (uint256[] memory ids) {
        // liquid  = currentWindowStart()’s id
        // start   = first id after the liquid one
        // end     = min(liquid + NUM_ACTIVE_MATURITIES, currentMaxMaturityId)
        (uint256 start, uint256 end) = _getActiveMaturityRange();

        if (end < start) return new uint256[](0); // nothing yet minted

        uint256 len = end - start + 1; // <= 40
        ids = new uint256[](len);

        for (uint256 i; i < len; ++i) {
            ids[i] = start + i; // simply add ids
        }
    }

    /**
     * @notice Returns the start and end maturity IDs for the current active maturity range
     * @return start The first maturity ID in the active range
     * @return end The last maturity ID in the active range
     */
    function getActiveMaturityRange() external view returns (uint256 start, uint256 end) {
        return _getActiveMaturityRange();
    }

    /**
     * @notice Returns the active maturity range for a specific reference timestamp
     * @dev Calculates which maturities were active at the given timestamp, independent of block.timestamp.
     *      Critical for yield calculations that may execute after a maturity boundary has passed.
     * @param referenceTimestamp The timestamp to calculate the active range for
     * @return start The first maturity ID in the active range
     * @return end The last maturity ID in the active range
     */
    function getYieldBearingMaturityRangeForTimestamp(uint256 referenceTimestamp)
        external
        view
        returns (uint256 start, uint256 end)
    {
        return _getActiveMaturityRangeForTimestamp(referenceTimestamp);
    }

    function getMaturityInfo(uint256 maturityId) external view returns (MaturityInfo memory) {
        uint256 timestamp = _timestampForMaturityId(maturityId);
        bool exists = maturityId <= currentMaxMaturityId;

        bool isActive = exists && isValidMaturityTimeStamp(timestamp);

        return MaturityInfo({timestamp: timestamp, isActive: isActive, exists: exists});
    }

    function getMaturityTimestamp(uint256 maturityId) external view returns (uint256) {
        return _getMaturityTimestamp(maturityId);
    }

    function getMaturityStartTimestamp(uint256 maturityId) public view returns (uint256) {
        return _getMaturityStartTimestamp(maturityId);
    }

    function getMaturityTimeframe(uint256 maturityId)
        public
        view
        returns (uint256 startTimestamp, uint256 endTimestamp)
    {
        endTimestamp = _timestampForMaturityId(maturityId);
        startTimestamp = endTimestamp - MATURITY_PERIOD;
    }

    /**
     * @notice Returns the maturity ID for a given timestamp
     * @param timestamp The timestamp to query
     * @return maturityId The corresponding maturity ID (0 if not a valid maturity)
     */
    function getMaturityIdForMaturityTimestamp(uint256 timestamp) public view returns (uint256 maturityId) {
        if (timestamp < adjustedStartTimestamp) return type(uint256).max;

        // Check if timestamp is aligned to maturity period
        if ((timestamp - adjustedStartTimestamp) % MATURITY_PERIOD != 0) return type(uint256).max;

        uint256 periodOffset = (timestamp - adjustedStartTimestamp) / MATURITY_PERIOD;
        uint256 candidateId = periodOffset;

        // Check if this ID is within our current range`
        if (candidateId > currentMaxMaturityId) {
            revert Errors.InvalidMaturityTimestamp(timestamp);
        }
        return candidateId;
    }

    /**
     * @notice Returns the current (liquid) maturity ID
     * @return activeMaturityId the first active maturity ID
     */
    function getFirstActiveMaturityId() public view returns (uint256) {
        return getActiveMaturities()[0];
    }

    /// @inheritdoc IMaturityManager
    function getMaxMaturityId() external view returns (uint256) {
        return _getMaxMaturityId();
    }

    //**********
    // VALIDATION HELPERS
    //**********

    /**
     * @notice Checks if a given timestamp is a valid maturity timestamp in the current window.
     * It must lie within the window and exactly on a 90-day boundary.
     * @param providedTimestamp The timestamp to verify.
     * @return True if the timestamp is valid, false otherwise.
     */
    function isValidMaturityTimeStamp(uint256 providedTimestamp) public view returns (bool) {
        uint256 windowStart = currentWindowStartTimestamp();
        // the very first valid maturity is at +1 period
        uint256 first = windowStart + MATURITY_PERIOD;
        uint256 last = windowStart + MATURITY_PERIOD * NUM_ACTIVE_MATURITIES;

        if (providedTimestamp < first || providedTimestamp > last) {
            return false;
        }
        return (providedTimestamp - first) % MATURITY_PERIOD == 0;
    }

    function isValidMaturityId(uint256 id) external view returns (bool) {
        if (id > currentMaxMaturityId) return false;
        return isValidMaturityTimeStamp(_timestampForMaturityId(id)); // aligned & in window
    }

    //**********
    // INTERNALS
    //**********

    // function _rebuildMaturityTimestamps() internal {
    //     for (uint256 i = 0; i <= currentMaxMaturityId;) {
    //         uint256 ts = adjustedStartTimestamp + i * MATURITY_PERIOD;
    //         maturityTimestamps[SafeCast.toUint128(i)] = ts;
    //         emit MaturityAdded(ts, i);
    //         unchecked {
    //             ++i;
    //         }
    //     }
    // }

    function _getMaxMaturityId() internal view returns (uint256) {
        return currentMaxMaturityId;
    }

    /**
     * @notice Internal implementation for timestamp-based active range calculation
     * @param referenceTimestamp The timestamp to calculate the active range for
     * @return start The first maturity ID in the active range
     * @return end The last maturity ID in the active range
     */
    function _getActiveMaturityRangeForTimestamp(uint256 referenceTimestamp)
        internal
        view
        returns (uint256 start, uint256 end)
    {
        if (referenceTimestamp <= adjustedStartTimestamp) {
            uint256 lastActiveMaturityId =
                NUM_ACTIVE_MATURITIES > currentMaxMaturityId ? currentMaxMaturityId : NUM_ACTIVE_MATURITIES;
            return (1, lastActiveMaturityId);
        }

        uint256 elapsed = referenceTimestamp - adjustedStartTimestamp;
        uint256 periods = elapsed / MATURITY_PERIOD;

        // CRITICAL: If exactly on a maturity boundary, use the PREVIOUS period's range
        // This ensures the expiring maturity is included in yield calculations
        // Example: At T(90 days), maturity 1 just expired, but yield for day 89→90
        // should still include maturity 1 since it was active during that period
        if (elapsed > 0 && elapsed % MATURITY_PERIOD == 0) {
            periods = periods - 1;
        }

        uint256 firstPeriod = periods + 1;
        uint256 lastPeriod = periods + NUM_ACTIVE_MATURITIES;

        if (firstPeriod > currentMaxMaturityId) {
            return (firstPeriod, firstPeriod - 1); // empty range
        }
        if (lastPeriod > currentMaxMaturityId) {
            lastPeriod = currentMaxMaturityId;
        }

        return (firstPeriod, lastPeriod);
    }

    /**
     * @notice Returns the start and end maturity IDs for the current active maturity range
     * @return start The first maturity ID in the active range
     * @return end The last maturity ID in the active range
     */
    function _getActiveMaturityRange() internal view returns (uint256 start, uint256 end) {
        uint256 currentLiquidMaturityId = getMaturityIdForMaturityTimestamp(currentWindowStartTimestamp());
        uint256 first = currentLiquidMaturityId + 1;
        uint256 last = currentLiquidMaturityId + NUM_ACTIVE_MATURITIES;
        if (first > currentMaxMaturityId) {
            return (first, first - 1); // empty range
        }
        if (last > currentMaxMaturityId) last = currentMaxMaturityId;
        return (first, last);
    }

    function _getMaturityStartTimestamp(uint256 maturityId) internal view returns (uint256) {
        return adjustedStartTimestamp + maturityId * MATURITY_PERIOD;
    }

    function _getMaturityTimestamp(uint256 maturityId) internal view returns (uint256) {
        return _timestampForMaturityId(maturityId);
    }

    /**
     * @notice Returns the timestamp for a given maturity ID. If mapping is not set, lazily compute the timestamp.
     * @param maturityId The maturity ID to query
     * @return The corresponding timestamp
     */
    function _timestampForMaturityId(uint256 maturityId) internal view returns (uint256) {
        return adjustedStartTimestamp + maturityId * MATURITY_PERIOD;
    }

    //******************
    // Upgradeability
    //*****************

    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlySystemAdmin {}

    //******************
    // MIDNIGHT HELPERS
    //******************

    function getMidnightTimestampForIndex(uint256 midnightIndex) external view returns (uint256) {
        return adjustedStartTimestamp + midnightIndex * 1 days;
    }

    function getMidnightIndexForTimestamp(uint256 timestamp) external view returns (uint256) {
        return _calcMidnightIndex(timestamp);
    }

    function getMidnightIndexForMaturityId(uint256 maturityId) external view returns (uint256) {
        return _calcMidnightIndex(_getMaturityStartTimestamp(maturityId));
    }

    // /// @notice Given any UNIX‐timestamp `t`, find:
    // ///   1) the “previous” UTC midnight 00:00:00 ≤ t
    // ///   2) the “next”   UTC midnight 00:00:00 >  t
    // ///   3) for each of those midnights, the assosciated midnight index
    // ///
    // /// @param currentTimestamp  an arbitrary UNIX‐timestamp (seconds since epoch, UTC).
    // /// @return previousMidnightIndex    the midnight index associated with the previous midnight
    // /// @return previousMidnightTimestamp      the timestamp of the previous midnight
    // /// @return nextMidnightIndex    the midnight index associated with the next midnight
    // /// @return nextMidnightTimestamp      the timestamp of the next midnight

    function getAdjacentMidnightInfo(uint256 currentTimestamp)
        external
        view
        returns (
            uint256 previousMidnightIndex,
            uint256 previousMidnightTimestamp,
            uint256 nextMidnightIndex,
            uint256 nextMidnightTimestamp
        )
    {
        // If before adjustedStartTimestamp, clamp to day 0 / day 1
        if (currentTimestamp <= adjustedStartTimestamp) {
            previousMidnightIndex = 0;
            previousMidnightTimestamp = adjustedStartTimestamp;
            nextMidnightIndex = 1;
            nextMidnightTimestamp = adjustedStartTimestamp + 1 days;
            return (previousMidnightIndex, previousMidnightTimestamp, nextMidnightIndex, nextMidnightTimestamp);
        }

        // Use the same index logic
        uint256 dayIndex = _calcMidnightIndex(currentTimestamp);

        previousMidnightIndex = dayIndex;
        previousMidnightTimestamp = adjustedStartTimestamp + dayIndex * 1 days;

        nextMidnightIndex = dayIndex + 1;
        nextMidnightTimestamp = adjustedStartTimestamp + (dayIndex + 1) * 1 days;
    }

    //******************
    // INTERNALS
    //******************

    /**
     * @notice Calculates the midnight index for a given timestamp
     * @param timestamp The timestamp to calculate the midnight index for
     * @return midnightIndex The midnight index
     */
    function _calcMidnightIndex(uint256 timestamp) internal view returns (uint256 midnightIndex) {
        // Clamp to slot 0, day 1 if before start
        if (timestamp < adjustedStartTimestamp) {
            return 0;
        }

        // Calculate maturity ID
        uint256 maturityId = (timestamp - adjustedStartTimestamp) / MATURITY_PERIOD;

        // Start of this maturity period
        uint256 maturityPeriodStartTimestamp;
        unchecked {
            maturityPeriodStartTimestamp = _getMaturityStartTimestamp(maturityId);
        }

        unchecked {
            midnightIndex = ((timestamp - maturityPeriodStartTimestamp) / 1 days) + (maturityId * MATURITY_DAYS);
        }
    }
}
