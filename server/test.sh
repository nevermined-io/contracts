#!/bin/sh

npx hardhat run ./scripts/deploy/deployContractsWrapper.js --network testing

npx hardhat run server/main.js --network testing --no-compile &

sleep 15

curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"coordinate_round1","params":{"ctx":"123"},"id":12}'
curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"coordinate_round2","params":{"ctx":"123"},"id":12}'

sleep 15

npx hardhat run server/setup.js --network testing

sleep 15

curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"listen","params":{},"id":12}' > test1.res.json

diff test1.res.json server/test1.json || exit 1

curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"setup","params":{},"id":12}' > test2.res.json

diff test2.res.json server/test2.json || exit 1

echo "Success"

