#!/usr/bin/env bash

rm contracts/verifier.sol

wget https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_14.ptau
wget https://github.com/iden3/circom/releases/download/v2.0.6/circom-linux-amd64

chmod +x circom-linux-amd64
./circom-linux-amd64 circuits/keytransfer.circom --r1cs --wasm --sym

mv keytransfer.r1cs circuits
mv keytransfer.sym circuits
mv keytransfer_js/keytransfer.wasm circuits
yarn run snarkjs plonk setup circuits/keytransfer.r1cs powersOfTau28_hez_final_14.ptau circuits/keytransfer.zkey
yarn run snarkjs zkey export verificationkey circuits/keytransfer.zkey circuits/verification_key.json
yarn run snarkjs zkey export solidityverifier circuits/keytransfer.zkey contracts/verifier.sol

