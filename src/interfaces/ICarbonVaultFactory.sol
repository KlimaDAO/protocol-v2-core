// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./ICarbonClassVault.sol";
import "./ICommonEvents.sol";

/**
 * @title ICarbonVaultFactory
 * @dev Interface for the CarbonVaultFactory contract which manages deployment and upgrading of CarbonClassVault proxies
 */
interface ICarbonVaultFactory is ICommonEvents {
    /**
     * @dev Struct containing information about a deployed vault
     */
    struct VaultInfo {
        uint256 currentVersion;
        uint256 deployedTimestamp;
        bool isActive;
    }

    /**
     * @dev Initializes the factory with the access manager
     * @param accessManager Address of the access manager contract
     */
    function initialize(address accessManager) external;

    /**
     * @dev Registers a new implementation for a specific version
     * @param version The version number for the implementation
     * @param implementation The address of the implementation contract
     */
    function registerImplementation(uint256 version, address implementation) external;

    /**
     * @dev Returns the implementation address for a specific version
     * @param version The version number to query
     * @return The implementation address
     */
    function getImplementationAddress(uint256 version) external view returns (address);

    /**
     * @dev Returns the latest registered version number
     * @return The latest version number
     */
    function getLatestVersion() external view returns (uint256);

    /**
     * @dev Returns all available version numbers
     * @return Array of available version numbers
     */
    function getAvailableVersions() external view returns (uint256[] memory);

    /**
     * @dev Deploys a new CarbonClassVault proxy with the specified implementation version
     * @param params The initialization parameters for the vault
     * @param implementationVersion The version of implementation to use
     * @return vault The address of the deployed vault proxy
     */
    function deployVault(ICarbonClassVault.VaultConfigInitParams memory params, uint256 implementationVersion)
        external
        returns (address vault);

    /**
     * @dev Returns all deployed vault addresses
     * @return Array of deployed vault addresses
     */
    function getDeployedVaults() external view returns (address[] memory);

    /**
     * @dev Returns information about a specific vault
     * @param vault The address of the vault to query
     * @return VaultInfo struct with details about the vault
     */
    function getVaultInfo(address vault) external view returns (VaultInfo memory);

    /**
     * @dev Upgrades a vault to a new implementation version
     * @param vault The address of the vault to upgrade
     * @param targetVersion The version to upgrade to
     */
    function upgradeVault(address vault, uint256 targetVersion) external;

    /**
     * @dev Sets the active status of a vault
     * @param vault The address of the vault
     * @param isActive Whether the vault should be active
     */
    function setVaultActive(address vault, bool isActive) external;

    /**
     * @dev Pauses all operations on the factory
     */
    function pause() external;

    /**
     * @dev Unpauses all operations on the factory
     */
    function unpause() external;

    /**
     * @dev Updates the access manager address
     * @param newAccessManager The new access manager address
     */
    function updateAccessManager(address newAccessManager) external;

    /**
     * @dev Returns whether the contract is paused
     * @return True if the contract is paused, false otherwise
     */
    function paused() external view returns (bool);

    /**
     * @dev Emitted when a new implementation is registered
     */
    event ImplementationRegistered(uint256 indexed version, address indexed implementation);

    /**
     * @dev Emitted when a new vault is deployed
     */
    event VaultDeployed(address indexed vault, uint256 indexed version);

    /**
     * @dev Emitted when a vault is upgraded
     */
    event VaultUpgraded(address indexed vault, uint256 indexed fromVersion, uint256 indexed toVersion);

    /**
     * @dev Emitted when a vault's active status is changed
     */
    event VaultStatusChanged(address indexed vault, bool isActive);
}
