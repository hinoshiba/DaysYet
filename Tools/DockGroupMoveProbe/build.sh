#!/bin/bash
set -euo pipefail

daysyet_group_probe_root="$(cd "$(dirname "$0")" && pwd)"
daysyet_group_probe_output="${1:-/tmp/daysyet-dock-group-move-probe}"
daysyet_group_probe_app="${daysyet_group_probe_output}/DaysYet Dock Group Move Probe.app"
mkdir -p "${daysyet_group_probe_app}/Contents/MacOS"
swiftc -swift-version 5 -framework AppKit "${daysyet_group_probe_root}/main.swift" \
  -o "${daysyet_group_probe_app}/Contents/MacOS/DockGroupMoveProbe"
"${daysyet_group_probe_app}/Contents/MacOS/DockGroupMoveProbe" --self-test
"${daysyet_group_probe_app}/Contents/MacOS/DockGroupMoveProbe" --render-icons "${daysyet_group_probe_output}"
python3 - "${daysyet_group_probe_app}" <<'PY'
import pathlib, plistlib, shutil, sys
app = pathlib.Path(sys.argv[1])
base = 'com.hinoshiba.daysyet.dock-group-move-probe'
def info(path, identifier, name, agent):
    with (path / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'DockGroupMoveProbe',
                      'CFBundleName': name, 'CFBundleDisplayName': name, 'CFBundlePackageType': 'APPL',
                      'CFBundleIconFile': 'AppIcon', 'LSUIElement': agent,
                      'NSHighResolutionCapable': True}, stream)
info(app, base, 'DaysYet Dock Group Move Probe', True)
for index in range(1, 7):
    helper = app / f'Contents/Helpers/Group Test {index}.app'
    (helper / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (helper / 'Contents/Resources').mkdir(parents=True, exist_ok=True)
    shutil.copy2(app / 'Contents/MacOS/DockGroupMoveProbe', helper / 'Contents/MacOS/DockGroupMoveProbe')
    info(helper, f'{base}.tile{index}', f'Group Test {index}', False)
PY
for daysyet_group_probe_index in 1 2 3 4 5 6; do
  daysyet_group_probe_helper="${daysyet_group_probe_app}/Contents/Helpers/Group Test ${daysyet_group_probe_index}.app"
  iconutil -c icns "${daysyet_group_probe_output}/tile${daysyet_group_probe_index}.iconset" \
    -o "${daysyet_group_probe_helper}/Contents/Resources/AppIcon.icns"
  codesign --force --sign - --options runtime "${daysyet_group_probe_helper}"
done
mkdir -p "${daysyet_group_probe_app}/Contents/Resources"
cp "${daysyet_group_probe_app}/Contents/Helpers/Group Test 1.app/Contents/Resources/AppIcon.icns" \
   "${daysyet_group_probe_app}/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime "${daysyet_group_probe_app}"
codesign --verify --deep --strict "${daysyet_group_probe_app}"
printf '%s\n' "${daysyet_group_probe_app}"
