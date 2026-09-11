# Privacy data map

| Data | Source | Purpose | Storage | Shared with | User deletion |
|---|---|---|---|---|---|
| Birth date | User input | Life-target calculation | iOS: App Group `UserDefaults`; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget only; macOS: Mac app only | Settings → Delete all data on that device |
| Healthy-age goal | User input | Personal planning progress | Same | Same | Same |
| Milestone title/start date/target date | User input | Custom progress and countdown | Same | Same | Same |
| Study plan name, start/end dates, available weekdays, and individual date additions/exclusions | User input | Count available study days remaining and display elapsed progress; no study completion records | Same | Same | Same |
| Labels, start/end times (minutes after local midnight), and enabled weekdays for two activity schedules | User settings; new-install defaults: daily activity 07:00–23:00 every day, work hours 09:00–18:00 Monday–Friday | Optional activity timelines: custom titles, local-time countdowns, and Off status, including overnight schedules | iOS: App Group `UserDefaults`; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget only; macOS: Mac app only | Settings → Delete all data on that device resets activity settings |
| Week start preference (`weekStartDay`: device calendar setting or a weekday) | User choice; defaults to device calendar setting | This week countdown, elapsed progress, and end date across the app, widgets, and Mac panel | iOS: App Group `UserDefaults`; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget only; macOS: Mac app only | Settings → Delete all data on that device resets the preference |
| Selected metrics (three on iOS, three to eight on macOS), display mode, value style, and theme | User choice | App, Widget, and desktop panel rendering | iOS: App Group + Widget configuration managed by iOS; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget + iOS configuration UI; macOS: Mac app only | iOS: Edit Widget / reset app; macOS: Settings → Delete all data |
| Desktop panel visibility, selected display identifier, screen edge, vertical position, size scale (icons and text), and keep-details-open preference | User choice | Place and display the Mac panel | Sandboxed `UserDefaults.standard` | Mac app only | Settings → Delete all data resets panel preferences |
| Launch at login registration and approval status | User choice in the Mac app or macOS System Settings | Start DaysYet when the user logs in | Managed by macOS through `SMAppService.mainApp`; no duplicate app preference | Mac app and macOS only | Disable Launch at login in the app or remove/disable DaysYet in macOS Login Items; resetting app data does not change this system setting |

Data is stored independently on each device. There is no device sync, and the Mac app does not share an App Group with the iOS app or include a WidgetKit extension.

Existing Work hours times and metric selections are retained during migration; all weekdays remain enabled for the migrated schedule to preserve its previous daily behavior. This migration happens on the device and sends no data externally. Activity labels may be visible in selected widgets or the Mac panel, just like milestone titles.

Study plans use an in-app calendar without reading or writing the device's calendar events. Study plan names may be visible in selected widgets or the Mac panel. All study settings are saved and deleted with the device's profile.

## Network paths

There are no application-initiated network requests. A user tap may hand a public project URL to the system browser. Apple may independently process App Store and operating-system information under its own policies.

## App Store privacy answer

For the current implementation: **Data Not Collected**. Re-audit before every release and whenever analytics, crash reporting, CloudKit, server validation, support forms, HealthKit, or another SDK is added.

## Required-reason APIs

The iOS app and Widget use App Group `UserDefaults`. Both executable bundles include a `PrivacyInfo.xcprivacy` declaration for `NSPrivacyAccessedAPICategoryUserDefaults`, approved reason `1C8F.1` (access by members of the same App Group). iOS production storage intentionally has no `UserDefaults.standard` fallback.

The Mac app uses `UserDefaults.standard` within its own sandbox for timeline and panel settings. Its `PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (data accessible only to the app). Mac preferences do not require App Group entitlements.

The Mac panel uses `ProcessInfo.systemUptime` to measure elapsed time during its selection animation. Its manifest declares `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1` for timing events within the app. These measurements stay in memory and are neither saved nor sent off-device. See Apple's [required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
