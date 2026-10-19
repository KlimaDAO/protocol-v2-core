// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin-upgradeable/contracts/access/manager/AccessManagedUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "../interfaces/ICarbonVaultFactory.sol";
import "../interfaces/ICarbonClassVault.sol";
import "../libraries/CarbonSystemRoleLib.sol";
import "../libraries/Errors.sol";

/**
 * @title CarbonVaultFactory
 * @dev Factory contract for deploying and managing CarbonClassVault proxies
 * Uses AccessManaged for role-based access control with IAccessManager
 * Implements UUPS upgradeable pattern and pausable functionality
 *
 * @notice This contract uses the UUPS upgradeable pattern and should be deployed behind a proxy.
 *         Do not use the constructor for initialization, use the initialize function instead.
 */
contract CarbonVaultFactory is
    Initializable,
    AccessManagedUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ICarbonVaultFactory
{
    // ============== State Variables ==============
    // Implementation registry
    mapping(uint256 => address) private _implementations;
    uint256[] private _availableVersions;
    uint256 private _latestVersion;

    // Vault tracking
    address[] private _deployedVaults;
    mapping(address => VaultInfo) private _vaultInfo;

    // ============== Events ==============
    // No events defined here, using the ones from the interface

    // ============== Modifiers ==============
    /**
     * @dev Modifier to check if the sender has the system admin role
     */
    modifier onlySystemAdmin() {
        IAccessManager accessManager = IAccessManager(authority());
        (bool hasAdminRole,) = accessManager.hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);
        if (!hasAdminRole) revert Errors.NotSystemAdmin();
        _;
    }

    /**
     * @dev Modifier to check if the sender has the vault manager role
     */
    modifier onlyVaultManager() {
        IAccessManager accessManager = IAccessManager(authority());
        (bool hasManagerRole,) = accessManager.hasRole(CarbonSystemRoleLib.CARBON_VAULT_MANAGER, msg.sender);
        if (!hasManagerRole) revert Errors.NotCarbonVaultManager();
        _;
    }

    /**
     * @dev Modifier to check if contract is not paused
     */
    modifier notPaused() {
        if (paused()) revert Errors.ContractPaused();
        _;
    }

    // ============== Constructor & Initializer ==============
    /**
     * @dev Constructor
     * Empty constructor for upgradeable contracts. No initialization happens here.
     * All initialization happens in the initialize function.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the factory with the access manager
     * @param accessManager Address of the access manager contract
     */
    function initialize(address accessManager) external initializer {
        if (accessManager == address(0)) revert Errors.ZeroAddressNotAllowed();

        __AccessManaged_init(accessManager);
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    // ============== Implementation Management Functions ==============
    /**
     * @dev Registers a new implementation for a specific version
     * @param version The version number for the implementation
     * @param implementation The address of the implementation contract
     */
    function registerImplementation(uint256 version, address implementation) external onlySystemAdmin notPaused {
        if (version == 0) revert Errors.InvalidVersion();
        if (implementation == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (_implementations[version] != address(0)) revert Errors.VersionAlreadyRegistered();

        _implementations[version] = implementation;
        _availableVersions.push(version);

        if (version > _latestVersion) {
            _latestVersion = version;
        }

        emit ImplementationRegistered(version, implementation);
    }

    /**
     * @dev Returns the implementation address for a specific version
     * @param version The version number to query
     * @return The implementation address
     */
    function getImplementationAddress(uint256 version) external view returns (address) {
        return _implementations[version];
    }

    /**
     * @dev Returns the latest registered version number
     * @return The latest version number
     */
    function getLatestVersion() external view returns (uint256) {
        return _latestVersion;
    }

    /**
     * @dev Returns all available version numbers
     * @return Array of available version numbers
     */
    function getAvailableVersions() external view returns (uint256[] memory) {
        return _availableVersions;
    }

    // ============== Vault Deployment Functions ==============
    /**
     * @dev Deploys a new CarbonClassVault proxy with the specified implementation version
     * @param params The initialization parameters for the vault
     * @param implementationVersion The version of implementation to use
     * @return vault The address of the deployed vault proxy
     */
    function deployVault(ICarbonClassVault.VaultConfigInitParams memory params, uint256 implementationVersion)
        external
        onlyVaultManager
        notPaused
        returns (address vault)
    {
        address implementation = _implementations[implementationVersion];
        if (implementation == address(0)) revert Errors.ImplementationNotRegistered();

        // Fix the encoding to match the actual struct layout
        bytes memory initData = abi.encodeWithSelector(ICarbonClassVault.initialize.selector, params);

        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);

        vault = address(proxy);

        // Record the deployed vault
        _deployedVaults.push(vault);
        _vaultInfo[vault] =
            VaultInfo({currentVersion: implementationVersion, deployedTimestamp: block.timestamp, isActive: true});

        emit VaultDeployed(vault, implementationVersion);
    }

    /**
     * @dev Returns all deployed vault addresses
     * @return Array of deployed vault addresses
     */
    function getDeployedVaults() external view returns (address[] memory) {
        return _deployedVaults;
    }

    /**
     * @dev Returns information about a specific vault
     * @param vault The address of the vault to query
     * @return VaultInfo struct with details about the vault
     */
    function getVaultInfo(address vault) external view returns (VaultInfo memory) {
        return _vaultInfo[vault];
    }

    // ============== Vault Upgrade Functions ==============
    /**
     * @dev Upgrades a vault to a new implementation version
     * @param vault The address of the vault to upgrade
     * @param targetVersion The version to upgrade to
     */
    function upgradeVault(address vault, uint256 targetVersion) external onlySystemAdmin notPaused {
        if (_vaultInfo[vault].currentVersion == 0) revert Errors.ClassVaultNotTracked();
        if (!_vaultInfo[vault].isActive) revert Errors.ClassVaultNotActive();

        address implementation = _implementations[targetVersion];
        if (implementation == address(0)) revert Errors.ImplementationNotRegistered();

        uint256 fromVersion = _vaultInfo[vault].currentVersion;

        // The vault uses UUPS pattern, so we need to call the upgradeTo function on the proxy
        ICarbonClassVault(vault).upgradeTo(implementation);

        // Update our tracking
        _vaultInfo[vault].currentVersion = targetVersion;

        emit VaultUpgraded(vault, fromVersion, targetVersion);
    }

    /**
     * @dev Sets the active status of a vault
     * @param vault The address of the vault
     * @param isActive Whether the vault should be active
     */
    function setVaultActive(address vault, bool isActive) external onlySystemAdmin notPaused {
        if (_vaultInfo[vault].currentVersion == 0) revert Errors.ClassVaultNotTracked();

        _vaultInfo[vault].isActive = isActive;

        emit VaultStatusChanged(vault, isActive);
    }

    // ============== Pausability Functions ==============
    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     * @return Whether the contract is paused
     */
    function paused() public view override(PausableUpgradeable, ICarbonVaultFactory) returns (bool) {
        return super.paused();
    }

    /**
     * @dev Pauses all operations on the factory
     * Only callable by system admin
     */
    function pause() external onlySystemAdmin {
        _pause();
    }

    /**
     * @dev Unpauses all operations on the factory
     * Only callable by system admin
     */
    function unpause() external onlySystemAdmin {
        _unpause();
    }

    // ============== Access Management Functions ==============
    /**
     * @dev Updates the access manager address
     * Only callable by system admin
     * @param newAccessManager The new access manager address
     */
    function updateAccessManager(address newAccessManager) external onlySystemAdmin {
        if (newAccessManager == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (newAccessManager.code.length == 0) revert Errors.NoCodeAtAddress(newAccessManager);
        _setAuthority(newAccessManager);
        emit AccessManagerUpdated(newAccessManager);
    }

    // ============== UUPS Upgrade Functions ==============
    /**
     * @dev Function that authorizes an upgrade to a new implementation.
     * Required by the UUPSUpgradeable module.
     * Only accounts with the system admin role can authorize upgrades.
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlySystemAdmin {}

    uint256[50] private __gap;
}
