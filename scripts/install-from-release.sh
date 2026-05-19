#!/usr/bin/env bash
set -euo pipefail

# Download the latest ClaudeUsageBot release and install it to /Applications.
# No repo clone, no Swift toolchain required — just curl + unzip.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/munolee/claude-usage-bot/main/scripts/install-from-release.sh | bash
#
# Pin a specific version:
#   VERSION=v0.1.0 bash install-from-release.sh

REPO="munolee/claude-usage-bot"
VERSION="${VERSION:-latest}"
ASSET="ClaudeUsageBot.zip"
APP="/Applications/ClaudeUsageBot.app"

if [ "$VERSION" = "latest" ]; then
    URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
else
    URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading ${URL}"
curl -fsSL "$URL" -o "$TMP/$ASSET"

echo "==> Stopping any running instance"
pkill -x ClaudeUsageBot 2>/dev/null || true
sleep 1

echo "==> Installing to $APP"
rm -rf "$APP"
ditto -x -k "$TMP/$ASSET" /Applications/

echo "==> Removing quarantine attribute (lets Gatekeeper run an unsigned build)"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Launching"
open "$APP"

cat <<'EOF'

Installed. ClaudeUsageBot is in /Applications and is now running.

Next steps:
  1. Claude Code CLI에 로그인된 상태인지 확인 (한 번 `claude` 실행해서 brower OAuth 통과).
  2. macOS keychain 다이얼로그가 뜨면 "항상 허용"을 누르세요.
  3. 마스코트 우클릭 → 메뉴 두 번째 줄이 "데이터: Anthropic API (Xs 전)"로 떠야 정상.
     (JSONL 추정으로 떠 있으면 keychain 권한이 거부된 상태입니다.)

자동 실행을 원하면 System Settings → General → Login Items 에서
/Applications/ClaudeUsageBot.app 을 추가하세요.
EOF
