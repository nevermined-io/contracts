#!/bin/sh

curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"coordinate_round1","params":{"ctx":"123"},"id":12}'
curl http://localhost:23451/json-rpc -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"coordinate_round2","params":{"ctx":"123"},"id":12}'

