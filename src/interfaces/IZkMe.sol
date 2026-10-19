// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IZkMe {
    function hasApproved(address cooperator, address user) external view returns (bool);
}
