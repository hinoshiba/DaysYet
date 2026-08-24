# Submission checklist

- [ ] App Store Connect Primary Language is Japanese; English (U.S.) localization is added.
- [ ] Bundle ID `com.hinoshiba.daysyet`, Widget ID `com.hinoshiba.daysyet.widget`, and App Group `group.com.hinoshiba.daysyet` are registered to the signing team.
- [ ] The release tag is immutable `vX.Y.Z`, and its version matches `project.yml` and `AppStore/configuration.yml`.
- [ ] The selected build is the successful Xcode Cloud archive for that exact tag/commit and Cloud build number.
- [ ] The archive contains the Widget extension, expected App Group entitlements, and 1024 × 1024 app icon.
- [ ] Japanese and English metadata match the build and pass length limits.
- [ ] All four locale/device screenshot folders contain 1–10 current images.
- [ ] GitHub Pages uses GitHub Actions as its source; the Japanese and English single-page sites return HTTP 200 without redirects, and their Product, Privacy, Support, Terms, and Accessibility section links work.
- [ ] Once the public App Store product URL exists, the site hero links to that exact listing and the Smart App Banner uses its confirmed numeric app ID; no unconfirmed listing URL is published.
- [ ] Private Vulnerability Reporting is enabled and its private reports are actively monitored.
- [ ] The seller identity required for each sales region is configured in App Store Connect, and every public support contact uses `support@hinoshiba.com`.
- [ ] `release_notes.txt` remains empty and What’s New is not submitted for this first version.
- [ ] App Privacy, Age Rating, Content Rights, export compliance, DSA status, Pricing and Availability, and release settings are complete.
- [ ] The optional App Review contact name, phone, and email fields follow the current DaysYet submission requirements; otherwise they remain blank.
- [ ] Review Notes explain Widget setup, no-login access, on-device storage, and the healthy-age disclaimer.
- [ ] VoiceOver, Larger Text, Dark Interface, Differentiate Without Color, Sufficient Contrast, and Reduced Motion claims are made only after every common task is verified.
- [ ] Internal TestFlight passes onboarding, editing, reset, Japanese/English, Small/Medium Widgets, per-Widget overrides, date boundaries, timezone changes, restart, and stale/empty states.
- [ ] Selecting the build and submitting it to App Review are completed explicitly in App Store Connect; pushing a tag does not submit it automatically.
