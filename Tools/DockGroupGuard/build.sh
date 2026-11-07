#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Explicit experiment. The existing direct build does not install a Dock
# input filter unless this additional compilation condition is supplied.
mode="${1:-build}"
case "$mode" in build|test) ;; *) echo 'usage: bash Tools/DockGroupGuard/build.sh [build|test]' >&2; exit 2 ;; esac
configuration=Release
if [[ "$mode" == test ]]; then configuration=Debug; fi
./build.sh project
xcodebuild -project DaysYet.xcodeproj -scheme DaysYetMac \
  -configuration "$configuration" -destination 'platform=macOS' \
  -derivedDataPath /tmp/daysyet-dock-group-guard \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DAYSYET_DIRECT_DOCK_DRAG DAYSYET_DOCK_GROUP_GUARD' \
  ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS= CODE_SIGNING_ALLOWED=NO "$mode"
