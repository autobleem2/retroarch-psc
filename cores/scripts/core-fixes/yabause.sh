build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR/yabause/src/libretro"

    make clean platform=armv7-neon-hardfloat || true
    make -j"$JOBS" \
        platform=armv7-neon-hardfloat \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp yabause_libretro.so /build/output/
}
