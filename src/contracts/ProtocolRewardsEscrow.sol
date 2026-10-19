// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import "../interfaces/IProtocolRewardsEscrow.sol";
import "../libraries/CarbonSystemRoleLib.sol";
import "../libraries/Errors.sol";

contract ProtocolRewardsEscrow is
    Initializable,
    UUPSUpgradeable,
    IProtocolRewardsEscrow,
    ReentrancyGuardTransientUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    EscrowConfig private config;
    EscrowBalance private escrowBalance;
    EscrowLimits private escrowLimits;
    uint256[50] private __gap;

    // =============================================================
    // Modifiers
    // =============================================================

    modifier onlyProtocolMinter() {
        (bool hasProtocolMinterRole,) =
            IAccessManager(config.accessManager).hasRole(CarbonSystemRoleLib.PROTOCOL_REWARDS_MINTER, msg.sender);
        if (!hasProtocolMinterRole) revert Errors.NotProtocolMinter();
        _;
    }

    modifier onlySystemAdmin() {
        address accessManager = config.accessManager;
        (bool hasAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);
        if (!hasAdminRole) revert Errors.NotSystemAdmin();
        _;
    }

    modifier onlyRewardManager() {
        if (msg.sender != config.rewardManager) {
            revert Errors.NotRewardManager();
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

    // =============================================================
    // Constructor & Initializer
    // =============================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param config_ The initial configuration for the escrow contract.
     */
    function initialize(EscrowConfig memory config_) external initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuardTransient_init();
        config = config_;
    }

    // =============================================================
    // External Functions
    // =============================================================

    /**
     * @notice Escrows K2 rewards. Only addresses with ProtocolMinter Role can call this function.
     * @param amount The amount of K2 to escrow.
     */
    function escrowK2Rewards(uint256 amount)
        external
        onlyProtocolMinter
        whenNotPaused
        nonZeroAmount(amount)
        nonReentrant
    {
        if (escrowBalance.k2RewardsEscrowed + amount > escrowLimits.maxK2EscrowAmount) {
            revert Errors.InvalidK2EscrowAmount(amount, escrowLimits.maxK2EscrowAmount);
        }

        escrowBalance.k2RewardsEscrowed += amount;
        IERC20(config.k2Token).safeTransferFrom(msg.sender, address(this), amount);
        emit K2RewardsEscrowed(amount);
    }

    /**
     * @notice Transfers K2 rewards to the Treasury.
     * @dev This function can only be called by a system admin.
     * @param totalK2YieldForTreasury The amount of K2 to transfer.
     */
    function transferK2ToTreasury(uint256 totalK2YieldForTreasury)
        external
        onlyRewardManager
        whenNotPaused
        nonReentrant
    {
        if (escrowBalance.k2RewardsEscrowed < totalK2YieldForTreasury) {
            revert Errors.InsufficientK2RewardsEscrowed(escrowBalance.k2RewardsEscrowed, totalK2YieldForTreasury);
        }

        escrowBalance.k2RewardsEscrowed -= totalK2YieldForTreasury;
        IERC20(config.k2Token).safeTransfer(config.treasury, totalK2YieldForTreasury);
        emit K2RewardsTransferredToTreasury(totalK2YieldForTreasury);
    }

    /**
     * @notice Transfers K2 rewards to the Rewards Manager.
     * @dev This function can only be called by the Reward Manager.
     * @param totalK2YieldForRewardManager The amount of K2 to transfer.
     */
    function transferK2ToRewardManager(uint256 totalK2YieldForRewardManager)
        external
        onlyRewardManager
        whenNotPaused
        nonReentrant
    {
        if (escrowBalance.k2RewardsEscrowed < totalK2YieldForRewardManager) {
            revert Errors.InsufficientK2RewardsEscrowed(escrowBalance.k2RewardsEscrowed, totalK2YieldForRewardManager);
        }
        escrowBalance.k2RewardsEscrowed -= totalK2YieldForRewardManager;
        IERC20(config.k2Token).safeTransfer(config.rewardManager, totalK2YieldForRewardManager);
        emit K2RewardsTransferredToRewardManager(totalK2YieldForRewardManager);
    }

    /**
     * @notice Sets the configuration for the escrow contract.
     * @param newConfig The new configuration.
     */
    function setConfiguration(EscrowConfig memory newConfig) external onlySystemAdmin whenNotPaused {
        _validateConfig(newConfig);
        EscrowConfig memory oldConfig = config;
        config = newConfig;
        emit ConfigurationUpdated(oldConfig, newConfig);
    }

    /**
     * @notice Sets the escrow limits for the contract.
     * @dev The max K2 escrow amount must be greater than zero.
     * @param newLimits The new escrow limits.
     */
    function setEscrowLimits(EscrowLimits memory newLimits)
        external
        onlySystemAdmin
        whenNotPaused
        nonZeroAmount(newLimits.maxK2EscrowAmount)
    {
        escrowLimits = newLimits;
        emit EscrowLimitsUpdated(newLimits);
    }

    /**
     * @notice Pauses the contract.
     * @dev This function can only be called by a system admin.
     */
    function pause() external onlySystemAdmin whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev This function can only be called by a system admin.
     */
    function unpause() external onlySystemAdmin whenPaused {
        _unpause();
    }

    // =============================================================
    // View Functions
    // =============================================================

    /**
     * @notice Gets the current escrow balance.
     * @return balance_ The current escrow balance.
     */
    function getEscrowBalance() external view returns (EscrowBalance memory balance_) {
        return escrowBalance;
    }

    /**
     * @notice Gets the current configuration.
     * @return config_ The current escrow configuration.
     */
    function getEscrowConfig() external view returns (EscrowConfig memory config_) {
        return config;
    }

    /**
     * @notice Gets the current escrow limits.
     * @return limits_ The current escrow limits.
     */
    function getEscrowLimits() external view returns (EscrowLimits memory limits_) {
        return escrowLimits;
    }

    function getConfiguration() external view returns (EscrowConfig memory config_) {
        return config;
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    function _validateConfig(EscrowConfig memory config_) internal pure {
        if (config_.k2Token == address(0)) revert Errors.InvalidK2TokenAddress();
        if (config_.kvcmToken == address(0)) revert Errors.InvalidKVCMTokenAddress();
        if (config_.treasury == address(0)) revert Errors.InvalidTreasuryAddress();
        if (config_.rewardManager == address(0)) revert Errors.InvalidRewardManagerAddress();
        if (config_.accessManager == address(0)) revert Errors.InvalidAccessManagerAddress();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlySystemAdmin {}
}
