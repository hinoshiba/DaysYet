# Native Dock URL-drag experiment

This development build tests whether the Dock can reposition six existing
application entries in one public AppKit dragging session. It offers Move,
Link, a combined public-operation mask, and Copy as a control. The source mask
permits operations; it does not command the Dock to reorder existing entries.
No successful native group-reorder result is established by building it.

```sh
bash Tools/NativeDockURLDrag/build.sh
```

The DaysYet build is under `/tmp/daysyet-direct-dock` by default. Override
`DAYSYET_URL_PROBE_DERIVED_DATA` to keep a separate build cache. Sign the app
and its embedded helpers before installing, as with the direct build. The
development menu **Dock一括ドラッグの検証…** opens the trial window.

The six payload apps are disposable fixtures under
`/tmp/daysyet-native-url-fixtures/DaysYet Dock Group Move Probe.app/Contents/Helpers`.
The build script generates them using the earlier fixture builder. Never open
that containing old probe app: its old preference-write/restart cleanup is
not part of this test. Opening an individual numbered fixture only exits.

Using fixture URLs matters: allowing Move for a real embedded helper URL
could let an accidental Finder drop move part of DaysYet itself. This test
never puts the installed helpers on the dragging pasteboard. A misplaced
Move can affect only the disposable fixture; the test then stops if its
payload is missing. It does not delete source files after a drag.

Seed the six numbered entries with Copy, then drag the same six URLs to a
different Dock gap using Move, Link, and the combined mask. Existing DaysYet
input panels, insertion filtering, and automatic ordering are suspended while
the window owns the test. Callback operation values alone do not count as
success: the same six identities must reach the intended contiguous gap,
with no duplicates or missing items and unchanged foreign order and records.
Other apps' identities and comparison records remain in memory only.

The result stays visible when retrying inspection. The `native-dock-url-probe`
and `native-dock-order` log categories record phase names, operation bits,
counts, and failure codes, never other applications' identities. Transient
inspection failures allow up to three fresh reads within a 1.5-second budget.
Rechecking preserves the original comparison state; it cannot turn an
unverified drag into a successful move. A released or expired preparation
returns to idle even if the source misses its mouse-up event.

External trial suspension removes the regular DaysYet input windows and
pauses their geometry updates until cleanup completes. The numbered fixture
icons **1–6**, rather than the normal progress circles, identify a successful
initial Copy. Do not attempt the next mode before the window confirms that
addition.

Closing the window removes only the trial's new fixture pins using their
verified native Dock menus. It does not write Dock preferences or restart
Dock. A persistent marker blocks the older registration cleanup while a test
or unresolved recovery exists, including after relaunch. Incomplete cleanup
keeps the recovery UI available instead of silently reloading Dock. Screen
Recording is neither needed nor requested.

## Device results

On 2026-11-04 the user reported that Copy added six icons and Move did not
relocate them. The resulting native order was not retained, so that report
alone does not establish the Dock's operation support. The follow-up Link
trial was blocked by inspection failure before mode selection. The retry and
source-lifecycle fixes address that trial issue; their tests do not prove a
native group move. Keep the result window open for verification during the
next device trial.

After the existing Accessibility entry was re-registered, the revised build
verified its initial state in 248 ms. An automated source gesture delivered
down, drag, and up in about 5 ms; the fresh preparation read finished in 32 ms
and correctly returned to idle without starting a drag after release. This
confirms the cancelled-preparation path, not a native Dock drop. A manual
Copy seed with visibly numbered fixture icons is still required before the
operation-mode trials can continue.
