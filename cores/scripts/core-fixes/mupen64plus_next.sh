build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    export CFLAGS="$CFLAGS -DEGL_NO_X11"
    export CXXFLAGS="$CXXFLAGS -DEGL_NO_X11"

    make clean platform=odroid BOARD=ODROIDGOA || true
    make -j"$JOBS" \
        platform=odroid \
        BOARD=ODROIDGOA \
        FORCE_GLES=1 \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp mupen64plus_next_libretro.so /build/output/
}
