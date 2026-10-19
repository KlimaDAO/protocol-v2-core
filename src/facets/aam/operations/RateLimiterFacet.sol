// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// interfaces
import {IRateLimiterFacet} from "src/interfaces/AssetManager/IRateLimiterFacet.sol";
import {RateLimiterLib} from "src/libraries/aam/RateLimiterLib.sol";
// libraries
import {AssetManagerStorage} from "src/libraries/storage/AssetManagerStorage.sol";
import {Errors} from "src/libraries/Errors.sol";
import {LibDiamond} from "src/libraries/LibDiamond.sol";
import {Constants} from "src/libraries/Constants.sol";

contract RateLimiterFacet is IRateLimiterFacet {
    modifier onlyStakingManager() {
        if (msg.sender != AssetManagerStorage.configLayout().aamConfig.stakingManager) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    function initialize() external onlyOwner {
        _initRateLimits();
    }

    function _initRateLimits() internal onlyOwner {
        if (
            AssetManagerStorage.classQuoterLayout().defaultKVCMRate != 0
                || AssetManagerStorage.classQuoterLayout().defaultK2Rate != 0
        ) {
            revert Errors.RateLimitsAlreadyInitialized();
        }

        AssetManagerStorage.classQuoterLayout().defaultKVCMRate = Constants.DEFAULT_KVCM_RATE;
        AssetManagerStorage.classQuoterLayout().defaultK2Rate = Constants.DEFAULT_K2_RATE;

        // store the zero allocation scenario fallback snapshot value for k2
        AssetManagerStorage.classQuoterLayout().fallbackK2AllocationSnapshotValue = Constants.WAD;
    }

    /* --- Default rate limits --- */
    function setDefaultKVCMRate(uint64 _defaultKVCMRate) external onlyOwner {
        RateLimiterLib.setDefaultKVCMRate(_defaultKVCMRate);
        emit DefaultKVCMRateUpdated(_defaultKVCMRate);
    }

    function setDefaultK2Rate(uint64 _defaultK2Rate) external onlyOwner {
        RateLimiterLib.setDefaultK2Rate(_defaultK2Rate);
        emit DefaultK2RateUpdated(_defaultK2Rate);
    }

    /* --- Minimum effective allocations --- */
    function setClassMinEffectiveAllocation(address carbonClass, uint128 kvcm, uint128 k2) external onlyOwner {
        RateLimiterLib.setClassMinEffectiveAllocation(carbonClass, kvcm, k2);
        emit ClassMinEffectiveAllocationUpdated(carbonClass, kvcm, k2);
    }

    function getMinEffectiveAllocation(address carbonClass) external view returns (uint256 kvcm, uint256 k2) {
        return (
            RateLimiterLib.getMinEffectiveKvcmAllocation(carbonClass),
            RateLimiterLib.getMinEffectiveK2Allocation(carbonClass)
        );
    }

    function getKvcmAllocationDefaultRate() external view returns (uint64) {
        return RateLimiterLib.getKvcmAllocationDefaultRate();
    }

    function getK2AllocationDefaultRate() external view returns (uint64) {
        return RateLimiterLib.getK2AllocationDefaultRate();
    }

    /* Staking Manager Only (external) */

    function updateKvcmAllocationRateLimiter(
        address carbonClass,
        uint256 preTxnKvcmAllocationValue,
        uint256 amountIfZeroPreTxn
    ) external onlyStakingManager {
        RateLimiterLib.updateKvcmAllocationRateLimiter(carbonClass, preTxnKvcmAllocationValue, amountIfZeroPreTxn);
    }

    function updateK2AllocationRateLimiter(
        address carbonClass,
        uint256 preTxnK2AllocationValue,
        uint256 amountIfZeroPreTxn
    ) external onlyStakingManager {
        RateLimiterLib.updateK2AllocationRateLimiter(carbonClass, preTxnK2AllocationValue, amountIfZeroPreTxn);
    }

    function getRateLimiterSnapshotValues(address carbonClass)
        external
        view
        returns (RateLimiterLib.RateLimiterSnapshotValues memory)
    {
        return RateLimiterLib.getRateLimiterSnapshotValues(carbonClass);
    }
}
