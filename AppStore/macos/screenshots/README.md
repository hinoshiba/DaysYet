# Native Mac screenshots

The Japanese and English folders contain seven screenshots each. The two widget-settings images were refreshed on 2026-11-11 from macOS 0.2.1 (14), with the default App Store feature flags and synthetic data. They show all four screen edges and placement clear of the Dock. The other twelve images from 0.2.0 (13) depict unchanged functionality and are retained. See the [0.2.1 release record](../../releases/0.2.1.md) for submission status.

| File | Current app content |
| --- | --- |
| `01-widget-settings.png` | All four screen edges, placement clear of the Dock, magnetic movement guidance, and graph magnification controls. |
| `02-side-widget.png` | Eight circles, with This month's remaining time and percentage expanded. Work hours shows its separate Off state. |
| `03-top-widget.png` | Three remaining-time strips above the fictional study plan's 13-day, 100% remaining detail. |
| `04-activity-hours.png` | Daily activity and Work hours, with start/end times, weekdays, current remaining time, and Off. This is a scrolled settings view. |
| `05-colors.png` | Four color templates and the first three timelines' native color controls for top placement. |
| `06-study-days.png` | A fictional plan from November 7 through December 4, 2026: Monday, Wednesday, Friday, plus November 7; 13 selected days. |
| `07-circle-selection.png` | Eight distinct timelines, removal controls, disabled Add Circle at the limit, and the study-plan summary. |

Every final image is a 2560 x 1600 RGB PNG with no alpha. The decoded native region is placed at 1:1 on white without resampling, retouching, generated artwork, or added captions. Native regions were compared byte for byte with the output crop. Source/output hashes and geometry are retained privately; the published files are covered by [SHA256SUMS](SHA256SUMS).

| Region | Native dimensions | Canvas position |
| --- | --- | --- |
| Updated widget settings | 1560 x 1384 | (500, 108); the title bar is cropped out |
| Other settings | 1560 x 1488 | (500, 56) |
| Study editor | 1640 x 1240 | (460, 180) |
| Side widget | 424 x 924 | (2136, 338), against the right edge |
| Top widget | 560 x 212 | (1000, 0), against the top edge |

Computer Use captured the running native app. Separate photography bundle IDs and ad-hoc launchers invoke the unchanged compiled binary with screenshot mode and a Japanese or English language argument. These private copies are not release archives. The profile is synthetic and nonpersistent; panel preferences use a temporary UUID-scoped suite, removed on quit. Normal app preferences, login items, Dock settings, and personal data were not changed. Both photography apps were quit after capture.

The Mac App Store build supports all four screen edges, stays clear of the Dock, and does not place timelines inside it. No direct-distribution feature flags were enabled. The 0.1.6 screenshots and their older preparation narrative are historical.
