# Privacy data map

| Data | Source | Purpose | Storage | Shared with | User deletion |
|---|---|---|---|---|---|
| Birth date | User input | Life-target calculation | App Group `UserDefaults` | App + Widget only | Settings → Delete all data |
| Healthy-age goal | User input | Personal planning progress | App Group `UserDefaults` | App + Widget only | Same |
| Milestone title/start date/target date | User input | Custom progress and countdown | App Group `UserDefaults` | App + Widget only | Same |
| Three selected metrics, display mode, value style, and theme | User choice | App and Widget rendering | App Group + Widget configuration managed by iOS | App + Widget + iOS configuration UI | Edit Widget / reset app |

## Network paths

There are no application-initiated network requests. A user tap may hand a public project URL to the system browser. Apple may independently process App Store and operating-system information under its own policies.

## App Store privacy answer

For the current implementation: **Data Not Collected**. Re-audit before every release and whenever analytics, crash reporting, CloudKit, server validation, support forms, HealthKit, or another SDK is added.

## Required-reason APIs

The app and Widget use App Group `UserDefaults`. Both executable bundles include a `PrivacyInfo.xcprivacy` declaration for `NSPrivacyAccessedAPICategoryUserDefaults`, approved reason `1C8F.1` (access by members of the same App Group). Production storage intentionally has no `UserDefaults.standard` fallback.
