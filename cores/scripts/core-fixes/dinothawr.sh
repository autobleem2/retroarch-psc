build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    sed -i 's/#include <future>/#include <atomic>/' audio/mixer.hpp
    sed -i 's/std::vector<std::future<std::vector<float>>> inflight;/std::vector<int> inflight;/' audio/mixer.hpp
    perl -0pi -e 's/inflight\.push_back\(async\(launch::async, \[path\]\(\) \{\s+VorbisFile file\{path\};\s+return file\.decode\(\);\s+\}\)\);/VorbisFile file(path);\n      finished.push(file.decode());/s' audio/mixer.cpp
    perl -0pi -e 's/static bool erase_vorbis_stream\(const future<vector<float>>& fut\)\s+\{\s+return !fut\.valid\(\);\s+\}/static bool erase_vorbis_stream(const int&)\n   {\n      return true;\n   }/s' audio/mixer.cpp
    perl -0pi -e 's/\s+for \(auto& fut : inflight\)\s+if \(fut\.wait_for\(chrono::seconds\(0\)\) == future_status::ready\)\s+finished\.push\(fut\.get\(\)\);\s+\n\s+cleanup\(\);/\n         cleanup();/s' audio/mixer.cpp

    export CFLAGS="$CFLAGS -DDONT_WANT_ARM_OPTIMIZATIONS"
    export CXXFLAGS="$CXXFLAGS -DDONT_WANT_ARM_OPTIMIZATIONS"

    make clean platform=unix || true
    make -j"$JOBS" \
        platform=unix \
        LIBS="-lm -lpthread -latomic" \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp dinothawr_libretro.so /build/output/
}
