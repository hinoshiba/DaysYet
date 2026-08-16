#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: ./Scripts/bump-version.sh <marketing-version> <build-number>" >&2
  exit 2
fi

readonly MARKETING_VERSION_VALUE="$1"
readonly BUILD_NUMBER_VALUE="$2"

/usr/bin/perl -0pi -e 's/MARKETING_VERSION: "[^"]+"/MARKETING_VERSION: "'"${MARKETING_VERSION_VALUE}"'"/' project.yml
/usr/bin/perl -0pi -e 's/CURRENT_PROJECT_VERSION: "[^"]+"/CURRENT_PROJECT_VERSION: "'"${BUILD_NUMBER_VALUE}"'"/' project.yml

xcodegen generate
echo "Updated to ${MARKETING_VERSION_VALUE} (${BUILD_NUMBER_VALUE})."
