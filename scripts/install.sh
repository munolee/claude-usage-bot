#!/usr/bin/env bash
# Build a release .app bundle, install it to /Applications, and restart any
# running instance so the new build takes over without a logout.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageBot"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "==> Building release bundle"
./scripts/package-app.sh

BUILT_APP=".build/release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "Build did not produce $BUILT_APP" >&2
    exit 1
fi

echo "==> Stopping any running instance"
pkill -f "$APP_NAME" >/dev/null 2>&1 || true
sleep 1

echo "==> Installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "==> Launching"
open "$INSTALL_PATH"

echo "Done. Launch later via Spotlight (⌘Space → $APP_NAME), Launchpad, or Finder."
echo "Auto-start on login: System Settings → General → Login Items → add $INSTALL_PATH"
