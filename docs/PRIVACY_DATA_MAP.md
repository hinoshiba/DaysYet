# Privacy data map

For iPhone / iPad, open Times → the top-right info button → About DaysYet → Delete all data. On Mac, use Settings → Delete all data. Both require confirmation and affect only the current device.

| Data | Source | Purpose | Storage | Shared with | User deletion |
|---|---|---|---|---|---|
| Birth date | User input | Life-target calculation | iOS: App Group `UserDefaults`; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget only; macOS: Mac app only | Delete all data using the device-specific route above |
| Healthy-age goal | User input | Time remaining toward a personal planning goal | Same | Same | Same |
| Milestone title/start date/target date | User input | Custom countdown and remaining percentage | Same | Same | Same |
| Study plan name, start/end dates, available weekdays, and individual date additions/exclusions | User input | Count available study days remaining and display remaining percentage; no study completion records | Same | Same | Same |
| Labels, start/end times (minutes after local midnight), and enabled weekdays for two activity schedules | User settings; new-install defaults: daily activity 07:00–23:00 every day, work hours 09:00–18:00 Monday–Friday | Optional activity timelines: custom titles, local-time countdowns, and Off status, including overnight schedules | iOS: App Group `UserDefaults`; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget only; macOS: Mac app only | Delete all data using the device-specific route above resets activity settings |
| Week start preference (`weekStartDay`: device calendar setting or a weekday) | User choice; defaults to device calendar setting | This week countdown, remaining percentage, and end date across the app, widgets, and Mac panel | iOS: App Group `UserDefaults`; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget only; macOS: Mac app only | Delete all data using the device-specific route above resets the preference |
| Selected metrics (three rows or one to eight circles on iOS, three to eight on macOS), widget layout, display mode, value style, theme, and custom colors | User choice | App, Widget, and desktop panel rendering | iOS: App Group + Widget configuration managed by iOS; macOS: sandboxed `UserDefaults.standard` | iOS: App + Widget + iOS configuration UI; macOS: Mac app only | iOS: Edit Widget / reset app; macOS: Settings → Delete all data |
| Circle preview size | User selection | Preview Small, Medium, or Large without changing an installed widget’s size | iOS scene storage | iOS app only | Managed with the app’s scene state; contains no timeline content |
| Desktop panel visibility, selected display identifier, screen edge, vertical position, size scale (icons and text), and keep-details-open preference | User choice | Place and display the Mac panel | Sandboxed `UserDefaults.standard` | Mac app only | Settings → Delete all data resets panel preferences |
| Launch at login registration and approval status | User choice in the Mac app or macOS System Settings | Start DaysYet when the user logs in | Managed by macOS through `SMAppService.mainApp`; no duplicate app preference | Mac app and macOS only | Disable Launch at login in the app or remove/disable DaysYet in macOS Login Items; resetting app data does not change this system setting |
| Dock circle image and display labels | Calculated timeline display | Render one native Dock item per selected circle | Local pipes and helper memory; no full profile in helpers | DaysYet and its embedded helpers on this Mac | Helpers exit when the group leaves the Dock or DaysYet quits |
| Dock item identities, order, frames, and relevant pointer/key events (direct prototype) | Accessibility and local input events | Find owned helpers, choose an insertion gap, preserve the group and unrelated apps' order | Memory only; diagnostic logs contain phases, counts and failure codes rather than foreign identities or input content | DaysYet on this Mac only | Released after the operation; revoke Accessibility in System Settings to stop Dock control |
| Removed DaysYet helper registration records (direct prototype recovery) | Exact owned embedded-helper URLs in Dock preferences | Recover leftover pinned helper entries | `~/Library/Application Support/DaysYet/Dock Recovery/`; only removed owned records | DaysYet on this Mac only | Delete this recovery folder when no longer needed; settings reset does not remove it |
| Optional Dock transition preference and regional still image (direct prototype) | Explicit user consent, Screen Recording permission, current Dock region | Cover intermediate native ordering animations | Preference in app defaults; image only in memory until finish, cancellation or watchdog expiry | DaysYet on this Mac only; region may include other apps and wallpaper | Turn the feature off; revoke Screen Recording in System Settings; no image file is created |

The tables' sandbox storage descriptions apply to normal Mac App Store builds. The separately built direct prototype uses app-specific `UserDefaults.standard` outside the sandbox. Accessibility-based Dock control and ScreenCaptureKit code are excluded from normal builds. The optional capture experiment is off by default; ordinary group movement requires no Screen Recording permission. Neither path adds network requests or audio capture.

Data is stored independently on each device. There is no device sync, and the Mac app does not share an App Group with the iOS app or include a WidgetKit extension.

Existing Work hours times and metric selections are retained during migration; all weekdays remain enabled for the migrated schedule to preserve its previous daily behavior. This migration happens on the device and sends no data externally. Activity labels may be visible in selected widgets or the Mac panel, just like milestone titles.

Study plans use an in-app calendar without reading or writing the device's calendar events. Study plan names may be visible in selected widgets or the Mac panel. All study settings are saved and deleted with the device's profile.

## Network paths

There are no application-initiated network requests. A user tap may hand a public project URL to the system browser. Apple may independently process App Store and operating-system information under its own policies.

## App Store privacy answer

For the current implementation: **Data Not Collected**. Re-audit before every release and whenever analytics, crash reporting, CloudKit, server validation, support forms, HealthKit, or another SDK is added.

## Required-reason APIs

The iOS app and Widget use App Group `UserDefaults`. Both executable bundles include a `PrivacyInfo.xcprivacy` declaration for `NSPrivacyAccessedAPICategoryUserDefaults`, approved reason `1C8F.1` (access by members of the same App Group). Shared profile storage intentionally has no `UserDefaults.standard` fallback. The iOS app additionally stores only the last widget editor type in its own `UserDefaults.standard`, with approved reason `CA92.1`; this key is removed when all data is reset. The Widget does not use or read that editor preference.

The Mac app uses `UserDefaults.standard` within its own sandbox for timeline and panel settings. Its `PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (data accessible only to the app). Mac preferences do not require App Group entitlements.

The Mac panel uses `ProcessInfo.systemUptime` to measure elapsed time during its selection animation. Its manifest declares `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1` for timing events within the app. These measurements stay in memory and are neither saved nor sent off-device. See Apple's [required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
