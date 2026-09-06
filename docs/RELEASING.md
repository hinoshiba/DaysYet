# Local Xcode App Store release procedure

Release archives are created on an authorized Mac in Xcode, validated in
Organizer, and uploaded explicitly to App Store Connect. GitHub Actions runs
unsigned checks and tests. A Git tag does not build, upload, submit, or publish
an app. The monitored public support contact is `support@hinoshiba.com`.

## Retire previous hosted automation once

If an earlier Xcode Cloud workflow exists, disable it in Xcode or App Store
Connect before the next release. Verify that branch or tag changes no longer
start builds or automatic distribution. Removing repository hooks does not
change server-side workflow settings. Preserve existing run history and build
artifacts, and record the verified state in the private release record.

## Products and configuration

| Product | Shared scheme | Archive destination | Bundle ID |
| --- | --- | --- | --- |
| iPhone / iPad | `DaysYet` | Any iOS Device | `com.hinoshiba.daysyet` |
| macOS | `DaysYetMac` | Any Mac | `com.hinoshiba.daysyet` |

Add macOS as a platform of the existing DaysYet App Store Connect record.
Both app targets intentionally use the same bundle ID; the Mac test bundle
keeps its separate `com.hinoshiba.daysyet.mac.tests` identifier.

The iOS app embeds `com.hinoshiba.daysyet.widget`; both use
`group.com.hinoshiba.daysyet`. The Mac app uses its own sandbox and has no
WidgetKit extension. Sharing an App Store record and bundle ID does not sync
preferences between operating systems or devices. Minimum runtime versions
are iOS / iPadOS 17 and macOS 14.

The Mac scheme supports local Archive. This does not establish Mac App Store
readiness: the macOS platform in the existing record, signing and entitlements, platform
metadata, screenshots, accessibility claims, and sandboxed behavior must be
verified for a Mac submission. The existing screenshot capture and release
asset checks cover the iOS submission package.

`project.yml` is the source of truth for targets and each platform's marketing
version and build number. The iOS app, Widget extension, and iOS tests share
one version; the Mac app and Mac tests share a separately managed version.
The generated project and shared schemes remain committed so a clean
checkout opens in Xcode and CI can verify reproducibility. Regenerate with
`./build.sh project` after configuration changes; include the generated files
in the same reviewed change.

## Configure the authorized Mac

1. Use a stable Xcode release and SDK accepted by App Store Connect for the
   chosen platform. Check the selected Xcode installation with
   `xcodebuild -version`. Install XcodeGen 2.45.4 for project generation.
2. In Xcode Settings > Accounts, use the authorized Apple Developer account.
   Confirm that the existing signing identity **and its private key** are
   available in the authorized Keychain, and that the app identifiers and
   any required provisioning profiles belong to the intended team. The iOS app and Widget
   need their own profiles with the same App Group entitlement.
3. Create the local configuration once, from the checkout root:

   ```sh
   cp -n Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```

   Fill `DEVELOPMENT_TEAM` in that local file. It is ignored by Git. The public
   `Config/Signing.xcconfig` includes it optionally, so unsigned builds and
   tests also work without it. Do not select a team or enter personal signing
   values in Xcode in a way that writes them into the tracked project.
4. Shared signing defaults use automatic signing and the generic **Apple
   Development** role for building and archiving. Organizer prepares the
   distribution signature for the chosen channel. iOS distribution uses
   **Apple Distribution**. Mac app signing can use **Apple Distribution** or
   an existing valid **Mac App Distribution** identity, whose legacy
   Keychain role is **3rd Party Mac Developer Application**. The Mac installer
   package uses **Mac Installer Distribution** (**3rd Party Mac Developer
   Installer**). In Organizer's manual signing flow, select the app and
   installer identities explicitly. See Apple's [certificate types](https://developer.apple.com/help/account/certificates/certificates-overview/).

   If manual Release signing is needed, set
   `CODE_SIGN_STYLE[config=Release] = Manual` locally and select the existing
   `CODE_SIGN_IDENTITY` for that platform. Scope platform-specific overrides
   to the appropriate target or SDK so a Mac-only role is not applied to iOS.
   Fill `DAYSYET_IOS_PROFILE` and `DAYSYET_WIDGET_PROFILE` with the existing
   iOS profile names. Set `DAYSYET_MAC_PROFILE` only when the Mac candidate's
   entitlements or distribution route require a profile. Each target
   references its own profile variable. Verify the resolved settings in
   Xcode before archiving. See Apple's [signing workflow](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html)
   and [archive-to-distribution process](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/).

   The current Mac app uses App Sandbox without restricted entitlements,
   so its Mac App Store route can leave the provisioning profile empty.
   **TestFlight always requires a profile.** Reassess the profile requirement
   when adding capabilities; see [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles#Entitlements-on-macOS).
5. Reuse the team's existing distribution identity for its certificate role.
   **Developer ID Application is not valid for a Mac App Store archive.**
   Developer ID Installer is also for distribution outside the Mac App Store.
   If the required identity or private key is unavailable, resolve access with
   the release owner before proceeding. Creating, exporting, importing,
   revoking, or replacing certificates and keys is a separate authorized task.

Keep private keys and credentials in Keychain or an approved encrypted secret
store. A local xcconfig contains settings, not passwords or private key data.
Do not upload certificates, provisioning profiles, export-option plists,
archives, or diagnostic bundles to GitHub Actions or the source repository.

## Prepare the candidate

1. Choose a marketing version and a build number greater than any already
   uploaded for that platform and version. Use
   `./Scripts/bump-version.sh ios <marketing-version> <build-number>` for iOS,
   or `./Scripts/bump-version.sh macos <marketing-version> <build-number>`
   for Mac. Omitting the platform preserves the original two-argument command
   and defaults to iOS. The script updates only the selected platform's
   targets in `project.yml`, its App Store configuration (`AppStore/configuration.yml`
   for iOS or `AppStore/macos/configuration.yml` for Mac), and regenerates the
   project. The other platform's version stays unchanged. No Cloud build
   number replaces this value.
2. Run the unsigned checks for the supported platforms:

   ```sh
   ./Scripts/check-compliance.sh --release
   ./build.sh test
   ./build.sh test-mac
   ```

3. Verify the chosen platform on supported hardware with synthetic personal
   data. Check Japanese and English, editing and reset, VoiceOver, display
   sizes, date boundaries, overnight work, week start settings, time zones,
   DST, and relaunch. For iOS, also verify Widget families and per-Widget
   configuration; for Mac, verify each edge, display transitions, hover,
   settings access, and sandbox behavior. Review the actual screenshots and
   metadata against this candidate; image size checks do not establish that
   their content is current.
4. Review and merge the source and version changes. Require CI to pass on the
   exact release commit. Start the Archive from that clean commit, with no
   tracked local modifications and no previously published tag reassigned.
   Record the commit, platform, Xcode version, marketing version, and build
   number in the release record.

## Archive, validate, and upload

1. Open `DaysYet.xcodeproj` in local Xcode. Select `DaysYet` and **Any iOS
   Device** for iOS, or `DaysYetMac` and **Any Mac** for macOS. Choose a generic
   device destination, not a Simulator or an architecture-specific test run.
2. Confirm Edit Scheme > Archive uses **Release**, and inspect the resolved
   signing team, certificate role, profile, version, build number, bundle IDs,
   and entitlements. For Mac, confirm the archive includes the intended
   processor architectures. Do not proceed if Xcode would need to create a
   new signing identity to resolve the configuration.
3. Choose **Product > Archive**. Open the resulting archive in Organizer and
   confirm its product, commit record, version, and build number. Archive
   success alone does not validate signing, platform eligibility, or review
   readiness. For Mac, the product is `DaysYet.app` and its distribution
   package is `DaysYet.pkg`; `DaysYetMac` remains the technical target,
   scheme, and module name.
4. Use Organizer's **Validate App** action when offered. Resolve validation
   errors, then choose **Distribute App**, select the **App Store Connect** /
   **TestFlight & App Store** route offered by the installed Xcode, and choose
   **Upload**. Review the signing and entitlement summary before confirming
   the upload. Do not choose Developer ID, direct distribution, or development
   export for an App Store candidate.
5. Wait for processing in App Store Connect. Confirm that the exact platform,
   version, and build appear and review any processing issues. Complete the
   relevant TestFlight checks, then verify App Privacy, export compliance,
   age rating, screenshots, review notes, and the live Privacy/Support URLs.
6. Select the processed build for the App Store version. Adding it for review,
   submitting it to App Review, and releasing an approved version are explicit
   App Store Connect actions; uploading does not perform them automatically.

Keep the signed archive and symbols in Organizer or approved private storage,
not in the checkout. If a corrected binary is needed, increase the build number
and repeat the checks. Tag the reviewed release commit with an immutable
`vX.Y.Z` tag according to the release record; never move or reuse an existing
tag. Source-facing GitHub release notes must not attach signed app artifacts.

## Before publishing source

Enable the local pre-commit guard once in this checkout, integrating it with
any existing hooks first:

```sh
git config --local core.hooksPath .githooks
```

The hook scans the exact Git index and rejects detected private material
before creating a commit. This is an opt-in local setting, not a repository
setting that a clone activates automatically.

Run the working-file check and inspect the exact staged content before a
public commit or push:

```sh
python3 Scripts/check-public-files.py
python3 Scripts/check-public-files.py --staged
git diff --cached --check
git diff --cached --stat
```

The checker rejects recognizable keys/tokens, fixed signing team or personal
certificate values, private local configuration, provisioning material, and
build artifacts. It prints paths and reasons, never matched values. It checks
working files by default and the Git index with `--staged`; it does **not**
scan Git history, images for personal data, or every possible secret format.
Before public release, also run the standard [Gitleaks](https://github.com/gitleaks/gitleaks)
history scan with redacted output:

```sh
gitleaks git --redact --log-opts="--all" .
```

Review the staged diff and any history that will become public separately,
including generated projects, screenshots, support data, and added archives.
Ignored files can still be force-added, so `.gitignore` alone is insufficient.
If a real credential is discovered, stop publication and coordinate private
remediation; deleting the latest copy does not remove it from existing history.
