pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './TemplateStoreLibrary.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

/**
 * @title Template Store Manager
 * @author Nevermined
 *
 * @dev Implementation of the Template Store Manager.
 *      Templates are blueprints for modular SEAs. When creating an Agreement, 
 *      a templateId defines the condition and reward types that are instantiated 
 *      in the ConditionStore. This contract manages the life cycle 
 *      of the template ( Propose --> Approve --> Revoke ).
 *      
 */
contract TemplateStoreManager is OwnableUpgradeable {

    using TemplateStoreLibrary for TemplateStoreLibrary.TemplateList;

    TemplateStoreLibrary.TemplateList internal templateList;

    modifier onlyOwnerOrTemplateOwner(address _id){
        require(
            msg.sender == owner() ||
            templateList.templates[_id].owner == msg.sender,
            'Invalid UpdateRole'
        );
        _;
    }

    /**
     * @dev initialize TemplateStoreManager Initializer
     *      Initializes Ownable. Only on contract creation.
     * @param _owner refers to the owner of the contract
     */
    function initialize(
        address _owner
    )
        public
        initializer()
    {
        require(
            _owner != address(0),
            'Invalid address'
        );

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
    }

    /**
     * @notice proposeTemplate proposes a new template
     * @param _id unique template identifier which is basically
     *        the template contract address
     */
    function proposeTemplate(address _id)
        external
        returns (uint size)
    {
        return templateList.propose(_id);
    }

    /**
     * @notice approveTemplate approves a template
     * @param _id unique template identifier which is basically
     *        the template contract address. Only template store
     *        manager owner (i.e OPNF) can approve this template.
     */
    function approveTemplate(address _id)
        external
        onlyOwner
    {
        return templateList.approve(_id);
    }

    /**
     * @notice revokeTemplate revoke a template
     * @param _id unique template identifier which is basically
     *        the template contract address. Only template store
     *        manager owner (i.e OPNF) or template owner
     *        can revoke this template.
     */
    function revokeTemplate(address _id)
        external
        onlyOwnerOrTemplateOwner(_id)
    {
        return templateList.revoke(_id);
    }

    /**
     * @notice getTemplate get more information about a template
     * @param _id unique template identifier which is basically
     *        the template contract address.
     * @return state template status
     * @return owner template owner
     * @return lastUpdatedBy last updated by
     * @return blockNumberUpdated last updated at.
     */
    function getTemplate(address _id)
        external
        view
        returns (
            TemplateStoreLibrary.TemplateState state,
            address owner,
            address lastUpdatedBy,
            uint blockNumberUpdated
        )
    {
        state = templateList.templates[_id].state;
        owner = templateList.templates[_id].owner;
        lastUpdatedBy = templateList.templates[_id].lastUpdatedBy;
        blockNumberUpdated = templateList.templates[_id].blockNumberUpdated;
    }

    /**
     * @notice getTemplateListSize number of templates
     * @return size number of templates
     */
    function getTemplateListSize()
        external
        view
        virtual
        returns (uint size)
    {
        return templateList.templateIds.length;
    }

    /**
     * @notice isTemplateApproved check whether the template is approved
     * @param _id unique template identifier which is basically
     *        the template contract address.
     * @return true if the template is approved
     */
    function isTemplateApproved(address _id) external view returns (bool) {
        return templateList.templates[_id].state ==
            TemplateStoreLibrary.TemplateState.Approved;
    }
    

}
