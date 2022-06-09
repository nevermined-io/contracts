#!/usr/bin/env bash

# Add SPDX (license information) lines
# to all source code files and documentation source files
# in this directory and subdirectories (recursively).
#
# To read about SPDX, see https://spdx.org/
#
# Note that this script might also edit files in your virtualenv,
# but that shouldn't be a problem,
# because Git should be ignoring changes in those files.

# http://redsymbol.net/articles/unofficial-bash-strict-mode/

#cd contracts/
set -euo pipefail
IFS=$'\n\t'

for file in contracts/**/*.sol
do
    echo -e "Adding headers to $file"
    sed -i '2s;^;// Copyright 2022 Nevermined AG.\
\
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)\
// Code is Apache-2.0 and docs are CC-BY-4.0\
;' $file
done
