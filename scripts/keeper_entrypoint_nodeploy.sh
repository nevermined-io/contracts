#!/bin/sh

# We need to move the artifacts folder where it is expected and start openethereum
mkdir -p /nevermined-contracts/artifacts
mkdir -p /nevermined-contracts/circuits
cp -rp /artifacts/* /nevermined-contracts/artifacts/
cp -rp /circuits/* /nevermined-contracts/circuits/

exec /home/openethereum/openethereum "$@"
