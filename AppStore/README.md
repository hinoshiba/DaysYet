# App Store submission resources

This directory is the source of truth for App Store Connect metadata and screenshots. Japanese is the primary language; English (U.S.) is the secondary localization.

```text
configuration.yml           Non-localized app identity and categories
metadata/ja/                Japanese localized metadata
metadata/en-US/             English (U.S.) localized metadata
screenshots/<locale>/       Accepted App Store device-class images
review/                     Review notes and questionnaire answers
```

Before submission:

1. Run `./Scripts/check-compliance.sh --release`.
2. Confirm every statement matches the selected build; never advertise an unimplemented feature.
3. Set App Store Connect Primary Language to **Japanese** and add **English (U.S.)**.
4. Use `support@hinoshiba.com` as the monitored review-contact email. Enter the review contact’s legal name and phone directly in App Store Connect; do not commit those private details here.
5. Confirm Pricing and Availability, App Privacy, Age Rating, Content Rights, DSA trader status, export compliance, and release settings in App Store Connect.
6. Upload the screenshots from both device-class folders for each locale.

`release_notes.txt` is intentionally empty while `initial_release: true`; App Store Connect does not accept What’s New text for the first version.

Generate fresh screenshots with `./Scripts/capture-store-screenshots.sh`. The optional capture workflow requires ImageMagick 7. If CoreSimulator is usable but `simctl bootstatus` is stalled by an OS migrator, set `DAYSYET_SCREENSHOT_SKIP_BOOTSTATUS=1` only after confirming the simulator Home Screen is responsive.

The four images in each locale/device folder show: (1) time left, (2) absolute target date and time, (3) the timeline library, and (4) on-device privacy and OSS information. All sample dates are fictional.

The 1024 × 1024 App Store icon is embedded in the build at `DaysYet/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; it is not uploaded as a separate metadata file.
