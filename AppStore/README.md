# App Store submission resources

**The current release candidate is iOS / iPadOS and macOS 0.1.6 (10).** Percentages, bars, and circles now count down the remaining time from 100% to 0%. The localized metadata and screenshots reflect that change. See the [0.1.6 countdown release record](releases/0.1.6-countdown.md) for validation and submission progress. Preparing these files does not establish an upload, App Review submission, approval, or public availability.

The previous iOS / iPadOS and macOS 0.1.4 (7) submissions were confirmed Waiting for Review on 2026-09-08 at 08:51 JST and 08:58 JST respectively. That record included 20 iPhone / iPad images and eight Mac images; see the [build 7 release record](releases/0.1.4-build7.md). The older submission narrative below records the initial Mac release and iOS 0.1.3. Those statuses and screenshot counts are historical. Use the current release record and [local Xcode release procedure](../docs/RELEASING.md) for this candidate.

## Earlier submission record

This directory contains the DaysYet App Store Connect metadata, screenshots, and review materials. Japanese is the primary language; English (U.S.) is the secondary localization. The release owner has chosen to add the native Mac app to the existing DaysYet record, Apple ID `6802000765`, with bundle ID `com.hinoshiba.daysyet`. The Mac target and platform configuration remain separate from iPhone / iPad. See [release readiness](review/release-readiness.md) for the current gaps.

On 2026-09-06 at 19:17 JST, the release owner's requested Japanese and English discovery update was saved in App Store Connect. The shared names were updated to **DaysYet - 人生時計とカウントダウン** and **DaysYet: Life & Time Countdown**, with localized subtitles. Both platforms' descriptions, promotional text, and keywords were also updated. All 16 text fields matched the local files as they stood then after navigating away and reading them again. At that time, iOS 0.1.3 (5) and macOS 0.1.2 (3) were Waiting for Review; this historical save confirmation does not establish approval, public availability, or search indexing. This requested change supersedes the name/keyword preservation instructions in the earlier submission record below. See the [discovery and social-link plan](marketing/discovery.md) for the research, selected terms, hashtag sets, and generated campaign links.

```text
configuration.yml           Existing iPhone / iPad app identity and categories
metadata/ja/                Japanese iPhone / iPad metadata
metadata/en-US/             English (U.S.) iPhone / iPad metadata
screenshots/<locale>/       iPhone / iPad device-class images
macos/configuration.yml     Native Mac platform and working candidate version
macos/metadata/<locale>/    Mac description, promotional text, keywords, update notes
macos/screenshots/<locale>/ Native Mac screenshots and capture record
review/                     Review instructions, questionnaire answers, and readiness
marketing/                  Discovery research, localized social copy, and campaign links
```

Build and upload the release on the authorized Mac using Xcode. Follow [the local release procedure](../docs/RELEASING.md), then complete the submission in the App Store Connect browser:

1. Use the macOS platform already added to the existing DaysYet record; do not create a separate app record. The Mac version is saved as 0.1.2 and the working archive is 0.1.2 (3); iOS 0.1.2 (4) remains released; the separately authorized iOS update candidate is 0.1.3 (5). `configuration.yml` describes iPhone / iPad; `macos/configuration.yml` describes native Mac. Confirm the processed build and reviewed source commit before submission. See [release readiness](review/release-readiness.md) for the current validation and upload status.
2. Run `./Scripts/check-compliance.sh --release`, complete the platform’s checks, and confirm every metadata statement matches the candidate.
3. In Xcode, select the platform’s shared scheme and an archive-capable destination, then choose **Product > Archive**. In Organizer, verify the resulting archive’s version, build, bundle identities, signing, entitlements, icon, and privacy report.
4. Use **Distribute App** in Organizer to upload to App Store Connect. Keep the archive on the authorized Mac. After Apple processes the upload, select that exact platform/version/build in App Store Connect.
5. Confirm Japanese and English (U.S.) metadata, current screenshots, and the review notes for the submitted platform. For Mac, use `macos/metadata/` and `review/notes-macos-en.txt`. Review the existing App Review contact directly in App Store Connect and keep it complete and current. Private review contact details belong there, not in this public repository; the public support contact remains `support@hinoshiba.com`.
6. Preserve the existing store names, categories, price, sales regions, and release method. Review App Privacy, Age Rating, Content Rights, and applicable regional compliance for the Mac addition. Apply any further commercial changes only if the release owner requests them.
7. After verification, use **Add for Review**, inspect the resulting draft submission, and then **Submit for Review** in the browser. Uploading an archive alone does not submit or publish it. [Apple’s submission instructions](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app) describe these separate steps.

When adding a platform, Apple transfers existing metadata except the description, promotional text, and screenshots. The Mac metadata folder supplies those text fields and Mac-specific `keywords.txt` files to replace inherited iOS Home Screen / Lock Screen terms only on the Mac version. Existing names, subtitles, and URLs remain unchanged, as do the iOS keywords. Review the inherited values in App Store Connect and retain the existing shared product identity. See [Apple’s Add platforms instructions](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms).

For the 2026-09-06 submission, the iPhone / iPad `release_notes.txt` files described the 0.1.3 update from released 0.1.2 (4): daily Work hours, overnight schedules, and selectable week starts across the app and Widgets. The Mac `release_notes.txt` files were empty for that initial platform release; a first platform version has no What’s New field. The separately authorized iOS 0.1.3 (5) update completed validation, upload, and processing. Its exact build, Japanese/English metadata and review notes, and all 20 refreshed screenshots are attached in App Store Connect.

On 2026-09-06 at 19:04 JST, final **Submit for Review** succeeded for iOS 0.1.3 (5). App Store Connect confirmed one submitted item and **Waiting for Review** (「審査待ち」). Automatic release after approval is enabled. The source was published through [PR #6](https://github.com/hinoshiba/DaysYet/pull/6); CI passed for the clean archived candidate `3fce5f8` and the identical source tree merged to main as `dc405d6`. Apple has not yet approved or publicly released this iOS update; iOS 0.1.2 (4) remains the released version.

Generate fresh iPhone / iPad screenshots with `./Scripts/capture-store-screenshots.sh`. The capture workflow requires ImageMagick 7. If CoreSimulator is usable but `simctl bootstatus` is stalled by an OS migrator, set `DAYSYET_SCREENSHOT_SKIP_BOOTSTATUS=1` only after confirming the simulator Home Screen is responsive.

Each locale/device folder contains seven screenshots recaptured on 2026-09-13 from the final iOS 0.1.6 (10) Debug build: (1) remaining-time bars, (2) time left with remaining percentage and bars, (3) the timeline library, (4) on-device privacy and OSS information, (5) the activity-hours and week-start editor, (6) the study-day editor, and (7) the study-day widget preview. The 28 images use fictional dates and schedules. Japanese and English iPhone/iPad combined-view and settings captures were visually checked for the new life-token heading, remaining percentages, matching bar lengths, layout, and the 0.1.6 (10) version label. iPhone images are 1320 × 2868 and iPad images are 2064 × 2752, RGB without alpha. The capture uses DEBUG-only navigation and sample-data arguments; the real app UI is captured without generated artwork. The website’s eight WebP images were regenerated from the iPhone captures. This refresh does not establish an upload or App Review submission.

Mac screenshots are saved under `macos/screenshots/<locale>/`: seven images per locale, 14 total, all recaptured on 2026-09-13 from the tested macOS 0.1.6 (10) Debug build. They show remaining-time circles, shrinking bars, current settings, and fictional study plans. Native 100%, 0%, and Off states were also verified. See [the Mac screenshot record](macos/screenshots/README.md) for capture isolation, source provenance, and pixel verification. Screenshot preparation does not establish upload or review submission. [Apple’s screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) require Mac images with a 16:10 aspect ratio and no alpha channel.

On 2026-09-06, **Submit for Review** succeeded separately for macOS 0.1.2, build 3. App Store Connect confirmed one submitted item and shows **Waiting for Review** (「審査待ち」), with no draft remaining. That submission contained only the Mac version. The public Mac website update is deployed and verified, and the existing automatic-release-after-approval setting remains selected. Apple has not yet approved the Mac release.

`Scripts/validate-store-assets.py` validates the iPhone / iPad metadata and screenshots. Its success does not validate `macos/` or establish Mac submission readiness. Check Mac descriptions (4,000 characters), promotional text (170 characters), keywords (100 bytes), update notes, screenshot dimensions, and the final native UI separately.

The release workflow uses local Xcode Archive and Organizer upload.

The iPhone / iPad App Store icon is embedded in the build at `DaysYet/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; the native Mac icon is in `DaysYetMac/Assets.xcassets/MacAppIcon.appiconset`. Validate the icon included in each archive.
