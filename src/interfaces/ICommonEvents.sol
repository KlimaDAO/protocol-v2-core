// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICommonEvents {
    // contract updates
    event AccessManagerUpdated(address accessManager);
    event SystemPauseStatusChanged(bool isPaused);
    event KvcmTokenUpdated(address kvcm);
    event K2TokenUpdated(address k2);
    event RewardManagerUpdated(address rewardManager);
    event MaturityManagerUpdated(address maturityManager);
    event StakingManagerUpdated(address stakingManager);
    event CarbonLedgerUpdated(address carbonLedger);
    event AAMUpdated(address aam);
    event RiskyYieldTokenUpdated(address riskyYieldToken);
    event K2YieldTokenUpdated(address k2YieldToken);
    event RetirementAggregatorUpdated(address retirementAggregator);
    event YieldDistributionIntervalUpdated(uint128 yieldDistributionInterval);
    event ProtocolSupplyOracleUpdated(address protocolSupplyOracle);
    /**
     * @dev Emitted when tokens (dust) are recovered from the vault contract address
     */
    event DustRemoved(address indexed tokenAddress, address indexed to, uint256 amount, uint256 tokenId);
}
