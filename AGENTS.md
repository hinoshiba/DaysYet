# Repository rules

## Code signing and release secrets

- Applications released by the same Apple Developer Team reuse the Team's approved existing distribution signing identity; do not create an application-specific distribution private key. Always use the certificate type appropriate for the platform and distribution channel.
- Restrict signing access to authorized maintainers and build systems. Keep signing identities and private keys only in the macOS Keychain or an approved private secret-management system outside this checkout.
- Never create a signing, certificate, secret, provisioning, or private-export directory inside this repository, including an ignored empty directory. Never copy or export private keys, certificates, certificate signing requests, provisioning profiles, keychains, App Store Connect API keys, credentials, recovery codes, notarization credentials, or signed release artifacts into this working tree, even temporarily.
- Never commit signing identity fingerprints, certificate subject names, personal names, Team IDs, Keychain paths, or signing-identity discovery output.
- Public CI must build without signing. Release signing is performed only in an authorized private environment, with credentials resolved at build time from Keychain or the private secret store.
- If signing material may have entered the working tree or Git history, stop. Do not merely delete it in a later commit. Use the private security reporting process and revoke or rotate the affected credential before continuing.
