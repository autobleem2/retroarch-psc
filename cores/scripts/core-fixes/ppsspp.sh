fetch_core() {
    PPSSPP_VERSION="${PPSSPP_VERSION:-$(core_ref_override)}"
    if [ -n "$PPSSPP_VERSION" ]; then
        CORE_TAG_SOURCE="override"
    elif [ "$CORE_REF_POLICY" = "pinned" ]; then
        PPSSPP_VERSION="$CORE_REF_VALUE"
        CORE_TAG_SOURCE="pinned"
    elif [ "$CORE_REF_POLICY" = "latest-tag" ]; then
        PPSSPP_VERSION="$(latest_version_tag_for_url https://github.com/hrydgard/ppsspp.git)"
        CORE_TAG_SOURCE="latest-tag"
    else
        echo "Error: unsupported PPSSPP policy in $CORE_REFS_FILE: $CORE_REF_POLICY" >&2
        exit 1
    fi
    CORE_TAG_REF_USED="$PPSSPP_VERSION"
    PPSSPP_DIR="/build/libretro-super/libretro-ppsspp"
    rm -rf "$PPSSPP_DIR"
    git clone --depth=1 --branch "$PPSSPP_VERSION" --recurse-submodules --shallow-submodules \
        https://github.com/hrydgard/ppsspp.git "$PPSSPP_DIR"
}

build_core() {
    # Override SYSTEM_PROCESSOR so CMake selects ARM paths instead of host x86.
    PPSSPP_DIR="/build/libretro-super/libretro-ppsspp"
    rm -rf "$PPSSPP_DIR/build"
    mkdir -p "$PPSSPP_DIR/build"
    cmake -S "$PPSSPP_DIR" -B "$PPSSPP_DIR/build" \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR=arm \
        -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc \
        -DCMAKE_CXX_COMPILER=arm-linux-gnueabihf-g++ \
        -DCMAKE_C_FLAGS="$PSC_CFLAGS" \
        -DCMAKE_CXX_FLAGS="$PSC_CFLAGS" \
        -DLIBRETRO=ON \
        -DARM=ON \
        -DUSING_GLES2=ON \
        -DUSING_FBDEV=ON \
        -DUSING_X11_VULKAN=OFF \
        -DUSE_WAYLAND_WSI=OFF \
        -DUSE_VULKAN_DISPLAY_KHR=OFF \
        -DUSE_FFMPEG=OFF \
        -DCMAKE_BUILD_TYPE=Release || true
    cmake --build "$PPSSPP_DIR/build" --target ppsspp_libretro -j"$JOBS" || true
    SO_FILE="$PPSSPP_DIR/build/lib/ppsspp_libretro.so"
    if [ -f "$SO_FILE" ]; then
        cp "$SO_FILE" /build/output/
    fi
}

core_source_dir() {
    echo "$PPSSPP_DIR"
}
