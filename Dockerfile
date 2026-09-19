# RetroArch + libretro cores for the PlayStation Classic - one Dockerfile, three targets.
#
#   docker build --target retroarch -o out/retroarch .      # the retroarch binary
#   docker build --target cores -t retroarch-psc-cores .    # the core build environment (then
#                                                           # cores/scripts/build-core.sh <core> in it)
#   docker build --target base -t retroarch-psc-base .      # just the toolchain, for experiments
#
# The Makefile wraps these. Merged from AutoBleem-NG's retroarch-psc and libretro-cores-psc
# (their two Dockerfiles shared the toolchain stage word for word); the recipe is theirs.
#
# Stages:
#   ctngbuild  Ubuntu 16.04 + crosstool-ng: GCC 9 / glibc 2.23 / binutils 2.32 / kernel 4.4 headers,
#              arm-linux-gnueabihf hard-float - matches the console's firmware (glibc 2.24, libstdc++
#              6.0.22 = GLIBCXX_3.4.22) so nothing built here needs a newer libc than the console has.
#   base       Ubuntu 18.04 with that toolchain, Ubuntu's armhf -dev packages (SDL2, EGL/GLES, ALSA, udev,
#              freetype, wayland, ...) as the sysroot, the psc-gcc/psc-g++ wrappers, UPX and CMake 3.26.
#   retroarch  RetroArch RETROARCH_VERSION with the four PSC patches, built by retroarch/Makefile.psc.
#   cores      libretro-super at LIBRETRO_SUPER_REF plus cores/scripts, ready to build one core per run.

# ==============================================================================
# Version Configuration
# ==============================================================================
ARG CROSSTOOL_NG_VERSION=1.28.0
ARG UPX_VERSION=5.0.2
ARG RETROARCH_VERSION=v1.22.2

# libretro-super commit (update periodically for new cores/fixes)
# Check latest: git ls-remote https://github.com/libretro/libretro-super.git HEAD
ARG LIBRETRO_SUPER_REF=d52d402682bf60f1cdb11148fd041c0145a8e9c0

# Toolchain versions - matched for PlayStation Classic compatibility
ARG CT_LINUX_VERSION=4_4
ARG CT_BINUTILS_VERSION=2_32
ARG CT_GLIBC_VERSION=2_23
ARG CT_GCC_VERSION=9

# User IDs for crosstool-ng build
ARG CTNG_UID=1000
ARG CTNG_GID=1000

# ==============================================================================
# Stage 1: Build Custom GCC Toolchain with crosstool-ng
# ==============================================================================
FROM ubuntu:16.04 AS ctngbuild

ARG CTNG_UID
ARG CTNG_GID
ARG CROSSTOOL_NG_VERSION
ARG CT_LINUX_VERSION
ARG CT_BINUTILS_VERSION
ARG CT_GLIBC_VERSION
ARG CT_GCC_VERSION

# Create user for crosstool-ng (cannot run as root)
RUN groupadd -g $CTNG_GID ctng && \
    useradd -d /home/ctng -m -g $CTNG_GID -u $CTNG_UID -s /bin/bash ctng

# Install crosstool-ng build dependencies
RUN apt-get update && \
    apt-get install -y \
        gcc g++ gperf bison flex texinfo help2man make libncurses5-dev \
        python3-dev autoconf automake libtool libtool-bin gawk wget bzip2 \
        xz-utils unzip patch libstdc++6 rsync meson ninja-build && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup crosstool-ng directories
RUN mkdir /opt/ctng && chmod 777 /opt/ctng && \
    mkdir /opt/x-tools && chmod 777 /opt/x-tools && \
    echo 'export PATH=/opt/ctng/bin:$PATH' >> /etc/profile

USER ctng

# Download and build crosstool-ng
RUN wget -O /tmp/crosstool.bz2 http://crosstool-ng.org/download/crosstool-ng/crosstool-ng-${CROSSTOOL_NG_VERSION}.tar.bz2 && \
    cd /home/ctng && tar xvf /tmp/crosstool.bz2 && \
    rm /tmp/crosstool.bz2 && \
    cd /home/ctng/crosstool-ng-${CROSSTOOL_NG_VERSION} && \
    ./configure --prefix=/opt/ctng && \
    make && \
    make install

# Configure and build ARM toolchain for PlayStation Classic
# - ARMv8-A compatible (hard float, NEON)
# - Matches original RetroArch binary's toolchain
RUN echo 'CT_CONFIG_VERSION="4"' >> /tmp/defconfig && \
    echo 'CT_PREFIX_DIR="/opt/x-tools/${CT_HOST:+HOST-${CT_HOST}/}${CT_TARGET}"' >> /tmp/defconfig && \
    echo 'CT_ARCH_ARM=y' >> /tmp/defconfig && \
    echo 'CT_OMIT_TARGET_VENDOR=y' >> /tmp/defconfig && \
    echo 'CT_ARCH_FLOAT_HW=y' >> /tmp/defconfig && \
    echo 'CT_KERNEL_LINUX=y' >> /tmp/defconfig && \
    echo 'CT_LINUX_V_'${CT_LINUX_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_BINUTILS_V_'${CT_BINUTILS_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_GLIBC_V_'${CT_GLIBC_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_GCC_V_'${CT_GCC_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_CC_LANG_CXX=y' >> /tmp/defconfig && \
    echo 'CT_CC_GCC_LIBGOMP=y' >> /tmp/defconfig && \
    cd /tmp && /opt/ctng/bin/ct-ng defconfig && \
    echo 'CT_ZLIB_MIRRORS="http://downloads.sourceforge.net/project/libpng/zlib/${CT_ZLIB_VERSION} https://www.zlib.net/ https://www.zlib.net/fossils"' >> /tmp/.config && \
    cd /tmp && /opt/ctng/bin/ct-ng build

# ==============================================================================
# Stage 2: the build environment both RetroArch and the cores use
# ==============================================================================
FROM ubuntu:18.04 AS base

LABEL maintainer="AutoBleem"
LABEL description="Build environment for RetroArch and libretro cores - PlayStation Classic (crosstool-ng)"

ARG UPX_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# Build tools: the union of what the RetroArch and the cores images installed.
RUN apt-get update && apt-get install -y \
    git \
    make \
    ninja-build \
    autoconf \
    libtool-bin \
    gettext \
    bc \
    pkg-config \
    pkg-config-arm-linux-gnueabihf \
    wget \
    curl \
    xz-utils \
    zip \
    patchelf \
    bsdmainutils \
    mesa-common-dev \
    libgl1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

# Download and install UPX for binary compression
RUN wget -q https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-amd64_linux.tar.xz && \
    tar -xf upx-${UPX_VERSION}-amd64_linux.tar.xz && \
    cp upx-${UPX_VERSION}-amd64_linux/upx /usr/local/bin/ && \
    chmod +x /usr/local/bin/upx && \
    rm -rf upx-${UPX_VERSION}-amd64_linux upx-${UPX_VERSION}-amd64_linux.tar.xz

# Install a newer CMake than Ubuntu 18.04's 3.10.2 - required by dirksimple
# (>=3.12) and other modern CMAKE recipes. Use the official Kitware binary.
RUN wget -q https://github.com/Kitware/CMake/releases/download/v3.26.6/cmake-3.26.6-linux-x86_64.tar.gz -O /tmp/cmake.tgz && \
    tar -xzf /tmp/cmake.tgz --strip-components=1 -C /usr/local && \
    rm /tmp/cmake.tgz && \
    cmake --version

# ==============================================================================
# Install ARM Libraries - Ubuntu bionic's armhf packages are the sysroot the
# cross compiler links against (the console's firmware ships the same ABI set).
# SDL2: the armhf *runtime* (linked through the libSDL2.so symlink made below) and the amd64 -dev package
# for the headers (copied to the armhf include dir below; its x86 SDL_config.h is why immintrin.h is
# faked) - libsdl2-dev:armhf and libsdl2-dev cannot be installed together, both own SDL_config.h.
# ==============================================================================
RUN dpkg --add-architecture armhf && \
    mv /etc/apt/sources.list /etc/apt/sources.list.bak && \
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu bionic main universe" > /etc/apt/sources.list && \
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu bionic-updates main universe" >> /etc/apt/sources.list && \
    echo "deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports bionic main universe" >> /etc/apt/sources.list && \
    echo "deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports bionic-updates main universe" >> /etc/apt/sources.list && \
    apt-get update && apt-get install -y \
    libasound2-dev:armhf \
    libudev-dev:armhf \
    libusb-1.0-0-dev:armhf \
    libsdl2-2.0-0:armhf \
    libsdl2-dev \
    libgles2-mesa-dev:armhf \
    libegl1-mesa-dev:armhf \
    libdrm-dev:armhf \
    libgbm-dev:armhf \
    libfreetype6-dev:armhf \
    libfreetype6-dev \
    libwayland-dev:armhf \
    libxkbcommon-dev:armhf \
    libexpat1-dev:armhf \
    zlib1g-dev:armhf \
    libpng-dev:armhf \
    libgl1-mesa-dev:armhf \
    && (apt-get remove -y libpulse-dev:armhf || true) \
    && rm -rf /var/lib/apt/lists/*

# Normalize SDL header locations for cores that hardcode <SDL2/SDL.h> or <SDL.h>.
RUN set -eux; \
    sdl_dir="$(find /usr/include -path '*/SDL2' -type d | head -n1)"; \
    test -n "$sdl_dir"; \
    mkdir -p /usr/include/arm-linux-gnueabihf/SDL2; \
    cp -a "$sdl_dir"/. /usr/include/arm-linux-gnueabihf/SDL2/

# ==============================================================================
# Copy Custom Toolchain from Stage 1
# ==============================================================================
RUN mkdir -p /opt/x-tools
COPY --from=ctngbuild /opt/x-tools/arm-linux-gnueabihf /opt/x-tools/arm-linux-gnueabihf

# ==============================================================================
# Environment Setup for Cross-Compilation
# ==============================================================================
ENV PATH="/opt/x-tools/arm-linux-gnueabihf/bin:${PATH}"
ENV CC=arm-linux-gnueabihf-gcc
ENV CXX=arm-linux-gnueabihf-g++
ENV AR=arm-linux-gnueabihf-ar
ENV PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig
ENV PKG_CONFIG_LIBDIR=/usr/lib/arm-linux-gnueabihf/pkgconfig
ENV PKG_CONFIG=/usr/bin/arm-linux-gnueabihf-pkg-config
ENV LDFLAGS="-L/usr/lib/arm-linux-gnueabihf -Wl,-rpath-link,/usr/lib/arm-linux-gnueabihf"
ENV LIBRARY_PATH=/usr/lib/arm-linux-gnueabihf

# Create dummy immintrin.h for SDL2 (SDL 2.0.8 has x86 intrinsics includes without ARM guards)
RUN mkdir -p /opt/arm-compat-headers && \
    echo '/* Dummy immintrin.h for ARM cross-compilation */' > /opt/arm-compat-headers/immintrin.h

# Create wrapper scripts that point crosstool-ng compiler to Ubuntu's ARM libraries
# Note: SDL2 headers go in /usr/include/SDL2/ (arch-independent) not armhf-specific path
RUN echo '#!/bin/bash' > /usr/bin/psc-gcc && \
    echo 'exec /opt/x-tools/arm-linux-gnueabihf/bin/arm-linux-gnueabihf-gcc -I/opt/arm-compat-headers -I/usr/include/SDL2 -idirafter /usr/include -idirafter /usr/include/arm-linux-gnueabihf -L/opt/x-tools/arm-linux-gnueabihf/arm-linux-gnueabihf/sysroot/usr/lib -L/usr/lib/arm-linux-gnueabihf "$@"' >> /usr/bin/psc-gcc && \
    chmod +x /usr/bin/psc-gcc && \
    echo '#!/bin/bash' > /usr/bin/psc-g++ && \
    echo 'exec /opt/x-tools/arm-linux-gnueabihf/bin/arm-linux-gnueabihf-g++ -I/opt/arm-compat-headers -I/usr/include/SDL2 -idirafter /usr/include -idirafter /usr/include/arm-linux-gnueabihf -L/opt/x-tools/arm-linux-gnueabihf/arm-linux-gnueabihf/sysroot/usr/lib -L/usr/lib/arm-linux-gnueabihf "$@"' >> /usr/bin/psc-g++ && \
    chmod +x /usr/bin/psc-g++

# Fix ARM library symlinks and pkg-config files
# Dev packages only install versioned .so files, not the unversioned symlinks needed for linking
RUN ln -sf libSDL2-2.0.so.0 /usr/lib/arm-linux-gnueabihf/libSDL2.so && \
    ln -sf libEGL.so.1 /usr/lib/arm-linux-gnueabihf/libEGL.so && \
    ln -sf libGLESv2.so.2 /usr/lib/arm-linux-gnueabihf/libGLESv2.so && \
    ln -sf libdrm.so.2 /usr/lib/arm-linux-gnueabihf/libdrm.so && \
    ln -sf libgbm.so.1 /usr/lib/arm-linux-gnueabihf/libgbm.so && \
    # SDL2 pkg-config (armhf headers in arch-specific include dir)
    echo 'prefix=/usr' > /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'exec_prefix=${prefix}' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'libdir=${exec_prefix}/lib/arm-linux-gnueabihf' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'includedir=${prefix}/include/arm-linux-gnueabihf' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'Name: sdl2' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'Description: Simple DirectMedia Layer' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'Version: 2.0.8' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'Libs: -L${libdir} -lSDL2' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    echo 'Cflags: -I${includedir}/SDL2 -D_REENTRANT' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/sdl2.pc && \
    # EGL pkg-config
    echo 'prefix=/usr' > /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    echo 'libdir=${prefix}/lib/arm-linux-gnueabihf' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    echo 'includedir=${prefix}/include' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    echo 'Name: egl' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    echo 'Description: EGL library' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    echo 'Version: 1.4' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    echo 'Libs: -L${libdir} -lEGL' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    echo 'Cflags: -I${includedir}' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/egl.pc && \
    # GLESv2 pkg-config
    echo 'prefix=/usr' > /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc && \
    echo 'libdir=${prefix}/lib/arm-linux-gnueabihf' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc && \
    echo 'includedir=${prefix}/include' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc && \
    echo 'Name: glesv2' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc && \
    echo 'Description: OpenGL ES 2.0 library' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc && \
    echo 'Version: 2.0' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc && \
    echo 'Libs: -L${libdir} -lGLESv2' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc && \
    echo 'Cflags: -I${includedir}' >> /usr/lib/arm-linux-gnueabihf/pkgconfig/glesv2.pc

WORKDIR /build
CMD ["/bin/bash"]

# ==============================================================================
# Stage 3a: RetroArch
# ==============================================================================
FROM base AS retroarch

ARG RETROARCH_VERSION
ARG PSC_BUILD_NUM=1
ENV PSC_BUILD_NUM=${PSC_BUILD_NUM}

# The RetroArch image linked with the toolchain's own sysroot ahead of Ubuntu's libraries.
ENV LDFLAGS="-L/opt/x-tools/arm-linux-gnueabihf/arm-linux-gnueabihf/sysroot/usr/lib -Wl,-rpath-link,/opt/x-tools/arm-linux-gnueabihf/arm-linux-gnueabihf/sysroot/lib -L/usr/lib/arm-linux-gnueabihf -Wl,-rpath-link,/usr/lib/arm-linux-gnueabihf"
ENV LIBRARY_PATH=/opt/x-tools/arm-linux-gnueabihf/arm-linux-gnueabihf/sysroot/usr/lib:/opt/x-tools/arm-linux-gnueabihf/arm-linux-gnueabihf/sysroot/lib:/usr/lib/arm-linux-gnueabihf

# Clone RetroArch with retry
RUN git config --global http.postBuffer 524288000 && \
    git config --global http.lowSpeedLimit 1000 && \
    git config --global http.lowSpeedTime 300 && \
    (git clone --depth=1 --branch ${RETROARCH_VERSION} https://github.com/libretro/RetroArch.git || \
     (sleep 10 && git clone --depth=1 --branch ${RETROARCH_VERSION} https://github.com/libretro/RetroArch.git) || \
     (sleep 30 && git clone --depth=1 --branch ${RETROARCH_VERSION} https://github.com/libretro/RetroArch.git))

WORKDIR /build/RetroArch
RUN git submodule update --init --recursive --depth 1

# Restore wl_shell fallback for PSC's Weston 1.11 (only supports wl_shell,
# not xdg_shell). Upstream removed wl_shell in 8345f08 (RA 1.7.9).
COPY retroarch/patches/wl_shell_fallback.patch /build/RetroArch/patches/wl_shell_fallback.patch
RUN git apply /build/RetroArch/patches/wl_shell_fallback.patch

# Skip the OES_standard_derivatives extension request when the runtime
# promotes the XMB ribbon shader to "#version 300 es" - PowerVR Rogue
# rejects the now-meaningless extension and refuses to compile the shader.
COPY retroarch/patches/xmb_ribbon_drop_oes_derivatives_ext.patch /build/RetroArch/patches/xmb_ribbon_drop_oes_derivatives_ext.patch
RUN git apply /build/RetroArch/patches/xmb_ribbon_drop_oes_derivatives_ext.patch

# Hide shader pipeline options that are too slow for PSC (PowerVR Rogue
# GE8300): only "Off" and "Ribbon Simplified" are usable; cap the menu
# range at XMB_SHADER_PIPELINE_SIMPLE_RIBBON.
COPY retroarch/patches/xmb_shader_pipeline_psc_limit.patch /build/RetroArch/patches/xmb_shader_pipeline_psc_limit.patch
RUN git apply /build/RetroArch/patches/xmb_shader_pipeline_psc_limit.patch

# Force S16_LE for ALSA: the PSC's MT8167 driver falsely reports FLOAT as
# supported via test_format, then rejects it with EINVAL in snd_pcm_hw_params.
# RA has no retry path, so audio init fails entirely without this patch.
COPY retroarch/patches/alsa_force_s16_psc_mtk.patch /build/RetroArch/patches/alsa_force_s16_psc_mtk.patch
RUN git apply /build/RetroArch/patches/alsa_force_s16_psc_mtk.patch

# Copy PSC-specific Makefile
COPY retroarch/Makefile.psc /build/RetroArch/Makefile.psc

# Build using PSC makefile with crosstool-ng compiler
RUN CC=psc-gcc CXX=psc-g++ make -f Makefile.psc -j$(nproc)

# Show binary info
RUN ls -lh retroarch && \
    arm-linux-gnueabihf-readelf -A retroarch | head -20

# The output: the stripped binary plus what it was built from
RUN mkdir -p /build/output && cp retroarch /build/output/ && \
    printf 'retroarch_version=%s\npsc_build=%s\nbuild_date=%s\ntoolchain=crosstool-ng-gcc9-glibc2.23\n' \
        "${RETROARCH_VERSION}" "${PSC_BUILD_NUM}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /build/output/VERSION

# `docker build --target retroarch -o <dir>` exports this stage's filesystem
FROM scratch AS retroarch-out
COPY --from=retroarch /build/output/ /

# ==============================================================================
# Stage 3b: the libretro core build environment
# ==============================================================================
FROM base AS cores

ARG LIBRETRO_SUPER_REF

# Download zlib headers and copy GL/GLES/EGL/KHR headers (avoid glibc conflicts)
RUN mkdir -p /opt/zlib-headers/GL /opt/zlib-headers/GLES2 /opt/zlib-headers/GLES3 \
             /opt/zlib-headers/EGL /opt/zlib-headers/KHR && \
    wget -q https://zlib.net/fossils/zlib-1.2.11.tar.gz -O /tmp/zlib.tar.gz && \
    tar -xzf /tmp/zlib.tar.gz -C /tmp && \
    cp /tmp/zlib-1.2.11/zlib.h /tmp/zlib-1.2.11/zconf.h /opt/zlib-headers/ && \
    rm -rf /tmp/zlib* && \
    cp /usr/include/png*.h /opt/zlib-headers/ 2>/dev/null || true && \
    cp /usr/include/GL/*.h /opt/zlib-headers/GL/ 2>/dev/null || true && \
    cp /usr/include/GLES2/*.h /opt/zlib-headers/GLES2/ 2>/dev/null || true && \
    cp /usr/include/GLES3/*.h /opt/zlib-headers/GLES3/ 2>/dev/null || true && \
    cp /usr/include/EGL/*.h /opt/zlib-headers/EGL/ 2>/dev/null || true && \
    cp /usr/include/KHR/*.h /opt/zlib-headers/KHR/ 2>/dev/null || true

# Clone libretro-super for core fetching/building (pinned version)
RUN git clone https://github.com/libretro/libretro-super.git && \
    cd libretro-super && \
    git checkout ${LIBRETRO_SUPER_REF}

# PSC-optimized compiler flags (Cortex-A35)
# Note: -isystem makes zlib-headers a "system include" searched AFTER local includes
# This allows cores with bundled zlib to use their own headers first
ENV PSC_CFLAGS="-march=armv8-a -mtune=cortex-a35 -mfpu=neon-fp-armv8 -mfloat-abi=hard -O3 -funroll-loops -ftree-vectorize -ffunction-sections -fdata-sections -isystem /opt/zlib-headers"
ENV PSC_LDFLAGS="-Wl,--gc-sections -Wl,--as-needed -L/usr/lib/arm-linux-gnueabihf -lz"

# libretro-super platform setting
# NOTE: "armv7" selects 32-bit ARM build rules (PSC has 32-bit userspace)
# Actual ARMv8 instruction set comes from PSC_CFLAGS (-march=armv8-a)
ENV platform="linux-armv7-neon-hardfloat"
ENV JOBS="4"

# Create output directory
RUN mkdir -p /build/output /build/metadata

# Copy build scripts
COPY cores/scripts/ /build/scripts/
RUN chmod +x /build/scripts/build-core.sh /build/scripts/audit-cores.sh /build/scripts/sync-core-info.sh && \
    ln -sf /build/scripts/build-core.sh /build/build-core.sh

# Default: interactive shell
CMD ["/bin/bash"]
