# App Store submission resources

This directory is the source of truth for App Store Connect metadata and screenshots. Japanese is the primary language; English (U.S.) is the secondary localization.

```text
configuration.yml           Non-localized app identity and categories
metadata/ja/                Japanese localized metadata
metadata/en-US/             English (U.S.) localized metadata
screenshots/<locale>/       Accepted App Store device-class images
review/                     Review notes and questionnaire answers
```

Before submission (after the tagged Xcode Cloud archive finishes):

1. Confirm the tag version, Xcode Cloud build number, commit, and selected App Store Connect build all match.
2. Confirm every statement matches the selected Cloud build; never advertise an unimplemented feature.
3. Set App Store Connect Primary Language to **Japanese** and add **English (U.S.)**.
4. Leave the optional App Review contact name, phone, and email fields blank unless the current submission requires them. The public support contact remains `support@hinoshiba.com`.
5. Confirm Pricing and Availability, App Privacy, Age Rating, Content Rights, DSA trader status, export compliance, and release settings in App Store Connect.
6. Upload the screenshots from both device-class folders for each locale.

The release workflow runs `./Scripts/check-compliance.sh --release` before its Archive action. It creates an App Store-eligible candidate in Xcode Cloud; selecting that build and submitting it to App Review remain explicit App Store Connect actions.

`release_notes.txt` contains the localized What’s New text for updates. Keep it empty only while `initial_release: true`, because App Store Connect does not accept What’s New text for the first version.

Generate fresh screenshots with `./Scripts/capture-store-screenshots.sh`. The optional capture workflow requires ImageMagick 7. If CoreSimulator is usable but `simctl bootstatus` is stalled by an OS migrator, set `DAYSYET_SCREENSHOT_SKIP_BOOTSTATUS=1` only after confirming the simulator Home Screen is responsive.

The four images in each locale/device folder show: (1) progress bars, (2) time left with percentage and bars, (3) the timeline library, and (4) on-device privacy and OSS information. All sample dates are fictional.

The 1024 × 1024 App Store icon is embedded in the build at `DaysYet/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; it is not uploaded as a separate metadata file.
