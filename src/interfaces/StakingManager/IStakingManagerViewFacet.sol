// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IStakingManager} from "./IStakingManager.sol";

interface IStakingManagerViewFacet is IStakingManager {
    function getAllocationsForClass(address carbonClass) external view returns (ClassAllocations memory);
    function getK2Locked() external view returns (uint256);
    function getKvcmLocked() external view returns (uint256);
}
