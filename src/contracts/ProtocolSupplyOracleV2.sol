// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/Errors.sol";
import "../libraries/CarbonSystemRoleLib.sol";

import "../interfaces/IProtocolSupplyOracle.sol";
import "../interfaces/IProtocolRewardsEscrow.sol";

/**
 * @title Protocol Supply Oracle V2
 * @notice This contract is responsible for providing the effective supply of KVCM and k2 tokens.
 * @dev The effective supply is calculated by subtracting locked tokens from the total supply.
 */
contract ProtocolSupplyOracleV2 is
    Initializable,
    UUPSUpgradeable,
    IProtocolSupplyOracleV2,
    ReentrancyGuardTransientUpgradeable
{
    /**
     * @notice Configuration for the ProtocolSupplyOracle.
     */
    ProtocolSupplyOracleConfig private config;
    address private treasury;

    /**
     * @dev Throws if the caller is not the system admin.
     */
    modifier onlySystemAdmin() {
        address accessManager = config.accessManager;
        (bool hasAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);
        if (!hasAdminRole) revert Errors.NotSystemAdmin();
        _;
    }

    /**
     * @dev Disables the initializer for the implementation contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param config_ The initial configuration for the oracle.
     */
    function initialize(ProtocolSupplyOracleConfig memory config_) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuardTransient_init();

        config = config_;
    }

    /**
     * @notice Sets the configuration for the oracle.
     * @param config_ The new configuration.
     */
    function setConfiguration(ProtocolSupplyOracleConfig memory config_) external onlySystemAdmin nonReentrant {
        _validateConfig(config_);
        ProtocolSupplyOracleConfig memory oldConfig = config;
        config = config_;
        emit SupplyOracleConfigurationUpdated(config, oldConfig);
    }

    /**
     * @notice Gets the current configuration of the oracle.
     * @return The current configuration.
     */
    function getConfiguration() external view returns (ProtocolSupplyOracleConfig memory) {
        return config;
    }

    /**
     * @notice Gets the effective supply of KVCM.
     * @return effectiveSupply The effective supply of KVCM.
     */
    function getKvcmSupply() external view returns (uint256 effectiveSupply) {
        effectiveSupply = IERC20(config.kvcmToken).totalSupply();
    }

    /**
     * @notice Gets the effective supply of k2.
     * @return effectiveSupply The effective supply of k2.
     */
    function getK2Supply() external view returns (uint256 effectiveSupply) {
        effectiveSupply = IERC20(config.k2Token).totalSupply();
        effectiveSupply -= IProtocolRewardsEscrow(config.rewardsEscrow).getEscrowBalance().k2RewardsEscrowed;
        effectiveSupply -= IERC20(config.k2Token).balanceOf(treasury);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation contract.
     * @notice This function is internal and can only be called by the system admin.
     */
    function _authorizeUpgrade(address) internal override onlySystemAdmin {}

    /**
     * @dev Validates the provided configuration.
     * @param config_ The configuration to validate.
     */
    function _validateConfig(ProtocolSupplyOracleConfig memory config_) internal pure {
        if (config_.kvcmToken == address(0)) revert Errors.InvalidKVCMTokenAddress();
        if (config_.k2Token == address(0)) revert Errors.InvalidK2TokenAddress();
        if (config_.accessManager == address(0)) revert Errors.InvalidAccessManagerAddress();
        if (config_.stakingManager == address(0)) revert Errors.InvalidStakingManagerAddress();
    }

    function setTreasury(address treasury_) external onlySystemAdmin nonReentrant {
        if (treasury_ == address(0)) revert Errors.InvalidTreasuryAddress();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function getTreasury() external view returns (address) {
        return treasury;
    }

    uint256[49] private __gap;
}
