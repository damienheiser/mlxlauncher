#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/MLXLauncher.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"

swift build -c "$CONFIGURATION"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp ".build/arm64-apple-macosx/$CONFIGURATION/MLXLauncher" "$MACOS/MLXLauncher"

# Copy MLX Metal shader library (required for GPU inference)
MLX_METALLIB="/opt/homebrew/lib/python3.14/site-packages/mlx/lib/mlx.metallib"
if [ -f "$MLX_METALLIB" ]; then
  cp "$MLX_METALLIB" "$MACOS/mlx.metallib"
  echo "Copied mlx.metallib from Python mlx package"
elif [ -f ".build/arm64-apple-macosx/$CONFIGURATION/mlx.metallib" ]; then
  cp ".build/arm64-apple-macosx/$CONFIGURATION/mlx.metallib" "$MACOS/mlx.metallib"
else
  echo "WARNING: mlx.metallib not found — GPU inference will fail"
  echo "Install: pip3 install mlx && copy mlx.metallib next to the binary"
fi

swift generate_icon.swift "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MLXLauncher</string>
  <key>CFBundleIdentifier</key>
  <string>io.engrave.mlxlauncher</string>
  <key>CFBundleName</key>
  <string>MLX Launcher</string>
  <key>CFBundleDisplayName</key>
  <string>MLX Launcher</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built $APP"
