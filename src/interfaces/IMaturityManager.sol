// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/ICommonEvents.sol";

/**
 * @title IMaturityManager
 * @notice Interface for managing lock maturities with deterministic mapping between timestamps and maturity IDs.
 *         Provides functionality for managing a fixed number of maturities within a sliding window.
 */
interface IMaturityManager is ICommonEvents {
    /**
     * @notice Information about a specific maturity
     * @dev Key is maturityId
     * @param timestamp Timestamp when the maturity occurs
     * @param isActive Whether the maturity is currently within the active window
     * @param exists Whether the maturity ID has been registered in the system
     */
    struct MaturityInfo {
        uint256 timestamp;
        bool isActive;
        bool exists;
    }

    event MaturityAdded(uint256 timestamp, uint256 maturityId);
    event MaxMaturityIdUpdated(uint256 firstActiveMaturityId, uint256 newMaxMaturityId);
    event ActiveWindowShifted(uint256 newFirstActiveMaturityId);
    event MaturityPeriodUpdated(uint256 newPeriod);

    /**
     * @notice Core configuration functions
     */

    // /**
    //  * @notice Returns the first active maturity boundary
    //  * @return The first active maturity boundary
    //  */
    // function firstActiveBoundary() external view returns (uint256);

    /**
     * @notice Updates the maximum valid maturity ID, extending the range of available maturities
     * @param newMaxMaturity The new maximum maturity ID to set
     * @dev This function is used to extend the range of valid maturityIds
     */
    function updateMaxMaturityId(uint256 newMaxMaturity) external;

    /**
     * @notice Maturity ID and timestamp mapping functions
     */

    /**
     * @notice Returns the maturity ID for a given timestamp
     * @param timestamp The timestamp to query
     * @return The corresponding maturity ID (0 if not a valid maturity)
     */
    function getMaturityIdForMaturityTimestamp(uint256 timestamp) external view returns (uint256);

    /**
     * @notice Returns the maturity timestamp for a given maturity ID
     * @param maturityId The ID of the maturity to query
     * @return The corresponding maturity timestamp
     */
    function getMaturityTimestamp(uint256 maturityId) external view returns (uint256);

    /**
     * @notice Active maturity window functions
     */

    /**
     * @notice Returns the current active maturity ID (first maturity in the active window)
     * @return The first active maturity ID in the current window
     */
    function getFirstActiveMaturityId() external view returns (uint256);

    /**
     * @notice Returns all current active maturity IDs
     * @return An array of active maturity IDs in the current window
     */
    function getActiveMaturities() external view returns (uint256[] memory);

    /**
     * @notice Returns the start and end maturity IDs for the current active maturity range
     * @return firstActiveMaturityId The first maturity ID in the active range
     * @return lastActiveMaturityId The last maturity ID in the active range
     */
    function getActiveMaturityRange()
        external
        view
        returns (uint256 firstActiveMaturityId, uint256 lastActiveMaturityId);

    /**
     * @notice Returns the active maturity range for a specific reference timestamp
     * @dev Use this when calculating yields for historical midnight indices to avoid
     *      timing issues where block.timestamp has already crossed a maturity boundary
     * @param referenceTimestamp The timestamp to calculate the active range for
     * @return firstActiveMaturityId The first maturity ID in the active range
     * @return lastActiveMaturityId The last maturity ID in the active range
     */
    function getYieldBearingMaturityRangeForTimestamp(uint256 referenceTimestamp)
        external
        view
        returns (uint256 firstActiveMaturityId, uint256 lastActiveMaturityId);

    /**
     * @notice Returns the effective start timestamp of the current maturity window
     * @return The timestamp marking the start of the current active window
     */
    function currentWindowStartTimestamp() external view returns (uint256);

    /**
     * @notice Validation and information functions
     */

    /**
     * @notice Checks if a given timestamp is a valid maturity timestamp
     * @param providedTimestamp The timestamp to verify
     * @return True if the timestamp is valid, false otherwise
     */
    function isValidMaturityTimeStamp(uint256 providedTimestamp) external view returns (bool);

    /**
     * @notice Returns comprehensive information about a specific maturity
     * @param maturityId The ID of the maturity to query
     * @return A MaturityInfo struct containing timestamp, active status, and existence
     */
    function getMaturityInfo(uint256 maturityId) external view returns (MaturityInfo memory);

    /**
     * @notice Returns the maximum maturity ID
     * @return The maximum maturity ID
     */
    function getMaxMaturityId() external view returns (uint256);

    /**
     * @notice Checks if a given maturity ID is valid
     * @param maturityId The ID of the maturity to verify
     * @return True if the maturity ID is valid, false otherwise
     */
    function isValidMaturityId(uint256 maturityId) external view returns (bool);

    /**
     * @notice Returns the number of maturities
     * @return The number of maturities
     */
    function getNumMaturities() external view returns (uint256);

    /**
     * @notice Returns the maturity period
     * @return The maturity period
     */
    function getMaturityPeriod() external view returns (uint256);

    //* MIDNIGHT *//

    /**
     * @notice Returns the midnight timestamp for a given midnight index
     * @param midnightIndex The index to query
     * @return The corresponding midnight timestamp
     */
    function getMidnightTimestampForIndex(uint256 midnightIndex) external view returns (uint256);

    /**
     * @notice Returns the midnight index for a given timestamp
     * @param timestamp The timestamp to query
     * @return The corresponding midnight index
     */
    function getMidnightIndexForTimestamp(uint256 timestamp) external view returns (uint256);

    /**
     * @notice Returns the midnight index for a given maturity ID
     * @param maturityId The ID of the maturity to query
     * @return The corresponding midnight index
     */
    function getMidnightIndexForMaturityId(uint256 maturityId) external view returns (uint256);

    /**
     * @notice Returns the adjacent midnight information for a given timestamp
     * @param currentTimestamp The timestamp to query
     * @return currentMidnightIndex The current midnight index
     * @return currentMidnightTimestamp The current midnight timestamp
     * @return nextMidnightIndex The next midnight index
     * @return nextMidnightTimestamp The next midnight timestamp
     */
    function getAdjacentMidnightInfo(uint256 currentTimestamp)
        external
        view
        returns (
            uint256 currentMidnightIndex,
            uint256 currentMidnightTimestamp,
            uint256 nextMidnightIndex,
            uint256 nextMidnightTimestamp
        );

    // Upgradeability

    /**
     * @notice Initializes the maturity manager
     * @param _initialStartTimestamp The initial start timestamp
     * @param _accessManager The access manager address
     */
    function initialize(uint256 _initialStartTimestamp, address _accessManager) external;

    /**
     * @notice Returns the maturity start timestamp for a given maturity ID
     * @param maturityId The ID of the maturity to query
     * @return startTimestamp The corresponding maturity start timestamp
     */
    function getMaturityStartTimestamp(uint256 maturityId) external view returns (uint256 startTimestamp);

    /**
     * @notice Returns the maturity timeframe for a given maturity ID
     * @param maturityId The ID of the maturity to query
     * @return startTimestamp The corresponding maturity timeframe
     * @return endTimestamp The corresponding maturity timeframe
     */
    function getMaturityTimeframe(uint256 maturityId)
        external
        view
        returns (uint256 startTimestamp, uint256 endTimestamp);
}
