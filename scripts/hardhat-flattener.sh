#!/usr/bin/env bash

CONTRACTS_FOLDER=contracts
FLATTENED_FOLDER=flattened

mkdir -p $FLATTENED_FOLDER
rm -rf $FLATTENED_FOLDER/*  # We remove in case it was already there

find $CONTRACTS_FOLDER \( -path 'contracts/test' -prune -o -path 'contracts/interfaces' -prune \) -o -name '*.sol' -print | while IFS=$'\n' read -r FILE; do
  FLATTENED_FILE=$FLATTENED_FOLDER/`basename $FILE`
  printf "Processing $FILE into $FLATTENED_FILE\n"
  npx hardhat flatten $FILE >> $FLATTENED_FILE  || echo "error processing: $FILE"
  sed -i '/\/\/ SPDX-License-Identifier.*/d' $FLATTENED_FILE
done

printf "\e[32m✔ Contracts flattened in folder $FLATTENED_FOLDER.\e[0m\n"
