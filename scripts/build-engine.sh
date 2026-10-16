#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=14.0
cd "$(dirname "$0")/.."
ROOT="$PWD/.engine"
mkdir -p "$ROOT/sources" "$ROOT/install"
cd "$ROOT/sources"
[ -f ffmpeg-8.0.3.tar.xz ] || curl -fL --retry 3 https://ffmpeg.org/releases/ffmpeg-8.0.3.tar.xz -o ffmpeg-8.0.3.tar.xz
[ -f libvpx-1.15.2.tar.gz ] || curl -fL --retry 3 https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.2.tar.gz -o libvpx-1.15.2.tar.gz
[ -f lame-3.100.tar.gz ] || curl -fL --retry 3 https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz -o lame-3.100.tar.gz
shasum -a 256 *.tar.* > SHA256SUMS
[ -d ffmpeg-8.0.3 ] || tar xf ffmpeg-8.0.3.tar.xz
[ -d libvpx-1.15.2 ] || tar xf libvpx-1.15.2.tar.gz
cd libvpx-1.15.2
./configure --prefix="$ROOT/install" --target=arm64-darwin20-gcc --disable-examples --disable-tools --disable-docs --disable-unit-tests --disable-shared --enable-static --enable-vp9-highbitdepth
make -j6
make install
cd "$ROOT/sources"
[ -d lame-3.100 ] || tar xf lame-3.100.tar.gz
cd lame-3.100
./configure --prefix="$ROOT/install" --disable-shared --enable-static --disable-frontend --disable-gtktest
make -j6
make install
# FFmpeg only needs libvpx pkg-config flags; this wrapper is local to the build.
cat > "$ROOT/vpx-pkg-config" <<WRAPPER
#!/bin/sh
case "\$*" in
*--modversion*) echo 1.15.2;;
*--cflags*) echo -I$ROOT/install/include;;
*--libs*) echo -L$ROOT/install/lib -lvpx -lm -lpthread;;
*--exists*|*--atleast-version*) exit 0;;
*) exit 0;;
esac
WRAPPER
chmod +x "$ROOT/vpx-pkg-config"
cd "$ROOT/sources/ffmpeg-8.0.3"
./configure --prefix="$ROOT/install" --arch=arm64 --target-os=darwin --cc=clang --disable-autodetect --disable-gpl --disable-nonfree --disable-shared --enable-static --disable-doc --disable-debug --disable-ffplay --disable-network --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-libvpx --enable-libmp3lame --pkg-config="$ROOT/vpx-pkg-config" --extra-cflags="-mmacosx-version-min=14.0 -I$ROOT/install/include" --extra-ldflags="-mmacosx-version-min=14.0 -L$ROOT/install/lib"
make -j6
make install
cp COPYING.LGPLv2.1 "$ROOT/install/FFmpeg-LICENSE.txt"
cp "$ROOT/sources/libvpx-1.15.2/LICENSE" "$ROOT/install/libvpx-LICENSE.txt"
cp "$ROOT/sources/libvpx-1.15.2/PATENTS" "$ROOT/install/libvpx-PATENTS.txt"
cp "$ROOT/sources/lame-3.100/COPYING" "$ROOT/install/LAME-LICENSE.txt"
"$ROOT/install/bin/ffmpeg" -version
