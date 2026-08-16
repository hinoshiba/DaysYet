# Release procedure

This document covers reproducible engineering steps. App Store agreements, tax and banking setup, rights clearance, and account-specific review contacts are maintained in the relevant private operator systems.

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
6. Before the first release, enable GitHub Pages with **GitHub Actions** as its source and enable Private Vulnerability Reporting in the repository settings. Confirm every `https://www.hinoshiba.com/DaysYet/` Japanese and English product, Privacy, Support, Terms, and Accessibility URL returns HTTP 200 without a redirect.

## Archive and TestFlight

1. In Xcode, select a generic iOS device and Product → Archive.
2. Validate the archive and inspect the app and Widget entitlements, Privacy Manifests, Bundle IDs, versions, app icon, embedded libraries, and `ja` / `en` resources.
3. Export and retain the Organizer privacy report, archive SHA-256, dependency inventory, SBOM, NOTICE, and asset/data-source register diffs.
4. Upload through Xcode Organizer and test with internal TestFlight before any external distribution.
5. Verify onboarding, edit/reset, all value styles, Widget rollover and refresh, device restart, and the published Privacy / Support URLs.

## Source release

After App Store approval, merge the reviewed release change, create a signed annotated `vX.Y.Z` tag, and publish an immutable GitHub Release with source-facing notes. Do not attach a signed IPA. Record the App Store version/build and retained archive hashes in the private release record.
