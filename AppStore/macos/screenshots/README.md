# Native Mac screenshots

The `ja/` and `en-US/` folders each contain seven images for the corresponding App Store Connect localization, for 14 images in total. On 2026-09-13, **only `01-widget-settings.png` in each locale was replaced** with a native DaysYet macOS **0.1.6 (9)** Debug capture showing the new graph magnification and detail-size controls. The other **12 images are retained byte for byte from 0.1.5 (8)**, captured on 2026-09-11, and show features unchanged in 0.1.6. This file records screenshot preparation and verification; it does not establish upload or review submission. The prior submission is recorded in the [0.1.5 release record](../../releases/0.1.5.md).

| File | Actual app content |
| --- | --- |
| `01-widget-settings.png` | 0.1.6 (9): the native Widget tab showing Position, Graph magnification enabled at 135%, Detail size at 100%, and detail display controls. The new option's default-off behavior and Reduce Motion guidance are visible. |
| `02-side-widget.png` | The expanded right-side widget with eight progress circles. Japanese shows the current month; English shows the fictional study plan. |
| `03-top-widget.png` | The expanded top widget with three progress strips, using the first three selected timelines. Japanese shows the current month; English shows the fictional study plan. |
| `04-activity-hours.png` | Two activity schedules with labels, start/end times, and active weekday controls. |
| `05-colors.png` | Four color templates and the visible timelines' individual color controls. Top placement is selected, so three color rows are shown. |
| `06-study-days.png` | The native study-plan editor with its name, date range, weekday selection, calendar, and selected-day count. |
| `07-circle-selection.png` | Eight distinct timelines, their remove controls, the disabled Add Circle button at the maximum, and the saved study-plan summary. |

Every final image is a **1280 × 800 RGB PNG without an alpha channel**. Decoded original screenshot pixels are placed at 1:1 on a white canvas, with no resampling, stretching, retouching, generated artwork, or added captions. Each output's app region was compared with its decoded native capture and matched byte for byte; every pixel outside that region was verified white. These dimensions meet [Apple's Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

| Native region | Size | Position on the canvas |
| --- | --- | --- |
| Settings, activity hours, colors, circle selection | 780 × 744 | `(250, 28)` |
| Study-plan editor | 820 × 620 | `(230, 90)` |
| Side widget | 204 × 462 | `(1076, 169)`, attached to the right edge |
| Top widget | 280 × 106 | `(500, 0)`, attached to the top edge |

The two 0.1.6 settings images were captured through Computer Use from a native Debug app built using the Xcode GUI. An ignored capture project overrode only the Mac Debug bundle ID to isolate the capture app; the product source and app UI were unchanged. Japanese and English screenshot-mode arguments supplied synthetic profiles and UUID-scoped temporary preferences. Normal app settings were not edited. A private source-hash manifest verifies all 44 tracked Swift files against the product source used for these captures.

The 12 retained 0.1.5 images were also captured from the running native Debug app through Computer Use with synthetic, temporary profiles and preferences. For those English captures, the same Debug app was copied with a dedicated capture-only Bundle ID and ad-hoc signature to keep it separate from the installed app. Product source and app UI were not changed for photography, and temporary language arguments applied only to the capture process.

The study plans in the retained images are fictional examples. Japanese uses September 11–October 8 with Monday, Wednesday, and Saturday selected, plus September 11 individually, for 13 selected and remaining days at capture. English uses September 1–28 with Monday, Wednesday, and Friday selected, plus September 12 individually, for 13 selected days and nine remaining days at capture. Remaining counts include today when selected and describe scheduled days, not completed study sessions. The activity images show daily activity from 07:00 to 23:00 every day and work hours from 09:00 to 18:00 with weekends off. No private desktop content or other app windows are included.

Original captures, composition commands, source/output hashes, app-region pixel hashes, and capture-app provenance are retained in private local release artifacts outside the published source. Raw tool captures are JPEG-encoded (some older local filenames end in `.png`); all published screenshot files were explicitly exported as RGB PNG. Both new settings images were verified to preserve their 780 × 744 native regions exactly at `(250, 28)`, and the retained 12 files were verified unchanged from the prior set.

The original 0.1.5 set replaced the eight screenshots prepared from macOS 0.1.4 (7) on 2026-09-08. Earlier screenshot dimensions, headings, counts, and submission statuses are historical and do not describe this mixed 0.1.6/0.1.5 set.
