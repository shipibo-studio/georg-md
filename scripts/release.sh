#!/usr/bin/env bash
# Georg md — Release build signed with Developer ID, notarized and packaged as a .dmg.
#
# Usage:
#   scripts/release.sh 1.0.0                 build + sign + notarize + .dmg in dist/
#   scripts/release.sh 1.0.0 --skip-notarize build + sign + .dmg only (local test, Gatekeeper will reject it)
#   scripts/release.sh 1.0.0 --publish       also creates the v1.0.0 release on GitHub with the .dmg
#
# Requirements: the team's "Developer ID Application" certificate in the keychain and a notarytool profile:
#   xcrun notarytool store-credentials georg-md --apple-id <apple-id> --team-id 34BRMF8X9A
# (it asks for an app-specific password from appleid.apple.com). Different profile name: NOTARY_PROFILE=…
set -euo pipefail

VERSION="${1:-}"
shift || true
NOTARIZE=1
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) NOTARIZE=0 ;;
    --publish) PUBLISH=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  echo "Usage: scripts/release.sh <version, e.g. 1.0.0> [--skip-notarize] [--publish]" >&2
  exit 2
fi
if [[ $PUBLISH == 1 && $NOTARIZE == 0 ]]; then
  echo "Refusing to publish a build that is not notarized." >&2
  exit 2
fi

TEAM="34BRMF8X9A"
IDENTITY="Developer ID Application"
PROFILE="${NOTARY_PROFILE:-georg-md}"
REPO="shipibo-studio/georg-md"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"   # monotonic, independent of git

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/build/release"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/Georg md.app"
DMG="$DIST/Georg-md-$VERSION.dmg"
NOTES="$DIST/Georg-md-$VERSION-notes.md"

step() { printf '\n==> %s\n' "$*"; }

step "Checking requirements"
# The release notes are this version's section of CHANGELOG.md (without the link references);
# publishing a version that has no section is refused before anything is built.
mkdir -p "$DIST"
awk -v head="## [$VERSION]" '
  index($0, head) == 1 { found = 1; next }
  found && /^## \[/ { exit }
  found && /^\[[^]]+\]: https?:/ { next }
  found { print }
' CHANGELOG.md > "$NOTES"
if [[ $PUBLISH == 1 ]] && ! grep -q '[^[:space:]]' "$NOTES"; then
  echo "CHANGELOG.md has no section for $VERSION; add it before publishing." >&2
  exit 1
fi
printf '\n---\n\nSigned with Developer ID and notarized by Apple. The SHA-256 of the disk image is in the attached `.sha256` file.\n' >> "$NOTES"
security find-identity -v -p codesigning | grep -q "$IDENTITY: .*($TEAM)" \
  || { echo "Missing the '$IDENTITY' certificate for team $TEAM in the keychain." >&2; exit 1; }
if [[ $NOTARIZE == 1 ]]; then
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || { echo "The notarytool profile '$PROFILE' does not exist or does not work. See the header of this script." >&2; exit 1; }
fi

step "Build Release $VERSION ($BUILD_NUMBER)"
xcodegen generate >/dev/null
rm -rf "$DERIVED"
xcodebuild -project GeorgMD.xcodeproj -scheme GeorgMD -configuration Release \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build | grep -E "error:|warning:|\*\* BUILD" || true
[[ -d "$APP" ]] || { echo "$APP was not built" >&2; exit 1; }

step "Verifying signatures"
codesign --verify --deep --strict --verbose=2 "$APP"
for bin in "$APP" "$APP/Contents/PlugIns/Georg md Preview.appex" "$APP/Contents/Helpers/georg"; do
  info="$(codesign -dvv "$bin" 2>&1)"
  grep -q "Authority=Developer ID Application: .*($TEAM)" <<<"$info" || { echo "Wrong signature on $bin" >&2; exit 1; }
  grep -q "flags=.*runtime" <<<"$info" || { echo "No hardened runtime: $bin" >&2; exit 1; }
  grep -q "Timestamp=" <<<"$info" || { echo "No timestamp: $bin" >&2; exit 1; }
  if codesign -d --entitlements - "$bin" 2>/dev/null | grep -q "get-task-allow"; then
    echo "Debug entitlement (get-task-allow) present in $bin" >&2; exit 1
  fi
done
# The unsandboxed development tool must never ship inside the bundle.
if find "$APP" -name "GeorgDevTool*" | grep -q .; then echo "GeorgDevTool inside the bundle" >&2; exit 1; fi

mkdir -p "$DIST"
if [[ $NOTARIZE == 1 ]]; then
  step "Notarizing the app"
  ZIP="$DIST/Georg-md-$VERSION-app.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

step "Creating $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Georg md.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Georg md $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY: Jorge Epuñan ($TEAM)" --timestamp "$DMG" 2>/dev/null \
  || codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ $NOTARIZE == 1 ]]; then
  step "Notarizing the .dmg"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  step "Gatekeeper"
  spctl -a -vv -t install "$DMG"
  spctl -a -vv "$APP"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"

if [[ $PUBLISH == 1 ]]; then
  step "Publishing v$VERSION to $REPO"
  gh release create "v$VERSION" "$DMG" "$DMG.sha256" --repo "$REPO" --title "Georg md $VERSION" \
    --notes-file "$NOTES"
fi

step "Done: $DMG"
