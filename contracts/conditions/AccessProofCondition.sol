pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';
import '../registry/DIDRegistry.sol';
import '../interfaces/ISecretStore.sol';
import '../interfaces/ISecretStorePermission.sol';
import '../agreements/AgreementStoreManager.sol';

interface IDisputeManager {
    function verifyProof(bytes memory proof, uint[] memory pubSignals) external view returns (bool);
}

/**
 * @title Access Condition with transfer proof
 * @author Nevermined
 *
 * @dev Implementation of the Access Condition with transfer proof.
 * The idea is that the hash of the decryption key is known before hand, and the key matching this hash
 * is passed from data provider to the buyer using this smart contract. Using ZK proof the key is kept
 * hidden from outsiders. For the protocol to work, both the provider and buyer need to have public keys
 * in the babyjub curve. To initiate the deal, buyer will pass the key hash and the public keys of participants.
 * The provider needs to pass the cipher text encrypted using MIMC (symmetric encryption). The secret key for MIMC
 * is computed using ECDH (requires one public key and one secret key for the curve). The hash function that is
 * used is Poseidon.
 */
contract AccessProofCondition is Condition {

    bytes32 constant public CONDITION_TYPE = keccak256('AccessProofCondition');

    AgreementStoreManager private agreementStoreManager;
    IDisputeManager private disputeManager;
    
    event Fulfilled(
        bytes32 indexed _agreementId,
        uint _origHash,
        uint[2] _buyer,
        uint[2] _provider,
        uint[2] _cipher,
        bytes _proof,
        bytes32 _conditionId
    );
    
   /**
    * @notice initialize init the 
    *       contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address
    * @param _agreementStoreManagerAddress agreement store manager address
    * @param _disputeManagerAddress dispute manager address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _agreementStoreManagerAddress,
        address _disputeManagerAddress
    )
        external
        initializer()
    {
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );

        agreementStoreManager = AgreementStoreManager(
            _agreementStoreManagerAddress
        );

        disputeManager = IDisputeManager(
            _disputeManagerAddress
        );
    }

    function changeDisputeManager(address _disputeManagerAddress) external onlyOwner {
        disputeManager = IDisputeManager(
            _disputeManagerAddress
        );
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _origHash is the hash of the key
    * @param _buyer buyer public key
    * @param _provider provider public key
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        uint _origHash,
        uint[2] memory _buyer,
        uint[2] memory _provider
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_origHash, _buyer[0], _buyer[1], _provider[0], _provider[1]));
    }

   /**
    * @notice fulfill key transfer
    * @dev The key with hash _origHash is transferred to the _buyer from _provider.
    * @param _agreementId associated agreement
    * @param _origHash is the hash of data to access
    * @param _buyer buyer public key
    * @param _provider provider public key
    * @param _cipher encrypted version of the key
    * @param _proof SNARK proof that the cipher text can be decrypted by buyer to give the key with hash _origHash 
    * @return condition state (Fulfilled/Aborted)
    */
    function fulfill(
        bytes32 _agreementId,
        uint _origHash,
        uint[2] memory _buyer,
        uint[2] memory _provider,
        uint[2] memory _cipher,
        bytes memory _proof
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        uint[] memory params = new uint[](7);
        params[0] = _buyer[0];
        params[1] = _buyer[1];
        params[2] = _provider[0];
        params[3] = _provider[1];
        params[4] = _cipher[0];
        params[5] = _cipher[1];
        params[6] = _origHash;
        require(disputeManager.verifyProof(_proof, params), 'Cannot verify snark');

        bytes32 _id = generateId(
            _agreementId,
            hashValues(_origHash, _buyer, _provider)
        );

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );

        emit Fulfilled(
            _agreementId,
            _origHash,
            _buyer,
            _provider,
            _cipher,
            _proof,
            _id
        );

        return state;
    }

}

