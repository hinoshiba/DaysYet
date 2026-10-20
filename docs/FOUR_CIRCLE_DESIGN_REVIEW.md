# Four-circle design and iPhone setup review

Reviewed on 2026-10-20 against the iOS 0.1.9 (14) source. The review covered Japanese and English typography, geometry, information density, navigation, persistence, accessibility, and existing widget compatibility.

## Findings and decisions

| Finding | Why it felt wrong | Decision |
|---|---|---|
| One-line Japanese titles occupied a bottom-aligned two-line box in large circles. | Empty space above the title moved the visible title/value group below the center. English wrapping produced a different balance. | Use one title line in every circle, centered with the value. Long names end in an ellipsis instead of making each title a different size. |
| Each title could shrink to 70%, and each percentage to 50%, independently. | Long Japanese names and 100% could become smaller than their neighbors. | Keep readable title sizes; budget percentage width for 100% before rendering any value. Use a smaller percent symbol on the same baseline. |
| A fixed 7pt ring was used in the 94pt preview circles. | The ring consumed a larger fraction of the preview than the real large widget and competed with its text. | Scale the stroke with circle diameter and reserve clear space inside its inner edge. |
| The app always previewed the noncompact grid at 224pt. | The actual Small family used different line counts, fonts, spacing, and strokes. | Preview the same compact layout at a representative 170pt outer size with 16pt margins; identify it as the Small preview. Actual host sizing remains controlled by iOS. |
| The type selector edited two independent configurations but did not replace an installed widget. | It looked like a display switch, while the crucial explanation was behind a question-mark icon. | Put an explicit Home Screen add/switch action next to the preview. Explain the distinction there, with exact gallery names and sizes in the guide. |
| Settings only switched tabs; a previously opened color editor could remain on screen. | A user looking for the layout switch could land in an unrelated editor. | Settings explicitly names both types and always returns to the layout chooser. |
| The editor started with Three rows on every launch. | Returning users lost their context. | Remember the last editor locally, retain the selection across navigation, and clear it with Delete all data. |

## Typography and geometry

The title remains above the value and inside its own circle. Default names have semantic short forms only in the Small family: for example, `1日の活動` becomes `活動`, and `This week` becomes `Week`. Custom names are never renamed. Large circles, settings pickers, and VoiceOver retain full names.

Each circle uses a centered text rectangle whose diagonal fits within the circle's inner diameter, with an additional 2pt clearance from the ring. This bounds the complete text frames, including their line heights and gap, rather than checking only the text's center. Titles use system typography; numeric values retain rounded monospaced digits. Colors and saved palettes are unchanged.

Small-circle time-left values display the first nonzero duration component, such as `3日`, `12時間`, or `36y`. This avoids splitting a quantity across lines or reducing Japanese units to unreadable type. Large circles retain detailed components on separate lines; VoiceOver retains the complete duration. A Small circle with no scheduled time displays a dash, while its accessibility summary retains the reason. The editor explains the Small/Large difference when Time left is selected.

Compact end dates omit the redundant “until” prefix/suffix, keep the localized date order with a two-digit year, and use a 24-hour clock for activities. Condensed proportional system digits preserve the complete value, including the tested `12/31/99`, `99/12/31`, and `23:59` cases at 158pt with AX5. Only these numeric strings may tighten from 11pt to 85% (9.35pt), a deliberate compact-date tradeoff that avoids dropping the year or truncating the date. The editor explains the short year and clock format. Titles and percentages do not shrink per cell.

Alternatives considered:

- **Shrink every long title:** rejected because equal-status circles would acquire different visual weights and very small Japanese glyphs.
- **Wrap titles to two lines:** rejected because a short title and a long title would give their values different apparent positions or require empty reserved space.
- **Move titles outside the rings:** rejected because it conflicts with the requested label-above-percentage design and consumes more of a Small widget's height.
- **Merge the two widget kinds into one global switch:** deferred because it would change independent installed-widget behavior and supported families. The current fix makes the real operation discoverable and preserves existing choices.

## Setup and compatibility

Route: **Settings → Widget settings (Three timelines / Four circles) → select the type → Add or switch on the Home Screen**.

The existing widget kinds and intent parameters remain unchanged. To change kinds, add the desired widget from the system gallery, check it, then optionally remove the old one. Editing a metric or theme in the app applies to placed widgets that follow App setting; explicit per-widget choices remain independent.

The remembered editor is an app-only preference. Screenshot fixtures use separate in-memory state. Delete all data resets this preference together with the profile. The iOS privacy manifest and data map declare the additional app-only UserDefaults use; there is no new network path or data collection.

## Validation

Native SwiftUI render attachments cover Small outer sizes 158, 170, and 186pt, Large 338pt, Japanese/English titles, CJK/Latin/emoji custom names, 0/9/99/100/<1%, Off, no schedule, durations, dates, and AX5. These are renders of the actual shared view, not screenshots of an operating-system widget host. Geometry checks cover circle diameters 56–180pt, two value-line budgets, and three text scales. iOS font measurements independently check that percentage glyphs fit without per-value shrinking.

Navigation UI tests cover Settings returning from Colors to the selected layout, the Japanese add/switch guide, selection persistence across relaunch, screenshot isolation, deletion reset, and maximum accessibility text.

Local validation passed: 127 iOS tests, including 11 native render attachments and independent glyph measurements; 230 Mac tests; and five iPhone navigation UI tests. Public-file, development-compliance, and whitespace checks passed. A separate iPhone SE simulator attempt was stopped during its initial operating-system data migration, before any app test ran; compact widths were instead checked by native shared-view rendering on the working simulator.

Physical-device Home Screen, StandBy, tinted/clear host appearance, and VoiceOver speech were not newly exercised in this review. An existing installed widget cannot be replaced by the app's editor selector.

## Primary references

- [Apple HIG: Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets): glanceable content, standard margins, readable text (generally at least 11pt), and meaningful content without reliance on color.
- [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography): legibility, hierarchy, and adapting to text size and available space.
- [Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings): minimize settings and place task-specific choices near the work they affect.
- [Apple: Add, edit, and remove widgets on iPhone](https://support.apple.com/guide/iphone/add-edit-and-remove-widgets-iphb8f1bf206/ios): system gallery selection and long-press editing are separate operations.
- [Apple: Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons): app-only and App Group UserDefaults purposes.

The layout formulas, short-title policy, and duration simplification are DaysYet design decisions informed by these references, not requirements prescribed by Apple.
