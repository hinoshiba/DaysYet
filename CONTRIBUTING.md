# Contributing

Thank you for helping improve this project.

## Before opening a change

- Search existing issues and pull requests.
- Keep one issue or pull request focused on one concern.
- Discuss large features, new SDKs, health-related claims, data sources, branding, payment, or networking in an issue before implementation.
- Never include real birth dates, health details, signing assets, API keys, `.p8` files, profiles, or screenshots containing personal information.

## Development

1. Install Xcode 16+ and XcodeGen 2.45.4.
2. Run `./build.sh test`.
3. Make the smallest coherent change.
4. Add tests for date boundaries, storage migrations, and Widget configuration behavior.
5. Run `./Scripts/check-compliance.sh` and `./build.sh test` before submitting.

`project.yml` is the source of truth. Do not commit the generated `DaysYet.xcodeproj`.

## License and provenance

Unless explicitly stated otherwise, contributions intentionally submitted for inclusion are provided under Apache License 2.0, as described by Section 5 of the license.

Use a Developer Certificate of Origin sign-off on commits:

```text
Signed-off-by: Your Name <your-email@example.com>
```

By signing off, you certify that you have the right to submit the contribution under the project license. Do not copy code, UI, copy, icons, screenshots, or data from competitors or unverified sources.

Any dependency, font, image, audio, dataset, or SDK addition must update the applicable notice/register and privacy review. See `docs/DEPENDENCY_POLICY.md`.

## Pull request checklist

- App and Widget build.
- Tests pass.
- Accessibility and Japanese/English layouts were checked.
- Privacy/data behavior is unchanged or documented.
- Licenses, assets, and data provenance are recorded.
- User-facing behavior and release documentation are updated.
