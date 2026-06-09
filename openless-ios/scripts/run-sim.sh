#!/bin/bash
# OpenLess iOS —— 一键：生成工程 → adhoc 签名构建 → 装到模拟器 → 启动
#
# adhoc 签名(CODE_SIGN_IDENTITY=-)是关键：让 App Group / 后台音频等 entitlements 在模拟器生效
# （未签名构建会清空 entitlements，导致键盘↔主App 的共享容器不通）。
#
# 用法：  scripts/run-sim.sh ["iPhone 17 Pro"]
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

DEVICE="${1:-iPhone 17 Pro}"
APP="build/Build/Products/Debug-iphonesimulator/OpenLess.app"
BUNDLE_ID="top.openless.ios"

echo "▸ 生成工程"
xcodegen generate >/dev/null

echo "▸ adhoc 签名构建（$DEVICE）"
xcodebuild -project OpenLess.xcodeproj -scheme OpenLess \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO PROVISIONING_PROFILE_SPECIFIER="" \
  build 2>&1 | grep -iE "error:| BUILD (SUCCEEDED|FAILED)" || true

echo "▸ 启动模拟器并安装"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
echo "✓ 完成：$BUNDLE_ID 已在「$DEVICE」启动（adhoc 签名，App Group 生效）"
