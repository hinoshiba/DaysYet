# Native Mac screenshots

Prepared on 2026-09-06 from the official DaysYet macOS 0.1.2 (3) archive, bundle ID `com.hinoshiba.daysyet`. The `ja/` and `en-US/` folders each contain the following three images, attached to the corresponding custom localization in App Store Connect.

| File | Actual app content |
| --- | --- |
| `01-widget-settings.png` | The native Widget settings tab, with placement, size, detail mode, and theme controls. |
| `02-side-widget.png` | The actual expanded right-side widget with three progress circles and the current week's remaining time. |
| `03-top-widget.png` | The actual expanded top widget with its progress strips and the current week's remaining time. |

Every final image is a 1280 × 800 RGB PNG without an alpha channel. Original screenshot pixels are placed at 1:1 on a white canvas; they are not resampled, stretched, repainted, or generated. The original Settings captures measure 1229 × 768, the side-widget captures 204 × 212, and the top-widget captures 280 × 106. Pixel equality between each captured region and its source was verified during export. These final dimensions meet [Apple's Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

The Settings capture sits at `(25, 16)` with white margins and no added text. The side capture attaches to the right edge at `(1076, 294)`; the top capture attaches to the upper edge at `(500, 0)`. Side and top canvases include a short localized heading and caption outside the captured app region.

All app content was captured from the archived native app through Computer Use. The side and top images capture the real resident panel with details kept open. The captures use built-in week, month, and year periods; no personal dates, account information, other app windows, or private desktop content are included. No mock webpage or earlier QA image is used as app content.

Unedited originals, hashes, and capture provenance are retained outside the public screenshot folders in ignored local release artifacts. Capture-only placement and detail settings were restored, temporary language choices were limited to the app launch, and the archived app was stopped after capture. The separate daily-preview app and its preferences were preserved.

These images are attached to the macOS 0.1.2, build 3 submission. Final Submit for Review succeeded on 2026-09-06; App Store Connect confirmed one submitted item, no remaining draft, and Waiting for Review. The public Mac website deployment has been verified. Apple approval and public Mac availability are still pending.
