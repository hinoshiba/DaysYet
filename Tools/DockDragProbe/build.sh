#!/bin/bash
set -euo pipefail

daysyet_probe_root="$(cd "$(dirname "$0")" && pwd)"
daysyet_probe_output="${1:-/tmp/daysyet-dock-drag-probe}"
mkdir -p "${daysyet_probe_output}/DaysYet Drag Probe.app/Contents/MacOS"
swiftc -swift-version 5 -framework AppKit \
  "${daysyet_probe_root}/main.swift" \
  -o "${daysyet_probe_output}/DaysYet Drag Probe.app/Contents/MacOS/DockDragProbe"
python3 - "${daysyet_probe_output}/DaysYet Drag Probe.app/Contents/Info.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'wb') as target:
    plistlib.dump({
        'CFBundleIdentifier': 'com.hinoshiba.daysyet.dock-drag-probe',
        'CFBundleExecutable': 'DockDragProbe',
        'CFBundleName': 'DaysYet Drag Probe',
        'CFBundleDisplayName': 'DaysYet Drag Probe',
        'CFBundlePackageType': 'APPL',
        'LSUIElement': True,
        'NSHighResolutionCapable': True,
    }, target)
PY
codesign --force --sign - --options runtime "${daysyet_probe_output}/DaysYet Drag Probe.app"
printf '%s\n' "${daysyet_probe_output}/DaysYet Drag Probe.app"
