build_core() {
    DOSBOX_DIR="/build/libretro-super/libretro-dosbox_core"

    make -C "$DOSBOX_DIR/libretro" -f Makefile.libretro \
        platform=unix \
        UNAME=PSC \
        TARGET_TRIPLET=arm-linux-gnueabihf \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        AS=arm-linux-gnueabihf-as \
        LD=arm-linux-gnueabihf-g++ \
        RANLIB=arm-linux-gnueabihf-ranlib \
        PKGCONFIG=arm-linux-gnueabihf-pkg-config \
        WITH_DYNAREC=arm \
        ARM_HARDFLOAT=1 \
        ARM_NEON=1 \
        WITH_FAKE_SDL=1 \
        BUNDLED_AUDIO_CODECS=0 \
        BUNDLED_LIBSNDFILE=0 \
        WITH_SDL_SOUND_WRAPPER=0 \
        WITH_FLUIDSYNTH=0 \
        WITH_BASSMIDI=0 \
        WITH_VOODOO=0 \
        -j"$JOBS" || true

    SO_FILE="$DOSBOX_DIR/libretro/dosbox_core_libretro.so"
    if [ -f "$SO_FILE" ]; then
        cp "$SO_FILE" /build/output/dosbox_core_libretro.so
    fi
}
