# Releasing Rinsewrite

Releases are signed with the maintainer's Developer ID
(`Developer ID Application: Bruno Cassina (22R95V8NA5)`) and notarized by
Apple, the app and the disk image both. Every build carries the designated
requirement in `packaging/designated_requirement.txt` (the bundle ID and the
Developer ID team), so macOS keeps the Accessibility grant from one build to
the next.

## Steps

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`, and add the version to `CHANGELOG.md`.
2. Write the release notes to `dist/notes.md`.
3. `make release`: builds, signs, notarizes and staples the app and the
   disk image, then publishes `Rinsewrite-<version>.dmg` as GitHub release
   `v<version>`.

Notarization uses the `notarytool` keychain profile in `NOTARY_PROFILE`
(default `tuckaway-notary`), shared with the other Bruno-Alumn apps:

```sh
xcrun notarytool store-credentials tuckaway-notary --apple-id <id> --team-id 22R95V8NA5
```

## The engine

The app bundle carries the engine's Python files (`engine/`), not Python
itself or the model. `make engine` installs both on the Mac that runs it.
Shipping a self-contained download (a bundled Python and a first-run model
download) is the next step before a public release.
