#!/bin/bash
# build-release.sh — reproducible release build for Chaos.
#
# Produces, from a clean state:
#   build/release/Chaos.app                 the app (Release configuration)
#   build/release/Chaos-v<full>.pkg         installer package
#   build/release/Chaos-v<full>.zip         zipped app bundle
#   build/release/SHA256SUMS                checksums for both artifacts
#   build/release/release-manifest.json     machine-readable release manifest
#
# Signing modes (env):
#   SIGNING_MODE=adhoc|developer-id   (default: adhoc)
#   SIGNING_IDENTITY="Developer ID Application: ..."   (developer-id mode)
#   INSTALLER_SIGNING_IDENTITY="Developer ID Installer: ..." (optional; pkg)
#   NOTARIZE=1                        submit+staple (requires notarytool creds;
#                                     READY BUT NOT EXECUTED in this repo — no
#                                     credentials committed, ever)
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
RELDIR="build/release"
STAGE="$ROOT/build/release/stage"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# --- 1. prerequisites -------------------------------------------------------
command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v swift     >/dev/null || fail "swift not found"
command -v pkgbuild  >/dev/null || fail "pkgbuild not found (Xcode toolchain)"
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
case "$SIGNING_MODE" in
  adhoc|developer-id) ;;
  *) fail "SIGNING_MODE must be adhoc or developer-id (got '$SIGNING_MODE')" ;;
esac
if [[ "$SIGNING_MODE" == "developer-id" && -z "${SIGNING_IDENTITY:-}" ]]; then
  fail "SIGNING_MODE=developer-id requires SIGNING_IDENTITY"
fi

# --- 2. version -------------------------------------------------------------
log "Resolving version"
# Safe eval: version.sh emits %q-quoted values (spaces survive intact).
eval "$(Tools/Release/version.sh --shell)"
Tools/Release/version.sh --check >/dev/null
log "Version: $TAG (marketing $MARKETING_VERSION, build $CURRENT_PROJECT_VERSION)"

# --- 3. clean ---------------------------------------------------------------
log "Cleaning previous artifacts"
rm -rf "$RELDIR"
mkdir -p "$RELDIR" "$STAGE"

# --- 4. build SPM products (CLI + stress worker) -----------------------------
log "Building ChaosKit CLI + stress worker (release)"
# NOTE: `swift build` honors only the LAST --product flag, so build in two passes.
swift build -c release --product chaos 2>&1 | tail -1
swift build -c release --product chaos-stress 2>&1 | tail -1
# Package.swift lives at the repo root, so SPM products land in <root>/.build/release
SPM_BIN="$ROOT/.build/release"
[[ -x "$SPM_BIN/chaos" ]] || SPM_BIN="$ROOT/ChaosKit/.build/release"  # older layout fallback
[[ -x "$SPM_BIN/chaos" ]]        || fail "chaos CLI missing after SPM build"
[[ -x "$SPM_BIN/chaos-stress" ]] || fail "chaos-stress missing after SPM build"

# --- 5. build the app (Release), which embeds the helpers --------------------
log "Building Chaos.app (Release configuration)"
xcodebuild -project Chaos.xcodeproj -target Chaos -configuration Release build \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CONFIGURATION_BUILD_DIR="$STAGE/appbuild" >/tmp/chaos-release-build.log 2>&1 \
  || { tail -30 /tmp/chaos-release-build.log >&2; fail "xcodebuild failed (log: /tmp/chaos-release-build.log)"; }
# Keep the artifacts dir clean: only the final .app, not xcodebuild intermediates.
APP="$RELDIR/Chaos.app"
rm -rf "$APP"
cp -R "$STAGE/appbuild/Chaos.app" "$APP"
[[ -d "$APP" ]] || fail "Chaos.app missing after build"

# The embed phase copies debug SPM binaries when present; force the release
# ones in every case so the artifact is never stale or mixed.
log "Embedding release CLI + stress worker"
mkdir -p "$APP/Contents/Helpers"
cp "$SPM_BIN/chaos" "$APP/Contents/Helpers/chaos"
cp "$SPM_BIN/chaos-stress" "$APP/Contents/MacOS/chaos-stress"

# --- 6. verify the bundle ----------------------------------------------------
log "Verifying bundle"
APPBIN="$APP/Contents/MacOS/Chaos"
[[ -x "$APPBIN" ]]                                || fail "app executable missing"
[[ -x "$APP/Contents/Helpers/chaos" ]]            || fail "CLI helper missing"
[[ -x "$APP/Contents/MacOS/chaos-stress" ]]       || fail "chaos-stress missing"
[[ -f "$APP/Contents/Info.plist" ]]               || fail "Info.plist missing"
ARCH_APP="$(lipo -info "$APPBIN" 2>/dev/null | sed 's/.*: //')"
log "App architecture: $ARCH_APP"
ARCH_CLI="$(lipo -info "$APP/Contents/Helpers/chaos" 2>/dev/null | sed 's/.*: //')"
case "$ARCH_APP" in *arm64*) ;; *) fail "app is not Apple Silicon capable: $ARCH_APP" ;; esac

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
APP_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$BUNDLE_ID" == "com.chaosengineering.Chaos" ]] || fail "unexpected bundle id: $BUNDLE_ID"
[[ "$APP_VER" == "$MARKETING_VERSION" ]] || fail "app version $APP_VER != $MARKETING_VERSION"
[[ "$APP_BUILD" == "$CURRENT_PROJECT_VERSION" ]] || fail "app build $APP_BUILD != $CURRENT_PROJECT_VERSION"
# Release notes must reference the exact artifact version (fail, don't publish drift).
if [[ -f RELEASE_NOTES.md ]] && ! grep -q "Chaos-v$FULL_VERSION" RELEASE_NOTES.md; then
  fail "RELEASE_NOTES.md does not mention Chaos-v$FULL_VERSION — update it before releasing"
fi
# Version consistency: artifact filenames must match the tag-derived version.
PKG_NAME="Chaos-v$FULL_VERSION.pkg"
ZIP_NAME="Chaos-v$FULL_VERSION.zip"
log "Bundle OK: $BUNDLE_ID $APP_VER ($APP_BUILD) → $PKG_NAME / $ZIP_NAME"

# --- 7. sign -----------------------------------------------------------------
sign_bundle() { # $1 = path, $2 = identity, $3... = extra args
  local path="$1" ident="$2"; shift 2
  codesign --force --sign "$ident" "$@" "$path"
}
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  log "Signing (Developer ID): $SIGNING_IDENTITY"
  # Sign nested code first, then the outer bundle (intentional, not --deep).
  sign_bundle "$APP/Contents/Helpers/chaos" "$SIGNING_IDENTITY" --timestamp --options runtime
  sign_bundle "$APP/Contents/MacOS/chaos-stress" "$SIGNING_IDENTITY" --timestamp --options runtime
  sign_bundle "$APP" "$SIGNING_IDENTITY" --timestamp --options runtime
  SIGN_MODE_LABEL="developer-id"
else
  log "Signing (ad-hoc)"
  sign_bundle "$APP/Contents/Helpers/chaos" "-"
  sign_bundle "$APP/Contents/MacOS/chaos-stress" "-"
  sign_bundle "$APP" "-"
  SIGN_MODE_LABEL="adhoc"
fi
codesign --verify --strict "$APP" || fail "app codesign verification failed"

# --- 8. pkg ------------------------------------------------------------------
log "Building $PKG_NAME"
PKG_ID="com.chaosengineering.Chaos"
PKGROOT="$STAGE/pkgroot"
mkdir -p "$PKGROOT/Applications"
rm -rf "$PKGROOT/Applications/Chaos.app"
cp -R "$APP" "$PKGROOT/Applications/Chaos.app"
COMPONENT_PLIST="$STAGE/chaos-component.plist"
cat > "$COMPONENT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>RootRelativeBundlePath</key>
    <string>Applications/Chaos.app</string>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleIsVersionChecked</key>
    <true/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
  </dict>
</array>
</plist>
PLIST
# postinstall symlinks /usr/local/bin/chaos -> the bundled CLI (guarded:
# never replaces unrelated files; failures are non-fatal by design).
SCRIPTS="$STAGE/scripts"
mkdir -p "$SCRIPTS"
cp "$ROOT/Tools/Release/pkg-scripts/postinstall" "$SCRIPTS/postinstall"
chmod +x "$SCRIPTS/postinstall"
# pkgbuild requires a strictly numeric version; the full preview tag lives in
# the app bundle (CFBundleShortVersionString/CFBundleVersion) and the manifest.
pkgbuild --root "$PKGROOT" \
         --identifier "$PKG_ID" \
         --version "$MARKETING_VERSION" \
         --install-location "/" \
         --component-plist "$COMPONENT_PLIST" \
         --scripts "$SCRIPTS" \
         "$RELDIR/$PKG_NAME" >/dev/null || fail "pkgbuild failed"
# Developer ID Installer signing (optional; package is ad-hoc unsigned otherwise)
if [[ "$SIGNING_MODE" == "developer-id" && -n "${INSTALLER_SIGNING_IDENTITY:-}" ]]; then
  log "Signing pkg (Developer ID Installer)"
  productbuild --package "$RELDIR/$PKG_NAME" \
    --sign "$INSTALLER_SIGNING_IDENTITY" "$RELDIR/$PKG_NAME.signed" >/dev/null \
    && mv "$RELDIR/$PKG_NAME.signed" "$RELDIR/$PKG_NAME" \
    || fail "productbuild signing failed"
fi

# --- 9. zip ------------------------------------------------------------------
log "Building $ZIP_NAME"
cd "$RELDIR"
ditto -c -k --keepParent Chaos.app "$ZIP_NAME"
cd "$ROOT"

# --- 10. checksums ------------------------------------------------------------
log "Generating SHA256SUMS"
(
  cd "$RELDIR"
  shasum -a 256 "$PKG_NAME" "$ZIP_NAME" > SHA256SUMS
  cat SHA256SUMS
)

# --- 11. notarization (READY BUT NOT EXECUTED path) ---------------------------
NOTARIZATION_STATUS="not-performed"
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  log "Notarization requested"
  if [[ "$SIGNING_MODE" != "developer-id" ]]; then
    fail "NOTARIZE=1 requires SIGNING_MODE=developer-id"
  fi
  # Credentials are read from the environment/keychain profile — never committed.
  # Requires one of:
  #   xcrun notarytool store-credentials chaos-notary  (keychain profile), or
  #   NOTARY_KEY_ID / NOTARY_KEY_PATH / NOTARY_KEY_ISSUER (App Store Connect API)
  log "Submitting $ZIP_NAME for notarization (notarytool)"
  xcrun notarytool submit "$RELDIR/$ZIP_NAME" --keychain-profile chaos-notary --wait \
    || xcrun notarytool submit "$RELDIR/$ZIP_NAME" \
         --key-id "${NOTARY_KEY_ID:?}" --key "${NOTARY_KEY_PATH:?}" --issuer "${NOTARY_KEY_ISSUER:?}" --wait \
    || fail "notarization submission failed"
  xcrun stapler staple "$APP" || fail "stapler failed for app"
  codesign --verify --strict "$APP" || fail "post-staple verification failed"
  xcrun stapler staple "$RELDIR/$PKG_NAME" || fail "stapler failed for pkg"
  pkgutil --check-signature "$RELDIR/$PKG_NAME" >/dev/null || fail "pkg signature check failed"
  NOTARIZATION_STATUS="stapled"
  # Re-zip so the zip contains the stapled app; regenerate checksums.
  rm -f "$RELDIR/$ZIP_NAME"
  cd "$RELDIR" && ditto -c -k --keepParent Chaos.app "$ZIP_NAME" && cd "$ROOT"
  ( cd "$RELDIR" && shasum -a 256 "$PKG_NAME" "$ZIP_NAME" > SHA256SUMS )
fi

# --- 12. manifest --------------------------------------------------------------
log "Writing release-manifest.json"
cat > "$RELDIR/release-manifest.json" <<EOF
{
  "tag": "$TAG",
  "version": "$FULL_VERSION",
  "marketingVersion": "$MARKETING_VERSION",
  "buildNumber": "$CURRENT_PROJECT_VERSION",
  "architecture": "$ARCH_APP",
  "bundleIdentifier": "$BUNDLE_ID",
  "artifacts": {
    "pkg":  { "name": "$PKG_NAME",  "sha256": "$(shasum -a 256 "$RELDIR/$PKG_NAME"  | awk '{print $1}')" },
    "zip":  { "name": "$ZIP_NAME",  "sha256": "$(shasum -a 256 "$RELDIR/$ZIP_NAME"  | awk '{print $1}')" }
  },
  "signing": { "mode": "$SIGN_MODE_LABEL", "identity": "${SIGNING_IDENTITY:-ad-hoc}" },
  "notarization": "$NOTARIZATION_STATUS"
}
EOF

log "Release artifacts ready in $RELDIR:"
ls -la "$RELDIR" | grep -vE "^total|^d|stage" || true
log "Done."
