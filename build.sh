#!/bin/bash
# Builds AI Quota.app. No Xcode required — swiftc from the Command Line Tools
# plus a hand-assembled bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/AI Quota.app"
BIN_NAME="AIQuota"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译"
swiftc -O \
  -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -framework Security -framework Combine \
  -lsqlite3 \
  -o "$APP/Contents/MacOS/$BIN_NAME" \
  "$ROOT"/Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key> <string>zh_CN</string>
  <key>CFBundleName</key>            <string>AI Quota</string>
  <key>CFBundleDisplayName</key>     <string>AI Quota</string>
  <key>CFBundleIdentifier</key>      <string>com.flyx.aiquota</string>
  <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
  <key>CFBundleExecutable</key>      <string>AIQuota</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.1.0</string>
  <key>CFBundleVersion</key>         <string>2</string>
  <key>CFBundleIconFile</key>        <string>AppIcon.icns</string>
  <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSMultipleInstancesProhibited</key> <true/>
  <key>LSUIElement</key>             <true/>
  <key>NSHighResolutionCapable</key> <true/>
  <key>NSPrincipalClass</key>        <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key> <string>Copyright © 2026 FlyX. Local utility.</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Prefer the local signing identity: it gives a designated requirement that
# survives rebuilds, so TCC grants are not silently revoked every install.
#
# Do NOT gate this on `find-identity -v`. A self-signed cert that was never
# installed as a trusted root is reported there as CSSMERR_TP_NOT_TRUSTED and
# filtered out — but codesign signs with it happily and `--verify --strict`
# passes, because that checks signature integrity, not chain trust. Gating on
# -v just means every build silently degrades to ad-hoc.
SIGN_ID="${AIQUOTA_SIGN_IDENTITY:-AI Quota Local Signing}"
if security find-identity -p codesigning 2>/dev/null | grep -Fq "\"$SIGN_ID\"" \
   && codesign --force --deep --sign "$SIGN_ID" "$APP" 2>/dev/null \
   && codesign --verify --deep --strict "$APP" 2>/dev/null; then
  echo "==> 签名 ($SIGN_ID)"
else
  echo "==> 签名 (ad-hoc — 找不到 \"$SIGN_ID\"，跑 ./make-signing-cert.sh 生成)"
  echo "    注意：ad-hoc 的指定要求是 cdhash，每次重编译都会让已授过的权限失效。"
  codesign --force --deep --sign - "$APP"
  codesign --verify --deep --strict "$APP"
fi

echo "==> 完成: $APP"
"$APP/Contents/MacOS/$BIN_NAME" --help >/dev/null && echo "==> 二进制可运行"
