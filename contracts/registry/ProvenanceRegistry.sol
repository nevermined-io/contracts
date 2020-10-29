pragma solidity 0.5.6;
// Copyright 2020 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './ProvenanceRegistryLibrary.sol';
import 'openzeppelin-eth/contracts/ownership/Ownable.sol';

/**
 * @title Provenance Registry
 * @author Keyko
 *
 * @dev Implementation of the Provenance Registry following the W3C PROV Specifications

 */
contract ProvenanceRegistry is Ownable {

    /**
     * @dev The ProvenanceRegistry Library takes care of the basic storage functions.
     */
    using ProvenanceRegistryLibrary for ProvenanceRegistryLibrary.ProvenanceRegisterList;

    /**
     * @dev state storage for the Provenance registry
     */
    ProvenanceRegistryLibrary.ProvenanceRegisterList internal provenanceRegisterList;

    // DID -> Address -> Boolean Permission
    mapping(bytes32 => mapping(address => bool)) DIDPermissions;

    modifier onlyProvenanceOwner(bytes32 _did)
    {
        require(
            msg.sender == provenanceRegisterList.provenanceRegisters[_did].owner,
            'Invalid Provenance owner can perform this operation.'
        );
        _;
    }

    modifier onlyValidAttributes(string _attributes)
    {
        require(
            bytes(_attributes).length <= 2048,
            'Invalid attributes size'
        );
        _;
    }

    /**
     * @dev This implementation does not store _attributes on-chain,
     *      but emits ProvenanceAttributeRegistered events to store it in the event log.
     */
    event ProvenanceAttributeRegistered(
        bytes32 indexed _did,
        address indexed _agentId,
        bytes32 indexed _activityId,
        address _agentInvolvedId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    event WasGeneratedBy(
        bytes32 indexed _did,
        address indexed _agentId,
        bytes32 indexed _activityId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    event Used(
        bytes32 indexed _did,
        address indexed _agentId,
        bytes32 indexed _activityId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    event WasDerivedFrom(
        bytes32 indexed _newEntityDid,
        bytes32 indexed _usedEntityDid,
        address indexed _agentId,
        bytes32 _activityId,
        string _attributes,
        uint256 _blockNumberUpdated
    );

    event WasAssociatedWith(
        bytes32 indexed _agentId,
        bytes32 indexed _entityDid,
        bytes32 indexed msg.sender,
        _activityId,
        _attributes,
        block.number
    );

    event ActedOnBehalf(
        address indexed _delegateAgentId,
        address indexed _responsibleAgentId,
        address indexed _entityDid,
        msg.sender,
        _activityId,
        _attributes,
        block.number
    );

    /**
     * @dev ProvenanceRegistry Initializer
     *      Initialize Ownable. Only on contract creation.
     * @param _owner refers to the owner of the contract.
     */
    function initialize(
        address _owner
    )
        public
        initializer
    {
        Ownable.initialize(_owner);
    }

    /**
     * @notice Implements the W3C PROV Generation action
     *
     * @param  _did refers to decentralized identifier (a bytes32 length ID) of the entity created
     */
    function wasGeneratedBy(
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        address[] memory _delegates,
        string _attributes
    )
        public
        onlyProvenanceOwner(_did)
        onlyValidAttributes(_attributes)
        returns (uint size)
    {

        uint updatedSize = provenanceRegisterList
            .create(_did, _agentId, _agentInvolvedId, _activityId);

        // push delegates to storage
        for (uint256 i = 0; i < _delegates.length; i++) {
            provenanceRegisterList.addDelegate(
                _did,
                _delegate[i]
            );

        }

        /* emitting _value here to avoid expensive storage */
        emit ProvenanceAttributeRegistered(
            _did,
            provenanceRegisterList.provenanceRegisters[_did].owner,
            _activityId,
            _agentInvolvedId,
            _attributes,
            block.number
        );

        emit WasGeneratedBy(
            _did,
            provenanceRegisterList.provenanceRegisters[_did].owner,
            _activityId,
            _attributes,
            block.number
        );

        return updatedSize;

    }

    /**
     * @notice Implements the W3C PROV Usage action
     *
     * @param  _did refers to decentralized identifier (a bytes32 length ID) of the entity created
     */
    function used(
        address _agentId,
        bytes32 _activityId,
        bytes32 _did,
        string _attributes
    )
        public
        onlyProvenanceOwnerOrDelegated(_did)
        onlyValidAttributes(_attributes)
        returns (uint size)
    {
      emit Used(
          _did,
          msg.sender,
          _activityId,
          _attributes,
          block.number
      );
    }


    /**
     * @notice Implements the W3C PROV Derivation action
     *
     * @param  _did refers to decentralized identifier (a bytes32 length ID) of the entity created
     */
    function wasDerivedFrom(
        bytes32 _newEntityDid,
        bytes32 _usedEntityDid,
        address _agentId,
        bytes32 _activityId,
        address[] memory _delegates,
        string _attributes
    )
        public
        onlyProvenanceOwnerOrDelegated(_did)
        onlyValidAttributes(_attributes)
        returns (uint size)
    {
      emit ProvenanceAttributeRegistered(
          _newEntityDid,
          provenanceRegisterList.provenanceRegisters[_did].owner,
          _activityId,
          _agentInvolvedId,
          _attributes,
          block.number
      );

      emit WasDerivedFrom(
          _newEntityDid,
          _usedEntityDid,
          msg.sender,
          _activityId,
          _attributes,
          block.number
      );
    }


    /**
     * @notice Implements the W3C PROV Association action
     *
     */
    function wasAssociatedWith(
        address _agentId,
        bytes32 _activityId,
        bytes32 _entityDid,
        bytes32 _signature,
        string _attributes
    )
        public
        onlyProvenanceOwnerOrDelegated(_did)
        onlyValidAttributes(_attributes)
        returns (uint size)
    {
      emit ProvenanceAttributeRegistered(
          _entityDid,
          msg.sender,
          _activityId,
          _agentInvolvedId,
          _attributes,
          block.number
      );

      emit WasAssociatedWith(
          _agentId,
          _entityDid,
          msg.sender,
          _activityId,
          _attributes,
          block.number
      );
    }

    /**
     * @notice Implements the W3C PROV Delegation action
     *
     */
    function actedOnBehalf(
        address _delegateAgentId,
        address _responsibleAgentId,
        bytes32 _entityDid,
        bytes32 _activityId,
        bytes32 _signature,
        string _attributes
    )
        public
        onlyProvenanceOwnerOrDelegated(_did)
        onlyValidAttributes(_attributes)
        returns (uint size)
    {

      emit ProvenanceAttributeRegistered(
          _entityDid,
          msg.sender,
          _activityId,
          _delegateAgentId,
          _attributes,
          block.number
      );

      emit ActedOnBehalf(
          _delegateAgentId,
          _responsibleAgentId,
          _entityDid,
          msg.sender,
          _activityId,
          _attributes,
          block.number
      );
    }


    /**
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @return last modified (update) block number of a DID.
     */
    function getBlockNumberUpdated(bytes32 _did)
        public
        view
        returns (uint256 blockNumberUpdated)
    {
        return provenanceRegisterList.provenanceRegisters[_did].blockNumberUpdated;
    }

    /**
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @return the address of the Provenance owner.
     */
    function getProvenanceOwner(bytes32 _did)
        public
        view
        returns (address provenanceOwner)
    {
        return provenanceRegisterList.provenanceRegisters[_did].owner;
    }

    /**
     * @return the length of the Provenance registry.
     */
    function getProvenanceRegistrySize()
        public
        view
        returns (uint size)
    {
        return provenanceRegisterList.provenanceRegisters.length;
    }

    /**
     * @return the length of the DID registry.
     */
    function getProvenanceRegisterIds()
        public
        view
        returns (bytes32[] memory)
    {
        return provenanceRegisterList.provenanceRegisters;
    }


}
