// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IProtocolSupplyOracle {
    struct ProtocolSupplyOracleConfig {
        address kvcmToken;
        address k2Token;
        address rewardManager;
        address rewardsEscrow;
        address stakingManager;
        address accessManager;
        address aam;
    }

    event SupplyOracleConfigurationUpdated(ProtocolSupplyOracleConfig newConfig, ProtocolSupplyOracleConfig prevConfig);

    function initialize(ProtocolSupplyOracleConfig memory config) external;

    // /**
    //  * @notice: This function will return the supply of Kvcm
    //  */
    function getKvcmSupply() external view returns (uint256);

    // /**
    //  * @notice: This function will return the supply of K2
    //  */
    function getK2Supply() external view returns (uint256);

    function setConfiguration(ProtocolSupplyOracleConfig memory config) external;

    function getConfiguration() external view returns (ProtocolSupplyOracleConfig memory config);
}

interface IProtocolSupplyOracleV2 is IProtocolSupplyOracle {
    event TreasuryUpdated(address treasury);

    function setTreasury(address treasury) external;
    function getTreasury() external view returns (address);
}
