#!/bin/bash
# Build "Desktop Games.app" from the Swift package and the assets inside stress_relief.exe.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="${1:-$ROOT/stress_relief.exe}"
BUILD="$ROOT/build"
APP="$BUILD/Desktop Games.app"

mkdir -p "$BUILD"
rm -rf "$BUILD/Assets"
echo "==> Extracting assets from $(basename "$EXE")"
(cd "$ROOT/tools" && uv run --no-project --with pillow --with pefile python extract.py "$EXE" "$BUILD/Assets")

echo "==> Building app icon"
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
uv run --no-project --with pillow python - "$BUILD/Assets/app_icon.png" "$ICONSET" <<'PY'
import sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
icon = Image.open(src).convert("RGBA")
for size in (16, 32, 128, 256, 512):
    for scale, suffix in ((1, ""), (2, "@2x")):
        px = size * scale
        resample = Image.NEAREST if px >= icon.width else Image.LANCZOS
        icon.resize((px, px), resample).save(f"{out}/icon_{size}x{size}{suffix}.png")
PY
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "==> Compiling"
ARCHS=(--arch arm64 --arch x86_64)
(cd "$ROOT" && swift build -c release "${ARCHS[@]}")
BIN="$(cd "$ROOT" && swift build -c release "${ARCHS[@]}" --show-bin-path)/DesktopGames"

echo "==> Assembling $(basename "$APP")"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DesktopGames"
cp -R "$BUILD/Assets" "$APP/Contents/Resources/Assets"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Desktop Games</string>
    <key>CFBundleDisplayName</key><string>Desktop Games</string>
    <key>CFBundleIdentifier</key><string>io.github.ucodia.desktopgames</string>
    <key>CFBundleExecutable</key><string>DesktopGames</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Desktop Games (Stress Reducers) (c) Miroslav Nemecek, Gemtree Software. Freeware. Unofficial macOS port.</string>
    <key>NSScreenCaptureUsageDescription</key><string>Desktop Games takes a picture of your screen so you can smash it.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "==> Done: $APP"
