# Dock drag receiver experiment

Build with `bash Tools/DockDragProbe/build.sh`, then open the resulting app.
Quit an existing probe before rebuilding it. This is an isolated development
tool and is not included in the DaysYet application targets.

The window accepts the probe's own application URL and DaysYet's installed
Dock helper URLs through `NSDraggingDestination`. It never opens, copies or
moves the dropped file. Its small comparison circle starts an ordinary AppKit
file-URL drag so the receiver can be checked independently of Dock behavior.
Dragging items in the real Dock still uses macOS's normal Dock behavior,
including any changes to the item's pinned position.

The probe records callback phases, pasteboard type names, operation masks and
whether an item matches. It does not record dropped file paths or general
clipboard contents. The log is `daysyet-dock-drag-probe-events.jsonl` inside
the user's temporary directory (shown by `getconf DARWIN_USER_TEMP_DIR`).

## Observed result, 2026-11-01

- The comparison circle produced `draggingEntered`, drag-image adjustment,
  `prepareForDragOperation`, `performDragOperation` and `draggingEnded`.
- A first version allowed text labels to interfere with the destination.
  The receiver now hit-tests the entire content area except its comparison
  source; the central drop was retested successfully.
- The user dragged the real Dock's TEST application icon onto the corrected
  receiver. The status remained at the comparison result, and no external
  drag-entry or drop callback was recorded for that attempt.

This does not establish behavior for all macOS versions or all Dock items.
It does establish that the tested public drag formats did not provide an
application-icon handoff in this configuration. Do not enable an invisible
production receiver on the basis of the comparison drag alone.
