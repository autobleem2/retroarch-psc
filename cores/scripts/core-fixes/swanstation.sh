build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    sed -i '/xxh_x86dispatch/d' dep/xxhash/CMakeLists.txt

    rm -rf build
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_PROCESSOR=armv7l

    cmake --build build --target swanstation_libretro --config Release -- -j"$JOBS"
    cp build/swanstation_libretro.so /build/output/
}
