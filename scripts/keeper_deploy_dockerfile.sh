#!/bin/bash

set -em

# default to false in case it is not set
DEPLOY_CONTRACTS="${DEPLOY_CONTRACTS:-false}"

echo "deploy contracts is ${DEPLOY_CONTRACTS}"

if [ "${DEPLOY_CONTRACTS}" = "true" ]
then
    /home/openethereum/openethereum \
      --config /home/openethereum/config/config.toml \
      --db-path /home/openethereum/chains \
      --keys-path /home/openethereum/.local/keys \
      --base-path /home/openethereum/base \
      --min-gas-price 0 \
      --jsonrpc-cors all \
      --jsonrpc-interface all \
      --jsonrpc-hosts all \
      --jsonrpc-apis all \
      --unsafe-expose \
      --no-warp \
      --unlock 0x00bd138abd70e2f00903268f3db08f2d25677c9e \
      --node-key 0xb3244c104fb56d28d3979f6cd14a8b5cf5b109171d293f4454c97c173a9f9374 &

    until curl --data '{"method":"web3_clientVersion","params":[],"id":1,"jsonrpc":"2.0"}' -H "Content-Type: application/json" -X POST localhost:8545
    do
        sleep 1
    done

    # remove ready flag if we deploy contracts
    rm -rf /nevermined-contracts/artifacts/*

    yarn run clean
    yarn run compile
    export NETWORK="${NETWORK_NAME:-development}"




    yarn run deploy:${NETWORK}

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
mv /nevermined-contracts/artifacts /nevermined-contracts/artifacts2
mv /nevermined-contracts/circuits /nevermined-contracts/circuits2

