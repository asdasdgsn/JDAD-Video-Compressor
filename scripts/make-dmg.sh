#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
[ -d "$OUT/JDAD视频压缩工具.app" ] || { echo "Run package.sh first" >&2; exit 1; }
SOURCES="$PWD/.build/MediaEngine-Sources"
mkdir -p "$SOURCES"
cp .engine/sources/*.tar.* .engine/sources/SHA256SUMS "$SOURCES/"
cp scripts/build-engine.sh "$SOURCES/build-engine.sh"
cp .engine/sources/ffmpeg-8.0.3/ffbuild/config.mak "$SOURCES/FFmpeg-config.mak"
cp .engine/sources/ffmpeg-8.0.3/config.h "$SOURCES/FFmpeg-config.h"
cp .engine/sources/libvpx-1.15.2/config.mk "$SOURCES/libvpx-config.mk"
cp .engine/sources/lame-3.100/config.status "$SOURCES/LAME-config.status"
cp LICENSES/* .engine/install/*LICENSE.txt .engine/install/*PATENTS.txt "$SOURCES/"
cat > "$SOURCES/REBUILD.txt" <<'TEXT'
Exact corresponding source archives for FrameShift's FFmpeg executables.
Extract archives or run the accompanying build-engine.sh in a new project directory with a scripts subdirectory.
The script expects scripts/build-engine.sh and creates .engine/sources and .engine/install. To reuse these exact downloads, place the three source tarballs in .engine/sources before running. Verify their recorded SHA256SUMS first.
Use an Apple Silicon Mac with Xcode Command Line Tools. Builds use MACOSX_DEPLOYMENT_TARGET=14.0. The full FrameShift source archive also contains this script and packaging instructions.
FFmpeg and LAME static libraries are linked into standalone command-line executables, not into the Swift application. You may rebuild or replace these executables and re-sign the modified application locally.
TEXT
tar -czf "$OUT/MediaEngine-Sources.tar.gz" -C .build MediaEngine-Sources
STAGE="$PWD/.build/JDAD-DMG-stage"
mkdir -p "$STAGE"
# This stage contains generated artifacts only.
if [ -d "$STAGE/JDAD视频压缩工具.app" ]; then rm -rf "$STAGE/JDAD视频压缩工具.app"; fi
ditto "$OUT/JDAD视频压缩工具.app" "$STAGE/JDAD视频压缩工具.app"
[ -L "$STAGE/Applications" ] || ln -s /Applications "$STAGE/Applications"
cp "$OUT/MediaEngine-Sources.tar.gz" "$STAGE/MediaEngine-Sources.tar.gz"
cp README.md "$STAGE/使用说明.md"
hdiutil create -ov -volname "JDAD视频压缩工具" -srcfolder "$STAGE" -format UDZO "$OUT/JDAD视频压缩工具-arm64.dmg"
