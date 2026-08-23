#!/bin/bash
# Verifies a previously created AI Quota release without launching the App.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${1:-}"
if [[ ! "$LABEL" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
  echo "用法: $0 1.3.0-beta.1" >&2
  exit 2
fi

BASE_VERSION="${LABEL%%-*}"
DIST="$ROOT/dist"
ZIP="$DIST/AI-Quota-$LABEL-macOS-arm64.zip"
DMG="$DIST/AI-Quota-$LABEL-macOS-arm64.dmg"
CHECKSUMS="$DIST/AI-Quota-$LABEL-SHA256.txt"
VERIFY_ROOT=""

cleanup() {
  if [[ -n "$VERIFY_ROOT" && "$VERIFY_ROOT" == /private/tmp/aiquota-release.* \
        && -d "$VERIFY_ROOT" && ! -L "$VERIFY_ROOT" ]]; then
    rm -rf -- "$VERIFY_ROOT"
  fi
}
trap cleanup EXIT

for input in "$ZIP" "$DMG" "$CHECKSUMS"; do
  [[ -f "$input" && ! -L "$input" ]] || {
    echo "缺少 Release 资产: $input" >&2
    exit 1
  }
done

while read -r expected name; do
  [[ -n "$expected" && -n "$name" ]]
  actual="$(shasum -a 256 "$DIST/$name" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    echo "SHA-256 不匹配: $name" >&2
    exit 1
  }
done < "$CHECKSUMS"

unzip -t "$ZIP" >/dev/null
hdiutil verify "$DMG" >/dev/null

VERIFY_ROOT="$(mktemp -d /private/tmp/aiquota-release.XXXXXX)"
[[ -d "$VERIFY_ROOT" && ! -L "$VERIFY_ROOT" ]]
ditto -x -k "$ZIP" "$VERIFY_ROOT"
APP="$VERIFY_ROOT/AI Quota.app"
[[ -d "$APP" && ! -L "$APP" ]]
codesign --verify --deep --strict "$APP"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" \
   == "$BASE_VERSION" ]]
file "$APP/Contents/MacOS/AIQuota" | grep -q 'arm64'
"$APP/Contents/MacOS/AIQuota" --help | grep -q "AI Quota $BASE_VERSION"

echo "Release verification passed for v$LABEL."
