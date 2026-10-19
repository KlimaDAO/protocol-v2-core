// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../libraries/LibDiamond.sol";
import "../../libraries/Errors.sol";
import "../../libraries/CarbonSystemRoleLib.sol";
import "../../libraries/storage/StakingManagerStorage.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

/**
 * @title StakingManagerPauseFacet
 * @dev Facet for managing system pause states with role-based access
 */
contract StakingManagerPauseFacet {
    event SystemPauseStatusChanged(bool isPaused);
    event KvcmStakingPauseStatusChanged(bool isPaused);
    event K2StakingPauseStatusChanged(bool isPaused);
    event LpStakingPauseStatusChanged(bool isPaused);

    modifier onlySystemAdmin() {
        IAccessManager accessManager = IAccessManager(StakingManagerStorage.configLayout().accessManager);
        (bool isSystemAdmin,) = accessManager.hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);
        (bool isStakingManagerAdmin,) =
            accessManager.hasRole(CarbonSystemRoleLib.KVCM_STAKING_MANAGER_ADMIN, msg.sender);

        if (msg.sender != LibDiamond.contractOwner() && !isSystemAdmin && !isStakingManagerAdmin) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    function getSystemPauseConfig()
        external
        view
        returns (bool systemPaused, bool kvcmStakingPaused, bool k2StakingPaused, bool lpStakingPaused)
    {
        return (
            StakingManagerStorage.managerPauseLayout().systemPaused,
            StakingManagerStorage.managerPauseLayout().kvcmStakingPaused,
            StakingManagerStorage.managerPauseLayout().k2StakingPaused,
            StakingManagerStorage.managerPauseLayout().lpStakingPaused
        );
    }

    function pauseSystem() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().systemPaused = true;
        emit SystemPauseStatusChanged(true);
    }

    function unpauseSystem() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().systemPaused = false;
        emit SystemPauseStatusChanged(false);
    }

    function isSystemPaused() external view returns (bool) {
        return StakingManagerStorage.managerPauseLayout().systemPaused;
    }

    function pauseKvcmStaking() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().kvcmStakingPaused = true;
        emit KvcmStakingPauseStatusChanged(true);
    }

    function unpauseKvcmStaking() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().kvcmStakingPaused = false;
        emit KvcmStakingPauseStatusChanged(false);
    }

    function pauseK2Staking() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().k2StakingPaused = true;
        emit K2StakingPauseStatusChanged(true);
    }

    function unpauseK2Staking() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().k2StakingPaused = false;
        emit K2StakingPauseStatusChanged(false);
    }

    function pauseLpStaking() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().lpStakingPaused = true;
        emit LpStakingPauseStatusChanged(true);
    }

    function unpauseLpStaking() external onlySystemAdmin {
        StakingManagerStorage.managerPauseLayout().lpStakingPaused = false;
        emit LpStakingPauseStatusChanged(false);
    }
}
