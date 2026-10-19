// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagerStorage} from "src/libraries/storage/AssetManagerStorage.sol";
import {RateLimiterSeedLib} from "src/common/upgradeInitializers/RateLimiterSeedLib.sol";
import {IStakingManagerViewFacet} from "src/interfaces/StakingManager/IStakingManagerViewFacet.sol";

/**
 * @title AllocationRateLimiterSeedInit
 * @notice One-shot diamond initializer that seeds uninitialized allocation rate limiters from each
 *         class's current on-chain allocation.
 *
 * @dev Rate-limiter state is keyed by quoter address. Replacing a class's quoter via
 *      removeQuoter + registerQuoter leaves the new quoter's limiter at 0/0, which makes the class
 *      quote a zero price until its next stake tx re-seeds it. This initializer repairs those classes in a one-time op.
 */
contract AllocationRateLimiterSeedInit {
    event AllocationRateLimitersSeeded(address indexed carbonClass, uint256 kvcmAllocation, uint256 k2Allocation);

    function seedClasses(address[] calldata carbonClasses) external {
        address stakingManager = AssetManagerStorage.configLayout().aamConfig.stakingManager;

        for (uint256 i = 0; i < carbonClasses.length; i++) {
            IStakingManagerViewFacet.ClassAllocations memory allocations =
                IStakingManagerViewFacet(stakingManager).getAllocationsForClass(carbonClasses[i]);

            RateLimiterSeedLib.seedAllocationRateLimiters(
                carbonClasses[i], allocations.kvcmAllocation, allocations.k2Allocation
            );

            emit AllocationRateLimitersSeeded(carbonClasses[i], allocations.kvcmAllocation, allocations.k2Allocation);
        }
    }
}
