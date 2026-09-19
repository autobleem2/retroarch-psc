build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    make clean platform=classic_armv7_a7 || true
    make -j"$JOBS" \
        platform=classic_armv7_a7 \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp melonds_libretro.so /build/output/
}
