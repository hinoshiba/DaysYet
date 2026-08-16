#!/bin/bash
set -euo pipefail

readonly MODE="${1:-development}"
readonly ICON_PATH="DaysYet/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
readonly EXPECTED_ICON_SHA256="0e51cbe928a9239a4a58a34986cfbc950250704903f035f42a40d87b8b1a636f"

required_files=(
  LICENSE NOTICE TRADEMARKS.md THIRD_PARTY_NOTICES.md ASSET_LICENSES.md
  DATA_SOURCES.md PRIVACY.md SECURITY.md CONTRIBUTING.md project.yml
  docs/DEPENDENCY_POLICY.md docs/PRIVACY_DATA_MAP.md docs/RELEASING.md
  AppStore/configuration.yml AppStore/README.md AppStore/review/notes-en.txt
  http_dist/.nojekyll http_dist/index.html http_dist/en/index.html
  http_dist/privacy/index.html http_dist/en/privacy/index.html
  http_dist/terms/index.html http_dist/en/terms/index.html
  http_dist/support/index.html http_dist/en/support/index.html
  Shared/Localizable.xcstrings
  DaysYet/ja.lproj/InfoPlist.strings DaysYet/en.lproj/InfoPlist.strings
  DaysYetWidget/ja.lproj/InfoPlist.strings DaysYetWidget/en.lproj/InfoPlist.strings
  DaysYet/PrivacyInfo.xcprivacy DaysYetWidget/PrivacyInfo.xcprivacy
  DaysYet/DaysYet.entitlements DaysYetWidget/DaysYetWidget.entitlements
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: missing required file: ${required_file}" >&2
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

if rg -i -q \
  '\b(TODO|TBD|FIXME)\b|placeholder|provisional|draft|公開準備中|daysyet\.dev|DaysYet Dev' \
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
assert_contains project.yml 'PRODUCT_BUNDLE_IDENTIFIER: com.hinoshiba.daysyet'
assert_contains project.yml 'PRODUCT_BUNDLE_IDENTIFIER: com.hinoshiba.daysyet.widget'
assert_contains Shared/ProfileRepository.swift 'group.com.hinoshiba.daysyet'
assert_contains DaysYet/DaysYet.entitlements 'group.com.hinoshiba.daysyet'
assert_contains DaysYetWidget/DaysYetWidget.entitlements 'group.com.hinoshiba.daysyet'
assert_contains DaysYetWidget/DaysYetWidget.swift 'com.hinoshiba.daysyet.widget.progress'

python3 Scripts/validate-store-assets.py

if [[ "${MODE}" == "--release" ]]; then
  python3 Scripts/validate-store-assets.py --require-screenshots --check-urls
  release_environment=(APPLE_TEAM_ID APP_REVIEW_CONTACT_NAME APP_REVIEW_CONTACT_EMAIL APP_REVIEW_CONTACT_PHONE)
  for variable in "${release_environment[@]}"; do
    if [[ -z "${!variable:-}" ]]; then
      echo "error: ${variable} must be set in the private release environment" >&2
      exit 1
    fi
  done
elif [[ "${MODE}" != "development" ]]; then
  echo "usage: ./Scripts/check-compliance.sh [--release]" >&2
  exit 2
fi

echo "Compliance checks passed (${MODE})."
