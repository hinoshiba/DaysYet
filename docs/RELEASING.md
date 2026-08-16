# Release procedure

This document covers reproducible engineering steps. The public support email is `support@hinoshiba.com`. The optional App Review contact fields are intentionally left blank, matching the accepted setup of the existing Youyaku listing. App Store agreements, tax and banking setup, and rights clearance are maintained in the relevant private operator systems.

## Version and verification

1. Start from a clean, up-to-date `main` branch with green CI.
2. Run `./Scripts/bump-version.sh X.Y.Z BUILD` with a monotonically increasing build number.
3. Run:

   ```bash
   ./Scripts/check-compliance.sh --release
   ./build.sh test
   ```

4. Verify the Japanese and English app, Widget gallery, Widget configuration, Small/Medium Widgets, VoiceOver, Dynamic Type, light/dark/tinted modes, timezone changes, DST, leap day, and date-boundary behavior.
5. Confirm the metadata and screenshots under `AppStore/` match the exact release build.
6. Before the first release, enable GitHub Pages with **GitHub Actions** as its source and enable Private Vulnerability Reporting in the repository settings. Confirm the Japanese page at `https://daysyet.hinoshiba.com/` and the English page at `https://daysyet.hinoshiba.com/en/` return HTTP 200 without a redirect; verify each page's `#privacy`, `#terms`, `#support`, and `#accessibility` section link and its `mailto:support@hinoshiba.com` contact.

## Archive and TestFlight

1. In Xcode, select a generic iOS device and Product → Archive.
2. Validate the archive and inspect the app and Widget entitlements, Privacy Manifests, Bundle IDs, versions, app icon, embedded libraries, and `ja` / `en` resources.
3. Export and retain the Organizer privacy report, archive SHA-256, dependency inventory, SBOM, NOTICE, and asset/data-source register diffs.
4. Upload through Xcode Organizer and test with internal TestFlight before any external distribution.
5. Verify onboarding, edit/reset, all value styles, Widget rollover and refresh, device restart, and the published Privacy / Support section URLs.

## Source release

After App Store approval, merge the reviewed release change, create a signed annotated `vX.Y.Z` tag, and publish an immutable GitHub Release with source-facing notes. Do not attach a signed IPA. Record the App Store version/build and retained archive hashes in the private release record.
