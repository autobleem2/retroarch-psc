build_core() {
    ./libretro-build.sh "$CORE_NAME"
    cp dist/unix/bsnes2014_performance_libretro.so /build/output/bsnes_performance_libretro.so
}
