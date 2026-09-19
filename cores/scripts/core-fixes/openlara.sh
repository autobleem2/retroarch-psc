build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR/src/platform/libretro"

    export CFLAGS="$CFLAGS -DEGL_NO_X11"
    export CXXFLAGS="$CXXFLAGS -DEGL_NO_X11"

    make -f Makefile clean platform=armv7-neon-hardfloat-gles || true
    make -f Makefile -j"$JOBS" \
        platform=armv7-neon-hardfloat-gles \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp openlara_libretro.so /build/output/
}
