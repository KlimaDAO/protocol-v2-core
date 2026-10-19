// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "libraries/storage/StakingManagerStorage.sol";
import "libraries/Errors.sol";
import "interfaces/IPool.sol";
import "interfaces/IMaturityManager.sol";
import "interfaces/StakingManager/IKvcmLPStakingFacet.sol";
import "interfaces/RewardManager/IRewardManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title BaseLPStakingFacet
 * @dev Abstract base contract for LP token staking facets
 */
abstract contract BaseLpStakingCore is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // Modifiers
    modifier whenNotPaused() {
        if (
            StakingManagerStorage.managerPauseLayout().systemPaused
                || StakingManagerStorage.managerPauseLayout().lpStakingPaused
        ) {
            revert Errors.SystemPaused();
        }
        _;
    }

    /**
     * @dev Stake LP tokens
     * @param lpToken Address of the LP token
     * @param amount Amount of LP tokens to stake
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     * @return lpStakeId Newly created stakeId
     */
    function stakeLP(address lpToken, uint256 maturityId, uint256 amount)
        external
        whenNotPaused
        returns (uint256 lpStakeId)
    {
        return _stakeLP(lpToken, maturityId, msg.sender, amount);
    }

    /**
     * @dev Stake LP tokens for a specified user
     * @param lpToken Address of the LP token
     * @param amount Amount of LP tokens to stake
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     * @param user Address to stake for
     * @return lpStakeId Newly created stakeId
     */
    function stakeLPFor(address lpToken, address user, uint256 maturityId, uint256 amount)
        external
        whenNotPaused
        returns (uint256 lpStakeId)
    {
        return _stakeLP(lpToken, maturityId, user, amount);
    }

    /**
     * @dev Stake LP tokens with permit
     * @param lpToken Address of the LP token
     * @param amount Amount of LP tokens to stake
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     * @param deadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     * @return lpStakeId Newly created stakeId
     */
    function stakeLPWithPermit(
        address lpToken,
        uint256 maturityId,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused returns (uint256 lpStakeId) {
        return _stakeLPWithPermit(lpToken, maturityId, msg.sender, amount, deadline, v, r, s);
    }

    /**
     * @dev Stake LP tokens for a specified user with permit
     * @param lpToken Address of the LP token
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     * @param user Address to stake for
     * @param amount Amount of LP tokens to stake
     * @param deadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     * @return lpStakeId Newly created stakeId
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
    ) external whenNotPaused returns (uint256 lpStakeId) {
        return _stakeLPWithPermit(lpToken, maturityId, user, amount, deadline, v, r, s);
    }

    /**
     * @dev Unstake an LP stake by its stakeId
     * @param lpToken Address of the LP token
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     */
    function unstakeLP(address lpToken, uint256 maturityId) external nonReentrant whenNotPaused {
        _unstakeLP(lpToken, maturityId, msg.sender);
    }

    /**
     * @dev Validate maturity ID and get timestamp through MaturityManager (for staking)
     * @param maturityId MaturityManager maturity ID (90-day buckets: 1, 2, 3...)
     * @return maturityTimestamp Aligned timestamp from MaturityManager
     */
    function _validateMaturityId(uint256 maturityId) internal view returns (uint256 maturityTimestamp) {
        StakingManagerStorage.StakingManagerConfigLayout storage config = StakingManagerStorage.configLayout();

        address maturityManager = config.maturityManager;
        if (maturityManager == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        IMaturityManager maturityManagerContract = IMaturityManager(maturityManager);

        // Validate that the maturityId is within active range
        (uint256 start, uint256 end) = maturityManagerContract.getActiveMaturityRange();
        if (maturityId < start || maturityId > end) {
            revert Errors.MaturityIdOutOfRange(maturityId, start, end);
        }

        // Get maturity timestamp from MaturityManager
        return maturityManagerContract.getMaturityTimestamp(maturityId);
    }

    /**
     * @dev Update global KVCM and K2 token totals
     * @param lpToken Address of the LP token
     * @param amount Amount of LP tokens being staked/unstaked
     * @param maturityId Maturity ID for maturity-specific totals
     * @param isStaking Whether tokens are being staked (true) or unstaked (false)
     * @dev Concrete function that calls virtual calculation functions
     */
    function _updateGlobalTotals(address lpToken, uint256 maturityId, uint256 amount, bool isStaking) internal {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();

        if (isStaking) {
            s.pairMaturityTotalStaked[lpToken][maturityId] += amount;
            s.pairs[lpToken].totalStaked += amount;
        } else {
            s.pairMaturityTotalStaked[lpToken][maturityId] -= amount;
            s.pairs[lpToken].totalStaked -= amount;
        }
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @dev Internal function to stake LP tokens with permit
     * @param lpToken Address of the LP token
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     * @param user Address to stake for
     * @param amount Amount of LP tokens to stake
     * @param deadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     * @return lpStakeId Newly created stakeId
     */
    function _stakeLPWithPermit(
        address lpToken,
        uint256 maturityId,
        address user,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (uint256 lpStakeId) {
        IERC20Permit(lpToken).permit(msg.sender, address(this), amount, deadline, v, r, s);
        return _stakeLP(lpToken, maturityId, user, amount);
    }

    function _getUserLPStake(address lpToken, uint256 maturityId, address user)
        internal
        view
        returns (IKvcmLPStakingFacet.LpStakeInfo storage)
    {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        IKvcmLPStakingFacet.LpStakeInfo storage stakeInfo = s.userStakeMapping[lpToken][maturityId][user];
        return stakeInfo;
    }

    function _getLatestLPStakeId(address lpToken) internal view returns (uint256) {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();

        (bool exists, uint256 latestLPStakeId) = s.lpToLatestStakeId.tryGet(lpToken);
        if (!exists) {
            return 0;
        }

        return latestLPStakeId;
    }

    /**
     * @dev Internal function to stake LP tokens
     * @param lpToken Address of the LP token
     * @param amount Amount of LP tokens to stake
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     * @param user Address to stake for
     * @return lpStakeId Newly created stakeId
     */
    function _stakeLP(address lpToken, uint256 maturityId, address user, uint256 amount)
        internal
        nonReentrant
        returns (uint256 lpStakeId)
    {
        if (amount == 0) revert Errors.ZeroAmount();
        if (user == address(0)) revert Errors.ZeroAddressNotAllowed();

        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage c = StakingManagerStorage.configLayout();

        // Validate pair exists and is active
        if (!s.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        // Validate maturityId through MaturityManager
        uint256 maturityTimestamp = _validateMaturityId(maturityId);

        if (maturityTimestamp <= block.timestamp) {
            revert Errors.InvalidMaturityTimestamp(maturityTimestamp);
        }

        // Transfer LP tokens from user to this contract FIRST (before updating any storage)
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);

        IKvcmLPStakingFacet.LpStakeInfo storage existingUserStake = _getUserLPStake(lpToken, maturityId, user);

        if (existingUserStake.principal == 0) {
            // new entry
            lpStakeId = _getLatestLPStakeId(lpToken) + 1;

            IKvcmLPStakingFacet.LpStakeInfo memory newStake = IKvcmLPStakingFacet.LpStakeInfo({
                lpStakeId: lpStakeId,
                stakeOwner: user,
                lpToken: lpToken,
                principal: amount,
                maturityId: maturityId,
                maturityTimestamp: SafeCast.toUint128(maturityTimestamp),
                startTimestamp: SafeCast.toUint128(block.timestamp),
                status: IKvcmLPStakingFacet.LpStakeStatus.OPEN
            });

            s.userStakeMapping[lpToken][maturityId][user] = newStake;
            s.lpToLatestStakeId.set(lpToken, lpStakeId);

            emit IKvcmLPStakingFacet.LpStaked(lpToken, maturityId, user, amount, lpStakeId);
        } else {
            existingUserStake.principal = existingUserStake.principal + amount;
            emit IKvcmLPStakingFacet.LpStakeUpdated(lpToken, maturityId, user, amount, lpStakeId);
        }

        // Update global and maturity totals via pair-specific logic
        _updateGlobalTotals(lpToken, maturityId, amount, true);
        IRewardManager(c.rewardManager).mintShareToLP(lpToken, maturityId, user, amount);
    }

    /**
     * @dev Internal function to unstake LP tokens
     * @param lpToken Address of the LP token
     * @param maturityId MaturityManager maturity ID (90-day buckets)
     * @param to Address to unstake to
     */
    function _unstakeLP(address lpToken, uint256 maturityId, address to) internal {
        StakingManagerStorage.LPStakingLayout storage s = StakingManagerStorage.lpStakingLayout();
        StakingManagerStorage.StakingManagerConfigLayout storage c = StakingManagerStorage.configLayout();

        // LP Owner
        address owner = msg.sender;

        IKvcmLPStakingFacet.LpStakeInfo storage existingStake = _getUserLPStake(lpToken, maturityId, owner);

        if (existingStake.lpStakeId == 0) revert Errors.LpStakeNotFound();
        if (existingStake.principal == 0) revert Errors.LpStakeNotFound();
        if (existingStake.stakeOwner != owner) revert Errors.NotAuthorized();
        if (existingStake.status != IKvcmLPStakingFacet.LpStakeStatus.OPEN) revert Errors.LpStakeAlreadyRedeemed();

        // Ensure maturity reached
        if (block.timestamp < existingStake.maturityTimestamp) {
            revert Errors.MaturityNotReached(block.timestamp, existingStake.maturityTimestamp);
        }

        uint256 lpStakeId = existingStake.lpStakeId;

        // Update global and maturity totals  via pair-specific logic
        uint256 principalToTransfer = existingStake.principal;

        // effects before state changes
        _updateGlobalTotals(existingStake.lpToken, existingStake.maturityId, principalToTransfer, false);

        // set stake status to redeemed
        existingStake.status = IKvcmLPStakingFacet.LpStakeStatus.REDEEMED;

        IRewardManager(c.rewardManager).burnSharesFromLP(lpToken, maturityId, owner);
        IERC20(lpToken).safeTransfer(to, principalToTransfer);

        emit IKvcmLPStakingFacet.LpStakeUnstaked(
            existingStake.lpToken, existingStake.maturityId, owner, principalToTransfer, lpStakeId
        );
    }

    function getTotalLPStaked(address lpToken, uint256 maturityId) external returns (uint256 lpStaked) {
        StakingManagerStorage.LPStakingLayout storage l = StakingManagerStorage.lpStakingLayout();

        if (!l.pairs[lpToken].isActive) revert Errors.InvalidPair(lpToken);

        return l.pairMaturityTotalStaked[lpToken][maturityId];
    }

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

        return totalLPsStaked;
    }
}
