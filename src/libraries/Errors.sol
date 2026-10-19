// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Errors
 * @notice Central catalogue of custom errors
 */
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                               COMMON / SHARED
    //////////////////////////////////////////////////////////////////////////*/
    error NotAuthorized();
    error NotOwner();
    error NotSystemAdmin();
    error NotCarbonMaturityManager();
    error SystemPaused();
    error ZeroAddress();
    error ZeroUint();
    error InvalidAddress();
    error InvalidToken(address token);
    error InvalidTokenId(uint256 tokenId);
    error ZeroAmount();
    error InvalidAmountTooSmall(uint256 amount);
    error InvalidAmountTooLarge(uint256 amount);
    error CarbonClassMismatch(address carbonClass, address expected);
    error InvalidMaturityId(uint256 maturityId);
    error InvalidMaturityPeriod(uint256 maturityPeriod);
    error InvalidMaturityTimestamp(uint256 timestamp);
    error InvalidMaturityRange(uint256 firstMaturityId, uint256 lastMaturityId);
    error ConversionExceedsUint128(uint256 value);
    error InvalidCirculatingSupply(uint256 midnightIndex, uint256 circulatingSupply);
    error AlreadyInitialized();
    error MaturityIdNotExpired(uint256 maturityId);
    error InvalidFutureSettlement(uint256 targetMidnightIndex, uint256 currentMidnightIndex);
    error InvalidValue();
    error AmountMismatch(uint256 requested, uint256 received);

    // testing

    error NotImplemented();

    /*//////////////////////////////////////////////////////////////////////////
                                ASSET MANAGER
    //////////////////////////////////////////////////////////////////////////*/
    error ZeroDiscountedBalance();
    error InsufficientCreditBalance(uint256 creditBalance, uint256 amount);
    error InsufficientKvcmIn(uint256 maxKvcmIn, uint256 kvcmReceived);
    error InsufficientKvcmOut(uint256 expected, uint256 actual);
    error CannotRetireEntireKvcmSupply();
    error MaturityIdMismatch(uint256 maturityId, uint256 discountFactorMaturityId);
    error ActiveMaturityLengthMismatch(uint256 maturityLength, uint256 discountFactorLength);
    error ZeroAllocationForClass(address carbonClass);
    error ZeroLiquidBalanceForClass(address carbonClass);
    error ZeroCouponBurnAmount();
    error QuoteCallFailed(address quoter, bytes reason);
    error SwapFailed(address quoter, bytes reason);
    error RetirementFailed(address quoter, bytes reason);
    error InvalidRecipient();
    error NoQuoterForClass(address carbonClass);
    error MaxKvcmInExceeded(uint256 expected, uint256 actual);
    error LockNotYetMatured(uint256 maturityId);
    error NoDiscountFactorForMaturity(uint256 maturityId);
    error InvalidQuoteType();
    error InvalidCouponBurnFrom(address account, address from);
    // Rate limiter errors
    error ZeroSnapshotValue();
    error ZeroSnapshotTime();
    error ZeroRate();
    error RateLimitsAlreadyInitialized();
    error ZeroAllocationSnapshotValue();
    error UninitializedAllocationRateLimiter(address carbonClass);
    error MinEffectiveAllocationNotSet(address carbonClass);
    error FallbackK2AllocationSnapshotValueCannotBeZero();
    error QuoterNotFound(address quoterAddress);
    error QuoterAlreadyRegistered(address quoterAddress);
    error CarbonClassAlreadyRegistered(address carbonClass);

    /*//////////////////////////////////////////////////////////////////////////
                             CARBON CLASS VAULT
    //////////////////////////////////////////////////////////////////////////*/
    error NotCarbonLedger();
    error CreditAlreadyRegistered();
    error CreditNotProperlyOnboarded();
    error CreditNotRegistered();
    error InvalidDefaultTokenId();
    error CannotWithdrawReservedTonnes();
    error CannotBurnMoreThanReserved();
    error InsufficientERC1155Balance();
    error InsufficientERC20Balance();
    error InconsistentTokenBalance();
    error InsufficientTotalTonnes();
    error NoTokensSpecified();
    error ArraysLengthMismatch();
    error NotERC1155Token();
    error NotERC20Token();
    error TransferNotFromCarbonLedger();
    error InsufficientApproval();
    error ZeroAddressNotAllowed();
    error NoCodeAtAddress(address addr);
    error CarbonVaultHasCredits();
    error TokenTypeNotMatchRegistration();
    error TokenIdAlreadyRegistered();
    error MaturityManagerNotSet();
    error MaturityNotReached(uint256 maturityId, uint256 maturityTimestamp);
    error NoTonnesToMature();
    error InsufficientLiquidTonnes();
    error InsufficientLiquidTokenTonnes();
    error InsufficientMaturityTonnes();
    error InsufficientMaturityTokenTonnes();
    error InsufficientTokenBalance();
    error InsufficientTokenTonnes();
    error SameMaturityId();
    error NoTonnesToMigrate();
    error BatchSizeTooLarge(uint256 provided, uint256 maximum);

    /*//////////////////////////////////////////////////////////////////////////
                             CARBON CLASS COUPONS
    //////////////////////////////////////////////////////////////////////////*/
    error ZeroAddressRewardManager();
    error CallerNotAuthorized(); // e.g. mint/burn callers
    error ZeroAddressForCoupons();
    error ZeroAmountForCoupons();
    error InsufficientAvailableTonnes();
    error CallerNotAuthorizedToBurn();
    error CannotReleaseMoreThanReserved();
    error InsufficientCouponRedemptionBalance(uint256 balance, uint256 amount);
    error InsufficientCouponBalance();

    /*//////////////////////////////////////////////////////////////////////////
                                CARBON LEDGER
    //////////////////////////////////////////////////////////////////////////*/
    error CallerNotAdmin();
    error CallerNotAdminOrManager();
    error CallerNotAdminOrLiquidityManager();
    error CallerNotMaturityExecutor();
    error ZeroAddressClass();
    error ClassNotInUnregisteredState(address classVault);
    error ClassNotRegistered(address classVault);
    error CreditNotInUnregisteredStateForClass(address classVault, address creditToken);
    error CarbonCreditNotRegisteredForClass(address classVault, address creditToken);
    error TokenIdNotRegistered(address classVault, address creditToken, uint256 tokenId);
    error SourceAndTargetVaultCannotBeSame(address vault);
    error DuplicateTokenIdsInArray(uint256 tokenId);
    error TooManyTokenIds(uint256 provided, uint256 maxAllowed);
    error InvalidMaxTokenIds();
    error AmountCannotBeZero();
    error CarbonCreditNotRegisteredInLedger(address creditToken);
    error CarbonCreditAlreadyExists(address creditToken);
    error InvalidConversionConfig();
    error TokenIdMustBeGreaterThanZeroForERC1155();
    error TokenIdMustBeZeroForERC20();
    error AmountTooLarge(uint256 amount, uint256 maxAmount);
    error TimelockPeriodNotElapsed(uint256 lastRemoval, uint256 currentTime);
    error InsufficientVaultBalance(uint256 vaultBalance, uint256 requestedAmount);
    error MigrationDepositFailed(
        address targetVault, address creditToken, uint256 amount, uint256 tokenId, string reason
    );
    error DepositFailed(address classVault, address creditToken, uint256 amount, uint256 tokenId);
    error InvalidClassVaultContract(address classVault);
    error FailedToRegisterCredit(address classVault, address creditToken);
    error InvalidTokenType();
    error RegistrationFailed();
    error UnregistrationFailed();
    error InsufficientCoupons();
    error NotCouponsIssuer();
    error NotCouponsLiquidityManager();
    error NotCarbonVaultManager();
    error NotCarbonLedgerAdmin();

    /*//////////////////////////////////////////////////////////////////////////
                             CARBON VAULT FACTORY
    //////////////////////////////////////////////////////////////////////////*/
    error InvalidVersion();
    error VersionAlreadyRegistered();
    error ImplementationNotRegistered();
    error ClassVaultNotTracked();
    error ClassVaultNotActive();
    error ContractPaused();

    /*//////////////////////////////////////////////////////////////////////////
                             STAKING MANAGER
    //////////////////////////////////////////////////////////////////////////*/
    error KvcmStakingPaused();
    error K2StakingPaused();
    error MaturityIdOutOfRange(uint256 maturityId, uint256 start, uint256 end);
    error MaturityIdStillActive(uint256 maturityId, uint256 start, uint256 end);
    error KvcmLockIsClosed();
    error KvcmLockNotPartialClaimed();
    error KvcmLockNotMatured();
    error TransfersNotAllowed();
    error KvcmLockMintFailed();
    error KvcmLockNotSet();
    error KvcmLockNotOwned();
    error K2TokenNotSet();
    error KvcmTokenNotSet();
    error KvcmLockTransferFailed();
    error KvcmLockAmountTooSmall(uint256 amount, uint256 minAmount);
    error KvcmAllocationExceedsLock(uint256 amount, uint256 priceAllocations, uint256 principal);
    error KvcmLockMatured();
    error InsufficientKvcmYieldAvailable(uint256 available, uint256 requested);
    error KvcmRetireAmountExceedsBalance(uint256 requested, uint256 balance);
    error KvcmUnlockProceedsShortfall(uint256 minimumExpected, uint256 actual);
    error KvcmYieldClaimProceedsShortfall(uint256 minimumExpected, uint256 actual);
    error KvcmYieldNotFullyRetired(uint256 claimed, uint256 actuallyRetired);
    error NoIncentivesToClaim();
    error RetirementAggregatorNotSet();
    error KvcmLockAllocationNotFound();
    error DeallocationAmountExceedsAllocatedAmount(uint256 allocatedAmount);
    error DeallocationAmountExceedsAllocatedAmountForClass(address carbonClass, uint256 allocatedAmount);
    error DeallocationAmountExceedsLockPriceAllocations(uint256 priceAllocations, uint256 amount);
    error InvalidAmounts(uint256 minLockAmount, uint256 maxLockAmount);
    error NoUnlockRequested(); // When trying to claim without unlocking first
    error NoK2Locked(); // When trying to interact with non-existent lock
    error InsufficientK2UnlockedPrincipal(uint256 unlockedPrincipal, uint256 amount);
    error InvalidAllocationsLength(); // When allocations length is 0 or greater than 50
    error AllocationsExceedsLockedAmount(uint256 totalAllocated, uint256 newAllocatedAmount);
    error ClaimRequired(); // open claim must be executed before new unlock request
    error ClaimNotAllowed(); // When trying to claim before conditions are met
    error NoK2ClaimEscrow(); // When trying to claim with no escrowed tokens
    error NoK2Allocated(); // When trying to interact with non-existent allocated amount
    error UnstakeExceedsExistingAllocation(uint256 unstakeAmount, uint256 existingAllocatedAmount);
    error InvalidMidnightTimestamp(); // When timestamp doesn't align with midnight
    error InvalidMinK2LockPeriod(); // k2 minLockPeriod is not set
    error MinimumK2LockPeriodNotMet(); // at least 24 hours must pass before unlocking k2 locks
    error LockedSlotsFull(); // when both slots are occupied and no empty slot is found. Indicates logic error.
    error InvalidDeadline(uint256 deadline); // when deadline is in the past

    /*//////////////////////////////////////////////////////////////////////////
                             LP STAKING
    //////////////////////////////////////////////////////////////////////////*/
    error InvalidPair(address lpToken);
    error PairAlreadyRegistered();
    error DelegateCallFailed();
    error TokenMismatch();
    error LpStakeNotFound();
    error LpStakeAlreadyRedeemed();
    error LpRewardsAlreadyClaimed();
    error PairFacetMustOverride(string functionName);
    error InvalidRange(uint256 fromId, uint256 toId); // When fromId > toId
    error RangeTooLarge(uint256 rangeSize); // When range size exceeds maximum

    /*//////////////////////////////////////////////////////////////////////////
                             REWARDS MANAGER
    //////////////////////////////////////////////////////////////////////////*/
    error KVCMCirculatingSupplyIsZero();
    error K2CirculatingSupplyIsZero();
    error NotRewardManagerStateUpdater();
    error KvcmAQExceedsSupply(uint256 aAQ, uint256 A);
    error BurnMoreRYSharesThanMinted();
    error InvalidArrayLength();
    error EmptyArray();
    error CannotPullBeforeStartDate();
    error CannotPullForFutureDay(uint256 requestedDay, uint256 currentDay);
    error PullExceedsDailyLimit(uint256 pulled, uint256 limit);

    /*//////////////////////////////////////////////////////////////////////////
                             REWARD MANAGER
    //////////////////////////////////////////////////////////////////////////*/
    error ZeroGammaSum();
    error AccumulatorNotFound(uint256 maturityId);
    error NoKvcmLocked();
    error NoElapsedTime();
    error YieldDistributionIntervalNotSet();
    error LockAlreadyMatured(uint256 lockId);
    error InvalidMaturityForUpdate(uint256 maturityId);
    error LockNotFound(uint256 lockId);

    error KVCMK2YQueueOverflow(uint256 maturityId, address user);
    error LPRYieldQueueOverflow(address lpToken, uint256 maturityId, address user);
    error K2StakersPositionsOverflow(address user);

    error KVCMYieldNotDistributed(uint256 midnightIndex);
    error TotalRiskyYieldRewardsIsZero(uint256 midnightIndex);
    error DiscountParameterIsZero(uint256 midnightIndex);
    error BetaIsZero(uint256 midnightIndex);
    error BetaSqIndexNotAdjacent(uint256 midnightIndex, uint256 lastNonZeroBetaSqIndex);

    error NoActiveYieldCurve(uint256 midnightIndex);
    error NoLPStakesForMaturities(address lpToken);
    error NoKVCMStakesForMaturities();
    error NoK2Stakers();
    error TotalSharesExceedsK2Supply(uint256 totalShares, uint256 k2Supply);
    error YieldExceedsEscrowBalance(uint256 yield, uint256 escrowBalance);
    error YieldExceedsDailyEmission(uint256 yield, uint256 dailyEmission);

    error ArrayTooLarge(uint256 provided, uint256 maximum);
    error DuplicateMaturityId(uint256 maturityId);
    error KVCMYieldIntervalNotSettled(uint256 midnightIndex);
    error RYMidnightIndexAlreadyProcessed(uint256 midnightIndex, uint256 lastProcessedIndex);
    error RYMidnightIndexOutOfOrder(uint256 midnightIndex, uint256 lastProcessedIndex);
    error K2YMidnightIndexAlreadyProcessed(uint256 midnightIndex, uint256 lastProcessedIndex);
    error K2YMidnightIndexOutOfOrder(uint256 midnightIndex, uint256 lastProcessedIndex);
    error KVCMK2YieldNotProcessedForMidnight(uint256 midnightIndex, uint256 lastProcessedKVCM);
    error InvalidMaturityIdGap(uint256 firstMaturityId, uint256 lastMaturityId, uint256 expectedGap);
    error MaturityIdsNotSorted(uint256 prevMaturityId, uint256 currentMaturityId);
    error LambdaGGExceedsScale(uint256 lambdaGG);
    error LambdaGGAndLambdaGExceedsScale(uint256 lambdaGG, uint256 lambdaG);
    error LambdasNotFinalized(uint256 midnightIndex);
    error LambdasAlreadyFinalized(uint256 midnightIndex);
    error FinalizedValuesMismatch(uint256 midnightIndex);
    error K2StakedExceedsSupply(uint256 G, uint256 k2Supply);
    error K2InLPExceedsSupply(uint256 L, uint256 k2Supply);
    error UtilisationExceedsScale(uint256 relUtilisation, uint256 absoluteUtilisation);
    error KVCMStakedExceedsSupply(uint256 kvcmStaked, uint256 kvcmSupply);
    error TotalSharesMismatch(address lpToken, uint256 maturityId, uint256 totalShares, uint256 currentShares);
    error PreviousMidnightNotFinalized(uint256 midnightIndex);
    error UnsupportedLPToken(address lpToken);
    error ZeroMidnightIndexYieldDistribution();

    /*//////////////////////////////////////////////////////////////////////////
                                PROTOCOL MINTER
    //////////////////////////////////////////////////////////////////////////*/
    error UnauthorizedSystemAdmin();
    error UnauthorizedRewardManager();
    error UnauthorizedAAM();

    /*//////////////////////////////////////////////////////////////////////////
                                PROTOCOL REWARDS ESCROW
    //////////////////////////////////////////////////////////////////////////*/
    error InvalidK2EscrowAmount(uint256 amount, uint256 maxAmount);
    error InsufficientK2RewardsEscrowed(uint256 available, uint256 requested);
    error InvalidKVCMTokenAddress();
    error InvalidK2TokenAddress();
    error InvalidAccessManagerAddress();
    error InvalidStakingManagerAddress();
    error InvalidTreasuryAddress();
    error InvalidRewardManagerAddress();
    error NotProtocolMinter();
    error NotRewardManager();
    error SharesToBurnGTSystem();
    error BurnMoreK2SharesThanMinted();
    error InvalidPreviousMidnightIndex(uint256 currentMidnightIndex, uint256 lastMidnightIndexYieldDistribution);
    error InconsistentSupplyForLocked(uint256 targetMidnightIndex, uint256 totalEffectiveLocked);
    error ZeroPricePerShare();
    error TooManyUnprocessedDeposits();
    error InvalidQueue();
    error InvalidQueueOrder(uint256 nextMidnightIndex, uint256 lastElementMidnightIndex);
    error InvalidMaturityYieldForInterval(uint256 midnightIndex, uint256 maturityId, uint256 maturityYieldForInterval);
    error IntervalAlreadySettled(uint256 midnightIndex);
    error PPSNotSet(uint256 midnightIndex, uint256 maturityId);
    error InvalidMaturityYields(uint256 passedLength, uint256 expectedLength);
    error InvalidAccruedYield(uint256 totalAccruedYield, uint256 yieldDistributed);
    error InvalidLockingInterval(uint256 maturityTimestamp);
    error InvalidMidnightIndex(uint256 midnightIndex);
    error ZeroCirculatingSupply(uint256 midnightIndex);
    error ZeroDiscountFactor();
    error EmptyCarbonClassesArray();
}
