#!/bin/sh

# We need to move the artifacts folder where it is expected and start openethereum
cp -rp /nevermined-contracts/artifacts2/* /nevermined-contracts/artifacts/
cp -rp /nevermined-contracts/circuits2/* /nevermined-contracts/circuits/

exec /home/openethereum/openethereum "$@"
