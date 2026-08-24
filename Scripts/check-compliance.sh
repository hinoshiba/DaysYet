#!/bin/bash
set -euo pipefail

readonly MODE="${1:-development}"
readonly ICON_PATH="DaysYet/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
readonly EXPECTED_ICON_SHA256="0e51cbe928a9239a4a58a34986cfbc950250704903f035f42a40d87b8b1a636f"
readonly EXPECTED_SUPPORT_EMAIL="support@hinoshiba.com"
readonly EXPECTED_BUNDLE_ID_PREFIX="com.hinoshiba"
readonly EXPECTED_APP_BUNDLE_ID="${EXPECTED_BUNDLE_ID_PREFIX}.daysyet"
readonly EXPECTED_WIDGET_BUNDLE_ID="${EXPECTED_APP_BUNDLE_ID}.widget"
readonly EXPECTED_TEST_BUNDLE_ID="${EXPECTED_APP_BUNDLE_ID}.tests"
readonly EXPECTED_APP_GROUP="group.${EXPECTED_APP_BUNDLE_ID}"
readonly EXPECTED_WIDGET_KIND="${EXPECTED_WIDGET_BUNDLE_ID}.progress"
readonly REJECTED_APP_FIRST_ID="$(printf '%s.%s.%s' daysyet hinoshiba com)"

required_files=(
  LICENSE NOTICE TRADEMARKS.md THIRD_PARTY_NOTICES.md ASSET_LICENSES.md
  AGENTS.md .gitignore build.sh DATA_SOURCES.md PRIVACY.md SECURITY.md
  CONTRIBUTING.md project.yml .github/PULL_REQUEST_TEMPLATE.md
  docs/DEPENDENCY_POLICY.md docs/PRIVACY_DATA_MAP.md docs/RELEASING.md
  AppStore/configuration.yml AppStore/README.md AppStore/review/notes-en.txt
  http_dist/.nojekyll http_dist/index.html http_dist/en/index.html
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

signing_ignore_patterns=(
  '*.mobileprovision' '*.provisionprofile' '*.cer' '*.crt' '*.der'
  '*.p12' '*.pkcs12' '*.pfx' '*.p8' '*.p7b' '*.p7c' '*.pem' '*.key'
  '*.csr' '*.certSigningRequest' '*.keychain' '*.keychain-db'
  '*.developerprofile' 'ExportOptions*.plist' '*.app' '*.pkg' '*.dmg'
  '/.signing-private/' '/.release-private/' '/signing/' '/certificates/'
  '/provisioning/' '/secrets/' '/private-release/' '/release-export/'
)
for signing_ignore_pattern in "${signing_ignore_patterns[@]}"; do
  assert_line .gitignore "${signing_ignore_pattern}"
done

readonly FORBIDDEN_SIGNING_PATH_PATTERN='(^|/)(\.signing-private|\.release-private|signing|certificates|provisioning|secrets|private-release|release-export)(/|$)|(^|/)ExportOptions[^/]*\.plist$|(^|/)[^/]+\.(app|xcarchive|dSYM)(/|$)|\.(cer|crt|der|p12|pkcs12|pfx|p8|p7b|p7c|pem|key|csr|certSigningRequest|keychain|keychain-db|developerprofile|mobileprovision|provisionprofile|ipa|pkg|dmg|xcresult)$'
tracked_signing_artifacts="$(git ls-files | rg -i "${FORBIDDEN_SIGNING_PATH_PATTERN}" || true)"
if [[ -n "${tracked_signing_artifacts}" ]]; then
  echo "error: tracked signing or private release material is forbidden:" >&2
  echo "${tracked_signing_artifacts}" >&2
  exit 1
fi

tracked_private_keys="$(git grep -I -n -E -- '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----' -- . ':(exclude)Scripts/check-compliance.sh' || true)"
if [[ -n "${tracked_private_keys}" ]]; then
  echo "error: tracked private-key material is forbidden" >&2
  exit 1
fi

tracked_identity_output="$(git grep -I -n -E -- '^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-Fa-f]{40}[[:space:]]+\"[^\"]+\"' -- . || true)"
if [[ -n "${tracked_identity_output}" ]]; then
  echo "error: signing-identity discovery output is forbidden" >&2
  exit 1
fi

assert_contains AGENTS.md "reuse the Team's approved existing distribution signing identity"
assert_contains AGENTS.md 'outside this checkout'
assert_contains AGENTS.md 'Public CI must build without signing'
assert_contains build.sh 'CODE_SIGNING_ALLOWED=NO'
if rg -q '^[[:space:]]*(DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER):' project.yml; then
  echo "error: signing identity and Team selection must remain outside project.yml" >&2
  exit 1
fi

assert_contains project.yml 'developmentLanguage: ja'
assert_line project.yml "bundleIdPrefix: ${EXPECTED_BUNDLE_ID_PREFIX}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_APP_BUNDLE_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_WIDGET_BUNDLE_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_TEST_BUNDLE_ID}"
assert_contains Shared/ProfileRepository.swift "${EXPECTED_APP_GROUP}"
assert_contains DaysYet/DaysYet.entitlements "${EXPECTED_APP_GROUP}"
assert_contains DaysYetWidget/DaysYetWidget.entitlements "${EXPECTED_APP_GROUP}"
assert_contains DaysYetWidget/DaysYetWidget.swift "${EXPECTED_WIDGET_KIND}"
assert_line Scripts/capture-store-screenshots.sh "readonly BUNDLE_ID=\"${EXPECTED_APP_BUNDLE_ID}\""
assert_line AppStore/configuration.yml "bundle_id: ${EXPECTED_APP_BUNDLE_ID}"
assert_line AppStore/configuration.yml "widget_bundle_id: ${EXPECTED_WIDGET_BUNDLE_ID}"
assert_line AppStore/configuration.yml "app_group: ${EXPECTED_APP_GROUP}"
assert_line AppStore/configuration.yml "widget_kind: ${EXPECTED_WIDGET_KIND}"

identifier_source_files=(
  project.yml AppStore/configuration.yml AppStore/review/submission-checklist.md
  DaysYet/DaysYet.entitlements DaysYetWidget/DaysYetWidget.entitlements
  Shared/ProfileRepository.swift DaysYetWidget/DaysYetWidget.swift
  Scripts/capture-store-screenshots.sh
)
if rg -F -q "${REJECTED_APP_FIRST_ID}" "${identifier_source_files[@]}"; then
  echo "error: app-first identifier remains in an identifier source" >&2
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
  release_environment=(APPLE_TEAM_ID APP_REVIEW_CONTACT_NAME APP_REVIEW_CONTACT_EMAIL APP_REVIEW_CONTACT_PHONE)
  for variable in "${release_environment[@]}"; do
    if [[ -z "${!variable:-}" ]]; then
      echo "error: ${variable} must be set in the private release environment" >&2
      exit 1
    fi
  done
  if [[ "${APP_REVIEW_CONTACT_EMAIL}" != "${EXPECTED_SUPPORT_EMAIL}" ]]; then
    echo "error: APP_REVIEW_CONTACT_EMAIL must be ${EXPECTED_SUPPORT_EMAIL}" >&2
    exit 1
  fi
elif [[ "${MODE}" != "development" ]]; then
  echo "usage: ./Scripts/check-compliance.sh [--release]" >&2
  exit 2
fi

echo "Compliance checks passed (${MODE})."
