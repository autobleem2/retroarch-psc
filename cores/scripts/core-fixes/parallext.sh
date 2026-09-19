build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    if ! grep -q -- "-DEGL_NO_X11" Makefile; then
        sed -i 's/COREFLAGS += -DOS_LINUX/COREFLAGS += -DOS_LINUX -DEGL_NO_X11/g' Makefile
    fi

    make clean \
        platform=unix \
        ARCH=arm \
        WITH_DYNAREC=arm || true

    make -j"$JOBS" \
        platform=unix \
        ARCH=arm \
        WITH_DYNAREC=arm \
        FORCE_GLES=1 \
        HAVE_NEON=1 \
        CPUFLAGS="-DARM -marm -mcpu=cortex-a35 -mfpu=neon -mfloat-abi=hard" \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp parallel_n64_libretro.so /build/output/parallext_libretro.so
}
