#!/bin/bash
# Builds DinguxCommander (SDL2) for gkdpixel2 (aarch64) using the rgb30 Docker toolchain.
# Output: files-pak/DinguxCommander

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/.dinguxcommander-src"
OUT_PAK="$SCRIPT_DIR/files-pak"

TOOLCHAIN_PREFIX=/work/MOSS/build.MOSS-RK3566.aarch64/toolchain
SYSROOT="$TOOLCHAIN_PREFIX/aarch64-libreelec-linux-gnueabi/sysroot"
CROSS="$TOOLCHAIN_PREFIX/bin/aarch64-libreelec-linux-gnueabi"

# ─── Clone source ─────────────────────────────────────────────────────────────

if [ ! -d "$SRC_DIR" ]; then
    echo "=== Cloning DinguxCommander ==="
    git clone --depth=1 https://github.com/od-contrib/commander "$SRC_DIR"
fi

# ─── Clean Docker-owned build dir ─────────────────────────────────────────────

if [ -d "$SRC_DIR/build" ]; then
    echo "=== Cleaning build dir (may require sudo) ==="
    sudo rm -rf "$SRC_DIR/build"
fi

# ─── Build in Docker ──────────────────────────────────────────────────────────

echo "=== Building DinguxCommander for aarch64 (SDL2) ==="

docker run --rm \
    -v "$SRC_DIR":/src \
    rgb30-toolchain /bin/bash -c "
set -e
TOOLCHAIN=$TOOLCHAIN_PREFIX
SYSROOT=$SYSROOT
CROSS=${CROSS}

cd /src
mkdir build && cd build

cmake .. \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=\${CROSS}-gcc \
    -DCMAKE_CXX_COMPILER=\${CROSS}-g++ \
    -DCMAKE_SYSROOT=\${SYSROOT} \
    -DCMAKE_FIND_ROOT_PATH=\${SYSROOT} \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DUSE_SDL2=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL2_LIBRARY=\${SYSROOT}/usr/lib/libSDL2-2.0.so.0 \
    -DSDL2_INCLUDE_DIR=\${SYSROOT}/usr/include/SDL2 \
    -DSDL2IMAGE_LIBRARY=\${SYSROOT}/usr/lib/libSDL2_image-2.0.so.0 \
    -DSDL2IMAGE_INCLUDE_DIR=\${SYSROOT}/usr/include/SDL2 \
    -DSDL2TTF_LIBRARY=\${SYSROOT}/usr/lib/libSDL2_ttf-2.0.so.0 \
    -DSDL2TTF_INCLUDE_DIR=\${SYSROOT}/usr/include/SDL2

make -j\$(nproc)
echo 'Build done.'
file commander
"

# ─── Install into Files.pak ───────────────────────────────────────────────────

echo "=== Installing DinguxCommander into Files.pak ==="
# Docker builds as root — use docker to copy out to avoid permission issues
docker run --rm \
    -v "$SRC_DIR":/src \
    -v "$OUT_PAK":/out \
    rgb30-toolchain cp /src/build/commander /out/DinguxCommander
chmod +x "$OUT_PAK/DinguxCommander"
cp -r "$SRC_DIR/res/." "$OUT_PAK/res/"

echo ""
echo "=== Done: $OUT_PAK/DinguxCommander ==="
file "$OUT_PAK/DinguxCommander"
