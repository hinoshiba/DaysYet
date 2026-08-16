#!/bin/sh
set -eu

# Xcode Cloud invokes this script before every action. Only a release Archive
# mutates the temporary checkout's build number.
if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  exit 0
fi

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
  echo "error: release archives must run in Xcode Cloud" >&2
  exit 1
fi

: "${CI_TAG:?Xcode Cloud release archives require a Git tag}"
: "${CI_BUILD_NUMBER:?Xcode Cloud did not provide a build number}"
: "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud did not provide the repository path}"
: "${CI_TEAM_ID:?Xcode Cloud did not provide the Apple Developer Team ID}"
: "${CI_BUNDLE_ID:?Xcode Cloud did not provide the product bundle ID}"
: "${CI_PRODUCT_PLATFORM:?Xcode Cloud did not provide the product platform}"
: "${CI_XCODE_SCHEME:?Xcode Cloud did not provide the Xcode scheme}"

if ! printf '%s\n' "$CI_TAG" | grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
  echo "error: release tag must use vX.Y.Z with numeric components: $CI_TAG" >&2
  exit 1
fi

if ! printf '%s\n' "$CI_BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$'; then
  echo "error: CI_BUILD_NUMBER must be a positive integer" >&2
  exit 1
fi

if [ "$CI_TEAM_ID" != "94HVVWXLK3" ]; then
  echo "error: Xcode Cloud selected unexpected Apple Developer Team: $CI_TEAM_ID" >&2
  exit 1
fi

if [ "$CI_BUNDLE_ID" != "com.hinoshiba.daysyet" ]; then
  echo "error: Xcode Cloud selected unexpected product bundle ID: $CI_BUNDLE_ID" >&2
  exit 1
fi

if [ "$CI_PRODUCT_PLATFORM" != "iOS" ] || [ "$CI_XCODE_SCHEME" != "DaysYet" ]; then
  echo "error: Xcode Cloud selected an unexpected product platform or scheme" >&2
  exit 1
fi

repo=$CI_PRIMARY_REPOSITORY_PATH
release_version=${CI_TAG#v}
configured_version=$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\([^"]*\)"/\1/p' "$repo/project.yml")
store_version=$(sed -n 's/^version: \([^[:space:]]*\)$/\1/p' "$repo/AppStore/configuration.yml")

for info_plist in "$repo/DaysYet/Info.plist" "$repo/DaysYetWidget/Info.plist"; do
  if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" != '$(MARKETING_VERSION)' ] || \
     [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" != '$(CURRENT_PROJECT_VERSION)' ]; then
    echo "error: $info_plist must inherit its version and build from Xcode settings" >&2
    exit 1
  fi
done

if [ "$configured_version" != "$release_version" ]; then
  echo "error: tag $CI_TAG does not match project.yml MARKETING_VERSION $configured_version" >&2
  exit 1
fi

if [ "$store_version" != "$release_version" ]; then
  echo "error: tag $CI_TAG does not match AppStore/configuration.yml version $store_version" >&2
  exit 1
fi

cd "$repo"
project_version=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);$/\1/p' DaysYet.xcodeproj/project.pbxproj | sort -u)
if [ "$project_version" != "$release_version" ]; then
  echo "error: checked-in Xcode project version $project_version does not match tag $CI_TAG" >&2
  exit 1
fi

./Scripts/check-compliance.sh --release

xcrun agvtool new-version -all "$CI_BUILD_NUMBER" >/dev/null
applied_build_number=$(xcrun agvtool what-version -terse | sort -u)
if [ "$applied_build_number" != "$CI_BUILD_NUMBER" ]; then
  echo "error: failed to apply Xcode Cloud build number $CI_BUILD_NUMBER" >&2
  exit 1
fi

echo "Prepared DaysYet $release_version ($CI_BUILD_NUMBER) for Xcode Cloud archive"
