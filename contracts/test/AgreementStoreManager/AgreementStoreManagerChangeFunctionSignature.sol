pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../agreements/AgreementStoreManager.sol';


contract AgreementStoreManagerChangeFunctionSignature is
    AgreementStoreManager
{
    using AgreementStoreLibrary for AgreementStoreLibrary.AgreementList;
    function createAgreement(
        bytes32 _id,
        bytes32 _did,
        address[] memory _conditionTypes,
        bytes32[] memory _conditionIds,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts,
        address _creator,
        address _sender
    )
        public
    {
        require(
            msg.sender == _sender && msg.sender == _creator,
            'Invalid sender address, should fail in function signature check'
        );
        require(
            templateStoreManager.isTemplateApproved(msg.sender) == true,
            'Template not Approved'
        );
        require(
            _conditionIds.length == _conditionTypes.length &&
            _timeLocks.length == _conditionTypes.length &&
            _timeOuts.length == _conditionTypes.length,
            'Arguments have wrong length'
        );

        for (uint256 i = 0; i < _conditionTypes.length; i++) {
            conditionStoreManager.createCondition(
                _conditionIds[i],
                _conditionTypes[i],
                _timeLocks[i],
                _timeOuts[i]
            );
        }
        agreementList.create(
            _id,
            _did,
            msg.sender,
            _conditionIds
        );
    }
}
