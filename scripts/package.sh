#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="$OUT/FrameShift.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Engine" "$APP/Contents/Resources/LICENSES"
cp "$BIN/FrameShift" "$APP/Contents/MacOS/FrameShift"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for tool in ffmpeg ffprobe; do
  cp ".engine/install/bin/$tool" "$APP/Contents/Resources/Engine/$tool"
  chmod +x "$APP/Contents/Resources/Engine/$tool"
  codesign --force --sign - "$APP/Contents/Resources/Engine/$tool"
done
cp .engine/install/*LICENSE.txt .engine/install/*PATENTS.txt "$APP/Contents/Resources/LICENSES/"
cp LICENSES/* "$APP/Contents/Resources/LICENSES/"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'APP=%s\n' "$APP"
