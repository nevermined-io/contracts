// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/**
 * @title Access Managed UUPS Upgradeable Interface
 * @author Nevermined AG
 * @notice Interface defining events and functionality for the Access Managed UUPS Upgradeable contract
 * @dev This interface establishes the core events for tracking upgrades in contracts that implement
 * the Universal Upgradeable Proxy Standard (UUPS) pattern with access management controls
 */
interface IAccessManagedUUPSUpgradeable {
    /**
     * @notice Emitted when an upgrade is authorized
     * @dev This event is emitted before the actual upgrade is performed, indicating an upgrade is pending
     * @param caller The address that initiated the upgrade (msg.sender)
     * @param newImplementation The address of the new implementation contract to upgrade to
     */
    event UpgradeAuthorized(address indexed caller, address indexed newImplementation);

    /**
     * @notice Error thrown when the authority is set to the zero address
     */
    error AuthorityCannotBeZero();
}
