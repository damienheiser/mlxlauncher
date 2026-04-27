#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/Engrave.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"

swift build -c "$CONFIGURATION"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

# The Swift binary is still named MLXLauncher (from Package.swift target name)
cp ".build/arm64-apple-macosx/$CONFIGURATION/MLXLauncher" "$MACOS/Engrave"

# Copy MLX Metal shader library (required for GPU inference)
MLX_METALLIB=""
for candidate in \
  ".build/arm64-apple-macosx/$CONFIGURATION/mlx.metallib" \
  "/opt/homebrew/lib/mlx.metallib" \
  "/opt/homebrew/lib/python3"*/site-packages/mlx/lib/mlx.metallib \
  "$HOME/.local/pipx/venvs/mlx/lib/python3"*/site-packages/mlx/lib/mlx.metallib \
  "$HOME/.local/pipx/venvs/mlx-lm/lib/python3"*/site-packages/mlx/lib/mlx.metallib; do
  if [ -f "$candidate" ]; then
    MLX_METALLIB="$candidate"
    break
  fi
done
if [ -n "$MLX_METALLIB" ]; then
  cp "$MLX_METALLIB" "$MACOS/mlx.metallib"
  echo "Copied mlx.metallib from $MLX_METALLIB"
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
  <string>Engrave</string>
  <key>CFBundleIdentifier</key>
  <string>io.engrave.app</string>
  <key>CFBundleName</key>
  <string>Engrave</string>
  <key>CFBundleDisplayName</key>
  <string>Engrave</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0-beta</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

echo "Built $APP"
