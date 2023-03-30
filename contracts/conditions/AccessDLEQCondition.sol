pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';
import '../registry/DIDRegistry.sol';
import '../interfaces/IAccessControl.sol';
import '../agreements/AgreementStoreManager.sol';
// import '../libraries/Bn128.sol';

struct G1Point {
    uint256 x;
    uint256 y;
}

struct DleqProof {
    uint256 f;
    uint256 e;
}

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

    function g1Zero() internal pure returns (G1Point memory) {
        return G1Point(0, 0);
    }

    /// @dev Wraps the scalar point multiplication pre-compile introduced in
    ///      Byzantium. The result of a point from G1 multiplied by a scalar
    ///      should match the point added to itself the same number of times.
    ///      Revert if the provided point isn't on the curve.
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

    /// @dev Wraps the point addition pre-compile introduced in Byzantium.
    ///      Returns the sum of two points on G1. Revert if the provided points
    ///      are not on the curve.
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

    /// @dev Returns true if G1 point is on the curve.
    function isG1PointOnCurve(G1Point memory point) internal view returns (bool) {
        return modExp(point.y, 2, P) == (modExp(point.x, 3, P) + 3) % P;
    }

    function g1() public pure returns (G1Point memory) {
        return G1Point(G1X, G1Y);
    }

    /// @dev Wraps the modular exponent pre-compile introduced in Byzantium.
    ///      Returns base^exponent mod p.
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

