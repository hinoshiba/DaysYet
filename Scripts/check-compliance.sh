#!/bin/bash
set -euo pipefail

readonly MODE="${1:-development}"
cd "$(dirname "$0")/.."
readonly ICON_PATH="DaysYet/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
readonly EXPECTED_ICON_SHA256="0e51cbe928a9239a4a58a34986cfbc950250704903f035f42a40d87b8b1a636f"
readonly EXPECTED_MAC_ICON_SHA256="e7b925a0b098adfacd92ba772ce0dc175567cd8166f3b633cd4ad95db28e7a98"
readonly EXPECTED_SUPPORT_EMAIL="support@hinoshiba.com"
readonly EXPECTED_APP_ID="com.hinoshiba.daysyet"
readonly EXPECTED_WIDGET_ID="${EXPECTED_APP_ID}.widget"
readonly EXPECTED_TEST_ID="${EXPECTED_APP_ID}.tests"
readonly EXPECTED_MAC_APP_ID="${EXPECTED_APP_ID}"
readonly EXPECTED_MAC_TEST_ID="${EXPECTED_APP_ID}.mac.tests"
readonly EXPECTED_APP_GROUP="group.${EXPECTED_APP_ID}"
readonly EXPECTED_WIDGET_KIND="${EXPECTED_WIDGET_ID}.progress"
readonly EXPECTED_LOCK_SCREEN_WIDGET_KIND="${EXPECTED_WIDGET_ID}.lock-screen"
readonly REVERSED_APP_ID="$(printf '%s.%s.%s' daysyet hinoshiba com)"

required_files=(
  LICENSE NOTICE TRADEMARKS.md THIRD_PARTY_NOTICES.md ASSET_LICENSES.md
  DATA_SOURCES.md PRIVACY.md SECURITY.md CONTRIBUTING.md project.yml
  docs/DEPENDENCY_POLICY.md docs/PRIVACY_DATA_MAP.md docs/RELEASING.md
  AppStore/configuration.yml AppStore/README.md AppStore/review/notes-en.txt
  AppStore/macos/configuration.yml
  http_dist/.nojekyll http_dist/index.html http_dist/en/index.html
  Shared/Localizable.xcstrings
  DaysYet/ja.lproj/InfoPlist.strings DaysYet/en.lproj/InfoPlist.strings
  DaysYetWidget/ja.lproj/InfoPlist.strings DaysYetWidget/en.lproj/InfoPlist.strings
  DaysYet/PrivacyInfo.xcprivacy DaysYetWidget/PrivacyInfo.xcprivacy
  DaysYet/DaysYet.entitlements DaysYetWidget/DaysYetWidget.entitlements
  DaysYetMac/Info.plist DaysYetMac/DaysYetMac.entitlements
  DaysYetMac/PrivacyInfo.xcprivacy
  DaysYetMac/ja.lproj/InfoPlist.strings DaysYetMac/en.lproj/InfoPlist.strings
  DaysYetMac/Assets.xcassets/MacAppIcon.appiconset/Contents.json
  DaysYet.xcodeproj/project.pbxproj
  DaysYet.xcodeproj/xcshareddata/xcschemes/DaysYet.xcscheme
  DaysYet.xcodeproj/xcshareddata/xcschemes/DaysYetMac.xcscheme
  Config/Signing.xcconfig Config/Signing.local.xcconfig.example
  Scripts/check-public-files.py
  .githooks/pre-commit
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: missing required file: ${required_file}" >&2
    exit 1
  fi
done

python3 Scripts/check-public-files.py

bash -n build.sh Scripts/*.sh
/bin/sh -n .githooks/pre-commit
if [[ ! -x .githooks/pre-commit ]]; then
  echo "error: public-file pre-commit hook must be executable" >&2
  exit 1
fi

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
  docs/STUDY_DAYS.md
  docs/screenshots/study-days/ios-en-calendar.png
  docs/screenshots/study-days/ios-ja-calendar.png
  docs/screenshots/study-days/ios-ja-overview.png
  docs/screenshots/study-days/ios-widget-preview-ja.png
  docs/screenshots/study-days/ipad-ja.png
  docs/screenshots/study-days/macos-en.png
  docs/screenshots/study-days/macos-ja.png
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
  '(^|[^[:alnum:]_])(TODO|TBD|FIXME)([^[:alnum:]_]|$)|placeholder|provisional|公開準備中|daysyet\.dev|DaysYet Dev' \
  README.md PRIVACY.md SECURITY.md TRADEMARKS.md docs AppStore http_dist; then
  echo "error: release placeholder or development identity remains in public content" >&2
  exit 1
fi

if /usr/bin/grep -E -i -R -I -q -- '(^|[^[:alnum:]_])draft([^[:alnum:]_]|$)' \
  AppStore/metadata http_dist; then
  echo "error: unfinished release copy remains in product metadata or the public site" >&2
  exit 1
fi

plutil -lint DaysYet/PrivacyInfo.xcprivacy DaysYetWidget/PrivacyInfo.xcprivacy \
  DaysYetMac/Info.plist DaysYetMac/DaysYetMac.entitlements DaysYetMac/PrivacyInfo.xcprivacy >/dev/null
for privacy_manifest in DaysYet/PrivacyInfo.xcprivacy DaysYetWidget/PrivacyInfo.xcprivacy; do
  assert_contains "${privacy_manifest}" "NSPrivacyAccessedAPICategoryUserDefaults"
  assert_contains "${privacy_manifest}" "1C8F.1"
done
assert_contains DaysYetMac/PrivacyInfo.xcprivacy "NSPrivacyAccessedAPICategoryUserDefaults"
assert_contains DaysYetMac/PrivacyInfo.xcprivacy "CA92.1"
assert_contains DaysYetMac/PrivacyInfo.xcprivacy "NSPrivacyAccessedAPICategorySystemBootTime"
assert_contains DaysYetMac/PrivacyInfo.xcprivacy "35F9.1"
assert_contains DaysYetMac/DaysYetMac.entitlements "com.apple.security.app-sandbox"

actual_icon_sha256="$(shasum -a 256 "${ICON_PATH}" | awk '{print $1}')"
if [[ "${actual_icon_sha256}" != "${EXPECTED_ICON_SHA256}" ]]; then
  echo "error: app icon changed; review its rights and update ASSET_LICENSES.md" >&2
  exit 1
fi
mac_icon_sha256="$(shasum -a 256 DaysYetMac/Assets.xcassets/MacAppIcon.appiconset/icon_1024.png | awk '{print $1}')"
# The legacy Mac asset includes rounded corners and transparent padding.
if [[ "${mac_icon_sha256}" != "${EXPECTED_MAC_ICON_SHA256}" ]]; then
  echo "error: Mac icon changed; review its shape and rights and update ASSET_LICENSES.md" >&2
  exit 1
fi

if find . -name Package.resolved -o -name Podfile.lock -o -name Cartfile.resolved | grep -q .; then
  echo "error: dependency lockfile detected; update notices, privacy review, and SBOM policy" >&2
  exit 1
fi

assert_contains project.yml 'developmentLanguage: ja'
assert_contains project.yml 'Debug: Config/Signing.xcconfig'
assert_contains project.yml 'Release: Config/Signing.xcconfig'
assert_contains Config/Signing.xcconfig '#include? "Signing.local.xcconfig"'
assert_contains .gitignore '*.local.xcconfig'
assert_contains DaysYet.xcodeproj/project.pbxproj 'baseConfigurationReference'
assert_contains DaysYet.xcodeproj/project.pbxproj 'Signing.xcconfig'
python3 - <<'PY'
from pathlib import Path
import json
import plistlib
import re
import subprocess

project = Path('project.yml').read_text()
stores = {
    'iOS': Path('AppStore/configuration.yml').read_text(),
    'macOS': Path('AppStore/macos/configuration.yml').read_text(),
}
version_settings = [
    ('MARKETING_VERSION', 'version', r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'),
    ('CURRENT_PROJECT_VERSION', 'build', r'[1-9][0-9]*'),
]
platform_versions = {}
for platform, store in stores.items():
    platform_versions[platform] = {}
    for project_key, store_key, pattern in version_settings:
        values = re.findall(rf'^{store_key}:\s*([^\s]+)\s*$', store, re.M)
        if len(values) != 1 or not re.fullmatch(pattern, values[0].strip('"')):
            raise SystemExit(f'error: {platform} AppStore configuration must define one valid {store_key}')
        platform_versions[platform][project_key] = values[0].strip('"')
expected_targets = {
    'DaysYet': 'com.hinoshiba.daysyet',
    'DaysYetWidget': 'com.hinoshiba.daysyet.widget',
    'DaysYetTests': 'com.hinoshiba.daysyet.tests',
    'DaysYetMac': 'com.hinoshiba.daysyet',
    'DaysYetMacTests': 'com.hinoshiba.daysyet.mac.tests',
}
target_spec = project.partition('\ntargets:\n')[2].partition('\nschemes:\n')[0]
objects = json.loads(subprocess.check_output([
    'plutil', '-convert', 'json', '-o', '-', 'DaysYet.xcodeproj/project.pbxproj'
]))['objects']
for target_name, expected_id in expected_targets.items():
    spec = re.search(rf'^  {target_name}:\n(.*?)(?=^  \w|\Z)', target_spec, re.M | re.S)
    if spec is None or not re.search(rf'^\s+PRODUCT_BUNDLE_IDENTIFIER: {re.escape(expected_id)}$', spec[1], re.M):
        raise SystemExit(f'error: {target_name} must use its expected bundle identifier in project.yml')
    target = next((value for value in objects.values()
                   if value.get('isa') == 'PBXNativeTarget' and value.get('name') == target_name), None)
    if target is None:
        raise SystemExit(f'error: generated project is missing {target_name}')
    configurations = objects[target['buildConfigurationList']]['buildConfigurations']
    if any(objects[configuration]['buildSettings'].get('PRODUCT_BUNDLE_IDENTIFIER') != expected_id
           for configuration in configurations):
        raise SystemExit(f'error: {target_name} has an unexpected bundle identifier in the generated project')
    platform = 'macOS' if target_name in {'DaysYetMac', 'DaysYetMacTests'} else 'iOS'
    for project_key, expected_value in platform_versions[platform].items():
        source = re.findall(rf'^        {project_key}: "([^"\n]+)"$', spec[1], re.M)
        resolved = [str(objects[configuration]['buildSettings'].get(project_key, ''))
                    for configuration in configurations]
        if source != [expected_value] or not resolved or any(value != expected_value for value in resolved):
            raise SystemExit(f'error: {target_name} {project_key} must agree in project.yml, '
                             f'generated target settings, and the {platform} AppStore configuration')
for name in ['DaysYet', 'DaysYetWidget', 'DaysYetMac']:
    with Path(name, 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if (info.get('CFBundleShortVersionString') != '$(MARKETING_VERSION)'
            or info.get('CFBundleVersion') != '$(CURRENT_PROJECT_VERSION)'):
        raise SystemExit(f'error: {name}/Info.plist must inherit its target version and build number')
PY
assert_line project.yml "bundleIdPrefix: ${EXPECTED_APP_ID}"
assert_line project.yml "VERSIONING_SYSTEM: apple-generic"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_APP_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_WIDGET_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_TEST_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_MAC_APP_ID}"
assert_line project.yml "PRODUCT_BUNDLE_IDENTIFIER: ${EXPECTED_MAC_TEST_ID}"
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
  http_dist/index.html
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
