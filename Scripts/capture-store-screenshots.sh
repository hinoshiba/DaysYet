#!/bin/bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DERIVED_DATA="${REPOSITORY_ROOT}/.build/AppStoreScreenshots"
readonly APP_PATH="${DAYSYET_SCREENSHOT_APP_PATH:-${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/DaysYet.app}"
readonly BUNDLE_ID="com.hinoshiba.daysyet"

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick is required to remove the simulator PNG alpha channel" >&2
  exit 1
fi

device_id() {
  local device_name="$1"
  xcrun simctl list devices available | sed -nE "s/.*${device_name// /[[:space:]]}.*\(([0-9A-F-]{36})\).*/\1/p" | head -n 1
}

readonly IPHONE_ID="${DAYSYET_SCREENSHOT_IPHONE_ID:-$(device_id 'iPhone 17 Pro Max')}"
readonly IPAD_ID="${DAYSYET_SCREENSHOT_IPAD_ID:-$(device_id 'iPad Pro 13-inch')}"

if [[ -z "${IPHONE_ID}" || -z "${IPAD_ID}" ]]; then
  echo "error: iPhone 17 Pro Max and iPad Pro 13-inch simulators are required" >&2
  exit 1
fi

cd "${REPOSITORY_ROOT}"
if [[ -z "${DAYSYET_SCREENSHOT_APP_PATH:-}" ]]; then
  xcodegen generate
  xcodebuild \
    -project DaysYet.xcodeproj \
    -scheme DaysYet \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${DERIVED_DATA}" \
    build
elif [[ ! -d "${APP_PATH}" ]]; then
  echo "error: DAYSYET_SCREENSHOT_APP_PATH does not point to an app bundle" >&2
  exit 1
fi

capture() {
  local simulator_id="$1"
  local locale="$2"
  local apple_locale="$3"
  local output_directory="$4"
  local language_argument="(${locale})"
  local simulator_user_id="501"

  mkdir -p "${output_directory}"
  xcrun simctl boot "${simulator_id}" 2>/dev/null || true
  if [[ "${DAYSYET_SCREENSHOT_SKIP_BOOTSTATUS:-0}" != "1" ]]; then
    xcrun simctl bootstatus "${simulator_id}" -b
  fi
  if [[ "${locale}" == "ja" ]]; then
    xcrun simctl spawn "${simulator_id}" defaults write NSGlobalDomain AppleLanguages -array 'ja-JP' 'en-JP'
  else
    xcrun simctl spawn "${simulator_id}" defaults write NSGlobalDomain AppleLanguages -array 'en-US' 'ja-JP'
  fi
  xcrun simctl spawn "${simulator_id}" defaults write NSGlobalDomain AppleLocale "${apple_locale}"
  xcrun simctl spawn "${simulator_id}" launchctl kickstart -k "user/${simulator_user_id}/com.apple.SpringBoard"
  sleep 10
  xcrun simctl ui "${simulator_id}" appearance light
  xcrun simctl status_bar "${simulator_id}" override \
    --time 9:41 \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --batteryState charged \
    --batteryLevel 100
  xcrun simctl uninstall "${simulator_id}" "${BUNDLE_ID}" 2>/dev/null || true
  xcrun simctl install "${simulator_id}" "${APP_PATH}"

  take_shot() {
    local filename="$1"
    local screenshot_path="${output_directory}/${filename}"
    local flattened_path="${output_directory}/.${filename}"
    shift
    xcrun simctl launch --terminate-running-process "${simulator_id}" "${BUNDLE_ID}" \
      -AppleLanguages "${language_argument}" \
      -AppleLocale "${apple_locale}" \
      --screenshot-mode \
      "$@" >/dev/null
    sleep 2
    xcrun simctl io "${simulator_id}" screenshot --type=png "${screenshot_path}"
    magick "${screenshot_path}" -background black -alpha remove -alpha off "PNG24:${flattened_path}"
    mv "${flattened_path}" "${screenshot_path}"
  }

  take_shot "01-widget-time-left.png"
  take_shot "02-widget-target-date.png" --screenshot-target-date
  take_shot "03-time-library.png" --screenshot-times
  take_shot "04-privacy-settings.png" --screenshot-settings
  xcrun simctl status_bar "${simulator_id}" clear
}

capture "${IPHONE_ID}" ja ja_JP "${REPOSITORY_ROOT}/AppStore/screenshots/ja/iphone-6.9"
capture "${IPHONE_ID}" en en_US "${REPOSITORY_ROOT}/AppStore/screenshots/en-US/iphone-6.9"
capture "${IPAD_ID}" ja ja_JP "${REPOSITORY_ROOT}/AppStore/screenshots/ja/ipad-13"
capture "${IPAD_ID}" en en_US "${REPOSITORY_ROOT}/AppStore/screenshots/en-US/ipad-13"

for simulator_id in "${IPHONE_ID}" "${IPAD_ID}"; do
  simulator_user_id="501"
  xcrun simctl spawn "${simulator_id}" defaults write NSGlobalDomain AppleLanguages -array 'ja-JP' 'en-JP'
  xcrun simctl spawn "${simulator_id}" defaults write NSGlobalDomain AppleLocale 'ja_JP'
  xcrun simctl status_bar "${simulator_id}" clear
  xcrun simctl spawn "${simulator_id}" launchctl kickstart -k "user/${simulator_user_id}/com.apple.SpringBoard"
done
sleep 10

python3 Scripts/validate-store-assets.py --require-screenshots
echo "App Store screenshots captured and validated."
