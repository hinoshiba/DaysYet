# Direct Dock drag experiment

This is an unpublished development experiment, not a distributed DaysYet
edition. DaysYet is distributed only through the Mac App Store.

This optional macOS build locates DaysYet's helper icons using Accessibility
and protects each verified tile's full rectangular area with an input panel. The panel owns a normal
mouse sequence and feeds the existing circle morph and edge docking code.
The direct build also moves these tiles as a group within the Dock, repairs
split groups, and includes a process-scoped insertion guard. The normal
sandboxed build excludes these Accessibility capabilities.

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
is no separate Dock display mode or individual-icon drag switch. Allow DaysYet in System Settings →
Privacy & Security → Accessibility. Dock insertion itself requires this permission:
without it, a settings choice or drag keeps the previous placement and opens
Settings, where the Accessibility status and system-settings link are shown. Permission is checked again before helper creation. Revoking it
removes the Dock tiles and returns the widget to another screen edge. Every
circle, including its transparent corners, moves the whole group. Option no
longer bypasses this behavior. Verified input panels are ready before hover,
so a fast approach and press cannot slip through the old hover-only guard.

The first-run guide explains launch at login, then shows how a Dock circle
gathers and attaches to another edge. Its Accessibility step opens the relevant
System Settings page and checks the actual permission while the guide is open.
Choose **Use the Dock** after granting access, or **Set up later**.
Settings groups **Launch at login** and **Accessibility** under **General**,
with their current system status. The tutorial is limited to first-run setup.
The normal build shows an edge-drag tutorial without requesting Accessibility
permission; Dock insertion is unavailable in builds without that capability.

The geometry reader matches exact helper app URLs. The optional drag filter
uses a fresh cached native Dock item subrole and rectangle at mouse-down,
without retaining its app identity.
These readers do not perform Accessibility actions or store other Dock items.
The native group mover separately selects only verified DaysYet helpers and
uses the Dock's standard keyboard ordering operation. It reads the full order
transiently to verify that unrelated items retain their relative order.
Hidden, missing or invalid positions
disable the input surface. Keep this experiment outside App Store builds:
Accessibility access to other apps requires a non-sandboxed distribution.
Normal builds omit the controller using `DAYSYET_DIRECT_DOCK_DRAG` and retain
the project's existing Sandbox settings.

Real-device checks still matter: dragging out of bottom/left/right Docks,
return to Dock, central release and Escape, auto-hide, magnification, modifier
keys, permission revocation, Dock restart, multiple displays and Spaces.
The prototype must fail closed when it cannot locate its own icons.

## Group behavior and leftover recovery

The circle count is preserved using one native helper tile per circle.
DaysYet owns the mouse interaction for all of them and maintains their
adjacency and configured order. This is an application-managed group, not
a new atomic macOS Dock item type.

The direct build enables `DAYSYET_DOCK_NATIVE_REORDER` and
`DAYSYET_DOCK_GROUP_GUARD`. A guard-only diagnostic build remains available
with `bash Tools/DockGroupGuard/build.sh [test]`; its artifacts are under
`/tmp/daysyet-dock-group-guard`. Building does not install the app.

The experiment uses the public
[`CGEvent.tapCreateForPid`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreateforpid(pid:place:options:eventsofinterest:callback:userinfo:))
API, scoped to the Dock process. It redirects only an immediate left-button
drag originating at a native application Dock item, while that drag is over
DaysYet's verified group. It chooses the nearer outside boundary and applies
the same boundary on mouse-up. It never drops an event, warps the pointer,
posts synthetic events, filters keys, or filters another process's events.
Source classification is cached on the AX reader's serial queue; no synchronous
AX request runs inside the input callback. Only a fresh matching application
item rectangle can arm the filter. Very fast approaches without a fresh
classification pass through rather than intercepting an unknown Dock control.
Clicks, Control-click menus, stationary long presses, separator resizing,
and movements outside the group pass through. Stale/missing geometry, a
display change, and permission loss cancel the routing.

On 2026-11-03 the user confirmed that another Dock icon could not be inserted
between DaysYet's circles in the installed prototype. This verifies that
interaction; geometry tests alone cannot establish how the Dock uses the
modified event location. The guard does not cover Finder-originated drags,
keyboard rearrangement, or save the group's location among other applications.
The native group monitor covers resulting splits separately: after the user
finishes interacting, it chooses the nearest boundary and restores the group.
A drawn preview covers the moving helper images, then hands back to their
actual native frames. It does not restart the Dock.

### Moving the group within the Dock

The interaction requirement is to move the visible circles as a block within
the Dock, as well as pull that block out to another screen edge. Persisting an
exact position across launches is secondary. While held over the Dock, the
preview stays collected into the grabbed circle at the pointer. The gap
between other applications determines the whole group's insertion point,
independently of which circle was grabbed. During a reorder, releasing restores
all existing native circles to full opacity before their slots move. The carried
circle stays visible until ordering completes, then returns to its own verified
slot; the overlay does not duplicate the other native circles. A new insertion
from a screen edge still unfolds the full group after the slots are ready.
A release on another screen edge retains the existing magnetic attachment and
helper-removal behavior. Ordinary edges unfold on contact while held.

### Retired visual transition prototype

The **Moving within the Dock** settings section and its screen-recording
consent UI have been removed. The snapshot transition is permanently disabled,
and preferences discard any saved opt-in from earlier builds. Dock placement
and group dragging continue through the native movement path. The capture and
cover implementation below is retained only as an inactive prototype.

The following describes the earlier experiment:

The native Dock still animates surrounding applications one exchange at a
time. The experimental
**Show Dock moves as one transition** setting covers that intermediate motion
with one temporary image of the Dock region. It is off by default. Its
explanation sheet must be explicitly accepted, and macOS Screen Recording
permission must already be granted before any capture or shareable-content
enumeration. Missing permission keeps the existing noncapturing behavior.
The normal sandboxed build omits this setting and capture implementation.

After mouse-up, the controller waits for the helpers to acknowledge their
current images and for the Dock's geometry to settle. It captures only the
verified Dock strip, including Trash and a small surrounding margin, then
keeps that image visible while native ordering runs beneath it. Once the final
layout is stable, the image fades out and the carried circle lands.
This does not make native ordering atomic or reduce its exchange count.

The captured strip also contains wallpaper and any other app content visible
behind the Dock. Pixels stay in memory and are discarded after the transition;
there is no audio capture, image file, network transfer, or image logging.
Geometry is checked against the current Dock process, display, orientation,
and all visible Dock items; invalid or oversized bounds never fall back to a
full-screen capture. A preparation failure stops the move before native input.
Clicks and scrolls cancel the cover rather than targeting stale icon positions.
Permission loss, display changes, cancellation, or an eight-second watchdog
release the image; an already-started mouse press is consumed through release.

This visual transition is a new prototype. Automated tests cover permission
and cancellation boundaries, capture geometry, pixel opacity, helper display
acknowledgements, and the cover's lifetime. Its actual ScreenCaptureKit output
and appearance over the native Dock require an explicitly authorized device
check; no successful visual result is claimed by these tests.
On 2026-11-03, 56 focused direct-build tests and 21 normal-build tests passed,
and the direct Release build succeeded. The update was installed with this
feature disabled, and its consent explanation was checked in the app. The
existing Accessibility permission was renewed; all six helpers returned with
no owned pins, unchanged foreign Dock records, and the same Dock process.
The user then enabled Screen Recording and tested the transition. Device logs
show successful regional capture and completed native moves, including a
transition that kept the old Dock image visible for about 5.5 seconds. This
concealed the intermediate movement without reducing the native ordering time.
The user rejected that frozen appearance. The feature and its system Screen
Recording permission were switched off, DaysYet was reopened, and all six
helpers remained available. The snapshot path stays disabled; it is not the
chosen solution for group movement.

Remaining public-API experiments are not established solutions. The earlier
file-URL probe advertised only `.copy`; `.move`, `.link`, and a mask including
`.generic` have not been tested for repositioning the same existing group.
Multiple AX selection has also not been verified. Temporarily changing helpers
to `.accessory` can remove their live Dock presence, but no public insertion
index guarantees that returning them to `.regular` restores them beside a moved
anchor. Existing stop/start cleanup must not be reused for such a collapse,
because removal of old saved helper registrations can restart the Dock.

### Earlier file-URL group probe

`bash Tools/DockGroupMoveProbe/build.sh` builds a separate capability probe at
`/tmp/daysyet-dock-group-move-probe/DaysYet Dock Group Move Probe.app`. It uses
six disposable numbered apps with distinct bundle IDs, separate from DaysYet.
Drag the row in its window into a Dock gap, then drag the same row from the
window into another gap. This distinguishes accepting several new app URLs
from rearranging several already-pinned app URLs. AppKit receives one
`NSDraggingSession` with six items; the probe itself never writes Dock
preferences during a drag. It checks for six consecutive items in their
original order, a changed position on the second drop, and unchanged relative
order of other app paths. A failed/no-op native operation is not a success.

Closing the probe removes only its exact embedded test-app registrations from
`persistent-apps` and `recent-apps`, backs those up locally, and reloads Dock
only when it removed records. It re-reads the current arrays before removing
its records, preserving other entries. This cleanup does not target DaysYet's
actual helpers. A cleanup failure keeps the probe open and explains how to
remove the numbered test items manually. The test requires no Accessibility
permission. Its build and ownership/group-detection checks pass.

On 2026-11-03 the user completed the two-drop check: all six test items could
be added, but they did not move together to another position. Inspection of
the resulting saved Dock records also found the six test entries separated
by other applications. The native file-URL drag therefore does not establish
a working group-reorder mechanism and has not been integrated into DaysYet.
The probe was closed and all six test registrations were removed. Hashes of
all unrelated records in `persistent-apps`, `recent-apps` and `persistent-others`
matched before and after cleanup, including their order and metadata.

The user explicitly rejected a workaround that reloads the Dock on each drop
because it flickers. Preserve the requirements of visible multiple circles,
moving them as one block within the Dock, and avoiding reloads during normal
interaction. Native keyboard ordering now supplies the rearrangement mechanism;
the rejected file-URL batch-insertion probe is retained only as development
evidence.

### Native group ordering

The mover reads the verified system Dock's order and resolves every member by
its exact embedded helper URL. It plans the fewest adjacent exchanges needed
to put all members together, without changing unrelated items' relative order.
It verifies the exact owned selection before each arrow and uses
`AXSelectedChildren` only when that selection needs to change. Balanced
Option-arrow events follow verification of system-wide Dock focus. Generated function
and numeric-pad flags must be preserved; replacing the flags prevented the
native ordering operation from working.

The default, enabled Control-F3 Dock-focus binding is required. The app never
changes system shortcuts. Permission loss, lock/sleep, display or Dock changes,
new physical input, unexpected ordering, or foreign preference changes stop
an in-flight move. Global keys are sent only while the verified own item has
Dock focus. Cancellation does not undo already completed exchanges; the next
idle check can repair the group's adjacency. The mover does not write Dock
preferences or restart the Dock. A bounded transaction and process-wide lease
prevent concurrent native operations.

`bash Tools/NativeDockMove/build.sh [test]` adds
`DAYSYET_DOCK_REORDER_PROBE` to the direct build, with artifacts under
`/tmp/daysyet-native-dock-move`. Command-Option-D opens development controls for
single-item movement, six-item movement, alignment, and cancellation. These
controls are excluded from the ordinary direct build. The optional diagnostic
unpin command has not been validated and is not used by normal movement.

On 2026-11-03 both computer-use and manual clicks verified native one-slot
movement. The six-member probe subsequently moved the group one foreign slot
forward and back successfully. Both operations reported zero new pins. The
Dock process remained running, and hashes of all unrelated records in
`persistent-apps`, `recent-apps`, and `persistent-others` remained unchanged.
The idle repair also passed a real-Dock check: moving the first circle one
slot across an unrelated app split the group, then the monitor restored the
configured contiguous group without a manual alignment operation. Dock PID,
foreign records, and zero-pin state remained unchanged. The ordinary direct
build (without probe controls) was then installed. Its settings-driven
left-Dock → bottom-edge → left-Dock round trip changed the live helper count
6 → 0 → 6, with no owned saved entries, foreign-record changes, or Dock restart.
The user then reported that an actual direct drag left circles separated.
The earlier button checks therefore do not establish a complete working
interaction. The next revision reselects the exact owned item before every
arrow, distinguishes a verified exchange from a later Dock selection change,
and returns an explicit group-contiguity result to the landing animation.
A partial layout is never used as a successful fan-out destination. A single
recovery attempt is allowed only if no physical input has intervened; idle
repair uses the same rule and remains available after cancellation. Its
preparation animation also watches for intervening input, so a click during
that short interval cannot be followed by a newly started repair.

A bounded read-budget expiry or AX `cannotComplete` response now retains the previous input geometry only until its
original 250ms expiry. Observed hidden, replaced, invalid, or off-screen items
invalidate that snapshot immediately, including when a later read times out.
An older geometry read cannot overwrite a fresh post-move snapshot. Diagnostic
logs distinguish captured group drags from native ordering failures, recording
only counts, stages, elapsed time, and fixed reasons; they do not contain other
apps' names/paths, physical key values, or pointer positions.

The next device run exposed a separate interrupted repair: 23 of 27 exchanges
were verified before a generic environment check failed. A subsequent repair
completed all 27 exchanges. The generic failure alone does not establish that
the Dock or display changed; a temporarily unavailable session/focus read also
used to produce it. Environment checks now distinguish confirmed changes or
blocked sessions from unavailable reads. Only the latter may be reread within
a short bounded worker-side budget, with no keys sent until all checks pass.
The final main-thread send guard does not wait or reuse a previous result.
Dock's optional Launch Services launch date is not a prerequisite: the mover
retains the verified running-application lifetime and checks termination, PID,
bundle path, and any available launch dates. This avoids preventing all moves
on systems where the system Dock has no launch date.

The revised direct build passed 334 tests; 19 focused sandboxed-build tests
also passed, followed by 26 direct regression tests for the process-lifetime
check. The user clarified that the original direct gesture did gather the
circles, and that the split after release recovered after a short wait.
After installing the lifetime correction, the real Dock completed an idle
repair with all 23 posted exchanges verified. All six helpers remained live,
with no owned saved entries, no Dock restart, and unchanged foreign records.
The user then verified a real left-Dock group drag: all six circles moved
together without separating after release. That captured gesture completed
all 30 planned exchanges, with zero new pins. This verifies the reported
transient split for that interaction. The separate foreign-insertion check
then exposed visible sorting during recovery: the final order was correct,
but the transition looked awkward. The planner was cycling already-correct
members around the same foreign anchor. A central intruder needed three
adjacent exchanges but took nine; an intruder near an end could need one but
take 21. The planner now exchanges only adjacent items whose order differs
from the final order, attaining the minimum exchange count while selecting
only owned members and preserving foreign order. Exhaustive permutation tests
check this lower bound, and all five gaps in a six-member group verify that
already-correct members do not move. Per-key safety checks are unchanged.
The user subsequently accepted foreign-insertion behavior: the other icon
could not be inserted within the group. Minimizing exchanges is still not an
atomic macOS grouping API.

The planner revision passed the exhaustive 2,880-case minimum-count check
and all single-intruder boundaries. In the full 335-test run, 334 passed and
one existing hover-animation timing test failed to observe an intermediate
scale. That test passed unchanged in a focused 15-test rerun together with
the planner/native-mover tests. All 14 focused normal-build tests passed.
After installation, the six helpers completed a five-exchange startup repair;
the Dock process and foreign saved records were unchanged, with zero owned
saved entries. The current refinement is a single-circle insertion
preview while dragging, with the complete group appearing after insertion.

The single-circle revision passed 28 focused tests in both direct and normal
builds. Review also caught a pending-commit edge change that could leave the
preview alive; the cleanup fix passed all 11 landing tests in both builds.
The initial full 337-test run had one failing test fixture: it changed the
source edge after installing its observer, cancelling its own first gesture.
The fixture now establishes preferences before constructing the controller;
the focused reruns passed, and the full suite was not repeated. The Release
build was installed and its executable verified. Startup grouped six helpers
with four verified exchanges, zero saved helper entries, unchanged foreign
records, and the same Dock process. The user accepted the new insertion-gap
placement, then reported that the one-at-a-time native movement felt slow.
The captured successful gesture completed 36 exchanges in 3,552 ms. A second
gesture was interrupted by physical input after 38 confirmed exchanges;
idle repair restored the remaining group with three more exchanges.

The throughput revision now evaluates forward and reverse minimal-exchange
plans, choosing the one with fewer member runs. Moving six members past six
foreign apps takes six runs in either direction, instead of 36 runs in the
previous backward-moving plan. A fresh identity, selection and focus check
allows an already-selected helper to continue without another selection write.
Per-exchange order reads retain live URLs and subroles, omitting unused frames;
the final layout still includes geometry. The worker's preliminary gate checks
priority interruption, while the full environment gate remains immediately
before main-thread input and throughout confirmation. Balanced key events
have 1 ms between events, with no sleep after the final release. Exact exchange,
foreign settings, permission, focus and physical-input checks remain in place.

This revision passed 40 focused direct-build tests and 16 normal-build tests,
including the exhaustive 2,880-case minimum-exchange check and symmetric run
counts. Release was built and installed. After renewing the existing
Accessibility grant, startup repair completed all five exchanges in 990 ms,
using four verified selection writes. All six helpers were live, with zero
saved helper entries, unchanged foreign records and the same Dock process.
This verifies delivery with the shorter event interval. The user subsequently
reported faster movement but still noticed individual native item movement.
Three captured drags completed 54/54 exchanges in 4,165 ms, 30/30 in 2,101 ms,
and 42/42 in 3,426 ms, each using six member runs. The verified selection-write
counts were 6, 5 and 6. These are different distances and are not a controlled
before/after benchmark. Native ordering is still sequential; throughput work
does not conceal other applications moving between the helper slots.
Aggregate diagnostics record order-read, dispatch and saved-state-read times
without storing app identities or physical input. `selectionWrites` counts
selection writes whose post-write verification also succeeded.

A renderer regression verified every pixel remains transparent for all eight
metric images after opacity-zero rendering, PNG/JSON transport, and the same
NSImage decoding used by the helper. It passed in the direct build. This proves
the transmitted image's alpha, not a WindowServer presentation acknowledgement.
At that stage the helper protocol had no redraw acknowledgement. The current
protocol acknowledges a display revision after submitting the native tile
contents, and the preview waits for those receipts before handoff. Native
running indicators, selection and foreign items remain outside the PNG's
control; a receipt is not a WindowServer presentation acknowledgement.

Previously, a drag outside the small circular hit area (or with Option held)
could move a helper in the native Dock and make it persistent. The helpers
then quit normally, but the Dock retained the pinned shortcut. The direct
build now removes saved `persistent-apps` and `recent-apps` entries only when
their file URLs exactly match helpers embedded in this DaysYet installation.
The main DaysYet app and every other app entry retain their metadata and order.
Cleanup runs on launch, before creating a new group, and when stopping it.

Only removed helper records are backed up under
`~/Library/Application Support/DaysYet/Dock Recovery/`. The latest preferences
are re-read before writing. The Dock is reloaded only if stale helper entries
were actually removed; ordinary dragging does not reload it. The normal
sandboxed build neither changes Dock preferences nor reloads the Dock.

## Local validation

On 2026-11-02, the group-input and leftover-recovery changes passed all 295
direct-build tests, 39 focused normal-build tests, and a final 14-test direct
regression run. After renewing Accessibility permission on the installed
build, selecting the left Dock edge created six helpers. Selecting the bottom
edge removed all six; no owned pinned or recent entries remained, and other
Dock entries and their order were unchanged. On 2026-11-03 the user confirmed
that grabbing a DaysYet icon moves all six together without separating them.
They also confirmed that the earlier version let another app split the group.
The new insertion guard and idle repair address that behavior; exact placement
persistence across launches is not promised.

The separate insertion-protection experiment passed all 306 tests on
2026-11-03, including 11 routing-policy regressions. The ordinary direct build
also passed 21 focused drag, permission and cleanup tests with the additional
filter disabled. The filter is now included in the installed native-group prototype. Its
geometry tests alone do not establish that macOS honors a redirected drop.
The combined prototype passed 327 tests, followed by 31 focused regressions
after cancellation and image-handoff fixes, and eight landing tests after
checking native-move completion, cancellation, and full-opacity handoff.
The block planner exhaustively
checks all 2,880 placements of three members among three unrelated items;
geometry tests cover bottom, left, and right Docks, insertion-gap hysteresis,
and identical gap selection regardless of the grabbed member.

On the development Mac (2026-11-01), after granting Accessibility, the app
located its real Dock circles. A manual direct grab contracted to one small
circle, attached to another screen edge, and removed the whole group from the
Dock. Dragging the edge widget back toward the Dock restored all three native
helper tiles. The direct build passed 252 unit tests; the normal build passed
251, with no AX inspection symbols in its binary. Center release, Escape and
input invalidation have unit coverage. Dock magnification, auto-hide and other
display/Space combinations still need real-device validation.

The early landing refinement kept the expanded row intact and temporarily
replaced native images during handoff. It passed 258 direct-build and 257
normal-build tests covering transparent gaps, slide hysteresis, late geometry,
and cancellation. The current reorder keeps native circles opaque after
release and animates only the carried circle. New insertion still unfolds the
full group. Neither path adds a shared background or rectangular target outline.
Attachment includes the Dock's reserved strip (or an observed auto-hidden icon
depth), so sliding retains the insertion target.

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

On 2026-11-05, the final opacity regression passed 45 direct-build and 44
normal-build focused tests. The installed build was manually verified: all
six original Dock circles remain visible while the group moves after release.
The normal path needs Accessibility only; Screen Recording remains disabled.
