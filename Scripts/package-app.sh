#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
SIGN_AND_NOTARIZE="${2:-true}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${AEROFLOW_APP_NAME:-AeroFlow}"
BUNDLE_ID="${AEROFLOW_BUNDLE_ID:-com.frostymur.AeroFlow}"
case "$APP_NAME" in
  .|..|*/*)
    echo "package-app: the app name must be a single directory name" >&2
    exit 1
    ;;
esac
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
SWIFT_BUILD_ARGS=(-c "$CONFIG" --arch arm64)

# Signing identity and notarization profile
SIGNING_IDENTITY="${AEROFLOW_SIGNING_IDENTITY:-Developer ID Application: Oliver Nikolic (VF8LDJRGFM)}"
NOTARIZE_PROFILE="${AEROFLOW_NOTARIZE_PROFILE:-AeroFlow-Notarize}"
ENTITLEMENTS="$ROOT_DIR/AeroFlow.entitlements"


echo "Building AeroFlow arm64 binary ($CONFIG)..."
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
EXECUTABLE="$BUILD_DIR/AeroFlow"
CLI_EXECUTABLE="$BUILD_DIR/aeroflowctl"

echo "Verifying arm64 binaries..."
lipo -info "$EXECUTABLE"
lipo -info "$CLI_EXECUTABLE"

echo "Packaging $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/AeroFlow"
cp "$CLI_EXECUTABLE" "$APP_DIR/Contents/MacOS/aeroflowctl"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if command -v plutil >/dev/null 2>&1; then
  plutil -replace AEROFLOWGitHash -string "$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo SNAPSHOT)" "$APP_DIR/Contents/Info.plist"
  if [ "$APP_NAME" != "AeroFlow" ] || [ "$BUNDLE_ID" != "com.frostymur.AeroFlow" ]; then
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
    plutil -replace CFBundleName -string "$APP_NAME" "$APP_DIR/Contents/Info.plist"
    plutil -replace CFBundleDisplayName -string "$APP_NAME" "$APP_DIR/Contents/Info.plist"
  fi
fi
cp -R "$BUILD_DIR/AeroFlow_AeroFlow.bundle" "$APP_DIR/Contents/Resources/"
python3 "$ROOT_DIR/Scripts/localization.py" package \
  --bundle "$BUILD_DIR/AeroFlow_AeroFlow.bundle" --app "$APP_DIR"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
fi

# Strip extended attributes (e.g. com.apple.provenance) so the release zip
# carries no AppleDouble ._* companions; those break the app's code-seal
# verification after install. The code signature lives in the Mach-O, not in
# xattrs, so this is safe to do before signing.
xattr -cr "$APP_DIR"

if [ "$SIGN_AND_NOTARIZE" = "true" ]; then
  echo "Signing $APP_DIR with hardened runtime..."
  codesign --force --options runtime --sign "$SIGNING_IDENTITY" --timestamp "$APP_DIR/Contents/MacOS/aeroflowctl"
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" --timestamp "$APP_DIR/Contents/MacOS/AeroFlow"
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" --timestamp "$APP_DIR"

  echo "Verifying signature..."
  codesign --verify --verbose "$APP_DIR"

  echo "Creating ZIP for notarization..."
  ZIP_PATH="$ROOT_DIR/dist/AeroFlow.zip"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

  echo "Submitting for notarization (this may take a few minutes)..."
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$APP_DIR"

  echo "Verifying notarization..."
  spctl --assess --verbose=2 "$APP_DIR"

  echo "Checking distribution readiness..."
  syspolicy_check distribution "$APP_DIR"

  rm -f "$ZIP_PATH"
  echo "Done! $APP_DIR is signed and notarized."
elif [ "$SIGN_AND_NOTARIZE" = "dev" ]; then
  if security find-identity -v -p codesigning | grep -qF "$SIGNING_IDENTITY"; then
    IDENTITY="$SIGNING_IDENTITY"
  else
    IDENTITY="-"
    echo "No '$SIGNING_IDENTITY' certificate found; using ad-hoc signing. macOS may request permissions again after rebuilding. See CONTRIBUTING.md for certificate setup." >&2
  fi
  echo "Signing $APP_DIR for development (identity: $IDENTITY)..."
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/aeroflowctl"
  codesign --force --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/AeroFlow"
  codesign --force --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR"
  codesign --verify --verbose "$APP_DIR"
  echo "Done. Launch with 'open $APP_DIR' so LaunchServices assigns the app identity."
else
  echo "Done. Open $APP_DIR to grant Accessibility permissions."
  echo "Note: App is not signed. Run with 'release true' to sign and notarize."
fi
