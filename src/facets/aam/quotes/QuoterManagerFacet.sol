// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// lib
import "../../../libraries/LibDiamond.sol";

// storage
import {AssetManagerStorage} from "../../../libraries/storage/AssetManagerStorage.sol";

// interfaces
import {IQuoterManager} from "../../../interfaces/AssetManager/IQuoterManager.sol";
import {Errors} from "../../../libraries/Errors.sol";

/**
 * @title QuoterManagerFacet
 * @dev Facet for managing quoters for different carbon classes
 */
contract QuoterManagerFacet is IQuoterManager {
    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) revert Errors.NotAuthorized();
        _;
    }

    modifier whenNotPaused() {
        if (AssetManagerStorage.configLayout().systemPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }

    /**
     * @dev Register a new quoter for a carbon class
     * @param quoterAddress The address of the quoter
     * @param carbonClass The carbon class the quoter supports
     * @param isActive Whether the quoter should be active immediately
     */
    function registerQuoter(address quoterAddress, address carbonClass, bool isActive)
        external
        onlyOwner
        whenNotPaused
    {
        if (carbonClass == address(0)) revert Errors.ZeroAddress();
        if (quoterAddress == address(0)) revert Errors.ZeroAddress();

        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        // Get the current array of quoter addresses
        address[] storage quoterAddresses = classQuoterLayout.quoterAddresses;

        // Check if the quoter is already registered
        if (classQuoterLayout.quoters[quoterAddress].exists) {
            revert Errors.QuoterAlreadyRegistered(quoterAddress);
        }

        // Check if there's already a quoter for this carbon class
        if (classQuoterLayout.classToQuoter[carbonClass] != address(0)) {
            revert Errors.CarbonClassAlreadyRegistered(carbonClass);
        }

        // Add quoter address to array
        quoterAddresses.push(quoterAddress);

        // Store the carbon class data
        AssetManagerStorage.ClassQuoterData storage data = classQuoterLayout.quoters[quoterAddress];
        data.carbonClass = carbonClass;
        data.isActive = isActive;
        data.exists = true;
        data.index = quoterAddresses.length - 1;

        // Store the mapping from quoter to carbon class
        classQuoterLayout.quoterToClass[quoterAddress] = carbonClass;

        // Store the mapping from carbon class to quoter
        classQuoterLayout.classToQuoter[carbonClass] = quoterAddress;

        // Rate limiter left at zero; the first allocation snapshots the class's minimum effective allocation.

        emit QuoterRegistered(quoterAddress, carbonClass);
    }

    /**
     * @dev Update an existing quoter
     * @param quoterAddress The address of the quoter to update
     * @param carbonClass The carbon class the quoter supports
     * @param isActive Whether the quoter should be active
     */
    function updateQuoter(address quoterAddress, address carbonClass, bool isActive) external onlyOwner whenNotPaused {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        // Check if the quoter exists
        if (!classQuoterLayout.quoters[quoterAddress].exists) {
            revert Errors.QuoterNotFound(quoterAddress);
        }

        // Get the current carbon class
        address currentClass = classQuoterLayout.quoters[quoterAddress].carbonClass;

        // If the carbon class is different, update the mappings
        if (currentClass != carbonClass) {
            // Remove the old mapping
            classQuoterLayout.classToQuoter[currentClass] = address(0);

            // Check if there's already a quoter for this carbon class
            if (classQuoterLayout.classToQuoter[carbonClass] != address(0)) {
                revert Errors.CarbonClassAlreadyRegistered(carbonClass);
            }

            // Update the quoter data
            classQuoterLayout.quoters[quoterAddress].carbonClass = carbonClass;

            // Update the mappings
            classQuoterLayout.quoterToClass[quoterAddress] = carbonClass;
            classQuoterLayout.classToQuoter[carbonClass] = quoterAddress;
        }

        // Update the active status
        classQuoterLayout.quoters[quoterAddress].isActive = isActive;

        emit QuoterUpdated(quoterAddress, carbonClass);
    }

    /**
     * @dev Replace a class's quoter with a new quoter address, carrying the rate-limiter state across.
     *      Use this for quoter (implementation) upgrades instead of removeQuoter + registerQuoter:
     *      which will reset the rate limiter snapshot to 0, making the class quote a zero swap price until its next stake tx re-seeds the limiter.
     * @param oldQuoter The current quoter address for the class
     * @param newQuoter The new quoter address to point the class at
     * @param isActive Whether the new quoter should be active immediately
     */
    function replaceQuoter(address oldQuoter, address newQuoter, bool isActive) external onlyOwner whenNotPaused {
        if (newQuoter == address(0)) revert Errors.ZeroAddress();

        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        // The old quoter must exist and the new one must not already be registered
        if (!classQuoterLayout.quoters[oldQuoter].exists) revert Errors.QuoterNotFound(oldQuoter);
        if (classQuoterLayout.quoters[newQuoter].exists) revert Errors.QuoterAlreadyRegistered(newQuoter);

        AssetManagerStorage.ClassQuoterData storage oldData = classQuoterLayout.quoters[oldQuoter];
        address carbonClass = oldData.carbonClass;

        // Carry state old -> new BEFORE deleting old. Copy metadata and, crucially, the rate limiters.
        AssetManagerStorage.ClassQuoterData storage newData = classQuoterLayout.quoters[newQuoter];
        newData.carbonClass = carbonClass;
        newData.isActive = isActive;
        newData.exists = true;
        newData.lastUpdateTimestamp = oldData.lastUpdateTimestamp;
        newData.liquidSupplyRateLimiter = oldData.liquidSupplyRateLimiter;
        newData.kvcmAllocationRateLimiter = oldData.kvcmAllocationRateLimiter;
        newData.k2AllocationRateLimiter = oldData.k2AllocationRateLimiter;

        // Reuse the old quoter's slot in the address array
        uint256 index = oldData.index;
        classQuoterLayout.quoterAddresses[index] = newQuoter;
        newData.index = index;

        // Repoint the class <-> quoter mappings to the new quoter
        classQuoterLayout.quoterToClass[newQuoter] = carbonClass;
        classQuoterLayout.classToQuoter[carbonClass] = newQuoter;

        // Remove the old quoter entry
        delete classQuoterLayout.quoterToClass[oldQuoter];
        delete classQuoterLayout.quoters[oldQuoter];

        emit QuoterReplaced(oldQuoter, newQuoter, carbonClass);
    }

    /**
     * @dev Deactivate a quoter
     * @param quoterAddress The address of the quoter to deactivate
     */
    function deactivateQuoter(address quoterAddress) external onlyOwner whenNotPaused {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        // Check if the quoter exists
        if (!classQuoterLayout.quoters[quoterAddress].exists) {
            revert Errors.QuoterNotFound(quoterAddress);
        }

        // Update the active status
        classQuoterLayout.quoters[quoterAddress].isActive = false;

        emit QuoterDeactivated(quoterAddress);
    }

    /**
     * @dev Activate a quoter
     * @param quoterAddress The address of the quoter to activate
     */
    function activateQuoter(address quoterAddress) external onlyOwner whenNotPaused {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        // Check if the quoter exists
        if (!classQuoterLayout.quoters[quoterAddress].exists) {
            revert Errors.QuoterNotFound(quoterAddress);
        }

        // Update the active status
        classQuoterLayout.quoters[quoterAddress].isActive = true;

        emit QuoterActivated(quoterAddress);
    }

    /**
     * @dev Remove a quoter
     * @param quoterAddress The address of the quoter to remove
     */
    function removeQuoter(address quoterAddress) external onlyOwner whenNotPaused {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        // Check if the quoter exists
        if (!classQuoterLayout.quoters[quoterAddress].exists) {
            revert Errors.QuoterNotFound(quoterAddress);
        }

        // Get the quoter's carbonClass before removal
        address carbonClass = classQuoterLayout.quoters[quoterAddress].carbonClass;

        // Get the current array of quoter addresses
        address[] storage quoterAddresses = classQuoterLayout.quoterAddresses;

        // Get the index of the quoter to remove
        uint256 indexToRemove = classQuoterLayout.quoters[quoterAddress].index;

        // Get the last quoter in the array
        address lastQuoter = quoterAddresses[quoterAddresses.length - 1];

        // Replace the quoter to remove with the last quoter in the array
        quoterAddresses[indexToRemove] = lastQuoter;

        // Update the index of the last quoter
        classQuoterLayout.quoters[lastQuoter].index = indexToRemove;

        // Remove the last quoter from the array
        quoterAddresses.pop();

        // Delete the quoter mappings
        delete classQuoterLayout.quoters[quoterAddress];
        delete classQuoterLayout.quoterToClass[quoterAddress];
        delete classQuoterLayout.classToQuoter[carbonClass];

        emit QuoterRemoved(quoterAddress);
    }

    /**
     * @dev Get the quoter for a specific carbon class
     * @param carbonClass The carbon class to get the quoter for
     * @return The address of the quoter for the carbon class
     */
    function getQuoterForClass(address carbonClass) external view returns (address) {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        address quoter = classQuoterLayout.classToQuoter[carbonClass];

        // Only return the quoter if it exists and is active
        if (quoter != address(0) && classQuoterLayout.quoters[quoter].isActive) {
            return quoter;
        }

        return address(0);
    }

    /**
     * @dev Check if a quoter is active
     * @param quoterAddress The address of the quoter to check
     * @return Whether the quoter is active
     */
    function isQuoterActive(address quoterAddress) external view returns (bool) {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        return classQuoterLayout.quoters[quoterAddress].isActive;
    }

    /**
     * @dev Get all registered quoters
     * @return An array of all registered quoter addresses
     */
    function getAllQuoters() external view returns (address[] memory) {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        return classQuoterLayout.quoterAddresses;
    }

    /**
     * @dev Get the carbon class supported by a quoter
     * @param quoterAddress The address of the quoter
     * @return The carbon class supported by the quoter
     */
    function getQuoterClass(address quoterAddress) external view returns (address) {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        return classQuoterLayout.quoterToClass[quoterAddress];
    }

    /**
     * @dev Check if a carbon class has a registered quoter
     * @param carbonClass The carbon class to check
     * @return Whether the carbon class has a registered quoter
     */
    function hasQuoterForClass(address carbonClass) external view returns (bool) {
        // Create a new ClassQuoterLayout for convenience
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        address quoter = classQuoterLayout.classToQuoter[carbonClass];
        return quoter != address(0);
    }

    /// @inheritdoc IQuoterManager
    function getAllCarbonClasses() external view returns (address[] memory classes) {
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();
        uint256 n = classQuoterLayout.quoterAddresses.length;
        classes = new address[](n);
        for (uint256 i; i < n; ++i) {
            classes[i] = classQuoterLayout.quoterToClass[classQuoterLayout.quoterAddresses[i]];
        }
    }
}
