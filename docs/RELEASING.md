# Xcode Cloud release procedure

DaysYet App Store binaries are built only by Xcode Cloud. Unsigned Simulator
builds and tests remain available for development, but local archive, export,
and upload are not release steps. The monitored public support contact is
`support@hinoshiba.com`.

## Release identity

- Xcode project: `DaysYet.xcodeproj`
- Shared scheme: `DaysYet`
- Platform: iOS / iPadOS 17 or later
- App bundle ID: `com.hinoshiba.daysyet`
- Widget bundle ID: `com.hinoshiba.daysyet.widget`
- App Group: `group.com.hinoshiba.daysyet`
- Apple Developer Team: `94HVVWXLK3`
- Version source: `MARKETING_VERSION` in `project.yml`
- Release tag: immutable `vX.Y.Z` (for example, `v0.1.1`)

`project.yml` is the project-configuration source of truth. The generated
project and shared scheme are intentionally committed because Xcode Cloud must
always be able to discover them. Run `xcodegen generate` after changing
`project.yml` and commit both; pull-request CI rejects a stale project.

## One-time Xcode Cloud setup

Complete initial onboarding in Xcode after this change reaches `main`:

1. Open `DaysYet.xcodeproj`, select the `DaysYet` scheme, and choose Product >
   Xcode Cloud > Create Workflow (or use the Cloud section of the Report
   navigator).
2. Select Team `94HVVWXLK3` and confirm the existing App Store Connect record
   whose bundle ID is exactly `com.hinoshiba.daysyet`. Do not create a second
   app record or change the bundle ID.
3. Grant Xcode Cloud access to `hinoshiba/DaysYet` through GitHub. Limit the
   authorization to the repository access required for this product.
4. Keep automatic signing enabled. Confirm that the app ID, Widget ID, and App
   Group above exist and that both shipped bundles have the App Group capability.
   Do not put certificates, private keys, profiles, or App Store Connect keys in
   GitHub.
5. Start an initial non-Archive validation build from `main` to establish the
   Xcode Cloud product. The release-only script intentionally rejects an Archive
   that was not started by a release tag.

After that first build, create or edit the release workflow with these settings:

| Section | Setting |
| --- | --- |
| General | Name `App Store Release`; enable **Restrict Editing** |
| Start Conditions | **Tag Changes**; custom pattern `v*`; remove branch-change conditions; set **Auto-cancel Builds** to **Off** in this condition's Options |
| Environment | Latest stable Xcode and macOS supported by the project; **Clean** enabled |
| Action 1 | **Test**, scheme `DaysYet`, current supported iPhone and iPad Simulators |
| Action 2 | **Archive**, platform **iOS**, scheme `DaysYet`, Deployment Preparation **TestFlight and App Store** |
| Post-Actions | None is required to upload the candidate. Add a TestFlight post-action only if every tagged build should be assigned to a specific tester group. |

The pre-Xcodebuild script rejects an Archive unless its platform, scheme,
bundle ID, and Team match DaysYet, `CI_TAG` is exactly `vX.Y.Z`, its version
matches `project.yml`, `AppStore/configuration.yml`, and the checked-in Xcode
project, and `CI_BUILD_NUMBER` is a positive integer. It
then applies the Cloud number as `CURRENT_PROJECT_VERSION` in the temporary
checkout and runs the release compliance checks.

In App Store Connect, open DaysYet > Xcode Cloud > Settings > Build Number and
set **Next Build Number** above the highest build already uploaded for the
current marketing version. The repository currently records build `1`; if
`0.1.0 (1)` already exists in App Store Connect, the first Cloud build must use
at least `2`.

## Protect release authority

Before enabling the release workflow, create an **Active** tag ruleset in
GitHub **Settings > Rules > Rulesets** for the `v*` target pattern. Enable
**Restrict creations**, **Restrict updates**, and **Restrict deletions**, and
allow bypass only for the designated release manager. Create a release tag only
on a reviewed `main` commit. Never move, replace, or reuse it. Keep Xcode Cloud
**Restrict Editing** enabled and limit workflow administration to the same
small release group.

## Prepare and tag a release

1. Update the marketing version and repository fallback build number. The
   helper also updates `AppStore/configuration.yml` and regenerates the project:

   ```sh
   ./Scripts/bump-version.sh 0.1.1 2
   ```

   Xcode Cloud replaces the fallback build number with `CI_BUILD_NUMBER` for
   the archive.
2. Run the repository checks and unsigned tests:

   ```sh
   ./Scripts/check-compliance.sh --release
   ./build.sh test
   ```

3. Verify the Japanese and English app, Widget gallery and configuration,
   Small/Medium Widgets, VoiceOver, Dynamic Type, light/dark/tinted modes,
   timezone and DST changes, leap day, and date boundaries on supported devices.
   Confirm the metadata and screenshots under `AppStore/` match the candidate.
4. Merge the version change through a reviewed pull request and wait for GitHub
   CI on the exact `main` commit to pass.
5. Create and push the tag on that commit:

   ```sh
   git tag -a v0.1.1 -m "DaysYet 0.1.1"
   git push origin v0.1.1
   ```

Never move or replace a release tag. Correct a failed or superseded candidate
with a new version tag.

## Verify the cloud release

1. In App Store Connect > DaysYet > Xcode Cloud, confirm `App Store Release`
   started from the expected tag and commit.
2. Require successful Test and Archive actions. In the archive report, confirm
   Team `94HVVWXLK3`, both bundle IDs, the App Group on both bundles, the tag's
   marketing version, the Xcode Cloud build number, app icon, Privacy Manifests,
   and Japanese/English resources.
3. Wait for processing and confirm the exact version/build appears in TestFlight
   and is eligible for App Store submission. Complete internal TestFlight checks.
4. Recheck App Privacy, age rating, export compliance, screenshots, review
   notes, and public Privacy/Support URLs against that binary.
5. Select the exact build for the App Store version and submit it to App Review
   explicitly. A release tag uploads a candidate; it does not submit or release
   the app automatically.

Keep signed archives and exported artifacts in Xcode Cloud/App Store Connect,
not in the checkout or ordinary GitHub Actions artifacts. After approval,
publish an immutable GitHub Release for the existing tag with source-facing
notes; do not attach an IPA.
