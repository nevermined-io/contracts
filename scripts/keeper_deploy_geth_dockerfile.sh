#!/bin/bash

set -em

# default to false in case it is not set
DEPLOY_CONTRACTS="${DEPLOY_CONTRACTS:-false}"

echo "deploy contracts is ${DEPLOY_CONTRACTS}"

if [ "${DEPLOY_CONTRACTS}" = "true" ]
then
    geth --dev --http --datadir /chain-data &

    until curl --data '{"method":"web3_clientVersion","params":[],"id":1,"jsonrpc":"2.0"}' -H "Content-Type: application/json" -X POST localhost:8545
    do
        sleep 1
    done

    # remove ready flag if we deploy contracts
    rm -f /nevermined-contracts/artifacts/*

    cd /nevermined-contracts
    yarn clean
    yarn compile

    npx hardhat run scripts/setup-geth.js --network geth-setup

    yarn deploy:geth-localnet

    # set flag to indicate contracts are ready
    touch /nevermined-contracts/artifacts/ready
fi

# Fix file permissions
EXECUTION_UID=$(id -u)
EXECUTION_GID=$(id -g)
USER_ID=${LOCAL_USER_ID:-$EXECUTION_UID}
GROUP_ID=${LOCAL_GROUP_ID:-$EXECUTION_GID}
chown -R $USER_ID:$GROUP_ID /nevermined-contracts/artifacts
chown -R $USER_ID:$GROUP_ID /nevermined-contracts/circuits

# We move the artifact directory as this path will be mounted in dockercompose
mv /nevermined-contracts/artifacts /artifacts
mv /nevermined-contracts/circuits /circuits
rm -rf /nevermined-contracts

killall geth
sleep 5
