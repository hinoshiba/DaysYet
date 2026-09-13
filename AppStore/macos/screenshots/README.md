# Native Mac screenshots

The `ja/` and `en-US/` folders each contain seven native screenshots, for 14 images in total. All 14 were recaptured on 2026-09-13 from the tested DaysYet macOS **0.1.6 (10)** Debug build and show the remaining-time countdown display. This file records screenshot preparation and verification; it does not establish upload or App Review submission. See the [0.1.6 release record](../../releases/0.1.6-countdown.md) for release status.

| File | Actual app content |
| --- | --- |
| `01-widget-settings.png` | Graph magnification enabled at 135%, detail size at 100%, the time + remaining percentage + bar mode, and the explanation of the 100% to 0% countdown direction. The magnification option's default-off behavior and Reduce Motion guidance are visible. |
| `02-side-widget.png` | The expanded right-side widget with eight remaining-time circles. The fictional study plan shows 7 days left, 53.8% in the detail, and a rounded 54% in its compact circle. Work hours shows Off. |
| `03-top-widget.png` | The expanded top widget with the first three timelines' remaining-time strips and the same study plan's 53.8% detail bar. |
| `04-activity-hours.png` | Two activity schedules with labels, start/end times, active weekdays, the daily time-left bar, and the separate Work hours Off state. |
| `05-colors.png` | Four color templates with clockwise-draining circle previews and individual color controls. Top placement is selected, so three color rows are shown. |
| `06-study-days.png` | The study-plan editor with its name, date range, weekday selection, calendar, selected-day count, and explanation of the remaining-day percentage. |
| `07-circle-selection.png` | Eight distinct timelines, their remove controls, the disabled Add Circle button at the maximum, and the saved study-plan summary. |

Every final image is a **1280 × 800 RGB PNG without an alpha channel**. Decoded original screenshot pixels are placed at 1:1 on a white canvas, with no resampling, stretching, retouching, generated artwork, or added captions. Each output's app region was compared with its decoded native capture and matched byte for byte; every pixel outside that region was verified white. These dimensions meet [Apple's Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

| Native region | Size | Position on the canvas |
| --- | --- | --- |
| Settings, activity hours, colors, circle selection | 780 × 744 | `(250, 28)` |
| Study-plan editor | 820 × 620 | `(230, 90)` |
| Side widget | 212 × 462 | `(1068, 169)`, attached to the right edge |
| Top widget | 280 × 106 | `(500, 0)`, attached to the top edge |

The captures were taken through Computer Use from the running native Debug app. Japanese and English capture-only copies have dedicated bundle identifiers, ad-hoc signatures, and launch-only language arguments. The compiled app code and product UI were unchanged; copied test-hosting frameworks and plug-ins were omitted from these photography bundles. Screenshot mode supplies a synthetic, non-persistent profile and UUID-scoped temporary panel preferences. Normal app settings were not edited, and both capture apps were quit after verification. A private source-hash manifest verifies the 44 tracked Swift files used for these captures.

Both fictional study plans use September 1–28, 2026, with Monday, Wednesday, and Friday selected, plus September 12 individually: 13 selected days and 7 remaining days at capture. Remaining counts include today when selected and describe scheduled days, not completed study sessions. The activity images show daily activity from 07:00 to 23:00 every day and work hours from 09:00 to 18:00 with weekends off. Capture time varies slightly between images, so live daily and weekly countdowns may differ. No private desktop content or other app windows are included.

Native endpoint checks on this build also verified a study plan with all seven selected days still available: its circle and bar were fully colored at 100%. A plan with only one past selected day showed 0% with no colored fill, while Work hours retained its distinct Off state. These test states are recorded in private QA images, not included in the store set.

Original JPEG captures, composition commands, source/output hashes, app-region pixel hashes, and capture-app provenance are retained in private local release artifacts outside the published source. All published images were explicitly exported as RGB PNG. This complete set replaces the mixed 0.1.6 (9) / 0.1.5 (8) captures; earlier screenshot descriptions and submission statuses are historical.
