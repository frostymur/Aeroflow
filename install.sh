#!/usr/bin/env bash
# AeroFlow installer.
# Downloads the latest release, installs the app to ~/Applications, strips the
# quarantine attribute (releases are ad-hoc signed — no Apple Developer ID),
# and links aeroflowctl into ~/.local/bin.
set -euo pipefail

REPO="${AEROFLOW_REPO:-frostymur/OmniWM}"
DEST_DIR="${AEROFLOW_DEST:-$HOME/Applications}"
APP_NAME="AeroFlow.app"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

echo "==> Resolving latest release of ${REPO}"
asset_url=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" |
  python3 -c '
import json, sys
release = json.load(sys.stdin)
asset = next((a for a in release.get("assets", []) if a["name"].endswith(".zip")), None)
if asset is None:
    raise SystemExit("no .zip asset in release " + release.get("tag_name", "?"))
print(asset["browser_download_url"])
')

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading ${asset_url}"
curl -fL --progress-bar -o "$TMP/aeroflow.zip" "$asset_url"

echo "==> Extracting"
unzip -q "$TMP/aeroflow.zip" -d "$TMP"
APP_SRC="$(find "$TMP" -maxdepth 2 -name "$APP_NAME" -print -quit)"
if [ -z "$APP_SRC" ]; then
  echo "release archive does not contain ${APP_NAME}" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
echo "==> Installing to ${DEST_DIR}/${APP_NAME}"
# Only stop an AeroFlow launched from this install destination, never
# another build (e.g. "AeroFlow Dev.app") the user may be running.
for pid in $(pgrep -f "${DEST_DIR}/${APP_NAME}/Contents/MacOS/AeroFlow" 2>/dev/null || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 1
rm -rf "${DEST_DIR:?}/${APP_NAME}"
cp -R "$APP_SRC" "$DEST_DIR/$APP_NAME"

echo "==> Stripping quarantine"
xattr -cr "$DEST_DIR/$APP_NAME"

CLI_SRC="$DEST_DIR/$APP_NAME/Contents/MacOS/aeroflowctl"
CLI_DIR="$HOME/.local/bin"
if [ -x "$CLI_SRC" ] && [ ! -e "$CLI_DIR/aeroflowctl" ]; then
  mkdir -p "$CLI_DIR"
  ln -s "$CLI_SRC" "$CLI_DIR/aeroflowctl"
  case ":$PATH:" in
    *":$CLI_DIR:"*) ;;
    *) echo "note: add $CLI_DIR to your PATH to use aeroflowctl" ;;
  esac
fi

echo "==> Done. Launch with: open \"${DEST_DIR}/${APP_NAME}\""
echo "    First launch needs Accessibility + Input Monitoring (System Settings -> Privacy & Security)."
