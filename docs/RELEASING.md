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

The app bundle carries the engine's Python files (`engine/`) and
`setup_engine.sh`, not Python itself or the model. **Install Engine…** in the
app runs that script in Terminal, which installs both in Application Support;
`make engine` does the same from a clone. An update replaces the app only, so
the engine carries over. A release that changes `engine/requirements.txt`
should say to choose Install Engine… again (it only adds what's missing).

## Updates

The app checks `releases/latest` once a day and offers the disk image whose
name starts with `Rinsewrite`. It installs it only if the app inside has the
same bundle ID and version as the release tag and meets the running app's
designated requirement, so a release must keep the `v<version>` tag, the
`Rinsewrite-<version>.dmg` name and the Developer ID signature.
