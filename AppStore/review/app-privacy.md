# App Privacy answers

Expected answers for the source candidate; verify them against each selected platform’s archive:

- Does this app collect data from this app? **No, we do not collect data from this app.**
- Tracking: **No**
- Third-party analytics or advertising SDKs: **None**
- Account creation: **None**
- HealthKit access: **None**
- Application-initiated networking: **None**

Birth date, target age, milestone start and target dates, daily work start and end times, week-start preference, and Widget display choices are processed only on device in the App Group shared by the iPhone / iPad app and Widget. Showing Work hours is optional; its schedule is not sent to an employer or any external service. Re-audit the answers against the archive and Xcode privacy report before every submission.

For the native Mac submission, the same categories of profile data and the desktop panel’s display, placement (including a dragged vertical position), size, visibility, and keep-open preferences are stored in the Mac app’s own sandbox. They are separate from the iPhone / iPad App Group, with no cross-device sync. Sharing an App Store record and bundle ID does not introduce data synchronization. The Mac archive uses its own privacy manifest; validate that archive’s privacy report separately.
