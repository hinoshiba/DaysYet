#!/bin/bash
set -euo pipefail

readonly REQUIRED_XCODEGEN_VERSION="2.45.4"
readonly MODE="${1:-build}"

if [[ $# -gt 1 ]]; then
  echo "usage: ./build.sh [project|build|test|mac|test-mac]" >&2
  exit 2
fi
case "${MODE}" in
  project|build|test|mac|test-mac) ;;
  *)
    echo "usage: ./build.sh [project|build|test|mac|test-mac]" >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: XcodeGen ${REQUIRED_XCODEGEN_VERSION} is required" >&2
  exit 1
fi

actual_xcodegen_version="$(xcodegen --version | awk '{print $2}')"
if [[ "${actual_xcodegen_version}" != "${REQUIRED_XCODEGEN_VERSION}" ]]; then
  echo "error: XcodeGen ${REQUIRED_XCODEGEN_VERSION} is required (found ${actual_xcodegen_version})" >&2
  exit 1
fi

xcodegen generate

case "${MODE}" in
  project)
    # Archive and upload are explicit actions in local Xcode Organizer.
    ;;
  build)
    xcodebuild \
      -project DaysYet.xcodeproj \
      -scheme DaysYet \
      -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO \
      build
    ;;
  test)
    daysyet_simulator_id="$(xcrun simctl list devices available | sed -nE 's/.*iPhone.*\(([0-9A-F-]{36})\).*/\1/p' | head -n 1)"
    if [[ -z "${daysyet_simulator_id}" ]]; then
      echo "error: no available iPhone simulator" >&2
      exit 1
    fi
    xcodebuild \
      -project DaysYet.xcodeproj \
      -scheme DaysYet \
      -destination "platform=iOS Simulator,id=${daysyet_simulator_id}" \
      CODE_SIGNING_ALLOWED=NO \
      test
    ;;
  mac)
    xcodebuild \
      -project DaysYet.xcodeproj \
      -scheme DaysYetMac \
      -sdk macosx \
      -destination 'platform=macOS' \
      CODE_SIGNING_ALLOWED=NO \
      build
    ;;
  test-mac)
    xcodebuild \
      -project DaysYet.xcodeproj \
      -scheme DaysYetMac \
      -destination 'platform=macOS' \
      CODE_SIGNING_ALLOWED=NO \
      test
    ;;
esac
