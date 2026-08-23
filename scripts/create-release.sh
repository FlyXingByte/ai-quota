#!/bin/bash
# Builds a private beta release: ZIP, drag-to-Applications DMG, and SHA-256 list.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${1:-}"
if [[ ! "$LABEL" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
  echo "用法: $0 1.3.0-beta.1" >&2
  exit 2
fi

BASE_VERSION="${LABEL%%-*}"
APP="$ROOT/build/AI Quota.app"
DIST="$ROOT/dist"
ZIP="$DIST/AI-Quota-$LABEL-macOS-arm64.zip"
DMG="$DIST/AI-Quota-$LABEL-macOS-arm64.dmg"
CHECKSUMS="$DIST/AI-Quota-$LABEL-SHA256.txt"
STAGE=""

cleanup() {
  if [[ -n "$STAGE" && "$STAGE" == /private/tmp/aiquota-dmg.* \
        && -d "$STAGE" && ! -L "$STAGE" ]]; then
    rm -rf -- "$STAGE"
  fi
}
trap cleanup EXIT

"$ROOT/build.sh"

actual_version="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
if [[ "$actual_version" != "$BASE_VERSION" ]]; then
  echo "版本不一致: App=$actual_version, Release=$LABEL" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"

mkdir -p "$DIST"
for output in "$ZIP" "$DMG" "$CHECKSUMS"; do
  if [[ -e "$output" ]]; then
    echo "拒绝覆盖已有 Release 资产: $output" >&2
    exit 1
  fi
done

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d /private/tmp/aiquota-dmg.XXXXXX)"
[[ -d "$STAGE" && ! -L "$STAGE" ]]
cp -R "$APP" "$STAGE/AI Quota.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AI Quota $LABEL" -srcfolder "$STAGE" \
  -format UDZO -ov "$DMG" >/dev/null

(
  cd "$DIST"
  shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" \
    > "$(basename "$CHECKSUMS")"
)

echo "==> Release 资产"
ls -lh "$ZIP" "$DMG" "$CHECKSUMS"
cat "$CHECKSUMS"
