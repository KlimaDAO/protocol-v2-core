// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IKvcmLPStakingFacet
 * @dev Interface for LP token staking operations. Handles pair registration and delegates staking operations
 * to pair-specific facets.
 */
interface IKvcmLPStakingFacet {
    enum LpStakeStatus {
        OPEN,
        REDEEMED
    }

    struct LpStakeInfo {
        uint256 lpStakeId; // Legacy: Kept for events and backwards compatibility
        address lpToken; // LP token address
        uint256 principal; // Amount of LP tokens staked
        uint256 maturityId; // Maturity bucket ID
        uint256 maturityTimestamp; // Timestamp when lpStake can be unstaked
        uint256 startTimestamp; // Timestamp when lpStake was created
        address stakeOwner; // Owner of the lpStake
        LpStakeStatus status; // Track if the stake is open or redeemed
    }

    // =============================================================================
    // EVENTS
    // =============================================================================

    event PairModuleRegistered(address indexed lpToken, address moduleAddress);
    event PairModuleUpdated(address indexed lpToken, address newModuleAddress);
    event PairModuleRemoved(address indexed lpToken);

    // LP Staking Events
    event LpStaked(
        address indexed lpAddress, uint256 indexed maturityId, address indexed user, uint256 amount, uint256 lpStakeId
    );

    event LpStakeUpdated(
        address indexed lpAddress,
        uint256 indexed maturityId,
        address indexed user,
        uint256 amountAdded,
        uint256 lpStakeId
    );

    event LpStakeUnstaked(
        address indexed lpAddress,
        uint256 indexed maturityId,
        address indexed user,
        uint256 amountRedeemed,
        uint256 lpStakeId
    );

    // =============================================================================
    // EXTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @dev Register a new LP pair facet
     * @param moduleAddress Address of the module implementation
     * @param token0 First token in the pair (must match pool's token0)
     * @param token1 Second token in the pair (must match pool's token1)
     * @param lpToken LP token address
     */
    function registerPairModule(address moduleAddress, address token0, address token1, address lpToken) external;

    /**
     * @dev Update an existing LP pair facet
     * @param lpToken Unique identifier for the pair
     * @param newModuleAddress New module implementation address
     */
    function updatePairModule(address lpToken, address newModuleAddress) external;

    /**
     * @dev Remove a LP pair facet
     * @param lpToken Unique identifier for the pair
     */
    function removePairModule(address lpToken) external;

    /**
     * @dev Get information about a registered pair
     * @param lpToken Unique identifier for the pair
     * @return module Module address
     * @return token0 First token address
     * @return token1 Second token address
     * @return isActive Whether the pair is active
     */
    function getLPStakingPairInfo(address lpToken)
        external
        view
        returns (address module, address token0, address token1, bool isActive);

    /**
     * @dev Stake LP tokens for a given pair for the caller
     * @param lpToken LP token address
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     * @param amount Amount of LP tokens to stake
     * @return lpStakeId Legacy stake identifier for events
     */
    function stakeLP(address lpToken, uint256 maturityId, uint256 amount) external returns (uint256 lpStakeId);

    function stakeLPFor(address lpToken, uint256 maturityId, address user, uint256 amount)
        external
        returns (uint256 lpStakeId);

    /**
     * @dev Stake LP tokens for a given pair with permit
     * @param lpToken Unique identifier for the pair
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     * @param amount Amount of LP tokens to stake
     * @param deadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     * @return lpStakeId Unique stake identifier
     */
    function stakeLPWithPermit(
        address lpToken,
        uint256 maturityId,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 lpStakeId);

    /**
     * @dev Stake LP tokens for a given pair for a specified user with permit
     * @param lpToken Unique identifier for the pair
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     * @param amount Amount of LP tokens to stake
     * @param user Address to stake for
     * @param deadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     * @return lpStakeId Unique stake identifier
     */
    function stakeLPForWithPermit(
        address lpToken,
        uint256 maturityId,
        address user,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 lpStakeId);

    /**
     * @dev Unstake LP tokens for a given pair
     * @param lpToken Unique identifier for the pair
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     */
    function unstakeLP(address lpToken, uint256 maturityId) external;

    /**
     * @dev Get a specific LP stake by composite key
     * @param lpToken LP token address
     * @param maturityId MaturityManager maturity ID
     * @param user Address of the stake owner
     * @return stake The stake information
     */
    function getLpStakeInfo(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (LpStakeInfo memory);

    /**
     * @dev Get total LP tokens staked for a specific pair and maturity
     * @param lpToken LP token address
     * @param maturityId MaturityManager maturity ID
     * @return lpStaked Total amount staked
     */
    function getTotalLPStaked(address lpToken, uint256 maturityId) external view returns (uint256 lpStaked);

    /**
     * @dev Get total LP tokens staked for a specific pair and maturity range
     * @param lpToken LP token address
     * @param fromId MaturityManager maturity ID
     * @param toId MaturityManager maturity ID
     * @return totalLPsStaked Total amount staked for each maturity in the range
     */
    function getTotalLPsStakedInRange(address lpToken, uint256 fromId, uint256 toId)
        external
        view
        returns (uint256[] memory totalLPsStaked);
}
