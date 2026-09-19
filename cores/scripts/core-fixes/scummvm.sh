build_core() {
    # LITE=1 uses lite_engines.list and keeps the build focused on classic
    # adventure engines instead of the full modern ScummVM engine set.
    SCUMMVM_DIR="/build/libretro-super/libretro-scummvm"
    make -C "$SCUMMVM_DIR/backends/platform/libretro" \
        platform=unix \
        SCUMMVM_PATH="$SCUMMVM_DIR/" \
        LITE=1 \
        -j"$JOBS" || true
    SO_FILE="$SCUMMVM_DIR/backends/platform/libretro/scummvm_libretro.so"
    if [ -f "$SO_FILE" ]; then
        cp "$SO_FILE" /build/output/
    fi
}

core_source_dir() {
    echo "$SCUMMVM_DIR"
}
