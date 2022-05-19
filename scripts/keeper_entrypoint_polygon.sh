#!/bin/sh

echo Starting up

# We need to move the artifacts folder where it is expected and the polygon-sdk
mkdir -p /nevermined-contracts/artifacts
mkdir -p /nevermined-contracts/circuits
cp -rp /artifacts/* /nevermined-contracts/artifacts/
cp -rp /circuits/* /nevermined-contracts/circuits/

cd /polygon-sdk
exec polygon-sdk server "$@"