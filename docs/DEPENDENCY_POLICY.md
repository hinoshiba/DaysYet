# Dependency policy

DaysYet currently ships with no third-party runtime libraries, fonts, stock images, analytics SDKs, advertising SDKs, or external datasets. XcodeGen 2.45.4 is a development-only MIT-licensed tool pinned by version and SHA-256 in CI. ImageMagick 7.1.2-27 is an optional development-only tool used to flatten Simulator screenshot alpha; it is not used by the app build or bundled in the product.

## Intake requirements

Every dependency, SDK, asset, font, sound, or dataset addition must record:

- exact version or commit, source URL, and content hash;
- direct and transitive licenses and required notices;
- whether it ships in the binary;
- Privacy Manifest and SDK-signature status where applicable;
- commercial and App Store compatibility;
- any new network path, collected data, or required user permission.

Licenses that usually permit review and inclusion include Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, ISC, Zlib, and 0BSD. Copyleft, source-available, non-commercial, no-derivatives, custom, proprietary, `NOASSERTION`, or unknown terms require explicit review before adoption.

Update `THIRD_PARTY_NOTICES.md`, `ASSET_LICENSES.md`, `DATA_SOURCES.md`, `PRIVACY.md`, the App Store privacy answers, and SBOM inputs in the same change whenever applicable.
