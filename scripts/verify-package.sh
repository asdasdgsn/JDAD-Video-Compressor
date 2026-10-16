#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/dist}"
OUT="$(cd "$OUT" && pwd)"
APP="$OUT/FrameShift.app"
codesign --verify --deep --strict "$APP"
for tool in ffmpeg ffprobe; do
  "$APP/Contents/Resources/Engine/$tool" -version >/dev/null
  if otool -L "$APP/Contents/Resources/Engine/$tool" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)' ; then echo "Non-system engine dependency" >&2; exit 1; fi
done
"$APP/Contents/Resources/Engine/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -E ' png ' >/dev/null
hdiutil verify "$OUT/FrameShift-arm64.dmg"
MOUNT="$(mktemp -d /tmp/FrameShift-mount.XXXXXX)"
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$OUT/FrameShift-arm64.dmg" >/dev/null
test -x "$MOUNT/FrameShift.app/Contents/MacOS/FrameShift"
test "$(readlink "$MOUNT/Applications")" = /Applications
test -f "$MOUNT/MediaEngine-Sources.tar.gz"
codesign --verify --deep --strict "$MOUNT/FrameShift.app"
printf 'Package verification passed.\n'
