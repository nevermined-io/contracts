pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


/**
 * @title Agreement Store Library
 * @author Nevermined
 *
 * @dev Implementation of the Agreement Store Library.
 *      For more information: https://github.com/oceanprotocol/OEPs/issues/125    
 *      TODO: update the OEP link 
 *      The agreement store library holds the business logic
 *      in which manages the life cycle of SEA agreement, each 
 *      agreement is linked to the DID of an asset, template, and
 *      condition IDs.
 */
library AgreementStoreLibrary {

    struct Agreement {
        bytes32 did; // UNUSED
        address templateId;
        bytes32[] conditionIds; // UNUSED
        address lastUpdatedBy; // UNUSED
        uint256 blockNumberUpdated; // UNUSED
    }

    struct AgreementList {
        mapping(bytes32 => Agreement) agreements;
        mapping(bytes32 => bytes32[]) didToAgreementIds;
        mapping(address => bytes32[]) templateIdToAgreementIds;
        bytes32[] agreementIds; // UNUSED
    }

    /**
     * @dev create new agreement
     *      checks whether the agreement Id exists, creates new agreement 
     *      instance, including the template, conditions and DID.
     * @param _self is AgreementList storage pointer
     * @param _id agreement identifier
     * @param _templateId template identifier
     */
    function create(
        AgreementList storage _self,
        bytes32 _id,
        bytes32 /* _did */,
        address _templateId,
        bytes32[] memory /* _conditionIds */
    )
        internal
    {
        require(
            _self.agreements[_id].templateId == address(0),
            'Id already exists'
        );

        _self.agreements[_id].templateId = _templateId;
    }
}
