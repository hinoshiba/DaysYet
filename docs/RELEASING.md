# Local Xcode release procedure

Create release archives on the authorized Mac in Xcode, validate and upload
through Organizer, then select the processed build in App Store Connect for
App Review. The monitored public support contact is `support@hinoshiba.com`.

Repository Xcode Cloud release hooks have been removed. This does not establish
whether a server-side workflow exists or is disabled; inspect App Store Connect
separately when retiring any previously configured workflow.

## Release identity

- Xcode project: `DaysYet.xcodeproj`
- Shared scheme: `DaysYet`
- Platform: iOS / iPadOS 17 or later
- App bundle ID: `com.hinoshiba.daysyet`
- Widget bundle ID: `com.hinoshiba.daysyet.widget`
- App Group: `group.com.hinoshiba.daysyet`
- Version source: `MARKETING_VERSION` in `project.yml`
- Build source: `CURRENT_PROJECT_VERSION` in `project.yml`

`project.yml` is the project-configuration source of truth. After changing it,
run `xcodegen generate` and commit the generated project and shared scheme;
pull-request CI rejects a stale project. Select the authorized Apple Developer
team locally for signing. Keep certificates, private keys, provisioning profiles,
and account credentials outside Git. Reuse the team's existing authorized
signing identities; Store distribution uses Apple Distribution, never Developer
ID signing.

## Prepare a candidate

1. Choose a marketing version and build number that App Store Connect accepts
   for the intended platform and version. Keep the project and
   `AppStore/configuration.yml` consistent with `Scripts/bump-version.sh`, and
   regenerate the project. An uploaded build number must not be reused.
2. Run `./Scripts/check-compliance.sh --release` and `./build.sh test`.
3. Verify Japanese and English UI, Widget configuration, Small/Medium and Lock
   Screen Widgets, VoiceOver, Dynamic Type, light/dark/tinted appearance, timezone
   and DST changes, leap day, and date boundaries on supported devices. Check
   that `AppStore/` metadata and screenshots describe the candidate.
4. Review the candidate commit and its CI result. Record the exact commit,
   version, and build used for the archive.

## Archive, validate, and upload

1. Open `DaysYet.xcodeproj`, select `DaysYet` and a generic iOS device destination,
   and choose Product > Archive. Use the authorized team's local signing setup.
2. Inspect the resulting archive in Organizer. Confirm the product, bundle IDs,
   version/build, signing team, App Group entitlement on the app and Widget,
   architectures, dSYM files, icon, Privacy Manifests, and Japanese/English
   resources against the intended candidate.
3. Use Organizer's App Store Connect distribution path to validate the app.
   Review the result and resolve errors before uploading. Validation and upload
   are separate from App Review submission.
4. Upload the candidate from Organizer and wait for App Store Connect processing.
   Confirm the exact version/build is available before selecting it for review.

## Submit the processed build

Check App Privacy, age rating, export compliance, screenshots, review notes,
and live Privacy/Support URLs against the uploaded binary. Select the exact
processed build on the existing DaysYet App Store record and submit it to App
Review. Preserve the intended release method and other shared Store settings.
A successful upload does not submit the app or make it publicly available.

Keep signed archives and distribution artifacts on the authorized Mac or in an
approved private release store, outside the checkout and ordinary GitHub Actions
artifacts. Once released, use an immutable source tag and GitHub Release for the
reviewed commit; never move an existing release tag or attach an IPA to a public
source release.
