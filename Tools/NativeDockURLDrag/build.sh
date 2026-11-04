#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mode="${1:-build}"
case "$mode" in build|test) ;; *) echo 'usage: bash Tools/NativeDockURLDrag/build.sh [build|test]' >&2; exit 2 ;; esac

# Build disposable URL payloads only. Do not launch the old containing probe:
# its historical cleanup restarts Dock and is not used by this experiment.
bash Tools/DockGroupMoveProbe/build.sh /tmp/daysyet-native-url-fixtures
configuration=Release
if [[ "$mode" == test ]]; then configuration=Debug; fi
daysyet_url_probe_derived="${DAYSYET_URL_PROBE_DERIVED_DATA:-/tmp/daysyet-direct-dock}"
./build.sh project
xcodebuild -project DaysYet.xcodeproj -scheme DaysYetMac \
  -configuration "$configuration" -destination 'platform=macOS' \
  -derivedDataPath "$daysyet_url_probe_derived" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DAYSYET_DIRECT_DOCK_DRAG DAYSYET_DOCK_NATIVE_REORDER DAYSYET_DOCK_REORDER_PROBE DAYSYET_DOCK_GROUP_GUARD' \
  ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS= CODE_SIGNING_ALLOWED=NO "$mode"
