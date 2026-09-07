# Native Mac screenshots

Prepared on 2026-09-08 from the native DaysYet macOS 0.1.4 (7) Debug app. The `ja/` and `en-US/` folders each contain four images for the corresponding App Store Connect localization. These are candidate screenshots; this file does not record an upload or review submission.

| File | Actual app content |
| --- | --- |
| `01-widget-settings.png` | The native Widget settings tab, with placement, size, and detail controls. |
| `02-side-widget.png` | The actual expanded right-side widget with three progress circles and the current month's remaining time. |
| `03-top-widget.png` | The actual expanded top widget with its progress strips and the current month's remaining time. |
| `04-activity-hours.png` | The native Timelines tab showing two activity schedules, their labels and times, and weekday controls. |

Every final image is a 1280 × 800 RGB PNG without an alpha channel. Decoded original screenshot pixels are placed at 1:1 on a white canvas; they are not resampled, stretched, repainted, or generated. The original Settings and activity captures measure 780 × 744, the side-widget captures 204 × 212, and the top-widget captures 280 × 106. Exact pixel equality between every captured app region and its decoded source was verified during export. These final dimensions meet [Apple's Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

The Settings and activity captures sit at `(250, 28)` with white margins and no added text. The side capture attaches to the right edge at `(1076, 294)`; the top capture attaches to the upper edge at `(500, 0)`. Side and top canvases retain the existing localized heading and caption. Every pixel outside those replaced app regions was verified unchanged.

All app content was captured from the running native Debug app through Computer Use. A copied app bundle with isolated preferences and `--screenshot-mode` supplied synthetic dates and schedules. The side and top images show the real resident panel with details kept open, using this month, this year, and a fictional milestone. The activity images show daily activity from 07:00 to 23:00 and work hours from 09:00 to 18:00, with weekends off for work. No personal dates, account information, other app windows, or private desktop content are included. No mock webpage or earlier QA image is used as app content.

Unedited originals, source and output hashes, app-region pixel hashes, and export provenance are retained outside the public screenshot folders in ignored local release artifacts. Temporary language choices were limited to the capture app launch. The isolated capture app was stopped after capture; the user's normal app preferences were kept separate.

The previous screenshots were captured from the official macOS 0.1.2 (3) archive and submitted on 2026-09-06. That is historical provenance for the replaced images, not the version or submission status of this set. See the release records for current store status.
