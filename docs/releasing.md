# Releasing Autohand Voice

Autohand Voice has three macOS workflows:

- `Build macOS` runs tests and required native checks on an Apple Silicon
  runner, builds both release executables, creates an ad-hoc-signed `.app`,
  packages a drag-to-Applications DMG, and uploads the DMG, SHA-256 checksum,
  and complete notices as workflow artifacts. Requires no secrets, but the
  artifact is only downloadable from the Actions run by someone signed into
  GitHub.
- `Nightly Build` runs on every push to `main` (and manually via
  `workflow_dispatch`). It builds the same ad-hoc-signed DMG as `Build macOS`
  and publishes it publicly to a single rolling GitHub Release tagged
  `nightlybuild-latest`, overwriting the previous one each time. This is the
  bleeding-edge channel — always exactly what's on `main`, not a stable,
  versioned release. The release notes always state plainly that it is
  ad-hoc signed and not notarized, and that Gatekeeper requires right-click →
  Open (or `xattr -dr com.apple.quarantine`) on first launch. It requires no
  secrets either.
- `Release macOS` runs for version tags (`v*.*.*`) and always publishes a
  real, permanent, versioned GitHub release for that tag — this is the one to
  link to for anyone downloading and installing the app directly, the way
  many indie macOS apps are distributed outside the App Store. Without a
  Developer ID Application certificate configured, it builds and publishes an
  ad-hoc-signed release clearly titled and labeled "(Unsigned)" in its notes,
  with the same Gatekeeper right-click-Open guidance as `Nightly Build`. Once
  the repository secrets below are configured, the exact same tag-push flow
  instead signs the app and DMG with hardened runtime, notarizes and staples
  the DMG, verifies it with `spctl`, and publishes a release with no
  "(Unsigned)" suffix and no Gatekeeper warning — no other change is needed
  to move from unsigned to notarized releases.

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

The tag must be `v<Brand.version>`, for example `v0.1.0`. The release workflow
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
(cd dist && shasum -a 256 -c Autohand-Voice-0.1.0-universal.dmg.sha256)
```

Local artifacts are ad-hoc signed and are not a substitute for the notarized
tagged release. The downloaded model, caches, recordings, certificates, and
credentials must never be committed or uploaded as build artifacts.

## Stable signing for nightly builds

Ad-hoc signed builds get a new code signature every time, so macOS treats
each update as a different app: it asks for the login password before
Autohand Voice can read its Keychain items, and Accessibility, Input
Monitoring and the login item need approving again. Signing nightly builds
with one long-lived self-signed certificate keeps the signature stable, so
those approvals survive updates. It does not notarize the app; Gatekeeper
still warns on first launch.

Create the certificate once, on a trusted Mac, and store it only as GitHub
secrets:

```bash
umask 077
openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem \
  -subj "/CN=Autohand Voice Self-Signed Code Signing/O=Autohand AI" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
password="$(openssl rand -hex 24)"
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem \
  -name "Autohand Voice Self-Signed Code Signing" \
  -out signing.p12 -passout "pass:$password"
base64 -i signing.p12 | gh secret set AUTOHAND_VOICE_SIGNING_P12_BASE64 --repo autohandai/voice
printf '%s' "$password" | gh secret set AUTOHAND_VOICE_SIGNING_P12_PASSWORD --repo autohandai/voice
rm -P key.pem signing.p12
```

The nightly workflow imports it into a temporary keychain when the secrets
exist and falls back to ad-hoc signing when they don't. Anyone holding the
private key can sign builds that macOS will treat as Autohand Voice, so keep
it only in the repository secrets. The first build signed with it needs one
last round of approvals; later updates keep them.

Autohand Voice also avoids reading Keychain at launch: the Talk key is read
the first time Talk needs it, and crash recovery reads its key only when a
recording is waiting to be recovered.
