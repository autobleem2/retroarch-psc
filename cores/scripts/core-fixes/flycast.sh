fetch_core() {
    FLYCAST_DIR="/build/libretro-super/libretro-flycast"
    FLYCAST_REF="${FLYCAST_REF:-$(core_ref_override)}"
    if [ -n "$FLYCAST_REF" ]; then
        CORE_TAG_SOURCE="override"
    elif [ "$CORE_REF_POLICY" = "pinned" ]; then
        FLYCAST_REF="$CORE_REF_VALUE"
        CORE_TAG_SOURCE="pinned"
    elif [ "$CORE_REF_POLICY" = "latest-tag" ]; then
        FLYCAST_REF="$(latest_version_tag_for_url https://github.com/flyinghead/flycast.git)"
        CORE_TAG_SOURCE="latest-tag"
    elif [ "$CORE_REF_POLICY" = "branch" ]; then
        CORE_TAG_SOURCE="branch"
    else
        echo "Error: unsupported Flycast policy in $CORE_REFS_FILE: $CORE_REF_POLICY" >&2
        exit 1
    fi

    rm -rf "$FLYCAST_DIR"
    if [ -n "$FLYCAST_REF" ]; then
        CORE_TAG_REF_USED="$FLYCAST_REF"
        echo "Using Flycast ref: $FLYCAST_REF"
        git clone --depth=1 --branch "$FLYCAST_REF" \
            https://github.com/flyinghead/flycast.git "$FLYCAST_DIR"
    else
        CORE_TAG_REF_USED=""
        echo "Using Flycast branch"
        git clone --depth=1 https://github.com/flyinghead/flycast.git "$FLYCAST_DIR"
    fi
    for submodule in core/deps/libchdr core/deps/asio core/deps/tinygettext; do
        if git -C "$FLYCAST_DIR" config --file .gitmodules --get-regexp "path" | grep -Fq "$submodule"; then
            git -C "$FLYCAST_DIR" submodule update --init --depth=1 "$submodule"
        fi
    done
}

build_core() {
    NO_FUTEX_HEADER="$FLYCAST_DIR/build/no-libstdcxx-futex.h"
    mkdir -p "$FLYCAST_DIR/build"
    cat > "$NO_FUTEX_HEADER" <<'EOF'
#include <bits/c++config.h>
#undef _GLIBCXX_HAVE_LINUX_FUTEX
EOF

    cmake -S "$FLYCAST_DIR" -B "$FLYCAST_DIR/build" -G Ninja \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR=arm \
        -DARCHITECTURE=arm \
        -DCMAKE_BUILD_TYPE=Release \
        -DLIBRETRO=ON \
        -DUSE_OPENGL=ON \
        -DUSE_GLES=ON \
        -DUSE_VULKAN=OFF \
        -DUSE_OPENMP=OFF \
        -DUSE_DX9=OFF \
        -DUSE_DX11=OFF \
        -DUSE_HOST_LIBZIP=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc \
        -DCMAKE_CXX_COMPILER=arm-linux-gnueabihf-g++ \
        -DCMAKE_C_FLAGS="$PSC_CFLAGS" \
        -DCMAKE_CXX_FLAGS="$PSC_CFLAGS -include $NO_FUTEX_HEADER" \
        -DCMAKE_SHARED_LINKER_FLAGS="$PSC_LDFLAGS"

    cmake --build "$FLYCAST_DIR/build" --target flycast_libretro --parallel "$JOBS"

    SO_FILE=$(find "$FLYCAST_DIR/build" -name flycast_libretro.so -type f | head -1)
    if [ -f "$SO_FILE" ]; then
        cp "$SO_FILE" /build/output/
    fi
}

core_source_dir() {
    echo "$FLYCAST_DIR"
}
