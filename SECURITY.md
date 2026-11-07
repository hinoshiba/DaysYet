# Security policy

## Supported versions

Security fixes are provided for the latest release and the current `main` branch.

## Reporting a vulnerability

Use the repository Security tab and select **Report a vulnerability** to send a private report. Do not disclose a vulnerability, privacy leak, signing secret, or personal date in a public issue.

If private vulnerability reporting is unavailable, email [support@hinoshiba.com](mailto:support@hinoshiba.com) with `[Security] DaysYet` in the subject and ask for a secure reporting channel. Do not include vulnerability details, secrets, credentials, or personal information in that email.

Please include:

- affected commit or version and iOS / iPadOS version;
- impact and realistic attack scenario;
- minimal reproduction using fictional dates;
- a suggested mitigation, if known.

Never send real birth dates, health details, provisioning profiles, certificates, private keys, App Store credentials, or recovery codes. No bug bounty is currently offered.

If signing material may have been exposed, stop using it and report the incident privately. The affected credential must be revoked or rotated before another release; removing it only from the latest commit is not sufficient.
