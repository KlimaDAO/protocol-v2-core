// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IKvcmStakingFacet {
    enum KvcmLockStatus {
        OPEN,
        REDEEMED,
        PARTIAL_CLAIMED
    }

    struct KvcmLockInfo {
        uint256 lockId;
        uint256 principal;
        uint256 priceAllocations;
        uint128 maturityTimestamp;
        uint128 startTimestamp;
        uint128 maturityId;
        address lockOwner;
        KvcmLockStatus status;
    }

    event KvcmLocked(
        address indexed user, uint256 indexed lockId, uint256 amount, uint256 startTimestamp, uint256 maturityId
    );
    event KvcmLockTransferred(address indexed from, address indexed to, uint256 indexed lockId, uint256 maturityId);
    event KvcmUnlocked(
        address indexed user,
        uint256 indexed lockId,
        uint256 indexed maturityId,
        uint256 amount,
        uint256 yield,
        uint256 carbonIncentives
    );
    event KvcmLockAllocated(
        address indexed user, uint256 indexed maturityId, address indexed carbonClass, uint256 amount
    );
    event KvcmLockDeallocated(
        address indexed user, uint256 indexed maturityId, address indexed carbonClass, uint256 amount
    );
    event KvcmLockReallocated(
        address indexed user,
        uint256 maturityId,
        address indexed fromCarbonClass,
        address indexed toCarbonClass,
        uint256 amount
    );

    event KvcmPartialClaim(
        address indexed user, uint256 indexed lockId, uint256 indexed maturityId, uint256 amount, uint256 yield
    );
    /**
     * @notice Lock KVCM tokens for the caller with a specified maturity
     * @dev Creates a new Kvcm lock NFT and transfers KVCM tokens from the caller
     * @param amount The amount of KVCM tokens to lock
     * @param maturityId The maturity ID that determines when the lock can be redeemed
     * @return lockId The unique identifier of the created lock
     */

    function lockKvcm(uint256 amount, uint128 maturityId) external returns (uint256 lockId);

    /**
     * @notice Lock KVCM tokens on behalf of another user with a specified maturity
     * @dev Creates a new Kvcm lock NFT owned by the specified user, but pays from the caller
     * @param amount The amount of KVCM tokens to lock
     * @param maturityId The maturity ID that determines when the lock can be redeemed
     * @param to The address that will own the created lock
     * @return lockId The unique identifier of the created lock
     */
    function lockKvcmFor(uint256 amount, uint128 maturityId, address to) external returns (uint256 lockId);

    /**
     * @notice Lock KVCM tokens using a permit signature for gasless approval
     * @dev Creates a new Kvcm lock NFT using ERC20 permit to avoid separate approval transaction
     * @param amount The amount of KVCM tokens to lock
     * @param maturityId The maturity ID that determines when the lock can be redeemed
     * @param deadline The deadline timestamp for the permit signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     * @return lockId The unique identifier of the created lock
     */
    function lockKvcmWithPermit(uint256 amount, uint128 maturityId, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        returns (uint256 lockId);

    /**
     * @notice Lock KVCM tokens on behalf of another user using a permit signature
     * @dev Creates a new Kvcm lock NFT owned by the specified user using ERC20 permit
     * @param amount The amount of KVCM tokens to lock
     * @param maturityId The maturity ID that determines when the lock can be redeemed
     * @param to The address that will own the created lock
     * @param deadline The deadline timestamp for the permit signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     * @return lockId The unique identifier of the created lock
     */
    function lockKvcmForWithPermit(
        uint256 amount,
        uint128 maturityId,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 lockId);

    /**
     * @notice Redeem a matured Kvcm lock and receive the principal amount
     * @dev Burns the lock NFT and transfers KVCM tokens to the caller
     * @param lockId The unique identifier of the lock to redeem
     */
    function unlockKvcm(uint256 lockId) external returns (uint256 principal, uint256 accruedYield);

    /**
     * @notice Redeem a matured Kvcm lock and send the principal to a specified address
     * @dev Burns the lock NFT and transfers KVCM tokens to the specified recipient
     * @param lockId The unique identifier of the lock to redeem
     * @param to The address to receive the redeemed KVCM tokens
     * @return principal KVCM principal transferred to `to`
     * @return accruedYield KVCM yield transferred to `to` by the reward manager for this unlock step
     */
    function unlockKvcmTo(uint256 lockId, address to) external returns (uint256 principal, uint256 accruedYield);

    /**
     * @notice Claim remaining yield for a partially claimed KVCM lock
     * @dev Only callable when lock status is PARTIAL_CLAIMED and by the lock owner
     * @param lockId The unique identifier of the lock to claim remaining yield for
     */
    function claimRemainingKvcmYield(uint256 lockId) external;

    /**
     * @notice Claim remaining yield for a partially claimed KVCM lock to a specified address
     * @dev Only callable when lock status is PARTIAL_CLAIMED and by the lock owner
     * @param lockId The unique identifier of the lock to claim remaining yield for
     * @param to The address to receive the remaining yield
     */
    function claimRemainingKvcmYieldTo(uint256 lockId, address to) external;

    /**
     * @notice Get detailed information about a specific Kvcm lock
     * @dev Returns the complete lock information including ownership, amounts, and status
     * @param lockId The unique identifier of the lock to query
     * @return Lock information struct containing all lock details
     */
    function getKvcmLockInfo(uint256 lockId) external view returns (KvcmLockInfo memory);

    function isKvcmLockMatured(uint256 lockId) external view returns (bool);

    function isKvcmLockOwned(uint256 lockId, address user) external view returns (bool);

    /**
     * @notice Allocate a portion of a Kvcm lock to a specific carbon class
     * @dev Moves allocation from unallocated to a specific carbon class for carbon pricing
     * @param lockId The unique identifier of the lock to allocate
     * @param carbonClass The carbon class to allocate the lock to
     * @param amount The amount to allocate to the carbon class
     */
    function allocateKvcm(uint256 lockId, address carbonClass, uint256 amount) external;

    /**
     * @notice Deallocate a portion of a Kvcm lock from a specific carbon class
     * @dev Moves allocation from a specific carbon class back to unallocated
     * @param lockId The unique identifier of the lock to deallocate
     * @param carbonClass The carbon class to deallocate the lock from
     * @param amount The amount to deallocate from the carbon class
     */
    function deallocateKvcm(uint256 lockId, address carbonClass, uint256 amount) external;

    /**
     * @notice Relocate a portion of a Kvcm lock allocation between carbon classes
     * @dev Moves allocation from one carbon class to another in a single transaction
     * @param lockId The unique identifier of the lock to relocate allocation for
     * @param fromCarbonClass The carbon class to relocate the lock allocation from
     * @param toCarbonClass The carbon class to relocate the lock allocation to
     * @param amount The amount to relocate between carbon classes
     */
    function reallocateKvcm(uint256 lockId, address fromCarbonClass, address toCarbonClass, uint256 amount) external;

    /**
     * @notice Cleans up all KVCM allocations for an expired maturity
     * @dev Removes all carbon class allocations from the maturity and updates global totals
     * @param maturityId The expired maturity ID to clean up
     */
    function cleanUpAllocationsForMaturity(uint256 maturityId) external;

    /**
     * @notice Get the total amount of KVCM tokens locked for a specific maturityId
     * @dev Returns the sum of all KVCM tokens locked for the specified maturityId
     * @param maturityId The maturity ID to query
     * @return The total amount of KVCM tokens locked for the maturityId
     */
    function getKvcmLockedForMaturity(uint128 maturityId) external view returns (uint256);

    /**
     * @notice Get the total amount of KVCM tokens locked for a range of maturityIds
     * @dev Returns the sum of all KVCM tokens locked for the specified range of maturityIds
     * @param firstMaturityId The first maturity ID to query
     * @param lastMaturityId The last maturity ID to query
     * @return maturityTotalLocked The total amount of KVCM tokens locked for the range of maturityIds
     * @return totalLocked The total amount of KVCM tokens locked for the range of maturityIds
     */
    function getKvcmLockedForMaturityRange(uint128 firstMaturityId, uint128 lastMaturityId)
        external
        view
        returns (uint256[] memory maturityTotalLocked, uint256 totalLocked);

    // function claimKvcmIncentives(uint256 amount) external;
    // function claimCarbonIncentives(uint256 amount) external;

    /**
     * @notice Get the total amount of KVCM tokens locked
     * @dev Returns the sum of all KVCM tokens locked
     * @return The total amount of KVCM tokens locked
     */
    function getTotalKvcmLocked() external view returns (uint256);

    /**
     * @notice Get the total KVCM allocated to a specific carbon class
     * @param carbonClass The carbon class address to query
     * @return The total KVCM amount allocated to the carbon class
     */
    function getKvcmAllocatedForCarbonClass(address carbonClass) external view returns (uint256);

    /**
     * @notice Get KVCM allocations for a list of carbon classes in a single call
     * @param carbonClasses Array of carbon class addresses to query
     * @return allocations Array of KVCM allocation amounts, one per carbon class
     */
    function getKvcmAllocationsForClasses(address[] calldata carbonClasses)
        external
        view
        returns (uint256[] memory allocations);
}
