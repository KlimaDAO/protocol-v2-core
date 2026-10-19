// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IK2YieldCurveFacet {
    struct K2YieldCurveParams {
        uint256 rewardCap;
        uint256 start;
        uint256 T;
        uint256 duration;
        int256 x0;
        uint256 P0_wad;
        uint256 P_end_wad;
        uint256 cumulativeOffset;
    }

    event ScheduleUpdated(uint256 start, uint256 T, uint256 duration, int256 x0, uint256 P0_wad);

    function initK2YieldSchedule(uint256 _rewardCap, uint256 _start, uint256 _T, uint256 _duration, uint256 _P0_wad)
        external;

    function updateSchedule(uint256 newStart, uint256 newT, uint256 newDuration, uint256 newP0_wad) external;

    function cumulativeAllocatedAt(uint256 ts) external view returns (uint256);

    function dailyEmission(uint256 dayId) external view returns (uint256);

    function emissionBetween(uint256 fromTs, uint256 toTs) external view returns (uint256);

    function getK2YieldCurveParams() external view returns (K2YieldCurveParams memory params);
}
