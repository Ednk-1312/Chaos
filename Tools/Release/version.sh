#!/bin/bash
# version.sh — derive release version metadata from the git tag.
#
# Tag format: vMAJOR.MINOR.PATCH-preview.N   (e.g. v0.1.0-preview.1)
#   MARKETING_VERSION       = MAJOR.MINOR.PATCH
#   CURRENT_PROJECT_VERSION = N
#   RELEASE_LABEL           = Preview N
#
# Usage:
#   Tools/Release/version.sh --shell    print KEY=VALUE lines (safe to eval)
#   Tools/Release/version.sh --check    verify tag ↔ Version.xcconfig agreement
#   Tools/Release/version.sh --update   rewrite Version.xcconfig from current tag
#   Tools/Release/version.sh            same as --shell
set -euo pipefail
cd "$(dirname "$0")/../.."

MODE="${1:---shell}"

# Tag: env override (CI) or the most recent v* tag.
TAG="${RELEASE_TAG:-$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)}"
if [[ -z "$TAG" ]]; then
  echo "error: no version tag found (expected vMAJOR.MINOR.PATCH-preview.N)" >&2
  exit 1
fi

if [[ ! "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)-preview\.([0-9]+)$ ]]; then
  echo "error: tag '$TAG' does not match vMAJOR.MINOR.PATCH-preview.N" >&2
  exit 1
fi
MAJOR="${BASH_REMATCH[1]}"; MINOR="${BASH_REMATCH[2]}"; PATCH="${BASH_REMATCH[3]}"; PREVIEW="${BASH_REMATCH[4]}"
MARKETING_VERSION="$MAJOR.$MINOR.$PATCH"
CURRENT_PROJECT_VERSION="$PREVIEW"
RELEASE_LABEL="Preview $PREVIEW"
FULL_VERSION="$MARKETING_VERSION-preview.$PREVIEW"

XCCONFIG="Version.xcconfig"

case "$MODE" in
  --shell)
    # %q keeps values safely word-split-proof for `eval "$(version.sh --shell)"`
    printf 'TAG=%q\n' "$TAG"
    printf 'MARKETING_VERSION=%q\n' "$MARKETING_VERSION"
    printf 'CURRENT_PROJECT_VERSION=%q\n' "$CURRENT_PROJECT_VERSION"
    printf 'RELEASE_LABEL=%q\n' "$RELEASE_LABEL"
    printf 'FULL_VERSION=%q\n' "$FULL_VERSION"
    ;;
  --update)
    cat > "$XCCONFIG" <<EOF
// Version.xcconfig — single source of truth for Chaos release versioning.
// Managed by Tools/Release/version.sh; committed defaults exist so a plain
// clone builds with correct versions without running release tooling.
//
//   git tag: $TAG
//   bundle short version: $MARKETING_VERSION
//   bundle build number:  $CURRENT_PROJECT_VERSION

MARKETING_VERSION = $MARKETING_VERSION
CURRENT_PROJECT_VERSION = $CURRENT_PROJECT_VERSION
EOF
    echo "updated $XCCONFIG from $TAG"
    ;;
  --check)
    # Verify xcconfig agrees with the tag.
    XC_MV="$(sed -n 's/^MARKETING_VERSION *= *//p' "$XCCONFIG" | tr -d '[:space:]')"
    XC_CPV="$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' "$XCCONFIG" | tr -d '[:space:]')"
    FAIL=0
    if [[ "$XC_MV" != "$MARKETING_VERSION" ]]; then
      echo "error: Version.xcconfig MARKETING_VERSION=$XC_MV does not match tag $TAG (expected $MARKETING_VERSION)" >&2
      FAIL=1
    fi
    if [[ "$XC_CPV" != "$CURRENT_PROJECT_VERSION" ]]; then
      echo "error: Version.xcconfig CURRENT_PROJECT_VERSION=$XC_CPV does not match tag $TAG (expected $CURRENT_PROJECT_VERSION)" >&2
      FAIL=1
    fi
    if [[ $FAIL -eq 1 ]]; then
      echo "run: Tools/Release/version.sh --update" >&2
      exit 1
    fi
    echo "version OK: $TAG → $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"
    ;;
  *)
    echo "usage: $0 [--shell|--check|--update]" >&2
    exit 2
    ;;
esac
