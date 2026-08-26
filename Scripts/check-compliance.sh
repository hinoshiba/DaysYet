#!/bin/bash
set -euo pipefail

readonly MODE="${1:-development}"
readonly ICON_PATH="DaysYet/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
readonly EXPECTED_ICON_SHA256="0e51cbe928a9239a4a58a34986cfbc950250704903f035f42a40d87b8b1a636f"
readonly EXPECTED_SUPPORT_EMAIL="support@hinoshiba.com"
readonly EXPECTED_TEAM_ID="94HVVWXLK3"
readonly EXPECTED_APP_ID="com.hinoshiba.daysyet"
readonly EXPECTED_WIDGET_ID="${EXPECTED_APP_ID}.widget"
readonly EXPECTED_TEST_ID="${EXPECTED_APP_ID}.tests"
readonly EXPECTED_APP_GROUP="group.${EXPECTED_APP_ID}"
readonly EXPECTED_WIDGET_KIND="${EXPECTED_WIDGET_ID}.progress"
readonly EXPECTED_LOCK_SCREEN_WIDGET_KIND="${EXPECTED_WIDGET_ID}.lock-screen"
readonly REVERSED_APP_ID="$(printf '%s.%s.%s' daysyet hinoshiba com)"

required_files=(
  LICENSE NOTICE TRADEMARKS.md THIRD_PARTY_NOTICES.md ASSET_LICENSES.md
  DATA_SOURCES.md PRIVACY.md SECURITY.md CONTRIBUTING.md project.yml
  docs/DEPENDENCY_POLICY.md docs/PRIVACY_DATA_MAP.md docs/RELEASING.md
  AppStore/configuration.yml AppStore/README.md AppStore/review/notes-en.txt
  http_dist/.nojekyll http_dist/index.html http_dist/en/index.html
  Shared/Localizable.xcstrings
  DaysYet/ja.lproj/InfoPlist.strings DaysYet/en.lproj/InfoPlist.strings
  DaysYetWidget/ja.lproj/InfoPlist.strings DaysYetWidget/en.lproj/InfoPlist.strings
  DaysYet/PrivacyInfo.xcprivacy DaysYetWidget/PrivacyInfo.xcprivacy
  DaysYet/DaysYet.entitlements DaysYetWidget/DaysYetWidget.entitlements
  DaysYet.xcodeproj/project.pbxproj
  DaysYet.xcodeproj/xcshareddata/xcschemes/DaysYet.xcscheme
  ci_scripts/ci_pre_xcodebuild.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: missing required file: ${required_file}" >&2
    exit 1
  fi
done

/bin/sh -n ci_scripts/*.sh
for cloud_script in ci_scripts/*.sh; do
  if [[ ! -x "${cloud_script}" ]]; then
    echo "error: Xcode Cloud script is not executable: ${cloud_script}" >&2
    exit 1
  fi
done

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -F -q "${expected}" "${file}"; then
    echo "error: expected value is missing from ${file}: ${expected}" >&2
    exit 1
  fi
}

assert_line() {
  local file="$1"
  local expected="$2"
  if ! awk -v expected="${expected}" '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (line == expected) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "${file}"; then
    echo "error: expected line is missing from ${file}: ${expected}" >&2
    exit 1
  fi
}

allowed_public_docs=(
  docs/DEPENDENCY_POLICY.md
  docs/PRIVACY_DATA_MAP.md
  docs/RELEASING.md
)
while IFS= read -r public_doc; do
  if [[ ! " ${allowed_public_docs[*]} " =~ " ${public_doc} " ]]; then
    echo "error: docs/ is an allowlisted public directory; review before adding: ${public_doc}" >&2
    exit 1
  fi
done < <(find docs -type f | sort)

if /usr/bin/grep -E -i -R -I -q -- \
  '(^|[^[:alnum:]_])(TODO|TBD|FIXME)([^[:alnum:]_]|$)|placeholder|provisional|draft|公開準備中|daysyet\.dev|DaysYet Dev' \
  README.md PRIVACY.md SECURITY.md TRADEMARKS.md docs AppStore http_dist; then
  echo "error: release placeholder or development identity remains in public content" >&2
  exit 1
fi

plutil -lint DaysYet/PrivacyInfo.xcprivacy DaysYetWidget/PrivacyInfo.xcprivacy >/dev/null
for privacy_manifest in DaysYet/PrivacyInfo.xcprivacy DaysYetWidget/PrivacyInfo.xcprivacy; do
  assert_contains "${privacy_manifest}" "NSPrivacyAccessedAPICategoryUserDefaults"
  assert_contains "${privacy_manifest}" "1C8F.1"
done

actual_icon_sha256="$(shasum -a 256 "${ICON_PATH}" | awk '{print $1}')"
if [[ "${actual_icon_sha256}" != "${EXPECTED_ICON_SHA256}" ]]; then
  echo "error: app icon changed; review its rights and update ASSET_LICENSES.md" >&2
  exit 1
fi

if find . -name Package.resolved -o -name Podfile.lock -o -name Cartfile.resolved | grep -q .; then
  echo "error: dependency lockfile detected; update notices, privacy review, and SBOM policy" >&2
  exit 1
fi

assert_contains project.yml 'developmentLanguage: ja'
assert_line project.yml "bundleIdPrefix: ${EXPECTED_APP_ID}"
assert_line project.yml "VERSIONING_SYSTEM: apple-generic"
assert_line project.yml "DEVELOPMENT_TEAM: \"${EXPECTED_TEAM_ID}\""
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_APP_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_WIDGET_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_TEST_ID}"
assert_contains Shared/ProfileRepository.swift "${EXPECTED_APP_GROUP}"
assert_contains DaysYet/DaysYet.entitlements "${EXPECTED_APP_GROUP}"
assert_contains DaysYetWidget/DaysYetWidget.entitlements "${EXPECTED_APP_GROUP}"
assert_contains DaysYetWidget/DaysYetWidget.swift "${EXPECTED_WIDGET_KIND}"
assert_contains DaysYetWidget/DaysYetLockScreenWidget.swift "${EXPECTED_LOCK_SCREEN_WIDGET_KIND}"
assert_line AppStore/configuration.yml "bundle_id: ${EXPECTED_APP_ID}"
assert_line AppStore/configuration.yml "widget_bundle_id: ${EXPECTED_WIDGET_ID}"
assert_line AppStore/configuration.yml "app_group: ${EXPECTED_APP_GROUP}"
assert_line AppStore/configuration.yml "widget_kind: ${EXPECTED_WIDGET_KIND}"
assert_line AppStore/configuration.yml "lock_screen_widget_kind: ${EXPECTED_LOCK_SCREEN_WIDGET_KIND}"

identifier_files=(
  project.yml
  Shared/ProfileRepository.swift
  DaysYet/DaysYet.entitlements
  DaysYetWidget/DaysYetWidget.entitlements
  DaysYetWidget/DaysYetWidget.swift
  DaysYetWidget/DaysYetLockScreenWidget.swift
  AppStore/configuration.yml
  AppStore/review/submission-checklist.md
  Scripts/capture-store-screenshots.sh
)
if /usr/bin/grep -F -q -- "${REVERSED_APP_ID}" "${identifier_files[@]}"; then
  echo "error: reversed app identifier remains in the repository" >&2
  exit 1
fi

public_contact_files=(
  README.md PRIVACY.md SECURITY.md CODE_OF_CONDUCT.md
  docs/RELEASING.md AppStore/README.md AppStore/review/submission-checklist.md
  http_dist/index.html http_dist/en/index.html
)
for public_contact_file in "${public_contact_files[@]}"; do
  assert_contains "${public_contact_file}" "${EXPECTED_SUPPORT_EMAIL}"
done

python3 Scripts/validate-store-assets.py

if [[ "${MODE}" == "--release" ]]; then
  python3 Scripts/validate-store-assets.py --require-screenshots --check-urls
elif [[ "${MODE}" != "development" ]]; then
  echo "usage: ./Scripts/check-compliance.sh [--release]" >&2
  exit 2
fi

echo "Compliance checks passed (${MODE})."
