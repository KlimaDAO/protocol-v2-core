// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IQuoterManager
 * @dev Interface for managing class quoters
 */
interface IQuoterManager {
    event QuoterRegistered(address indexed quoterAddress, address indexed carbonClass);
    event QuoterUpdated(address indexed quoterAddress, address indexed carbonClass);
    event QuoterReplaced(
        address indexed oldQuoterAddress, address indexed newQuoterAddress, address indexed carbonClass
    );
    event QuoterDeactivated(address indexed quoterAddress);
    event QuoterActivated(address indexed quoterAddress);
    event QuoterRemoved(address indexed quoterAddress);
    /**
     * @dev Register a new quoter for a carbon class
     * @param quoterAddress The address of the quoter
     * @param carbonClass The carbon class the quoter supports
     * @param isActive Whether the quoter should be active immediately
     */

    function registerQuoter(address quoterAddress, address carbonClass, bool isActive) external;

    /**
     * @dev Update an existing quoter
     * @param quoterAddress The address of the quoter to update
     * @param carbonClass The carbon class the quoter supports
     * @param isActive Whether the quoter should be active
     */
    function updateQuoter(address quoterAddress, address carbonClass, bool isActive) external;

    /**
     * @dev Replace a class's quoter with a new quoter address, carrying rate-limiter state across
     * @param oldQuoter The current quoter address for the class
     * @param newQuoter The new quoter address to point the class at
     * @param isActive Whether the new quoter should be active immediately
     */
    function replaceQuoter(address oldQuoter, address newQuoter, bool isActive) external;

    /**
     * @dev Deactivate a quoter
     * @param quoterAddress The address of the quoter to deactivate
     */
    function deactivateQuoter(address quoterAddress) external;

    /**
     * @dev Activate a quoter
     * @param quoterAddress The address of the quoter to activate
     */
    function activateQuoter(address quoterAddress) external;

    /**
     * @dev Remove a quoter
     * @param quoterAddress The address of the quoter to remove
     */
    function removeQuoter(address quoterAddress) external;

    /**
     * @dev Get the quoter for a specific carbon class
     * @param carbonClass The carbon class to get the quoter for
     * @return The address of the quoter for the carbon class
     */
    function getQuoterForClass(address carbonClass) external view returns (address);

    /**
     * @dev Check if a quoter is active
     * @param quoterAddress The address of the quoter to check
     * @return Whether the quoter is active
     */
    function isQuoterActive(address quoterAddress) external view returns (bool);

    /**
     * @dev Get all registered quoters
     * @return An array of all registered quoter addresses
     */
    function getAllQuoters() external view returns (address[] memory);

    /**
     * @dev Get the carbon class supported by a quoter
     * @param quoterAddress The address of the quoter
     * @return The carbon class supported by the quoter
     */
    function getQuoterClass(address quoterAddress) external view returns (address);

    /**
     * @dev Check if a carbon class has a registered quoter
     * @param carbonClass The carbon class to check
     * @return Whether the carbon class has a registered quoter
     */
    function hasQuoterForClass(address carbonClass) external view returns (bool);

    /**
     * @dev Get all registered carbon class addresses
     * @return classes Array of carbon class addresses (one per registered quoter)
     */
    function getAllCarbonClasses() external view returns (address[] memory classes);
}
