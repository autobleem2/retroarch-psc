#!/usr/bin/env bash
# Build RetroArch for the PlayStation Classic with AutoBleem's own console toolchain - the one in the
# autobleem-build Docker image (AutoBleem2/docker: Debian Stretch's gcc-6 with the console's glibc 2.24
# sysroot under /opt/psc, and SDL2 2.0.12 built for Wayland/GLES/ALSA). The same compiler and sysroot
# pcsx-ab and the launcher are built with, so nothing new to keep in step; the crosstool-ng route in the
# Dockerfile (AutoBleem-NG's GCC 9 / glibc 2.23) is the alternative when this image is not around.
#
#   docker run --rm -u root -v "$PWD:$PWD" -w "$PWD" autobleem-build retroarch/build.sh    (make retroarch)
#
# Runs as root on purpose: Stretch's freetype (the one thing RetroArch wants that the image's sysroot
# lacks - the console firmware has libfreetype.so.6) is unpacked into the sysroot for this container's
# life, and the output is chowned back to OUT_UID:OUT_GID. Incremental: the RetroArch checkout stays in
# work/RetroArch (the patches are applied once, on a fresh clone).
#
# Knobs: RETROARCH_VERSION (tag to build; default from the Dockerfile's ARG), PSC_BUILD_NUM (the build
# number in --version), JOBS, PSC_TOOLCHAIN (/opt/psc), OUT_DIR (dist/retroarch), OUT_UID/OUT_GID.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

PSC_TOOLCHAIN="${PSC_TOOLCHAIN:-/opt/psc}"
SYSROOT="$PSC_TOOLCHAIN/sysroot"
CC_="$PSC_TOOLCHAIN/bin/armv8-sony-linux-gnueabihf-gcc"
CXX_="$PSC_TOOLCHAIN/bin/armv8-sony-linux-gnueabihf-g++"
STRIP_="$PSC_TOOLCHAIN/bin/armv8-sony-linux-gnueabihf-strip"
READELF_="$PSC_TOOLCHAIN/bin/armv8-sony-linux-gnueabihf-readelf"
RETROARCH_VERSION="${RETROARCH_VERSION:-$(grep -oP '^ARG RETROARCH_VERSION=\K\S+' Dockerfile)}"
PSC_BUILD_NUM="${PSC_BUILD_NUM:-1}"
JOBS="${JOBS:-$(nproc)}"
OUT_DIR="${OUT_DIR:-dist/retroarch}"
WORK="$ROOT/work"
SRC="$WORK/RetroArch"
STRETCH="http://archive.debian.org/debian/pool/main"

for t in "$CC_" "$CXX_" "$STRIP_"; do
    [ -x "$t" ] || { echo "error: $t not found - run this inside the autobleem-build image" >&2; exit 1; }
done

# --- freetype into the sysroot (Stretch's own package, the version the console's libfreetype.so.6 is) ---
if [ ! -f "$SYSROOT/usr/include/freetype2/ft2build.h" ]; then
    echo "=== freetype: Stretch's libfreetype6-dev into the sysroot ==="
    [ "$(id -u)" = 0 ] || { echo "error: needs root to unpack freetype into $SYSROOT (docker run -u root)" >&2; exit 1; }
    mkdir -p "$WORK/debs" && cd "$WORK/debs"
    for deb in f/freetype/libfreetype6_2.6.3-3.2+deb9u1_armhf.deb f/freetype/libfreetype6-dev_2.6.3-3.2+deb9u1_armhf.deb; do
        [ -f "$(basename "$deb")" ] || wget -q "$STRETCH/$deb"
        dpkg-deb -x "$(basename "$deb")" "$SYSROOT"
    done
    cd "$ROOT"
    # the dev package's libfreetype.so is an absolute symlink into /usr/lib/... - make it relative
    ln -sfn libfreetype.so.6 "$SYSROOT/usr/lib/arm-linux-gnueabihf/libfreetype.so"
    # freetype-config is a host script; RetroArch's configure asks pkg-config, which is what we set up
fi

# pkg-config answers from the sysroot only, every path prefixed with it (that is what makes the .pc
# files' /usr/... right for a cross build). sdl2.pc: the image's SDL2 lives in /opt/psc/sdl2, outside the
# sysroot, but the sysroot links usr/include/SDL2 and usr/lib/libSDL2* to it - so a .pc with prefix=/usr
# describes it correctly once the sysroot prefix is applied.
PC_DIR="$WORK/pkgconfig"
mkdir -p "$PC_DIR"
cat > "$PC_DIR/sdl2.pc" <<'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: sdl2
Description: Simple DirectMedia Layer (the autobleem-build image's 2.0.12)
Version: 2.0.12
Libs: -L${libdir} -lSDL2
Cflags: -I${includedir}/SDL2 -D_REENTRANT
EOF
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/arm-linux-gnueabihf/pkgconfig:$SYSROOT/usr/share/pkgconfig:$SYSROOT/usr/lib/pkgconfig"
export PKG_CONFIG_PATH="$PC_DIR"
# sdl2.pc is outside the sysroot - pkg-config prefixes its paths all the same (SYSROOT_DIR applies to
# every -I/-L), which is what we want here
for lib in alsa libudev wayland-client wayland-egl egl glesv2 freetype2 zlib sdl2; do
    pkg-config --exists "$lib" || { echo "error: pkg-config cannot find $lib in the sysroot" >&2; exit 1; }
done
echo "=== sysroot: $(pkg-config --modversion egl | head -1) EGL, GLESv2 $(pkg-config --modversion glesv2), freetype $(pkg-config --modversion freetype2), SDL2 $(pkg-config --modversion sdl2) ==="

# --- the source ---
if [ ! -d "$SRC/.git" ]; then
    echo "=== cloning RetroArch $RETROARCH_VERSION ==="
    mkdir -p "$WORK"
    git clone --depth=1 --branch "$RETROARCH_VERSION" https://github.com/libretro/RetroArch.git "$SRC"
    git -C "$SRC" submodule update --init --recursive --depth 1
    for p in wl_shell_fallback xmb_ribbon_drop_oes_derivatives_ext xmb_shader_pipeline_psc_limit alsa_force_s16_psc_mtk; do
        echo "=== patch: $p ==="
        git -C "$SRC" apply "$ROOT/retroarch/patches/$p.patch"
    done
    echo "$RETROARCH_VERSION" > "$SRC/.psc-version"
elif [ "$(cat "$SRC/.psc-version" 2>/dev/null)" != "$RETROARCH_VERSION" ]; then
    echo "error: $SRC is $(cat "$SRC/.psc-version" 2>/dev/null || echo '?'), not $RETROARCH_VERSION - remove work/RetroArch" >&2
    exit 1
fi

# --- configure + build: retroarch/Makefile.psc's flags, our compiler. Read that file's header before
# touching any of these (neon-vfpv4 not neon-fp-armv8, NEON_CFLAGS, HAVE_C_A7A7, ...). ---
cd "$SRC"
CPU="-march=armv8-a -mtune=cortex-a35 -mfpu=neon-vfpv4 -mfloat-abi=hard"
OPT="-O3 -fno-pie -fomit-frame-pointer -ffunction-sections -fdata-sections -funroll-loops -ftree-vectorize \
-fno-math-errno -fno-trapping-math -fno-signed-zeros -fprefetch-loop-arrays"
export CC="$CC_" CXX="$CXX_"
export CFLAGS="$CPU $OPT"
export CXXFLAGS="$CPU $OPT"
export ASFLAGS="$CPU"
export LDFLAGS="-no-pie -Wl,--gc-sections -Wl,--as-needed -Wl,--allow-shlib-undefined -static-libstdc++ -static-libgcc"

if [ ! -f config.mk ] || [ "${RECONFIGURE:-}" = 1 ]; then
    echo "=== configure ==="
    ./configure \
        --host=arm-linux-gnueabihf \
        --disable-pulse \
        --enable-wayland \
        --disable-x11 \
        --disable-opengl \
        --disable-opengl1 \
        --disable-opengl_core \
        --enable-opengles \
        --enable-egl \
        --enable-freetype \
        --enable-udev \
        --enable-alsa \
        --enable-neon \
        --enable-sdl2 \
        --disable-discord
    grep -E '^HAVE_(WAYLAND|EGL|OPENGLES|FREETYPE|UDEV|ALSA|NEON|SDL2|OPENGL|X11|PULSE) ' config.mk || true
fi

echo "=== make (JOBS=$JOBS) ==="
make HAVE_CLASSIC=1 \
    GIT_VERSION="autobleem-$PSC_BUILD_NUM" \
    NEON_CFLAGS="-mfpu=neon-vfpv4" \
    NEON_ASFLAGS="-mfpu=neon-vfpv4" \
    -j"$JOBS"
"$STRIP_" -v retroarch

# --- the output ---
cd "$ROOT"
mkdir -p "$OUT_DIR"
cp "$SRC/retroarch" "$OUT_DIR/retroarch"
printf 'retroarch_version=%s\npsc_build=%s\nbuild_date=%s\ntoolchain=autobleem-build-gcc6-glibc2.24\n' \
    "$RETROARCH_VERSION" "$PSC_BUILD_NUM" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT_DIR/VERSION"
if [ -n "${OUT_UID:-}" ]; then chown -R "$OUT_UID:${OUT_GID:-$OUT_UID}" "$OUT_DIR" "$WORK"; fi

echo "=== $OUT_DIR/retroarch ==="
ls -l "$OUT_DIR/retroarch"
if [ -x "$READELF_" ]; then
    "$READELF_" -A "$OUT_DIR/retroarch" | grep -E 'Tag_(CPU_arch|FP_arch|Advanced_SIMD|ABI_VFP)' || true
    echo "needs: $("$READELF_" -V "$OUT_DIR/retroarch" | grep -oE 'GLIBC(XX)?_[0-9.]+' | sort -uV | tail -3 | tr '\n' ' ')"
    echo "libraries: $("$READELF_" -d "$OUT_DIR/retroarch" | grep -c NEEDED) - $("$READELF_" -d "$OUT_DIR/retroarch" | grep -oE '\[[^]]+\]' | tr -d '[]' | tr '\n' ' ')"
    "$READELF_" -d "$OUT_DIR/retroarch" | grep -qE 'RPATH|RUNPATH' && echo "WARNING: RPATH/RUNPATH set" || true
fi
