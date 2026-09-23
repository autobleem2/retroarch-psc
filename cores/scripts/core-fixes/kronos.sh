build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR/yabause/src/libretro"

    export CFLAGS="$CFLAGS -DGL_PIXEL_BUFFER_BARRIER_BIT=0x00000080 -DGL_READ_WRITE=0x88BA"
    export CXXFLAGS="$CXXFLAGS -DGL_PIXEL_BUFFER_BARRIER_BIT=0x00000080 -DGL_READ_WRITE=0x88BA"

    make clean platform=armv7-neon-hardfloat || true
    make -j"$JOBS" \
        platform=armv7-neon-hardfloat \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp kronos_libretro.so /build/output/
}
