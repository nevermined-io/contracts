#!/usr/bin/env bash

FLATTENED_FOLDER=flattened
REPORT_FILE=mythrilReport.txt
TIMEOUT=30

rm -f $REPORT_FILE

for CONTRACT in $FLATTENED_FOLDER/*.sol; do
  printf "Processing $CONTRACT\n"
  myth a $CONTRACT -o markdown --execution-timeout $TIMEOUT -t 5 2>> $REPORT_FILE
done

printf "\e[32m✔ Mythril analysis done, report file created: $REPORT_FILE.\e[0m\n"
