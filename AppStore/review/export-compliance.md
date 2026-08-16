# Export compliance notes

DaysYet does not implement, bundle, or directly call cryptographic algorithms. It makes no application-initiated network requests. User-selected public links are opened by the system browser.

`ITSAppUsesNonExemptEncryption` is set to `false` in the app Info.plist. Reconfirm this answer if networking, authentication, cloud sync, receipt validation, encrypted storage, or a third-party SDK is added.
