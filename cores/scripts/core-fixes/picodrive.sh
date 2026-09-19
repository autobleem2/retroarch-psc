build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    make -f Makefile.libretro clean platform=armv7-neon-hardfloat use_cyclone=0 || true
    make -f Makefile.libretro -j"$JOBS" \
        platform=armv7-neon-hardfloat \
        use_cyclone=0 \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp picodrive_libretro.so /build/output/
}
