patch_core() {
    # The Makefile defaults HAVE_SSE=1 and only zeros it for specific named
    # ARM platforms. Our generic platform does not match those branches.
    YABA_MK="/build/libretro-super/libretro-yabasanshiro/yabause/src/libretro/Makefile"
    if [ -f "$YABA_MK" ]; then
        sed -i 's|^HAVE_SSE = 1$|HAVE_SSE = 0|' "$YABA_MK"
    fi
}
