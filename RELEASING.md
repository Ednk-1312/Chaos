# Releasing Chaos

Everything below runs locally from a clean checkout. No step depends on
machine-specific state; signing/notarization activate only when you provide
credentials.

## Version model

One source of truth: the **git tag**.

```
v0.1.0-preview.1
└─ MARKETING_VERSION       = 0.1.0        (Version.xcconfig → every target)
└─ CURRENT_PROJECT_VERSION = 1            (build number = preview number)
└─ RELEASE_LABEL           = "Preview 1"
└─ artifacts               = Chaos-v0.1.0-preview.1.{pkg,zip}
```

`Tools/Release/version.sh` parses the tag, cross-checks `Version.xcconfig`
(`--check`), and can rewrite it (`--update`). `Tools/Release/build-release.sh`
fails loudly if the built bundle, artifact names, and tag disagree.

Tag format: `vMAJOR.MINOR.PATCH-preview.N`. Bumping a release = new tag.

## Local preview release (unsigned/ad-hoc)

```bash
git checkout main && git pull
Tools/Release/build-release.sh                       # ad-hoc signed, notarization skipped
# or pin a version without a local tag (CI does this):
RELEASE_TAG=v0.1.0-preview.1 Tools/Release/build-release.sh
```

Outputs in `build/release/`:

| File | What |
|---|---|
| `Chaos-v<ver>.pkg` | Installer → `/Applications/Chaos.app`, symlinks `/usr/local/bin/chaos` |
| `Chaos-v<ver>.zip` | Standalone app (preserves codesign) |
| `SHA256SUMS` | Checksums for both |
| `release-manifest.json` | Version, arch, hashes, signing/notarization status |

The script cleans its own build directory first, verifies bundle contents,
architecture, bundle ID, and version agreement, and **fails loudly** if
anything is missing.

## Signing modes

`SIGNING_MODE` environment variable (default `adhoc`):

| Mode | Behavior |
|---|---|
| `adhoc` (default) | `codesign -` on helpers + app. No account needed. |
| `developer-id` | Signs helpers → app (`SIGNING_IDENTITY`, e.g. `Developer ID Application: …`), then pkg (`INSTALLER_SIGNING_IDENTITY`, `Developer ID Installer: …`), with `--options runtime --timestamp`. Fails if identities are missing — never falls back silently. |

```bash
# Local signed release (identities in your keychain):
SIGNING_MODE=developer-id \
SIGNING_IDENTITY="Developer ID Application: ACME (TEAMID)" \
INSTALLER_SIGNING_IDENTITY="Developer ID Installer: ACME (TEAMID)" \
Tools/Release/build-release.sh
```

Signing order is innermost-first (CLI → stress worker → app), then the pkg.
Verification after signing: `codesign --verify --strict` on the app; the script
aborts if it fails. No certificates or provisioning material ever lives in the
repository — identities come from the environment/keychain.

## Notarization

Ready but **not yet executed** (needs Apple Developer credentials). Two paths:

1. Keychain profile (simplest):
   ```bash
   xcrun notarytool store-credentials chaos-notary   # once, interactive
   NOTARIZE=1 SIGNING_MODE=developer-id SIGNING_IDENTITY=… INSTALLER_SIGNING_IDENTITY=… \
     Tools/Release/build-release.sh
   ```
2. App Store Connect API key (CI-friendly): set `NOTARY_KEY_ID`, `NOTARY_KEY_PATH`,
   `NOTARY_KEY_ISSUER` in the environment.

With `NOTARIZE=1` the script submits the zip + pkg via `notarytool --wait`,
staples the app and pkg, re-verifies signatures, re-stamps the zip with the
stapled app, and regenerates `SHA256SUMS`. Manifest records
`"notarization": "stapled"`.

## GitHub release (automated)

Pushing a tag `vX.Y.Z-preview.N` triggers `.github/workflows/release.yml`:
clean checkout → version check → tests → build → package → checksums → GitHub
Release with pkg/zip/SHA256SUMS/manifest attached. Rerunning for the same tag
updates assets in place (idempotent). Notarization in CI activates automatically
when a `NOTARY_PROFILE` secret is configured (environment: `release`).

Ordinary pushes/PRs never publish and never see signing secrets
(`.github/workflows/ci.yml` runs tests + an ad-hoc packaging dry-run only).

## Verification recipes

```bash
shasum -a 256 -c SHA256SUMS                        # artifact integrity
codesign --verify --strict /Applications/Chaos.app # app signature
pkgutil --check-signature Chaos-v*.pkg             # installer signature (signed pkgs)
xcrun stapler validate /Applications/Chaos.app     # notarization ticket
spctl -a -vv /Applications/Chaos.app               # Gatekeeper assessment
```

## Emergency rollback

To pull bad artifacts from a published release without touching history:

```bash
gh release upload v0.1.0-preview.2 --clobber <good assets>   # replace assets
gh release delete v0.1.0-preview.2 --cleanup-tag             # full removal (rare)
```

Delete only the *release*, never force-push tags or rewrite history; the tag
you delete can be re-cut from the same commit if needed.

## Checklist

- [ ] `Tools/Release/version.sh --check` passes on the release commit
- [ ] `swift test` green
- [ ] `Tools/Release/build-release.sh` green from a clean checkout
- [ ] `SHA256SUMS` verifies
- [ ] ad-hoc preview installed and CLI smoke-tested (`chaos status`)
- [ ] if signing: `codesign --verify --strict` + `pkgutil --check-signature`
- [ ] if notarizing: `stapler validate` + `spctl -a -vv`
