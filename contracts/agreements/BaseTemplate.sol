// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAgreement} from '../interfaces/IAgreement.sol';
import {IAsset} from '../interfaces/IAsset.sol';
import {IHook} from '../interfaces/IHook.sol';
import {ITemplate} from '../interfaces/ITemplate.sol';
import {AccessManagedUUPSUpgradeable} from '../proxy/AccessManagedUUPSUpgradeable.sol';
import {ERC2771ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol';
import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';

/**
 * @title BaseTemplate
 * @author Nevermined
 * @notice Abstract base contract for all agreement templates in the Nevermined protocol
 * @dev BaseTemplate provides common functionality and storage for derived template contracts,
 *      establishing a consistent pattern for agreement creation and management. It implements
 *      the ITemplate interface and inherits AccessManagedUUPSUpgradeable for secure proxy
 *      upgrades. The contract uses ERC-7201 namespaced storage to ensure storage safety
 *      across upgrades and inheritance chains.
 *
 *      Derived templates (like FixedPaymentTemplate and FiatPaymentTemplate) extend this base
 *      contract to implement specific agreement workflows while maintaining consistent
 *      access patterns to the AgreementsStore and AssetsRegistry.
 */
abstract contract BaseTemplate is ITemplate, AccessManagedUUPSUpgradeable, ERC2771ContextUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("nevermined.basetemplate.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_TEMPLATE_STORAGE_LOCATION =
        0xe216fc96f789fa9c96a1eaa661bfd7aef52752717013e765adce03d67eb13e00;

    /// @custom:storage-location erc7201:nevermined.basetemplate.storage
    struct BaseTemplateStorage {
        /// @notice Reference to the AssetsRegistry contract
        IAsset assetsRegistry;
    }

    // Trusted forwarder is stored as an immutable variable
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {}

    // solhint-disable-next-line func-name-mixedcase
    function __BaseTemplate_init(IAsset _assetsRegistryAddress) internal onlyInitializing {
        require(_assetsRegistryAddress != IAsset(address(0)), InvalidAssetsRegistryAddress());
        BaseTemplateStorage storage $ = _getBaseTemplateStorage();
        $.assetsRegistry = _assetsRegistryAddress;
    }

    /**
     * @notice Internal function to get the contract's storage reference
     * @return $ Storage reference to the BaseTemplateStorage struct
     * @dev Uses ERC-7201 namespaced storage pattern for upgrade safety
     */
    function _getBaseTemplateStorage() internal pure returns (BaseTemplateStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := BASE_TEMPLATE_STORAGE_LOCATION
        }
    }

    /**
     * @notice Executes all before hooks for a plan
     * @param _planId The ID of the plan
     * @param _agreementId The ID of the agreement being created
     * @param _creator The address of the agreement creator
     * @param _conditionIds Array of condition IDs for the agreement
     * @param _conditionStates Array of condition states for the agreement
     * @param _params Additional parameters for the agreement
     */
    function _executeBeforeHooks(
        uint256 _planId,
        bytes32 _agreementId,
        address _creator,
        bytes32[] memory _conditionIds,
        IAgreement.ConditionState[] memory _conditionStates,
        bytes[] memory _params
    ) internal {
        BaseTemplateStorage storage $ = _getBaseTemplateStorage();
        IHook[] memory hooks = $.assetsRegistry.getPlanHooks(_planId);

        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].beforeAgreementRegistered(
                _agreementId, _creator, _planId, _conditionIds, _conditionStates, _params
            );
        }
    }

    /**
     * @notice Executes all after hooks for a plan
     * @param _planId The ID of the plan
     * @param _agreementId The ID of the agreement that was created
     * @param _creator The address of the agreement creator
     * @param _conditionIds Array of condition IDs for the agreement
     * @param _params Additional parameters for the agreement
     */
    function _executeAfterHooks(
        uint256 _planId,
        bytes32 _agreementId,
        address _creator,
        bytes32[] memory _conditionIds,
        bytes[] memory _params
    ) internal {
        BaseTemplateStorage storage $ = _getBaseTemplateStorage();
        IHook[] memory hooks = $.assetsRegistry.getPlanHooks(_planId);

        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].afterAgreementCreated(_agreementId, _creator, _planId, _conditionIds, _params);
        }
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }
}
