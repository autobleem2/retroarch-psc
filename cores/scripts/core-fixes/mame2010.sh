build_core() {
    # libretro-super's generic path leaves PTR64 enabled, which trips MAME's
    # validity check on the PSC's 32-bit userspace.
    # The classic_armv8_a35 branch also fills TARGET instead of TARGETLIB and
    # forgets to add SHARED to LDFLAGS, so pass the final link pieces here.
    MAME2010_DIR="/build/libretro-super/libretro-mame2010"
    make -C "$MAME2010_DIR" \
        platform=classic_armv8_a35 \
        PTR64=0 \
        VRENDER=soft \
        TARGETLIB=mame2010_libretro.so \
        LDFLAGS="$PSC_LDFLAGS -fPIC -shared -Wl,--version-script=src/osd/retro/link.T -Wl,--no-undefined" \
        LIBS="-lz -lpthread" \
        -j"$JOBS" || true
    SO_FILE="$MAME2010_DIR/mame2010_libretro.so"
    if [ -f "$SO_FILE" ]; then
        cp "$SO_FILE" /build/output/
    fi
}

core_source_dir() {
    echo "$MAME2010_DIR"
}
