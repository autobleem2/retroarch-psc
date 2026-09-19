patch_core() {
    EMUSCV_MK="/build/libretro-super/libretro-emuscv/Makefile.libretro"
    EMUSCV_HDR="/build/libretro-super/libretro-emuscv/src/emuscv.h"
    EMUSCV_SDL_SHIM="/build/libretro-super/libretro-emuscv/src/SDL.h"
    if [ -f "$EMUSCV_MK" ]; then
        sed -i \
            -e 's|^\t\$(CC) \$(OBJOUT) tools/bin2c/bin2c|\t/usr/bin/gcc $(OBJOUT) tools/bin2c/bin2c|' \
            -e 's|^\t\$(CXX) \$(OBJOUT) tools/dasm7801/dasm7801|\t/usr/bin/g++ $(OBJOUT) tools/dasm7801/dasm7801|' \
            -e 's|^\t@clear|\t@:|' \
            -e 's|`sdl2-config --cflags`|-I/usr/include/SDL2 -I/usr/include/arm-linux-gnueabihf/SDL2 -I/usr/include/arm-linux-gnueabihf -I/usr/include|g' \
            -e 's|^binary\.%\.c: %$|binary.%.c: % tools/bin2c/bin2c$(EXE_EXT)|' \
            "$EMUSCV_MK"
    fi
    if [ -f "$EMUSCV_HDR" ]; then
        sed -i 's|<SDL2/SDL.h>|<SDL.h>|' "$EMUSCV_HDR"
    fi
    if [ -f "$EMUSCV_HDR" ]; then
        cat > "$EMUSCV_SDL_SHIM" <<'EOF'
#pragma once

#if defined(__has_include)
#  if __has_include("/usr/include/SDL2/SDL.h")
#    include "/usr/include/SDL2/SDL.h"
#  elif __has_include("/usr/include/arm-linux-gnueabihf/SDL2/SDL.h")
#    include "/usr/include/arm-linux-gnueabihf/SDL2/SDL.h"
#  else
#    error "SDL.h shim could not locate SDL2/SDL.h"
#  endif
#else
#  include "/usr/include/SDL2/SDL.h"
#endif
EOF
    fi
}

configure_core_flags() {
    # emuscv.h includes <SDL2/SDL.h>, while its Makefile only adds
    # -I/usr/include/SDL2. Search host /usr/include after the cross sysroot.
    export CFLAGS="$CFLAGS -I/usr/include/arm-linux-gnueabihf/SDL2 -I/usr/include/arm-linux-gnueabihf -idirafter /usr/include"
    export CXXFLAGS="$CXXFLAGS -I/usr/include/arm-linux-gnueabihf/SDL2 -I/usr/include/arm-linux-gnueabihf -idirafter /usr/include"

    # Generated binary*.h files lack proper dependencies for parallel builds.
    export JOBS=1
}

build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    make -f Makefile.libretro clean || true
    make -f Makefile.libretro -j"$JOBS" \
        CC=psc-gcc \
        CXX=psc-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp emuscv_libretro.so /build/output/
}
