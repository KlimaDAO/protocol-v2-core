# RiskyYieldFacet Test Cases

## computeFinalizedLambdas() & setFinalizedLambdas()

| #   | Scenario                   | Condition                                     | Expected Behavior                                        |
| --- | -------------------------- | --------------------------------------------- | -------------------------------------------------------- |
| 1   | Genesis (Day 1)            | `midNightIndex = 1`, no activity              | Copy lambdas from genesis (0s), no validation            |
| 2   | Day 2+ No Activity         | `midNightIndex > 1`, lambdas = 0              | Check previous finalized, copy lambdas from previous day |
| 3   | Day with Activity          | lambdas > 0, lastUpdate < midnight            | Accumulate remaining time delta, update lambdas          |
| 4   | Already Finalized          | `lastLambdaUpdateTimestamp == midnightEnd`    | Revert with `LambdasAlreadyFinalized`                    |
| 5   | Previous Not Finalized     | `midNightIndex > 1`, previous not finalized   | Revert with `PreviousMidnightNotFinalized`               |
| 6   | Invalid Index (0)          | `midNightIndex = 0`                           | Revert with `InvalidMidnightIndex`                       |
| 7   | Already Finalized - Read   | Call `computeFinalizedLambdas()` on finalized | Return existing values from cache                        |
| 8   | No Updates, lastUpdate = 0 | lambdas > 0, lastUpdate = 0                   | Return current accumulated values (no delta)             |

## Beta Propagation

| #   | Scenario                  | Condition                      | Expected Behavior                              |
| --- | ------------------------- | ------------------------------ | ---------------------------------------------- |
| 9   | No Activity - Beta Copy   | lambdas = 0 at write time      | Copy `betaSq` from `midNightIndex - 1`         |
| 10  | With Activity - Beta Set  | lambdas > 0 during day         | Beta already set by allocs/deallocs, no copy   |
| 11  | Genesis Beta              | `midNightIndex = 1`, no betaSq | `_getBetaSqForDay()` returns SCALE (1e18)      |
| 12  | Beta Lookup Fallback      | No betaSq for day N            | Search back up to 365 days for non-zero betaSq |
| 13  | Multiple No-Activity Days | Days 1-5 no activity           | Beta propagates forward each day               |

## Beta Update Functions

| #   | Scenario     | Condition                     | Expected Behavior                       |
| --- | ------------ | ----------------------------- | --------------------------------------- |
| 14  | Kvcm Stake   | `updateBetaSqOnKvcmStake()`   | Update betaSq, store in cache for dayId |
| 15  | Kvcm Unstake | `updateBetaSqOnKvcmUnstake()` | Update betaSq, store in cache for dayId |
| 16  | K2 Stake     | `updateBetaSqOnK2Stake()`     | Update betaSq, store in cache for dayId |
| 17  | K2 Unstake   | `updateBetaSqOnK2Unstake()`   | Update betaSq, store in cache for dayId |
| 18  | Zero Amount  | Any update with amount = 0    | Return 0, no state change               |
| 19  | Zero Address | carbonClass = address(0)      | Revert with `ZeroAddress`               |

## Edge Cases

| #   | Scenario                         | Condition                             | Expected Behavior                             |
| --- | -------------------------------- | ------------------------------------- | --------------------------------------------- |
| 20  | Multiple Consecutive No-Activity | Days 1-10 all no activity             | Each day copies from previous, chain of 0s    |
| 21  | Activity After Long Dormancy     | Day 100 first activity after 99 days  | Beta looked up from genesis, lambdas computed |
| 22  | Midnight Boundary                | lastUpdate exactly at midnight        | remainingDelta = 0, no accumulation           |
| 23  | Same Day Multiple Updates        | Multiple allocs in same dayId         | betaSq overwritten each time for same dayId   |
| 24  | Cross-Midnight Update            | Update at 11:59 PM, finalize 12:01 AM | Accumulate 1 minute remaining delta           |

## Struct & Interface Changes

| #   | Scenario                  | Condition                          | Expected Behavior                        |
| --- | ------------------------- | ---------------------------------- | ---------------------------------------- |
| 25  | FinalizationValues Struct | Call returns struct                | Contains only finalGG, finalG, finalQ    |
| 26  | Interface Inheritance     | Use IRiskyYieldFacet types         | All structs/events accessible externally |
| 27  | Struct Parameter          | Call `setFinalizedLambdas(values)` | Accepts FinalizationValues struct        |

# K2YieldFacet Test Cases

## Utilisation Calculation

| #   | Scenario                 | Condition                                                  | Expected Behavior                                         |
| --- | ------------------------ | ---------------------------------------------------------- | --------------------------------------------------------- |
| 28  | Utilisation Bounds Check | `relUtilisation <= 1e18` and `absoluteUtilisation <= 1e18` | `utilisation` result must be less than or equal to `1e18` |
