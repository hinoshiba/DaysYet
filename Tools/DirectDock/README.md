# Direct Dock drag experiment

This optional macOS build locates DaysYet's helper icons using Accessibility
and places an input panel over the hovered circle. The panel owns a normal
mouse sequence and feeds the existing circle morph and edge docking code.
It does not begin or intercept macOS's native Dock rearrangement drag.

```sh
bash Tools/DirectDock/build.sh test
bash Tools/DirectDock/build.sh
```

The unsigned app is in
`/tmp/daysyet-direct-dock/Build/Products/Release/DaysYet.app`.
Sign the helpers and containing app with the intended local/distribution
identity before use. A changed ad-hoc signature can require a new Accessibility
grant. No signing keys or credentials are created by this script.

In DaysYet settings, choose the screen edge that contains the macOS Dock;
DaysYet joins the Dock automatically. Choose another edge to leave it. There
is no separate Dock display mode. Enable **Drag directly from the Dock
(experimental)** under **Get started** and allow DaysYet in System Settings →
Privacy & Security → Accessibility. The user controls this permission. Without it, the
existing click-to-open group remains available. Hold Option over a circle for
normal Dock rearrangement and its native context menu.

The first-run guide explains launch at login, then shows how a Dock circle
gathers and attaches to another edge. Its Accessibility step opens the relevant
System Settings page and checks the actual permission while the guide is open.
Choose **Enable direct dragging** after granting access, or **Set up later**.
Reopen the guide from **Settings → Widget → Get started**. The normal build
shows an edge-drag tutorial without requesting Accessibility permission.

The reader matches exact helper app URLs, reads only geometry for those items,
does not perform Accessibility actions, does not alter Dock preferences and
does not store or log other Dock items. Hidden, missing or invalid positions
disable the input surface. Keep this experiment outside App Store builds:
Accessibility access to other apps requires a non-sandboxed distribution.
Normal builds omit the controller using `DAYSYET_DIRECT_DOCK_DRAG` and retain
the project's existing Sandbox settings.

Real-device checks still matter: dragging out of bottom/left/right Docks,
return to Dock, central release and Escape, auto-hide, magnification, Option
bypass, permission revocation, Dock restart, multiple displays and Spaces.
The prototype must fail closed when it cannot locate its own icons.

## Local validation

On the development Mac (2026-11-01), after granting Accessibility, the app
located its real Dock circles. A manual direct grab contracted to one small
circle, attached to another screen edge, and removed the whole group from the
Dock. Dragging the edge widget back toward the Dock restored all three native
helper tiles. The direct build passed 252 unit tests; the normal build passed
251, with no AX inspection symbols in its binary. Center release, Escape and
input invalidation have unit coverage. Dock magnification, auto-hide and other
display/Space combinations still need real-device validation.

The landing refinement keeps the expanded circle row intact on release and
hands each circle to its actual native Dock slot. Its preview has no shared
background or rectangular target outline. Attachment includes the Dock's
reserved strip (or the observed source icon depth for an auto-hidden Dock),
so movement along that strip does not repeatedly collapse the row. Temporary
helper images stay transparent during the handoff and are restored on finish
or cancellation. The refined direct build passed 258 tests and the normal
build passed 257, including transparent-gap rendering, slide hysteresis,
late-arriving Dock geometry and cancellation during the committed handoff.

The ordinary bottom rail also keeps its full shape during horizontal movement,
including the first few points of a press. Pulling 32 points inward detaches
it into a circle. This uses the original attachment rather than requiring its
inset center to touch the physical display edge. Its small decorative handle
has been removed. The additional source-slide regressions bring the direct
suite to 260 tests (259 in the normal build).

The bottom rail now meets the physical screen edge with curved shoulders.
Hovering expands the same surface upward, with the centered detail typography
used by the top panel. Circle positions stay fixed through expansion, and the
detail clears the largest hover magnification. Geometry and rendered snapshots
cover 3, 6 and 8 circles, including large details. The direct suite passed 263
tests and the normal suite passed 262; the final shoulder adjustment also
passed the 11 focused bottom-surface and docking tests.
