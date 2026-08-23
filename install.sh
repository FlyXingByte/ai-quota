#!/bin/bash
# Builds and installs AI Quota.app into /Applications, then starts it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_APP="$ROOT/build/AI Quota.app"
DEST="/Applications/AI Quota.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if pgrep -f "AI Quota.app/Contents/MacOS/AIQuota" >/dev/null 2>&1; then
  echo "==> 停止正式版和构建版实例"
  pkill -f "AI Quota.app/Contents/MacOS/AIQuota" || true
  sleep 1
fi

"$ROOT/build.sh"

if [ -e "$DEST" ]; then
  if [ ! -d "$DEST" ] || [ -L "$DEST" ]; then
    echo "拒绝覆盖异常安装目标: $DEST" >&2
    exit 1
  fi
  echo "==> 覆盖已安装的版本 $DEST"
  rm -rf "$DEST"
fi

echo "==> 安装到 $DEST"
cp -R "$ROOT/build/AI Quota.app" "$DEST"
codesign --verify --deep --strict "$DEST"
if ! "$LSREGISTER" -f "$DEST"; then
  echo "警告：LaunchServices 刷新失败；App 已安装，可稍后重新运行 install.sh" >&2
fi

# The build product shares the installed app's bundle identity. Keeping both
# visible makes Finder, LaunchServices, and privacy/login-item UI ambiguous.
if [ "$BUILD_APP" != "$ROOT/build/AI Quota.app" ] || [ -L "$BUILD_APP" ]; then
  echo "拒绝清理异常构建目标: $BUILD_APP" >&2
  exit 1
fi
rm -rf "$BUILD_APP"
echo "==> 已清理构建副本，避免系统识别出两个 AI Quota"

echo "==> 启动"
open "$DEST"
echo "==> 完成。菜单栏右上角会出现一个仪表盘图标。"
