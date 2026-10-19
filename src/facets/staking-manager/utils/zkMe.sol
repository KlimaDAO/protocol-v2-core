// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IZkMe} from "../../../interfaces/IZkMe.sol";
import {Errors} from "../../../libraries/Errors.sol";
import {StakingManagerStorage} from "../../../libraries/storage/StakingManagerStorage.sol";

library ZkMeUtilsLib {
    error ZkMeRequired();

    function hasApproved(address user) external view returns (bool verified) {
        if (user == address(0)) revert Errors.ZeroAddress();

        StakingManagerStorage.IntegrationConfigLayout storage config = StakingManagerStorage.integrationConfigLayout();

        // zkMe verification is always required
        if (!config.zkMeRequired) {
            revert ZkMeRequired();
        }

        address cooperator = config.zkMeCooperator;
        address zkMeVerify = config.zkMeVerify;

        if (cooperator == address(0)) revert Errors.ZeroAddress();
        if (zkMeVerify == address(0)) revert Errors.ZeroAddress();

        verified = IZkMe(zkMeVerify).hasApproved(cooperator, user);
    }
}
