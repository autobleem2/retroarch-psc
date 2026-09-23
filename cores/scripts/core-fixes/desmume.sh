build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR/desmume/src/frontend/libretro"

    if ! grep -q "defined(PSC_NO_PCAP)" ../../wifi.cpp; then
        sed -i 's/defined(WEBOS)/defined(WEBOS) || defined(PSC_NO_PCAP)/' ../../wifi.cpp
    fi

    export CXXFLAGS="$CXXFLAGS -DPSC_NO_PCAP"

    make -f Makefile.libretro clean platform=classic_armv7_a7 || true
    make -f Makefile.libretro -j"$JOBS" \
        platform=classic_armv7_a7 \
        LIBS="-lpthread" \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++

    cp desmume_libretro.so /build/output/
}
