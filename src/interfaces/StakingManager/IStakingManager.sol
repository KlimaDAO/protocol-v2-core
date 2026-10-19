// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IStakingManager {
    struct ClassAllocations {
        address carbonClass;
        uint256 kvcmAllocation;
        uint256 k2Allocation;
    }
}
