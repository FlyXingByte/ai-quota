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
  <key>CFBundleShortVersionString</key> <string>1.3.3</string>
  <key>CFBundleVersion</key>         <string>10</string>
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

# Use a named signing identity only when macOS reports it as valid. An imported
# but untrusted self-signed certificate can make codesign appear to succeed while
# strict verification fails with CSSMERR_TP_NOT_TRUSTED.
SIGN_ID="${AIQUOTA_SIGN_IDENTITY:-AI Quota Local Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$SIGN_ID\""; then
  echo "==> 签名 ($SIGN_ID)"
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "==> 签名 (ad-hoc — 没有可验证的本地签名身份)"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

echo "==> 完成: $APP"
"$APP/Contents/MacOS/$BIN_NAME" --self-test >/dev/null && echo "==> 离线自检通过"
