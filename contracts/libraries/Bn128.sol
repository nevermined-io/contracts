// SPDX-License-Identifier: MIT

// from https://github.com/medusa-network/medusa-contracts/blob/main/src/Bn128.sol
// parts extracted/inspired from https://github.com/keep-network/keep-core/edit/main/solidity/random-beacon/contracts/libraries/AltBn128.sol
pragma solidity ^0.8.0;

// G1Point implements a point in G1 group.

struct G1Point {
    uint256 x;
    uint256 y;
}

struct DleqProof {
    uint256 f;
    uint256 e;
}

/// @title Operations on bn128
/// @dev Implementations of common elliptic curve operations on Ethereum's
///      alt_bn128 curve. Whenever possible, use post-Byzantium
///      pre-compiled contracts to offset gas costs.
library Bn128 {
    using ModUtils for uint256;

    // p is a prime over which we form a basic field
    // Taken from go-ethereum/crypto/bn256/cloudflare/constants.go
    uint256 internal constant p = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @dev Gets generator of G1 group.
    ///      Taken from go-ethereum/crypto/bn256/cloudflare/curve.go
    uint256 internal constant g1x = 1;
    uint256 internal constant g1y = 2;

    //// --------------------
    ////       DLEQ PART
    //// --------------------
    uint256 internal constant base2x = 5671920232091439599101938152932944148754342563866262832106763099907508111378;
    uint256 internal constant base2y = 2648212145371980650762357218546059709774557459353804686023280323276775278879;
    uint256 internal constant r = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

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
            uint256(keccak256(abi.encodePacked(_label, _rg1.x, _rg1.y, _rg2.x, _rg2.y, w1.x, w1.y, w2.x, w2.y))) % r;
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
    function scalarMultiply(G1Point memory p_1, uint256 scalar) internal view returns (G1Point memory p_2) {
        // 0x07     id of the bn256ScalarMul precompile
        // 0        number of ether to transfer
        // 96       size of call parameters, i.e. 96 bytes total (256 bit for x, 256 bit for y, 256 bit for scalar)
        // 64       size of call return value, i.e. 64 bytes / 512 bit for a BN256 curve point
        assembly {
            let arg := mload(0x40)
            mstore(arg, mload(p_1))
            mstore(add(arg, 0x20), mload(add(p_1, 0x20)))
            mstore(add(arg, 0x40), scalar)
            // 0x07 is the ECMUL precompile address
            if iszero(staticcall(not(0), 0x07, arg, 0x60, p_2, 0x40)) { revert(0, 0) }
        }
    }

    /// @dev Wraps the point addition pre-compile introduced in Byzantium.
    ///      Returns the sum of two points on G1. Revert if the provided points
    ///      are not on the curve.
    function g1Add(G1Point memory a, G1Point memory b) internal view returns (G1Point memory c) {
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
        return point.y.modExp(2, p) == (point.x.modExp(3, p) + 3) % p;
    }

    function g1() public pure returns (G1Point memory) {
        return G1Point(g1x, g1y);
    }

}

library ModUtils {
    /// @dev Wraps the modular exponent pre-compile introduced in Byzantium.
    ///      Returns base^exponent mod p.
    function modExp(uint256 base, uint256 exponent, uint256 p) internal view returns (uint256 o) {
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
