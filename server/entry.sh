#!/bin/bash

RETRY_COUNT=0
COMMAND_STATUS=1

printf '\n\e[33m◯ Waiting for contracts to be generated...\e[0m\n'

cd /nevermined-contracts

ls ~


until [ $COMMAND_STATUS -eq 0 ] || [ $RETRY_COUNT -eq 120 ]; do
  cat ~/.nevermined/nevermined-contracts/artifacts/ready
  COMMAND_STATUS=$?
  if [ $COMMAND_STATUS -eq 0 ]; then
    break
  fi
  sleep 5
  let RETRY_COUNT=RETRY_COUNT+1
done

cp ~/.nevermined/nevermined-contracts/artifacts/AccessDLEQCondition.*.json frost-contracts.json

echo Ok

npx hardhat run --no-compile --network tools server/main.js &

until curl -H "Content-Type: application/json" -X POST localhost:23451/ready
    do
        sleep 1
    done

echo "Make secret"

# Make the shared secret

curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"coordinate_round1","params":{"ctx":"123"},"id":12}'
sleep 2
curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"coordinate_round2","params":{"ctx":"123"},"id":12}'

sleep 2

curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"setup","params":{},"id":12}'

echo Ready

# Start listening for contract

until false; do
    curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"listen","params":{},"id":12}'
    sleep 10
done

