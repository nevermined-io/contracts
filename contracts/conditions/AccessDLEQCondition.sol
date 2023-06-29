pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';
import '../registry/DIDRegistry.sol';
import '../interfaces/IAccessControl.sol';
import '../agreements/AgreementStoreManager.sol';
import '../conditions/LockPaymentCondition.sol';
import '../conditions/rewards/EscrowPaymentCondition.sol';

struct G1Point {
    uint256 x;
    uint256 y;
}

struct DleqProof {
    uint256 e;
    uint256 f;
}

/**
 * @title Access Condition with DLEQ transfer proof
 * @author Nevermined
 *
 * @dev Implementation of the Access Condition with transfer proof (DLEQ).
 * The idea is that actors are able to share decryption keys, also there are proofs that
 * correct keys have been shared.
 * The system has three actors:
 *  - Network (can be several actors with threshold signature)
 *  - Data provider: encrypts the original data, sends decryption key to network
 *  - Data consumer: gets a decryption key from the network
 *
 * The network has secret y, and public key yG = Y
 *
 * Data provider view
 * - Will first need to generate password (256 bits, or probably a bit less)
 * - The data has to be encrypted and the encrypted data is made publicly available
 * - Then will have to generate a secret key x
 * - Public key xG: identifier for the secret
 * - The shared secret will then be xyG (ecdh)
 * - The password is encrypted with the shared secret (just xor)
 * - The encrypted password and corresponding public key xG are stored by the network
 * - There could be a ZK-SNARK that gives knowledge of the hash of the password, but it depends on the curve if it’s efficient
 * - Data provider can forget the secret key (it shouldn’t be used again)
 * - In theory could forget the password, but probably the network will have to change the key like once in a year, so it will have to be resent
 *
 * Consumer view
 * - First can download the encrypted data
 * - Can get the corresponding encrypted password and xG from network / smart contracts
 * - Will have to generate a secret key z
 * - So the agreement will include xG and yG, also encrypted password and zG
 * - The network will send y(xG+zG) to fulfill the agreement. There will probably have to be some way to send a reward to the network (re-encrytion)
 * - The consumer will get the shared secret by: y(xG+zG) - yzG = xyG
 * - Now the consumer will get the password with xor and can decrypt the downloaded data
 *
 * Correctness guarantees (DLEQ proof that reencryption was correct)
 *
 * Making sure that the network sends the correct result (DLEQ; discrete logarithm equality)
 *
 * DLEQ basic description
 * - Given points G, H
 * - Send points X, Y
 * - DLEQ proves that there exists x such that X = xG and Y = xH
 * - In other words, G/X = H/Y
 * - This is a ZK proof
 *
 * Proving that re-encryption is correct
 * - We have points G and xG+zG
 * - Send points Y, R (Y is the previously known public key Y=yG)
 * - Will prove that R = y(xG+zG)
 * - So just DLEQ is enough to prove the correctness
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
    
    LockPaymentCondition internal lockPaymentCondition;
    AccessDLEQCondition internal accessCondition;
    EscrowPaymentCondition internal rewardCondition;

    event Authorized(uint[2] secret, uint[2] buyer, bytes32 agreementId, bytes32 label);

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
        address _agreementStoreManagerAddress,
        address payable _lock,
        address payable _escrow
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
        lockPaymentCondition = LockPaymentCondition(_lock);
        accessCondition = AccessDLEQCondition(address(this)) ;
        rewardCondition = EscrowPaymentCondition(_escrow);
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
    * @dev The key with hash _origHash is transferred to the _buyer from _provider. See the decription of the class for more details.
    * 
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

        G1Point memory _rebase = g1Add(g1p(_buyer), g1p(_secretId));
        // check the dleq proof
        require(dleqverify(g1(), _rebase, g1p(_provider), g1p(_reencrypt), DleqProof(_proof[0], _proof[1]), _id), 'Proof failed');

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

    ///////////////////////////////////////////////////////////////////////////////////////

    // Manager for re-encryptions

    struct Params {
        bytes32 _agreementId;
        uint _cipher;
        uint[2] _secretId;
        uint[2] _provider;
        uint[2] _buyer;
    }

    // secret x buyer public key
    mapping (bytes32 => mapping(bytes32 => bool)) public authorized;
    mapping (bytes32 => Params) public authorizedParams;

    mapping (bytes32 => SecretPrice[]) public prices;

    uint[2] public network;

    // secret has owner
    mapping (bytes32 => address) public secretOwner;

    event AddSecret(bytes32 indexed h, uint[2] secretId);

    struct SecretPrice {
        uint num;
        address token;
        uint tokenType;
    }

   /**
    * @notice Set network public key
    * 
    * @param point Public key (bn256 curve point)
    */
    function setNetworkPublicKey(uint[2] memory point) public onlyOwner {
        network = point;
    }

   /**
    * @notice Hash bn256 point to get an ID
    * 
    * @param point Bn256 curve point
    */
    function pointId(uint[2] memory point) public pure returns (bytes32) {
        return keccak256(abi.encode(point));
    }

   /**
    * @notice Add a secret to the contract. The sendre will be it's owner.
    * 
    * @param point Public key for the secret
    */
    function addSecret(uint[2] memory point) public {
        bytes32 h = keccak256(abi.encode(point));
        require(secretOwner[h] == address(0), 'Secret exists');
        secretOwner[h] = _msgSender();
        emit AddSecret(h, point);
    }

   /**
    * @notice Add price information for a secret
    * 
    * @param id ID for the secret
    * @param price Price that will be accepted for the secret
    * @param token Price token
    * @param tokenType Token type, currently ERC-20
    */
    function addPrice(bytes32 id, uint price, address token, uint tokenType) public {
        require(secretOwner[id] == _msgSender(), 'Not secret owner');
        prices[id].push(SecretPrice(price, token, tokenType));
    }

   /**
    * @notice fulfill key transfer (by network)
    * 
    * @param agreementId associated agreement
    * @param reencrypt Re-encryption key from provider to buyer
    * @param proof DLEQ proof of correctness
    */
    function fulfillFromNetwork(bytes32 agreementId, uint[2] memory reencrypt, uint[2] memory proof) public {
        Params memory p = authorizedParams[agreementId];
        this.fulfill(agreementId, p._cipher, p._secretId, network, p._buyer, reencrypt, proof);
    }

    function auth(
        uint secretId1,
        uint secretId2,
        bytes[] memory _params,
        bytes32[2] memory id
    ) internal {
        uint buyer1;
        uint buyer2;
        uint p1;
        uint p2;
        uint cipher;
        (cipher, secretId1, secretId2, p1, p2, buyer1, buyer2) = abi.decode(_params[0], (uint,uint,uint,uint,uint,uint,uint));
        require(p1 == network[0] && p2 == network[1], 'not correct network');


        uint[2] memory arr1 = [secretId1,secretId2];
        uint[2] memory arr2 = [buyer1,buyer2];
        authorized[keccak256(abi.encode(arr1))][keccak256(abi.encode(arr2))] = true;
        authorizedParams[id[0]] = Params(id[0], cipher, arr1, [p1, p2], arr2);
        emit Authorized(arr1, arr2, id[0], id[1]);
    }

   /**
    * @notice Validate agreement for fulfillment by network
    * 
    * @param id Agreement Id
    * @param _params Params fot the agreement
    * @param priceIdx Price index to use
    */
    function authorizeAccessTemplate(bytes32 id, bytes[] memory _params, uint priceIdx) public {
        uint secretId1;
        uint secretId2;
        (, secretId1, secretId2, , , , ) = abi.decode(_params[0], (uint,uint,uint,uint,uint,uint,uint));
        bytes32[] memory conditionIds = new bytes32[](3);
        for (uint i = 0; i < 3; i++) {
            conditionIds[i] = keccak256(_params[i]);
        }
        bytes32 lockConditionId = keccak256(abi.encode(id, address(lockPaymentCondition), conditionIds[1]));
        bytes32 accessId = keccak256(abi.encode(id, address(accessCondition), conditionIds[0]));
        bytes32 sid = keccak256(abi.encode([secretId1, secretId2]));

        checkParamsLock(_params, sid, priceIdx);


        // need to check that has correct payment
        checkParamsEscrow(_params, lockConditionId, accessId);

        // check that lock condition is fulfilled
        require(conditionStoreManager.getConditionState(lockConditionId) == ConditionStoreLibrary.ConditionState.Fulfilled, 'lock condition not fulfilled');

        auth(secretId1, secretId2, _params, [id, accessId]);
    }

    function checkParamsLock(bytes[] memory _params, bytes32 sid, uint priceIdx) internal view {
        bytes32 _did;
        address _rewardAddress;
        address _tokenAddress;
        uint256[] memory _amounts;
        address[] memory _receivers;
        (_did, _rewardAddress, _tokenAddress, _amounts, _receivers) = abi.decode(_params[1], (bytes32, address, address, uint256[], address[]));
        SecretPrice memory price = prices[sid][priceIdx];
        require(price.tokenType == 20, 'erc-20 token required');
        require(_amounts[0] >= price.num, 'amount too small');
        require(_tokenAddress == price.token, 'wrong token');
        require(_receivers[0] == secretOwner[sid], 'owner not first receiver');
    }

    function checkParamsEscrow(bytes[] memory _params, bytes32 lockPaymentId, bytes32 transferId) internal pure {
        bytes32 _did0;
        address payable _rewardAddress;
        address _tokenAddress;
        uint256[] memory _amounts;
        address[] memory _receivers;
        (_did0, _rewardAddress, _tokenAddress, _amounts, _receivers) = abi.decode(_params[1], (bytes32, address, address, uint256[], address[]));

        bytes32 _did2;
        uint256[] memory _amounts2;
        address[] memory _receivers2;
        // address _returnAddress;
        address _lockPaymentAddress;
        address _tokenAddress2;
        bytes32 _lockCondition;
        bytes32[] memory _releaseConditions;
        (
            _did2,
            _amounts2,
            _receivers2,
            ,// _returnAddress,
            _lockPaymentAddress, 
            _tokenAddress2,
            _lockCondition,
            _releaseConditions
        ) = abi.decode(_params[2], (bytes32, uint256[], address[], address, address, address, bytes32, bytes32[]));

        require(_lockCondition == lockPaymentId, 'lock mismatch 2');
        require(_releaseConditions.length == 1, 'bad release condition');
        require(keccak256(abi.encode(_did0, _tokenAddress, _amounts, _receivers)) == keccak256(abi.encode(_did2, _tokenAddress2, _amounts2, _receivers2)), 'escrow mismatch');
        require(_releaseConditions[0] == transferId, 'tranfer mismatch');
    } 

    ///////////////////////////////////////////////////////////////////////////////////////

   /** 
    * @notice g1p Convert array to point.
    * @param p array [x,y]
    */
    function g1p(uint[2] memory p) internal pure returns (G1Point memory) {
        return G1Point(p[0], p[1]);
    }

    // p is a prime over which we form a basic field
    // Taken from go-ethereum/crypto/bn256/cloudflare/constants.go
    uint256 internal constant P = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @dev Gets generator of G1 group.
    ///      Taken from go-ethereum/crypto/bn256/cloudflare/curve.go
    uint256 internal constant G1X = 1;
    uint256 internal constant G1Y = 2;

    //// --------------------
    ////       DLEQ PART
    //// --------------------
    uint256 internal constant R = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

   /** 
    * @notice dleqverify verify DLEQ proof
    * @dev The key with hash _origHash is transferred to the _buyer from _provider. See the decription of the class for more details.
    * 
    * @param _g1 First base point
    * @param _g2 Second base point
    * @param _rg1 First base point multiplied by the secret
    * @param _rg2 Second base point multiplied by the secret
    * @param _label Identifier for the proof (added to transcript)
    * @return true if the proof was correct
     */
    function dleqverify(
        G1Point memory _g1,
        G1Point memory _g2,
        G1Point memory _rg1,
        G1Point memory _rg2,
        DleqProof memory _proof,
        bytes32 _label
    )
        internal
        view
        returns (
            bool
        )
    {
        // w1 = f*G1 + rG1 * e
        G1Point memory w1 = g1Add(scalarMultiply(_g1, _proof.f), scalarMultiply(_rg1, _proof.e));
        // w2 = f*G2 + rG2 * e
        G1Point memory w2 = g1Add(scalarMultiply(_g2, _proof.f), scalarMultiply(_rg2, _proof.e));
        uint256 challenge =
            uint256(keccak256(abi.encodePacked(_label, _rg1.x, _rg1.y, _rg2.x, _rg2.y, w1.x, w1.y, w2.x, w2.y))) % R;
        if (challenge == _proof.e) {
            return true;
        }
        return false;
    }

    /** @dev Wraps the scalar point multiplication pre-compile introduced in
     *      Byzantium. The result of a point from G1 multiplied by a scalar
     *      should match the point added to itself the same number of times.
     *      Revert if the provided point isn't on the curve.
     */
    function scalarMultiply(G1Point memory p1, uint256 scalar) internal view returns (G1Point memory p2) {
        // 0x07     id of the bn256ScalarMul precompile
        // 0        number of ether to transfer
        // 96       size of call parameters, i.e. 96 bytes total (256 bit for x, 256 bit for y, 256 bit for scalar)
        // 64       size of call return value, i.e. 64 bytes / 512 bit for a BN256 curve point
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let arg := mload(0x40)
            mstore(arg, mload(p1))
            mstore(add(arg, 0x20), mload(add(p1, 0x20)))
            mstore(add(arg, 0x40), scalar)
            // 0x07 is the ECMUL precompile address
            if iszero(staticcall(not(0), 0x07, arg, 0x60, p2, 0x40)) { revert(0, 0) }
        }
    }

    /* @dev Wraps the point addition pre-compile introduced in Byzantium.
     *      Returns the sum of two points on G1. Revert if the provided points
     *      are not on the curve.
     */
    function g1Add(G1Point memory a, G1Point memory b) internal view returns (G1Point memory c) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let arg := mload(0x40)
            mstore(arg, mload(a))
            mstore(add(arg, 0x20), mload(add(a, 0x20)))
            mstore(add(arg, 0x40), mload(b))
            mstore(add(arg, 0x60), mload(add(b, 0x20)))
            // 0x60 is the ECADD precompile address
            if iszero(staticcall(not(0), 0x06, arg, 0x80, c, 0x40)) { revert(0, 0) }
        }
    }

    /** @dev Returns true if G1 point is on the curve. */
    function isG1PointOnCurve(G1Point memory point) internal view returns (bool) {
        return modExp(point.y, 2, P) == (modExp(point.x, 3, P) + 3) % P;
    }

    /** @dev Returns the base point. */
    function g1() public pure returns (G1Point memory) {
        return G1Point(G1X, G1Y);
    }

    /** @dev Wraps the modular exponent pre-compile introduced in Byzantium.
     *     Returns base^exponent mod p.
     */
    function modExp(uint256 base, uint256 exponent, uint256 p) internal view returns (uint256 o) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Args for the precompile: [<length_of_BASE> <length_of_EXPONENT>
            // <length_of_MODULUS> <BASE> <EXPONENT> <MODULUS>]
            let output := mload(0x40)
            let args := add(output, 0x20)
            mstore(args, 0x20)
            mstore(add(args, 0x20), 0x20)
            mstore(add(args, 0x40), 0x20)
            mstore(add(args, 0x60), base)
            mstore(add(args, 0x80), exponent)
            mstore(add(args, 0xa0), p)

            // 0x05 is the modular exponent contract address
            if iszero(staticcall(not(0), 0x05, args, 0xc0, output, 0x20)) { revert(0, 0) }
            o := mload(output)
        }
    }


}

