# Counterclockwise remaining-time rings

Applies to the next iOS/iPadOS and macOS release.

Remaining-time rings now shrink counterclockwise, keeping their starting point
at 12 o'clock. At 75% the upper-left quarter is empty; at 50% the right half
remains colored; at 25% only the upper-right quarter remains colored. At 100%
the entire ring is colored, and at 0% no colored arc remains.

This applies to the four-circle Home Screen widget and its in-app preview,
the circular Lock Screen widget, Mac rail circles, and Mac settings previews.
The website demo and Japanese/English descriptions use the same direction.

This is a rendering change. Existing profiles and widget configurations remain
compatible; remaining-time calculations, percentage values, and accessibility
labels are unchanged.

Existing store screenshots and earlier release records describe their captured
versions. Refresh the affected store screenshots when preparing the next release.

## Validation

Local checks on 2026-11-01 passed: 127 iOS tests, 230 macOS tests, public-file
and compliance checks, bilingual-site validation, and store-asset validation.
Regenerating the Xcode project produced no changes.

Visual review covered native iOS shared-view renders in Japanese and English
at 158, 170, and 338 points, plus the 32-point Mac ring at 100%, 75%, 50%, 25%,
0%, and Off. The Lock Screen extension builds with the iOS app; physical-device
WidgetKit hosting was not exercised in this change.
