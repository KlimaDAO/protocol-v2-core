// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IProtocolMinter
 * @dev Interface for the ProtocolMinter contract
 */
interface IProtocolMinter {
    // ============== Structs ==============

    /// @dev Storage struct for protocol configuration
    struct ProtocolMinterConfig {
        address kvcmToken; // The KVCM token contract
        address k2Token; // The K2 token contract
        address rewardManager; // The RewardManager contract
        address rewardsEscrow; // The RewardsEscrow contract
        address aam; // The Asset Manager contract
        address protocolAccessManager; // The Protocol Access Manager
    }

    // ============== Events ==============

    /// @notice Emitted when KVCM is minted to the RewardManager
    /// @param recipient The address that received the minted KVCM
    /// @param amount The amount of KVCM minted
    event KVCMMintedToRewardManager(address indexed recipient, uint256 amount);

    /// @notice Emitted when KVCM is minted to the AAM
    /// @param recipient The address that received the minted KVCM
    /// @param amount The amount of KVCM minted
    event KVCMMintedToAAM(address indexed recipient, uint256 amount);

    /// @notice Emitted when K2 is transferred to the RewardManager
    /// @param amount The amount of K2 transferred
    event K2TransferredToRewardManager(uint256 amount);

    /// @notice Emitted when the protocol configuration is updated
    /// @param kvcmToken The new KVCM token address
    /// @param k2Token The new K2 token address
    /// @param rewardManager The new RewardManager address
    /// @param rewardsEscrow The new RewardsEscrow address
    /// @param aam The new AAM address
    event ConfigurationUpdated(
        address kvcmToken, address k2Token, address rewardManager, address rewardsEscrow, address aam
    );

    // ============== External Functions ==============

    /**
     * @notice Mint KVCM tokens to the RewardManager
     * @dev Only callable by the RewardManager contract
     * @param amount The amount of KVCM to mint
     */
    function mintKvcmToRewardManager(uint256 amount) external;

    /**
     * @notice Transfer K2 tokens from RewardsEscrow to RewardManager
     * @dev Calls transferToRewardManagers on the RewardsEscrow contract
     * @param amount The amount of K2 to transfer
     */
    function transferK2ToRewardManager(uint256 amount) external;

    /**
     * @notice Mint KVCM tokens to the AAM
     * @dev Only callable by the AAM contract
     * @param amount The amount of KVCM to mint
     */
    function mintKvcmToAAM(uint256 amount) external;

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
    ) external;

    /**
     * @dev Pause the contract
     * Only callable by system admin
     */
    function pause() external;

    /**
     * @dev Unpause the contract
     * Only callable by system admin
     */
    function unpause() external;

    /**
     * @notice Get the current protocol configuration
     * @return config The current configuration struct
     */
    function getConfiguration() external view returns (ProtocolMinterConfig memory config);

    /**
     * @notice Get the KVCM token address
     * @return The KVCM token contract address
     */
    function getKvcmToken() external view returns (address);

    /**
     * @notice Get the K2 token address
     * @return The K2 token contract address
     */
    function getK2Token() external view returns (address);

    /**
     * @notice Get the RewardManager address
     * @return The RewardManager contract address
     */
    function getRewardManager() external view returns (address);

    /**
     * @notice Get the RewardsEscrow address
     * @return The RewardsEscrow contract address
     */
    function getRewardsEscrow() external view returns (address);

    /**
     * @notice Get the AAM address
     * @return The AAM contract address
     */
    function getAAM() external view returns (address);

    /**
     * @notice Get the ProtocolAccessManager address
     * @return The ProtocolAccessManager contract address
     */
    function getProtocolAccessManager() external view returns (address);
}
