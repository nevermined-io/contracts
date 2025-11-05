// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAccessManagedUUPSUpgradeable} from '../interfaces/IAccessManagedUUPSUpgradeable.sol';
import {
    AccessManagedUpgradeable
} from '@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

abstract contract AccessManagedUUPSUpgradeable is
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    IAccessManagedUUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _authority The address of the authority controlling the upgrade process
     */
    // solhint-disable-next-line func-name-mixedcase
    function __AccessManagedUUPSUpgradeable_init(address _authority) internal onlyInitializing {
        __AccessManaged_init(_authority);
    }

    /**
     * @notice Authorizes an upgrade
     * @dev This function leverages the restricted modifier from AccessManagedUpgradeable to ensure that
     *      only the authority can authorize an upgrade
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override restricted {
        require(newImplementation != address(0), AuthorityCannotBeZero());
        emit UpgradeAuthorized(msg.sender, newImplementation);
    }
}
