# Releasing Autohand Voice

Autohand Voice has two macOS workflows:

- `Build macOS` runs tests and required native checks on an Apple Silicon
  runner, builds both release executables, creates an ad-hoc-signed `.app`,
  packages a drag-to-Applications DMG, and uploads the DMG, SHA-256 checksum,
  and complete notices as workflow artifacts.
- `Release macOS` runs for version tags, requires a Developer ID Application
  certificate, signs the app and DMG with hardened runtime, notarizes and
  staples the DMG, then creates the private GitHub release.

The release workflow intentionally fails when signing or notarization
credentials are absent. It never publishes an unsigned or unnotarized tagged
release.

## Repository secrets

Configure these Actions secrets in `autohandai/voice`:

| Secret | Value |
|---|---|
| `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password protecting the `.p12` |
| `APPLE_KEYCHAIN_PASSWORD` | Ephemeral CI keychain password |
| `APPLE_ID` | Apple ID used by `notarytool` |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer team identifier |

The workflow imports the certificate into a temporary keychain and deletes
that keychain even when a prior step fails.

## Version contract

Before tagging, update both:

- `Brand.version` in
  `Sources/AutohandVoiceCore/Brand.swift`
- `CFBundleShortVersionString` in `Resources/Info.plist`

The tag must be `v<Brand.version>`, for example `v1.0.0`. The release workflow
rejects a tag that does not match `Brand.version`. The GitHub run number
becomes `CFBundleVersion`.

## Local release-equivalent checks

```bash
swift test
swift build -c release
./.build/release/autohand-voice check --json
./scripts/build-app.sh
./scripts/build-installer.sh
codesign --verify --deep --strict --verbose=2 "dist/Autohand Voice.app"
(cd dist && shasum -a 256 -c Autohand-Voice-1.0.0-arm64.dmg.sha256)
```

Local artifacts are ad-hoc signed and are not a substitute for the notarized
tagged release. The downloaded model, caches, recordings, certificates, and
credentials must never be committed or uploaded as build artifacts.
