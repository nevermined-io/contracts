pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';
import '../registry/DIDRegistry.sol';
import '../interfaces/IAccessControl.sol';
import '../agreements/AgreementStoreManager.sol';
import '../libraries/Bn128.sol';

/**
 * @title Access Condition with DLEQ transfer proof
 * @author Nevermined
 *
 * @dev Implementation of the Access Condition with transfer proof (DLEQ).
 * 
 */
contract AccessDLEQCondition is Condition {

    bytes32 constant public CONDITION_TYPE = keccak256('AccessDLEQCondition');

    AgreementStoreManager private agreementStoreManager;

    event Fulfilled(
        bytes32 indexed _agreementId,
        uint _cipher,
        uint[2] _secretId,
        uint[2] _buyer,
        uint[2] _provider,
        uint[2] _reencrypt,
        uint[2] _proof,
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
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _agreementStoreManagerAddress
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
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _cipher is the encrypted key
    * @param _buyer buyer public key
    * @param _provider provider public key
    * @param _secretId public key for the secret used in encryption
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        uint _cipher,
        uint[2] memory _secretId,
        uint[2] memory _provider,
        uint[2] memory _buyer
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_cipher, _secretId[0], _secretId[1], _provider[0], _provider[1], _buyer[0], _buyer[1]));
    }

   /**
    * @notice fulfill key transfer
    * @dev The key with hash _origHash is transferred to the _buyer from _provider.
    * @param _agreementId associated agreement
    * @param _buyer buyer public key
    * @param _provider provider public key
    * @param _cipher encrypted version of the key
    * @param _reencrypt Re-encryption key from provider to buyer
    * @param _proof DLEQ proof of correctness
    * @return condition state (Fulfilled/Aborted)
    */
    function fulfill(
        bytes32 _agreementId,
        uint _cipher,
        uint[2] memory _secretId,
        uint[2] memory _provider,
        uint[2] memory _buyer,
        uint[2] memory _reencrypt,
        uint[2] memory _proof
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_cipher, _secretId, _provider, _buyer)
        );


        G1Point memory _rebase = Bn128.g1Add(g1p(_buyer), g1p(_secretId));
        // check the dleq proof
        require(Bn128.dleqverify(Bn128.g1(), _rebase, g1p(_provider), g1p(_reencrypt), DleqProof(_proof[0], _proof[1]), _id), 'Proof failed');

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );

        emit Fulfilled(
            _agreementId,
            _cipher,
            _secretId,
            _buyer,
            _provider,
            _reencrypt,
            _proof,
            _id
        );

        return state;
    }

    function g1p(uint[2] memory p) internal pure returns (G1Point memory) {
        return G1Point(p[0], p[1]);
    }

}

