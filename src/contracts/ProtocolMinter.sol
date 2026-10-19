// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IProtocolMinter.sol";
import "../interfaces/IRewardsEscrow.sol";
import "../interfaces/tokens/IKVCM.sol";
import "../libraries/Errors.sol";
import "../libraries/CarbonSystemRoleLib.sol";

/**
 * @title ProtocolMinter
 * @dev UUPS upgradeable contract for minting KVCM tokens and managing K2 transfers
 * Uses direct IAccessManager interaction for role-based access control
 *
 * @notice This contract serves as the central minting authority for the protocol,
 *         allowing controlled minting of KVCM tokens to authorized contracts
 *         and managing K2 token transfers from the rewards escrow
 */
contract ProtocolMinter is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    IProtocolMinter,
    ReentrancyGuardTransientUpgradeable
{
    using SafeERC20 for IERC20;

    // ============== Storage ==============

    /// @dev Main configuration storage
    ProtocolMinterConfig private _config;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    // ============== Modifiers ==============

    /// @dev Ensures only system admin can call the function
    modifier onlySystemAdmin() {
        address accessManager = _config.protocolAccessManager;
        (bool hasAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (!hasAdminRole) {
            revert Errors.UnauthorizedSystemAdmin();
        }
        _;
    }

    /// @dev Ensures only the RewardManager can call the function
    modifier onlyRewardManager() {
        if (msg.sender != _config.rewardManager) {
            revert Errors.UnauthorizedRewardManager();
        }
        _;
    }

    /// @dev Ensures only the AAM can call the function
    modifier onlyAAM() {
        if (msg.sender != _config.aam) {
            revert Errors.UnauthorizedAAM();
        }
        _;
    }

    /// @dev Ensures the provided address is not zero
    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) {
            revert Errors.ZeroAddressNotAllowed();
        }
        _;
    }

    /// @dev Ensures the provided amount is not zero
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        _;
    }

    // ============== Constructor ==============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============== Initialization ==============

    /**
     * @dev Initialize the ProtocolMinter contract
     * @param accessManager The Protocol Access Manager contract address
     * @param kvcmToken The KVCM token contract address
     * @param k2Token The K2 token contract address
     * @param rewardManager The RewardManager contract address
     * @param rewardsEscrow The RewardsEscrow contract address
     * @param aam The Asset Manager contract address
     */
    function initialize(
        address accessManager,
        address kvcmToken,
        address k2Token,
        address rewardManager,
        address rewardsEscrow,
        address aam
    )
        external
        initializer
        nonZeroAddress(accessManager)
        nonZeroAddress(kvcmToken)
        nonZeroAddress(k2Token)
        nonZeroAddress(rewardManager)
        nonZeroAddress(rewardsEscrow)
        nonZeroAddress(aam)
    {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuardTransient_init();

        _config.protocolAccessManager = accessManager;
        _config.kvcmToken = kvcmToken;
        _config.k2Token = k2Token;
        _config.rewardManager = rewardManager;
        _config.rewardsEscrow = rewardsEscrow;
        _config.aam = aam;

        emit ConfigurationUpdated(kvcmToken, k2Token, rewardManager, rewardsEscrow, aam);
    }

    // ============== External Functions ==============

    /**
     * @notice Mint KVCM tokens to the RewardManager
     * @dev Only callable by the RewardManager contract
     * @param amount The amount of KVCM to mint
     */
    function mintKvcmToRewardManager(uint256 amount)
        external
        nonReentrant
        onlyRewardManager
        nonZeroAmount(amount)
        whenNotPaused
    {
        _mintKVCM(_config.rewardManager, amount);
        emit KVCMMintedToRewardManager(_config.rewardManager, amount);
    }

    /**
     * @notice Transfer K2 tokens from RewardsEscrow to RewardManager
     * @dev Calls transferToRewardManagers on the RewardsEscrow contract
     * @param amount The amount of K2 to transfer
     */
    function transferK2ToRewardManager(uint256 amount)
        external
        nonReentrant
        onlyRewardManager
        nonZeroAmount(amount)
        whenNotPaused
    {
        // Call the RewardsEscrow contract to transfer K2 to RewardManager
        IRewardsEscrow(_config.rewardsEscrow).transferK2ToRewardManager(amount);
        emit K2TransferredToRewardManager(amount);
    }

    /**
     * @notice Mint KVCM tokens to the AAM
     * @dev Only callable by the AAM contract
     * @param amount The amount of KVCM to mint
     */
    function mintKvcmToAAM(uint256 amount) external onlyAAM nonZeroAmount(amount) whenNotPaused nonReentrant {
        _mintKVCM(_config.aam, amount);
        emit KVCMMintedToAAM(_config.aam, amount);
    }

    // ============== Configuration Functions ==============

    /**
     * @notice Update the protocol configuration
     * @dev Only callable by system admin
     * @param kvcmToken The new KVCM token address
     * @param k2Token The new K2 token address
     * @param rewardManager The new RewardManager address
     * @param rewardsEscrow The new RewardsEscrow address
     * @param aam The new AAM address
     */
    function updateConfiguration(
        address kvcmToken,
        address k2Token,
        address rewardManager,
        address rewardsEscrow,
        address aam
    )
        external
        onlySystemAdmin
        whenNotPaused
        nonZeroAddress(kvcmToken)
        nonZeroAddress(k2Token)
        nonZeroAddress(rewardManager)
        nonZeroAddress(rewardsEscrow)
        nonZeroAddress(aam)
    {
        _config.kvcmToken = kvcmToken;
        _config.k2Token = k2Token;
        _config.rewardManager = rewardManager;
        _config.rewardsEscrow = rewardsEscrow;
        _config.aam = aam;

        emit ConfigurationUpdated(kvcmToken, k2Token, rewardManager, rewardsEscrow, aam);
    }

    // ============== Pausability Functions ==============

    /**
     * @dev Pause the contract
     * Only callable by system admin
     */
    function pause() external onlySystemAdmin {
        _pause();
    }

    /**
     * @dev Unpause the contract
     * Only callable by system admin
     */
    function unpause() external onlySystemAdmin {
        _unpause();
    }

    // ============== View Functions ==============

    /**
     * @notice Get the current protocol configuration
     * @return config The current configuration struct
     */
    function getConfiguration() external view returns (ProtocolMinterConfig memory config) {
        return _config;
    }

    /**
     * @notice Get the KVCM token address
     * @return The KVCM token contract address
     */
    function getKvcmToken() external view returns (address) {
        return _config.kvcmToken;
    }

    /**
     * @notice Get the K2 token address
     * @return The K2 token contract address
     */
    function getK2Token() external view returns (address) {
        return _config.k2Token;
    }

    /**
     * @notice Get the RewardManager address
     * @return The RewardManager contract address
     */
    function getRewardManager() external view returns (address) {
        return _config.rewardManager;
    }

    /**
     * @notice Get the RewardsEscrow address
     * @return The RewardsEscrow contract address
     */
    function getRewardsEscrow() external view returns (address) {
        return _config.rewardsEscrow;
    }

    /**
     * @notice Get the AAM address
     * @return The AAM contract address
     */
    function getAAM() external view returns (address) {
        return _config.aam;
    }

    /**
     * @notice Get the ProtocolAccessManager address
     * @return The ProtocolAccessManager contract address
     */
    function getProtocolAccessManager() external view returns (address) {
        return _config.protocolAccessManager;
    }

    // ============== Internal Functions ==============

    /**
     * @dev Internal function to mint KVCM tokens
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function _mintKVCM(address to, uint256 amount) internal {
        IKVCM(_config.kvcmToken).mint(to, amount);
    }

    /**
     * @dev Authorization for UUPS upgrades
     * Only system admin can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlySystemAdmin {}
}
