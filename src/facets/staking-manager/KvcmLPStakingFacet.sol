// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../libraries/LibDiamond.sol";
import "../../libraries/storage/StakingManagerStorage.sol";
import "../../libraries/RevertHelper.sol";
import "../../libraries/Errors.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/StakingManager/IKvcmLPStakingFacet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ZkMeUtilsLib} from "./utils/zkMe.sol";
import "../../libraries/IntegrationErrors.sol";

/**
 * @title KvcmLPStakingFacet
 * @dev Main entry point for LP token staking operations. Handles pair registration and delegates staking operations
 * to pair-specific facets.
 */
contract KvcmLPStakingFacet is IKvcmLPStakingFacet {
    using SafeERC20 for IERC20;

    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) revert Errors.NotAuthorized();
        _;
    }

    modifier whenNotPaused() {
        if (
            StakingManagerStorage.managerPauseLayout().systemPaused
                || StakingManagerStorage.managerPauseLayout().lpStakingPaused
        ) {
            revert Errors.SystemPaused();
        }
        _;
    }

    modifier whenVerified(address user) {
        if (!ZkMeUtilsLib.hasApproved(user)) revert IntegrationErrors.ZkMeNotVerified(user);
        _;
    }

    // ============ EXTERNAL STATE-CHANGING FUNCTIONS ============

    /**
     * @dev Register a new LP pair facet
     * @param moduleAddress Address of the module implementation
     * @param token0 First token in the pair (must match pool's token0)
     * @param token1 Second token in the pair (must match pool's token1)
     * @param lpToken LP token address
     */
    function registerPairModule(address moduleAddress, address token0, address token1, address lpToken)
        external
        onlyOwner
    {
        if (moduleAddress == address(0)) revert Errors.ZeroAddress();
        if (lpToken == address(0)) revert Errors.ZeroAddress();

        // Validate token addresses against pool's actual tokens
        (address poolToken0, address poolToken1) = IPool(lpToken).tokens();
        if (token0 != poolToken0 || token1 != poolToken1) revert Errors.TokenMismatch();

        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        if (s.pairModules[lpToken] != address(0)) revert Errors.PairAlreadyRegistered();

        s.pairModules[lpToken] = moduleAddress;

        // Initialize pair fields
        s.pairs[lpToken].token0 = token0;
        s.pairs[lpToken].token1 = token1;
        s.pairs[lpToken].isActive = true;

        s.authorizedLPTokens[lpToken] = true;

        emit PairModuleRegistered(lpToken, moduleAddress);
    }

    /**
     * @dev Update an existing LP pair facet
     * @param lpToken Address of the LP token for the pair
     * @param newModuleAddress New module implementation address
     */
    function updatePairModule(address lpToken, address newModuleAddress) external onlyOwner {
        if (newModuleAddress == address(0)) revert Errors.ZeroAddress();

        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        if (s.pairModules[lpToken] == address(0)) revert Errors.InvalidPair(lpToken);

        s.pairModules[lpToken] = newModuleAddress;
        emit PairModuleUpdated(lpToken, newModuleAddress);
    }

    /**
     * @dev Remove a LP pair facet
     * @param lpToken Address of the LP token for the pair
     */
    function removePairModule(address lpToken) external onlyOwner {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        if (s.pairModules[lpToken] == address(0)) revert Errors.InvalidPair(lpToken);

        delete s.pairModules[lpToken];
        delete s.pairs[lpToken];
        s.authorizedLPTokens[lpToken] = false;

        emit PairModuleRemoved(lpToken);
    }

    /**
     * @dev Stake LP tokens for a given pair
     * @param lpToken Unique identifier for the pair
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     * @param amount Amount of LP tokens to stake
     * @return lpStakeId Unique stake identifier
     */
    function stakeLP(address lpToken, uint256 maturityId, uint256 amount)
        external
        whenNotPaused
        whenVerified(msg.sender)
        returns (uint256 lpStakeId)
    {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();

        // Get the pair-specific facet
        address facet = s.pairModules[lpToken];
        if (facet == address(0)) revert Errors.InvalidPair(lpToken);

        // Validate pair is active
        if (!s.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        // Delegate call to the appropriate pair facet
        (bool success, bytes memory returnData) =
            facet.delegatecall(abi.encodeWithSignature("stakeLP(address,uint256,uint256)", lpToken, maturityId, amount));

        if (!success) {
            RevertHelper.revertWithData(returnData);
        }
        lpStakeId = abi.decode(returnData, (uint256));
        return lpStakeId;
    }

    /**
     * @dev Stake LP tokens for a given pair for a specified user
     * @param lpToken Unique identifier for the pair
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     * @param user Address to stake for
     * @param amount Amount of LP tokens to stake
     * @return lpStakeId Unique stake identifier
     */
    function stakeLPFor(address lpToken, uint256 maturityId, address user, uint256 amount)
        external
        whenNotPaused
        whenVerified(user)
        returns (uint256 lpStakeId)
    {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();

        // Get the pair-specific facet
        address facet = s.pairModules[lpToken];
        if (facet == address(0)) revert Errors.InvalidPair(lpToken);

        // Validate pair is active
        if (!s.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        // Delegate call to the appropriate pair facet (module expects lpToken, user, maturityId, amount)
        (bool success, bytes memory returnData) = facet.delegatecall(
            abi.encodeWithSignature("stakeLPFor(address,address,uint256,uint256)", lpToken, user, maturityId, amount)
        );

        if (!success) {
            RevertHelper.revertWithData(returnData);
        }
        lpStakeId = abi.decode(returnData, (uint256));
        return lpStakeId;
    }

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
    ) external whenNotPaused whenVerified(msg.sender) returns (uint256 lpStakeId) {
        StakingManagerStorage.LPStakingLayout storage layout = StakingManagerStorage.lpStakingLayout();

        address facet = layout.pairModules[lpToken];
        if (facet == address(0)) revert Errors.InvalidPair(lpToken);
        if (!layout.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        (bool success, bytes memory returnData) = facet.delegatecall(
            abi.encodeWithSignature(
                "stakeLPWithPermit(address,uint256,uint256,uint256,uint8,bytes32,bytes32)",
                lpToken,
                maturityId,
                amount,
                deadline,
                v,
                r,
                s
            )
        );

        if (!success) {
            RevertHelper.revertWithData(returnData);
        }
        return abi.decode(returnData, (uint256));
    }

    /**
     * @dev Stake LP tokens for a given pair for a specified user with permit
     * @param lpToken Unique identifier for the pair
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     * @param user Address to stake for
     * @param amount Amount of LP tokens to stake
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
    ) external whenNotPaused whenVerified(user) returns (uint256 lpStakeId) {
        StakingManagerStorage.LPStakingLayout storage layout = StakingManagerStorage.lpStakingLayout();

        address facet = layout.pairModules[lpToken];
        if (facet == address(0)) revert Errors.InvalidPair(lpToken);
        if (!layout.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        (bool success, bytes memory returnData) = facet.delegatecall(
            abi.encodeWithSignature(
                "stakeLPForWithPermit(address,uint256,address,uint256,uint256,uint8,bytes32,bytes32)",
                lpToken,
                maturityId,
                user,
                amount,
                deadline,
                v,
                r,
                s
            )
        );

        if (!success) {
            RevertHelper.revertWithData(returnData);
        }
        return abi.decode(returnData, (uint256));
    }

    function unstakeLP(address lpToken, uint256 maturityId) external whenNotPaused {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();

        address facet = s.pairModules[lpToken];
        if (facet == address(0)) revert Errors.InvalidPair(lpToken);

        // Validate pair is active
        if (!s.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        // Delegate call to the appropriate pair facet
        (bool success, bytes memory result) =
            facet.delegatecall(abi.encodeWithSignature("unstakeLP(address,uint256)", lpToken, maturityId));

        if (!success) {
            RevertHelper.revertWithData(result);
        }
    }

    // ============ EXTERNAL VIEW FUNCTIONS ============

    /**
     * @dev Get information about a registered pair
     * @param lpToken Address of the LP token for the pair
     * @return facet Facet address
     * @return token0 First token address
     * @return token1 Second token address
     * @return isActive Whether the pair is active
     */
    function getLPStakingPairInfo(address lpToken)
        external
        view
        returns (address facet, address token0, address token1, bool isActive)
    {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        StakingManagerStorage.LPStakingPairInfo storage pair = s.pairs[lpToken];

        facet = s.pairModules[lpToken];
        token0 = pair.token0;
        token1 = pair.token1;
        isActive = pair.isActive;
    }

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
        returns (IKvcmLPStakingFacet.LpStakeInfo memory)
    {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        return s.userStakeMapping[lpToken][maturityId][user];
    }

    /**
     * @dev Get total LP tokens staked for a specific pair and maturity
     * @param lpToken LP token address
     * @param maturityId MaturityManager maturity ID
     * @return lpStaked Total amount staked
     */
    function getTotalLPStaked(address lpToken, uint256 maturityId) external view returns (uint256 lpStaked) {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        return s.pairMaturityTotalStaked[lpToken][maturityId];
    }

    /**
     * @dev Get the total amount of LP tokens staked for a given pair
     * @param lpToken Address of the LP token for the pair
     * @return totalStaked The total amount of LP tokens staked
     */
    function getPairTotalStaked(address lpToken) external view returns (uint256 totalStaked) {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        StakingManagerStorage.LPStakingPairInfo storage pair = s.pairs[lpToken];
        totalStaked = pair.totalStaked;
    }

    /**
     * @dev Get the total amount of LP tokens staked for a given pair and maturity
     * @param lpToken Address of the LP token for the pair
     * @param maturityId Maturity ID
     * @return totalStaked The total amount of LP tokens staked
     */
    function getPairMaturityTotalStaked(address lpToken, uint256 maturityId)
        external
        view
        returns (uint256 totalStaked)
    {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        totalStaked = s.pairMaturityTotalStaked[lpToken][maturityId];
    }

    /**
     * @dev Get total LP tokens staked for a range of maturity IDs
     * @param lpToken LP token address
     * @param fromId Starting maturity ID
     * @param toId Ending maturity ID
     * @return totalLPsStaked Array of total staked amounts for each maturity in the range
     */
    function getTotalLPsStakedInRange(address lpToken, uint256 fromId, uint256 toId)
        external
        view
        returns (uint256[] memory totalLPsStaked)
    {
        StakingManagerStorage.LPStakingLayout storage l = StakingManagerStorage.lpStakingLayout();

        if (fromId > toId) revert Errors.InvalidRange(fromId, toId);
        if (!l.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        uint256 rangeSize = toId - fromId + 1;
        // keeping batch size at 40.
        if (rangeSize > 40) revert Errors.RangeTooLarge(rangeSize);

        totalLPsStaked = new uint256[](rangeSize);

        uint256 arrayIndex = 0;
        for (uint256 maturityId = fromId; maturityId <= toId;) {
            totalLPsStaked[arrayIndex] = l.pairMaturityTotalStaked[lpToken][maturityId];
            unchecked {
                ++arrayIndex;
                ++maturityId;
            }
        }
    }
}
