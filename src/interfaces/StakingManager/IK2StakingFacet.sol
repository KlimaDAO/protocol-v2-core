// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

interface IK2StakingFacet {
    event K2Locked(address indexed user, uint256 amount, uint256 targetUnlock, uint256 lockId);
    event K2UnlockRequested(address indexed user, uint256 amount, uint256 claimTimestamp);
    event K2Claimed(address indexed user, uint256 amount);
    event K2Allocated(address indexed user, uint256 amount, address carbonClass);
    event K2Deallocated(address indexed user, uint256 amount, address carbonClass);
    event K2Reallocated(address indexed user, uint256 amount, address fromCarbonClass, address toCarbonClass);

    enum K2LockStatus {
        INACTIVE,
        LOCKED, // no active unlock request
        UNLOCK_REQUESTED
    }

    /**
     * @notice Escrowed principal info
     * @param amount The amount of principal that is escrowed
     * @param unlockTimestamp The timestamp at which the principal can be unlocked
     */
    struct EscrowedPrincipalInfo {
        uint128 amount;
        uint128 unlockTimestamp;
    }

    /**
     * @notice K2 lock info
     * @param initialized Whether the lock is initialized
     * @param lockId The lock ID
     * @param unlockedPrincipal The amount of principal that is unlocked
     * @param escrowedPrincipalInfo The escrowed principal info
     * @param claimEscrow The amount of principal that is claimed
     * @param startTimestamp The timestamp at which the lock started
     * @param claimTimestamp The timestamp at which the principal can be claimed
     */
    struct K2LockInfo {
        bool initialized;
        uint256 lockId;
        uint256 unlockedPrincipal;
        EscrowedPrincipalInfo[2] escrowedPrincipalInfo;
        uint256 claimEscrow;
        uint128 startTimestamp;
        uint128 claimTimestamp;
        uint256 totalAllocated;
        EnumerableMap.AddressToUintMap allocations;
        K2LockStatus status;
    }

    struct AllocationInfo {
        address carbonClass;
        uint256 amount;
    }

    struct K2LockView {
        uint256 unlockedPrincipal;
        uint256 escrowedPrincipal;
        uint256 claimEscrow;
        uint256 startTimestamp;
        uint256 claimTimestamp;
        uint256 totalAllocated;
        K2LockStatus status;
    }

    /**
     * @notice Get the K2 lock info for a user
     * @param user The address of the user to get the lock info for
     * @return lock The K2 lock info
     * @return allocations The allocations for the user
     */
    function getK2LockInfo(address user)
        external
        view
        returns (K2LockView memory lock, AllocationInfo[] memory allocations);

    /**
     * @notice Get the raw K2 lock info for a user
     * @param user The address of the user to get the lock info for
     * @return lockId The lock ID
     * @return unlockedPrincipal The amount of K2 tokens unlocked
     * @return escrowedPrincipalInfo The escrowed principal info
     * @return claimEscrow The amount of K2 tokens claimed
     * @return startTimestamp The start timestamp
     * @return claimTimestamp The claim timestamp
     * @return totalAllocated The total amount of K2 tokens allocated
     * @return status The status of the lock
     */
    function getRawK2LockInfo(address user)
        external
        view
        returns (
            uint256 lockId,
            uint256 unlockedPrincipal,
            EscrowedPrincipalInfo[2] memory escrowedPrincipalInfo,
            uint256 claimEscrow,
            uint128 startTimestamp,
            uint128 claimTimestamp,
            uint256 totalAllocated,
            K2LockStatus status
        );

    /**
     * @notice Lock K2 tokens for the caller
     * @param amount The amount of K2 tokens to lock
     */
    function lockK2(uint256 amount) external;

    /**
     * @notice Lock K2 tokens for a user
     * @param amount The amount of K2 tokens to lock
     * @param user_ The address of the user to lock for
     */
    function lockK2For(uint256 amount, address user_) external;

    /**
     * @notice Lock K2 tokens for the caller with permit
     * @param amount The amount of K2 tokens to lock
     * @param deadline The deadline for the permit
     * @param v The v parameter of the permit
     * @param r The r parameter of the permit
     * @param s The s parameter of the permit
     */
    function lockK2WithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice Lock K2 tokens for a user with permit
     * @param amount The amount of K2 tokens to lock
     * @param user_ The address of the user to lock for
     * @param deadline The deadline for the permit
     * @param v The v parameter of the permit
     * @param r The r parameter of the permit
     * @param s The s parameter of the permit
     */
    function lockK2ForWithPermit(uint256 amount, address user_, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /**
     * @notice Unlock K2 tokens for the caller
     * @param amount The amount of K2 tokens to unlock
     */
    function unlockK2(uint256 amount) external;

    /**
     * @notice Claim K2 tokens for the caller
     */
    function claimK2() external returns (uint256 claimAmount);

    /**
     * @notice Claim K2 tokens for a user
     * @param user_ The address of the user to claim for
     */
    function claimK2For(address user_) external returns (uint256 claimAmount);

    /**
     * @notice Allocate K2 tokens to a carbon class
     * @param amount The amount of K2 tokens to allocate
     * @param carbonClass_ The carbon class to allocate to
     */
    function allocateK2(uint256 amount, address carbonClass_) external;

    /**
     * @notice Deallocate K2 tokens from a carbon class
     * @param amount The amount of K2 tokens to deallocate
     * @param carbonClass_ The carbon class to deallocate from
     */
    function deallocateK2(uint256 amount, address carbonClass_) external;

    /**
     * @notice Reallocate K2 tokens from one carbon class to another
     * @param amount The amount of K2 tokens to reallocate
     * @param fromCarbonClass_ The carbon class to reallocate from
     * @param toCarbonClass_ The carbon class to reallocate to
     */
    function reallocateK2(uint256 amount, address fromCarbonClass_, address toCarbonClass_) external;

    /**
     * @notice Batch allocate K2 tokens to multiple carbon classes
     * @param allocations_ The allocations to batch allocate
     */
    function batchAllocateK2(AllocationInfo[] calldata allocations_) external;

    /**
     * @notice Batch deallocate K2 tokens from multiple carbon classes
     * @param allocations_ The allocations to batch deallocate
     */
    function batchDeallocateK2(AllocationInfo[] calldata allocations_) external;

    /**
     * @notice Get the amount of K2 tokens allocated to a carbon class
     * @param carbonClass The carbon class to get the allocated amount for
     * @return The amount of K2 tokens allocated to the carbon class
     */
    function getK2AllocatedForCarbonClass(address carbonClass) external view returns (uint256);

    function getTotalK2Allocations() external view returns (uint256);
    /**
     * @notice Get the current locked and unlocked principal for a user
     * @param user The address of the user to get the principal for
     * @return unlockedPrincipal The amount of K2 tokens unlocked
     * @return escrowedPrincipal The amount of K2 tokens escrowed
     */
    function getK2LockedPrincipalLockStatus(address user)
        external
        view
        returns (uint256 unlockedPrincipal, uint256 escrowedPrincipal);

    /**
     * @notice Get the total amount of K2 tokens locked for a user, both unlocked and locked
     * @param user The address of the user to get the locked amount for
     * @return The total amount of K2 tokens locked for the user
     */
    function getK2LockedTotalPrincipal(address user) external view returns (uint256);

    /**
     * @notice Get the total amount of K2 tokens staked
     * @return The total amount of K2 tokens staked
     */
    function getTotalK2Staked() external view returns (uint256);

    /**
     * @notice Get K2 allocations for a list of carbon classes in a single call
     * @param carbonClasses Array of carbon class addresses to query
     * @return allocations Array of K2 allocation amounts, one per carbon class
     */
    function getK2AllocationsForClasses(address[] calldata carbonClasses)
        external
        view
        returns (uint256[] memory allocations);
}
