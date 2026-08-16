# Submission checklist

- [ ] App Store Connect Primary Language is Japanese; English (U.S.) localization is added.
- [ ] Bundle ID `com.hinoshiba.daysyet`, Widget ID, and App Group are registered to the signing team.
- [ ] Version/build match `project.yml` and `AppStore/configuration.yml`.
- [ ] A validated build with the Widget extension and 1024 × 1024 app icon is selected.
- [ ] Japanese and English metadata match the build and pass length limits.
- [ ] All four locale/device screenshot folders contain 1–10 current images.
- [ ] GitHub Pages uses GitHub Actions as its source; all Japanese and English Product, Privacy, Support, Terms, and Accessibility URLs return HTTP 200 without redirects.
- [ ] Private Vulnerability Reporting is enabled and GitHub Issues notifications are actively monitored.
- [ ] The seller identity and support contact required for each sales region are configured in App Store Connect and, where required, on the Support page.
- [ ] `release_notes.txt` remains empty and What’s New is not submitted for this first version.
- [ ] App Privacy, Age Rating, Content Rights, export compliance, DSA status, Pricing and Availability, and release settings are complete.
- [ ] App Review contact legal name, monitored email, and phone are entered privately in App Store Connect.
- [ ] Review Notes explain Widget setup, no-login access, on-device storage, and the healthy-age disclaimer.
- [ ] VoiceOver, Larger Text, Dark Interface, Differentiate Without Color, Sufficient Contrast, and Reduced Motion claims are made only after every common task is verified.
- [ ] Internal TestFlight passes onboarding, editing, reset, Japanese/English, Small/Medium Widgets, per-Widget overrides, date boundaries, timezone changes, restart, and stale/empty states.
