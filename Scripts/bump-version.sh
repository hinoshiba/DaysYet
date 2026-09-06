#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM_VALUE=ios
if [[ $# -eq 3 ]]; then
  PLATFORM_VALUE="$1"
  shift
fi

if [[ $# -ne 2 || ! "$PLATFORM_VALUE" =~ ^(ios|macos)$ || ! "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: ./Scripts/bump-version.sh [ios|macos] <marketing-version> <build-number>" >&2
  exit 2
fi

readonly PLATFORM_VALUE
readonly MARKETING_VERSION_VALUE="$1"
readonly BUILD_NUMBER_VALUE="$2"

python3 - "$PLATFORM_VALUE" "$MARKETING_VERSION_VALUE" "$BUILD_NUMBER_VALUE" <<'PY'
from pathlib import Path
import re
import sys

platform, version, build = sys.argv[1:]
targets, configuration = {
    'ios': (['DaysYet', 'DaysYetWidget', 'DaysYetTests'], 'AppStore/configuration.yml'),
    'macos': (['DaysYetMac', 'DaysYetMacTests'], 'AppStore/macos/configuration.yml'),
}[platform]
project_path = Path('project.yml')
project = project_path.read_text()
prefix, separator, target_section = project.partition('\ntargets:\n')
target_section, scheme_separator, suffix = target_section.partition('\nschemes:\n')
if not separator or not scheme_separator:
    raise SystemExit('error: project.yml is missing its targets or schemes section')

for target_name in targets:
    pattern = rf'^  {re.escape(target_name)}:\n(.*?)(?=^  \w|\Z)'
    match = re.search(pattern, target_section, re.M | re.S)
    if match is None:
        raise SystemExit(f'error: project.yml is missing {target_name}')
    block = match[0]
    for key, value in [('MARKETING_VERSION', version), ('CURRENT_PROJECT_VERSION', build)]:
        block, count = re.subn(rf'^        {key}: "[^"\n]+"$',
                               f'        {key}: "{value}"', block, flags=re.M)
        if count != 1:
            raise SystemExit(f'error: {target_name} must define exactly one {key}')
    target_section = target_section[:match.start()] + block + target_section[match.end():]

configuration_path = Path(configuration)
metadata = configuration_path.read_text()
for key, value in [('version', version), ('build', build)]:
    metadata, count = re.subn(rf'^{key}: .+$', f'{key}: {value}', metadata, flags=re.M)
    if count != 1:
        raise SystemExit(f'error: {configuration} must define exactly one {key}')

project_path.write_text(prefix + separator + target_section + scheme_separator + suffix)
configuration_path.write_text(metadata)
PY

xcodegen generate
echo "Updated the ${PLATFORM_VALUE} release sources to ${MARKETING_VERSION_VALUE} (${BUILD_NUMBER_VALUE})."
