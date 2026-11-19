#!/usr/bin/env bash
# Georg md — build Release firmado con Developer ID, notarizado y empaquetado en .dmg.
#
# Uso:
#   scripts/release.sh 1.0.0                 build + firma + notarización + .dmg en dist/
#   scripts/release.sh 1.0.0 --skip-notarize solo build + firma + .dmg (prueba local, Gatekeeper lo rechazará)
#   scripts/release.sh 1.0.0 --publish       además crea el release v1.0.0 en GitHub con el .dmg
#
# Requisitos: certificado "Developer ID Application" del equipo en el llavero y un perfil de notarytool:
#   xcrun notarytool store-credentials georg-md --apple-id <apple-id> --team-id 34BRMF8X9A
# (pide una contraseña específica de app de appleid.apple.com). Otro nombre de perfil: NOTARY_PROFILE=…
set -euo pipefail

VERSION="${1:-}"
shift || true
NOTARIZE=1
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) NOTARIZE=0 ;;
    --publish) PUBLISH=1 ;;
    *) echo "Opción desconocida: $arg" >&2; exit 2 ;;
  esac
done
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  echo "Uso: scripts/release.sh <versión, p. ej. 1.0.0> [--skip-notarize] [--publish]" >&2
  exit 2
fi
if [[ $PUBLISH == 1 && $NOTARIZE == 0 ]]; then
  echo "No se publica un build sin notarizar." >&2
  exit 2
fi

TEAM="34BRMF8X9A"
IDENTITY="Developer ID Application"
PROFILE="${NOTARY_PROFILE:-georg-md}"
REPO="shipibo-studio/georg-md"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"   # monótono, sin depender de git

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/build/release"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/Georg md.app"
DMG="$DIST/Georg-md-$VERSION.dmg"

step() { printf '\n==> %s\n' "$*"; }

step "Comprobando requisitos"
security find-identity -v -p codesigning | grep -q "$IDENTITY: .*($TEAM)" \
  || { echo "Falta el certificado '$IDENTITY' del equipo $TEAM en el llavero." >&2; exit 1; }
if [[ $NOTARIZE == 1 ]]; then
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || { echo "No existe o no funciona el perfil de notarytool '$PROFILE'. Ver el encabezado de este script." >&2; exit 1; }
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
[[ -d "$APP" ]] || { echo "No se generó $APP" >&2; exit 1; }

step "Verificando firma"
codesign --verify --deep --strict --verbose=2 "$APP"
for bin in "$APP" "$APP/Contents/PlugIns/Georg md Preview.appex" "$APP/Contents/Helpers/georg"; do
  info="$(codesign -dvv "$bin" 2>&1)"
  grep -q "Authority=Developer ID Application: .*($TEAM)" <<<"$info" || { echo "Firma incorrecta en $bin" >&2; exit 1; }
  grep -q "flags=.*runtime" <<<"$info" || { echo "Sin hardened runtime: $bin" >&2; exit 1; }
  grep -q "Timestamp=" <<<"$info" || { echo "Sin sello de tiempo: $bin" >&2; exit 1; }
  if codesign -d --entitlements - "$bin" 2>/dev/null | grep -q "get-task-allow"; then
    echo "Entitlement de depuración (get-task-allow) presente en $bin" >&2; exit 1
  fi
done
# La herramienta de desarrollo sin sandbox nunca debe viajar en el bundle.
if find "$APP" -name "GeorgDevTool*" | grep -q .; then echo "GeorgDevTool dentro del bundle" >&2; exit 1; fi

mkdir -p "$DIST"
if [[ $NOTARIZE == 1 ]]; then
  step "Notarizando la app"
  ZIP="$DIST/Georg-md-$VERSION-app.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

step "Creando $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Georg md.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Georg md $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY: Jorge Epuñan ($TEAM)" --timestamp "$DMG" 2>/dev/null \
  || codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ $NOTARIZE == 1 ]]; then
  step "Notarizando el .dmg"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  step "Gatekeeper"
  spctl -a -vv -t install "$DMG"
  spctl -a -vv "$APP"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"

if [[ $PUBLISH == 1 ]]; then
  step "Publicando v$VERSION en $REPO"
  gh release create "v$VERSION" "$DMG" "$DMG.sha256" --repo "$REPO" --title "Georg md $VERSION" \
    --notes "Signed with Developer ID and notarized by Apple. SHA-256 in the attached .sha256 file."
fi

step "Listo: $DMG"
