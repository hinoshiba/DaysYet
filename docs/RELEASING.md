# Release procedure

This document covers reproducible engineering steps. The public support and App Review email is `support@hinoshiba.com`; App Store agreements, tax and banking setup, rights clearance, and private review-contact details such as legal name and phone are maintained in the relevant private operator systems.

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

## Signing assets

Applications released by the same Apple Developer Team reuse the Team-managed approved distribution signing identity; do not create an application-specific distribution private key. The certificate type must match the platform and distribution channel. This iOS App Store release uses the App Store distribution identity selected by Xcode or the private release system. A Developer ID Application identity is for macOS software distributed outside the Mac App Store, not for this release. See Apple's [certificate overview](https://developer.apple.com/help/account/certificates/certificates-overview).

Resolve signing material only from an authorized macOS Keychain or private release system outside the checkout. Do not export it into this working tree, create a repository signing directory, or paste identity names, fingerprints, Team IDs, personal details, Keychain paths, or identity-discovery output into source, public logs, issues, pull requests, or release notes. Public CI remains unsigned.

If exposure is suspected, stop the release and use the private security process. Revoke or rotate the affected credential before signing another build; deleting a file in a later commit is not remediation for material already present in Git history.

## Archive and TestFlight

1. In Xcode, select a generic iOS device and Product → Archive.
2. Validate the archive and inspect the app and Widget entitlements, Privacy Manifests, Bundle IDs, versions, app icon, embedded libraries, and `ja` / `en` resources.
3. Export and retain the Organizer privacy report, archive SHA-256, dependency inventory, SBOM, NOTICE, and asset/data-source register diffs.
4. Upload through Xcode Organizer and test with internal TestFlight before any external distribution.
5. Verify onboarding, edit/reset, all value styles, Widget rollover and refresh, device restart, and the published Privacy / Support section URLs.

## Source release

After App Store approval, merge the reviewed release change, create a signed annotated `vX.Y.Z` tag, and publish an immutable GitHub Release with source-facing notes. Do not attach a signed IPA. Record the App Store version/build and retained archive hashes in the private release record.
