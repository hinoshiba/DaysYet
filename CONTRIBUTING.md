# Contributing

Thank you for helping improve this project.

## Before opening a change

- Search existing issues and pull requests.
- Keep one issue or pull request focused on one concern.
- Discuss large features, new SDKs, health-related claims, data sources, branding, payment, or networking in an issue before implementation.
- Never include real birth dates, health details, signing assets, API keys, `.p8` files, profiles, or screenshots containing personal information.

## Development

1. Install Xcode 16+ and XcodeGen 2.45.4.
2. Run `./build.sh test` for iOS and `./build.sh test-mac` for macOS.
3. Make the smallest coherent change.
4. Add tests for date boundaries, storage migrations, and Widget configuration behavior.
5. Run `./Scripts/check-compliance.sh`, `./build.sh test`, and `./build.sh test-mac` before submitting.

`project.yml` is the project-configuration source of truth. The generated
`DaysYet.xcodeproj` and shared schemes are committed so a clean checkout opens
in Xcode. Run `./build.sh project` after changing `project.yml` and commit both;
pull-request CI rejects a stale generated project.

Unsigned builds and tests need no signing configuration. For an authorized
device build or release, use the ignored `Config/Signing.local.xcconfig` as
described in [Local Xcode releases](docs/RELEASING.md). Keep team identifiers,
personal certificate identities, provisioning profiles, and credentials out of
the tracked project. Do not generate or transfer signing identities as a
routine contribution step.

Before publishing a commit, run `python3 Scripts/check-public-files.py` and
`python3 Scripts/check-public-files.py --staged`, then review the staged diff.
The checks inspect working files and the Git index respectively, not previous
history or personal details embedded in images. GitHub Actions does not sign,
archive, upload, or submit releases.

Enable the repository's staged-file guard in each local checkout:

```sh
git config --local core.hooksPath .githooks
```

The pre-commit hook runs the same index scan and blocks a detected private
file before it becomes a commit. If you already maintain Git hooks, integrate
this check with them before changing `core.hooksPath`.

## License and provenance

Unless explicitly stated otherwise, contributions intentionally submitted for inclusion are provided under Apache License 2.0, as described by Section 5 of the license.

Use a Developer Certificate of Origin sign-off on commits with your public
contributor identity. Project contact information uses `support@hinoshiba.com`.

By signing off, you certify that you have the right to submit the contribution under the project license. Do not copy code, UI, copy, icons, screenshots, or data from competitors or unverified sources.

Any dependency, font, image, audio, dataset, or SDK addition must update the applicable notice/register and privacy review. See `docs/DEPENDENCY_POLICY.md`.

## Pull request checklist

- iPhone / iPad app, Widget, and Mac app build.
- Tests pass.
- Accessibility and Japanese/English layouts were checked.
- Privacy/data behavior is unchanged or documented.
- Licenses, assets, and data provenance are recorded.
- User-facing behavior and release documentation are updated.

Use local Xcode for development and releases. Pull-request builds and tests
are unsigned and require no maintainer credentials. After changing the
repository, run the relevant checks, review the diff, then git commit and
git push your branch. Submit it with the common pull-request template.
The maintainer uses `support@hinoshiba.com` for public commit email metadata.
