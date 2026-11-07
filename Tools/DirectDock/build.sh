#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Explicit, unsigned direct-distribution experiment. Normal project builds
# retain their Sandbox configuration and omit the Accessibility controller.
mode="${1:-build}"
case "$mode" in build|test) ;; *) echo 'usage: bash Tools/DirectDock/build.sh [build|test]' >&2; exit 2 ;; esac
configuration=Release
if [[ "$mode" == test ]]; then configuration=Debug; fi
./build.sh project
xcodebuild -project DaysYet.xcodeproj -scheme DaysYetMac \
  -configuration "$configuration" -destination 'platform=macOS' \
  -derivedDataPath /tmp/daysyet-direct-dock \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DAYSYET_DIRECT_DOCK_DRAG DAYSYET_DOCK_NATIVE_REORDER DAYSYET_DOCK_GROUP_GUARD' \
  ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS= CODE_SIGNING_ALLOWED=NO "$mode"
