build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    make clean platform=armv7-neon-hardfloat || true
    make -j"$JOBS" \
        platform=armv7-neon-hardfloat \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++

    cp mednafen_pcfx_libretro.so /build/output/
}
