#!/bin/bash
# Produces Developer ID signed, Apple-notarized, stapled release assets.
#
# This is the path for anyone other than you running the app: a locally signed
# build trips Gatekeeper on every other Mac. Notarization is what removes that,
# and it needs two things this repository cannot contain — a Developer ID
# certificate and notary credentials, both tied to a paid Apple Developer
# Program membership. Preflight below says exactly what is missing.
#
#   ./scripts/notarize-release.sh 1.4.0 [--replace]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${1:-}"
REPLACE="${2:-}"
PROFILE="${AIQUOTA_NOTARY_PROFILE:-AI Quota Notary}"

if [[ ! "$LABEL" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
  echo "用法 / usage: $0 1.4.0 [--replace]" >&2
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
  if [[ -n "$STAGE" && "$STAGE" == /private/tmp/aiquota-notarize.* \
        && -d "$STAGE" && ! -L "$STAGE" ]]; then
    rm -rf -- "$STAGE"
  fi
}
trap cleanup EXIT

# ---- Preflight -------------------------------------------------------------
# Everything that can be checked without spending a notarization round-trip.

missing=0

IDENTITY="${AIQUOTA_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  # -v is right here, unlike the local development identity: a real Developer ID
  # certificate chains to Apple and must show up as valid.
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
              | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ]; then
  cat >&2 <<'MSG'
✗ 找不到 Developer ID Application 证书 / no Developer ID Application certificate

  需要一次性完成 / one-time setup:
  1. 加入 Apple Developer Program（$99/年）：https://developer.apple.com/programs/
  2. Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
     （或在 developer.apple.com/account/resources/certificates 里创建后双击导入登录钥匙串）
  3. 确认：security find-identity -v -p codesigning | grep "Developer ID Application"
MSG
  missing=1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<MSG
✗ 找不到公证凭据 / no notary credentials for profile "$PROFILE"

  需要一次性完成 / one-time setup:
  1. 在 https://appleid.apple.com → 登录与安全 → App 专用密码，生成一个
  2. 团队 ID 在 https://developer.apple.com/account → Membership details
  3. xcrun notarytool store-credentials "$PROFILE" \\
       --apple-id <你的 Apple ID> --team-id <TEAMID> --password <App 专用密码>
     （凭据存进钥匙串，之后不再需要密码）
MSG
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  echo "" >&2
  echo "补齐以上条件后重新运行 / re-run once the above exist:" >&2
  echo "  $0 $LABEL" >&2
  exit 1
fi

for output in "$ZIP" "$DMG" "$CHECKSUMS"; do
  if [[ -e "$output" ]]; then
    if [[ "$REPLACE" == "--replace" ]]; then
      rm -f -- "$output"
    else
      echo "已存在同版本资产 / asset exists: $output" >&2
      echo "（传 --replace 覆盖 / pass --replace to overwrite）" >&2
      exit 1
    fi
  fi
done

echo "==> 使用身份 / signing identity: $IDENTITY"

# ---- Build and sign --------------------------------------------------------
# build.sh adds the hardened runtime and a secure timestamp for a Developer ID
# identity; notarization rejects a submission without either.
AIQUOTA_SIGN_IDENTITY="$IDENTITY" "$ROOT/build.sh"

actual_version="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
if [[ "$actual_version" != "$BASE_VERSION" ]]; then
  echo "版本不一致 / version mismatch: App=$actual_version, Release=$LABEL" >&2
  exit 1
fi

if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q 'flags=.*runtime'; then
  echo "签名缺少 hardened runtime / signature has no hardened runtime" >&2
  exit 1
fi

# ---- Notarize the app ------------------------------------------------------
STAGE="$(mktemp -d /private/tmp/aiquota-notarize.XXXXXX)"
[[ -d "$STAGE" && ! -L "$STAGE" ]]
SUBMISSION="$STAGE/submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"

echo "==> 提交公证 / submitting the app (this waits for Apple)"
if ! xcrun notarytool submit "$SUBMISSION" --keychain-profile "$PROFILE" --wait; then
  echo "公证失败，取日志 / notarization failed; fetch the log with:" >&2
  echo "  xcrun notarytool log <submission-id> --keychain-profile \"$PROFILE\"" >&2
  exit 1
fi

echo "==> 装订 / stapling the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# ---- Package ---------------------------------------------------------------
mkdir -p "$DIST"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

DMG_STAGE="$STAGE/dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/AI Quota.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "AI Quota $LABEL" -srcfolder "$DMG_STAGE" \
  -format UDZO -ov "$DMG" >/dev/null

# The DMG is a separate artifact and gets its own ticket, so a user who never
# unpacks it is still checked offline.
echo "==> 提交 DMG 公证 / submitting the disk image"
if ! xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait; then
  echo "DMG 公证失败 / disk image notarization failed" >&2
  exit 1
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# ---- Verify the way Gatekeeper will ----------------------------------------
echo "==> 校验 / verification"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

(
  cd "$DIST"
  shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "$(basename "$CHECKSUMS")"
)

echo ""
echo "==> 已公证的 Release 资产 / notarized release assets"
ls -lh "$ZIP" "$DMG" "$CHECKSUMS"
cat "$CHECKSUMS"
echo ""
echo "这两个文件在任何 Mac 上都能直接打开，不再需要右键或 xattr。"
echo "These open on any Mac — no right-click, no xattr."
