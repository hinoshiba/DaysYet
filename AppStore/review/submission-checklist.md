# Submission checklist

## iOS 0.1.3 (5)

- [x] The release owner separately authorized the iPhone / iPad update on 2026-09-06.
- [x] [PR #6](https://github.com/hinoshiba/DaysYet/pull/6) published the shared source. [CI passed for candidate `3fce5f8`](https://github.com/hinoshiba/DaysYet/actions/runs/34025340509) and [main merge `dc405d6`](https://github.com/hinoshiba/DaysYet/actions/runs/34025766316), which has the same source tree.
- [x] The official archive was created from clean candidate `3fce5f8`; app and Widget versions are 0.1.3 (5). Signatures, App Group/profile entitlements, privacy manifests, and matching dSYMs were verified, with no test bundle included.
- [x] Apple validation, upload, and processing completed; exact iOS build 5 is selected for version 0.1.3.
- [x] Japanese and English descriptions, promotional text, localized What's New, and review notes are saved for the update.
- [x] All 20 reviewed screenshots are attached: five per language/device set for Japanese and English, iPhone and iPad.
- [x] Add for Review and final Submit for Review succeeded. Submission details confirm iOS 0.1.3 (5), submitted on 2026-09-06 at 19:04 JST, and Waiting for Review (「審査待ち」). App Store Connect confirmed one submitted item.
- [x] Automatic release after approval is enabled; the existing non-phased release setting is preserved.
- [ ] Apple has approved iOS 0.1.3 and its public availability has been verified. iOS 0.1.2 (4) remains the released version.

## Mac submission and shared checks

- [x] The release owner selected native Mac as an additional platform on the existing DaysYet record, Apple ID `6802000765`. This does not submit an iOS update.
- [x] The macOS platform is added to the existing DaysYet record, and version 0.1.2 is saved.
- [ ] App Store Connect Primary Language is Japanese; English (U.S.) localization is added.
- [x] For iOS / iPadOS, Bundle ID `com.hinoshiba.daysyet`, Widget ID `com.hinoshiba.daysyet.widget`, and App Group `group.com.hinoshiba.daysyet` match the existing record and signing capabilities.
- [x] The native Mac target and working archive use `com.hinoshiba.daysyet`, matching the existing record and `macos/configuration.yml`. See [release readiness](release-readiness.md).
- [x] The working Mac candidate is 0.1.2 (3), and its App Store Connect version is saved as 0.1.2. iOS 0.1.2 (4) remains released.
- [x] Published source and candidate/main CI are recorded in the iOS section above. The earlier Mac archive retains its separate historical verification record.
- [x] The DaysYet Mac archive succeeded and its Apple silicon/Intel architectures, product names, strict signature, sandbox, Hardened Runtime, privacy manifest, resources, payload permissions, and dSYM were verified.
- [x] Apple Validate passed without errors. Its sole warning concerns the provisioning profile needed for TestFlight.
- [x] The iOS archive contains the Widget extension and expected App Group entitlements. The Mac archive contains the native app, its sandbox entitlements, and Mac privacy manifest.
- [x] Organizer upload completed for DaysYet 0.1.2 (3), with only the TestFlight provisioning-profile warning.
- [x] App Store Connect processing succeeded; Mac build 0.1.2 (3) is attached to version 0.1.2 and saved.
- [x] Japanese and English Mac descriptions, promotional text, and Mac-specific keywords are saved in App Store Connect. The top-level `metadata/` remains iPhone / iPad copy.
- [ ] Review the saved Mac copy against the attached candidate and screenshots before submission, keeping shared names, subtitles, and URLs unchanged.
- [x] iOS 0.1.3 (5) screenshots are refreshed and visually reviewed for both languages and both device classes: five images per set, including the Work hours / week-start editor.
- [x] Japanese and English (U.S.) each have three 1280 × 800 RGB screenshots under `macos/screenshots/<locale>/`, attached to their correct App Store Connect localizations. Settings and expanded side/top widgets come from the official archive; captured pixels are preserved at 1:1 on white canvases, without resampling or generated app UI.
- [x] The Mac website update was deployed from commit `a61d44918b989af74ef0044df4251a386351e8a6`. [Pages deployment succeeded](https://github.com/hinoshiba/DaysYet/actions/runs/34011053964); Japanese and English pages and CSS returned HTTP 200 with hashes matching the public commit. Mac preparation, the interactive preview, and independent local Mac storage are reflected on the live site.
- [ ] Any public store link uses the confirmed listing for that platform. An unconfirmed Mac listing is not published.
- [ ] Private Vulnerability Reporting is enabled and its private reports are actively monitored.
- [ ] The seller identity required for each sales region is configured in App Store Connect, and every public support contact uses `support@hinoshiba.com`.
- [ ] Localized What’s New text describes only changes in the selected update; a first platform version is handled as an initial release.
- [x] The shared published App Privacy declaration was reviewed; no data collected remains accurate for the Mac app.
- [ ] Finish Age Rating, Content Rights, export compliance, and applicable regional checks for Mac. Preserve existing store names, categories, price, sales regions, and release method. Draft readiness does not independently document these checks.
- [ ] The App Review contact is complete and current in App Store Connect. Private names, phone numbers, and email addresses are not copied into this repository.
- [x] The Mac review notes from `notes-macos-en.txt` are saved, covering side dragging, saved position, hover, double-click settings, Work hours, week starts, no-login access, local storage, and the healthy-age disclaimer.
- [ ] VoiceOver, Larger Text, Dark Interface, Differentiate Without Color, Sufficient Contrast, and Reduced Motion claims are made only after the submitted platform’s common tasks are verified.
- [ ] iOS / iPadOS validation covers onboarding, editing, reset, Japanese/English, Small/Medium and Lock Screen Widgets, per-Widget overrides, Work hours before/during/after a shift and overnight, week-start changes, DST/timezone boundaries, restart, and stale/empty states.
- [ ] Mac validation covers top/left/right placement, side dragging and restored position after relaunch, hover selection, moving details, 80–150% size, all detail modes, double-click settings, hiding/reopening, quitting, display changes, Work hours, week starts, and Reduced Motion.
- [x] Add for Review succeeded. The draft was inspected before submission and contained only macOS 0.1.2, build 3.
- [x] Final Submit for Review succeeded for Mac on 2026-09-06. App Store Connect confirmed one submitted item, no remaining draft, and Waiting for Review (「審査待ち」). The existing automatic-release-after-approval setting remains selected. That Mac-only submission is separate from the iOS update recorded above.
- [ ] Apple has approved the Mac version and its public availability has been verified.
