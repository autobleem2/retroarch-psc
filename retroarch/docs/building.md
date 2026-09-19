# Building RetroArch for PSC

Docker-based cross-compilation for RetroArch on PlayStation Classic.

## Requirements

- Docker

## Quick Start

From the repository root (this file lives in `retroarch/docs/`):

```bash
make retroarch    # build and extract the binary
ls dist/retroarch/retroarch
```

`make package` adds it to `dist/release/retroarch-psc-<tag>.zip` next to the cores tarball - see the
root README for the release layout and the tag scheme (`v<RetroArch version>-<build>`).

## Configuration

Edit the root Dockerfile's ARGs to customize the build:

| ARG | Default | Description |
|-----|---------|-------------|
| `RETROARCH_VERSION` | v1.22.2 | RetroArch git tag |
| `CROSSTOOL_NG_VERSION` | 1.28.0 | Toolchain builder version |
| `CT_GCC_VERSION` | 9 | GCC version |
| `CT_GLIBC_VERSION` | 2_23 | glibc version |

### Build Specific Version

```bash
make retroarch RETROARCH_VERSION=v1.19.1
```

## Toolchain

Two-stage Docker build:

1. **Stage 1** (Ubuntu 16.04): Build crosstool-ng ARM toolchain
   - GCC 9, glibc 2.23, kernel headers 4.4

2. **Stage 2** (Ubuntu 18.04): Compile RetroArch
   - Uses custom toolchain from stage 1
   - Links against Ubuntu armhf libraries

### Target Architecture

- **CPU**: ARMv8-A Cortex-A35 (PSC SoC)
- **FPU**: NEON + VFPV4, hard-float ABI

### Compiler Flags

```
-march=armv8-a -mtune=cortex-a35 -mfpu=neon-vfpv4 -mfloat-abi=hard
-O3 -funroll-loops -ftree-vectorize -ffunction-sections -fdata-sections
```

`-mfpu=neon-vfpv4` (not `neon-fp-armv8`) is intentional: the PSC kernel's HWCAP advertises only VFPV3/VFPV4 even though the silicon is ARMv8, so emitting ARMv8 FPU instructions traps at runtime.

## Build Features

Enabled:
- SDL2 (input/joystick)
- Wayland (native context, with `wl_shell` fallback for PSC's Weston 1.11)
- OpenGL ES + EGL
- Freetype (fonts)
- ALSA (audio)
- udev (device hotplug)
- NEON SIMD

Disabled:
- PulseAudio
- X11
- Desktop OpenGL
- Discord integration

## Debugging

```bash
DOCKER_BUILDKIT=1 docker build --target retroarch -t retroarch-psc-ra .
docker run --rm -it retroarch-psc-ra
# Inside container:
cd /build/RetroArch
make -f Makefile.psc clean
CC=psc-gcc CXX=psc-g++ make -f Makefile.psc -j$(nproc)
```

## Output

The build produces a stripped ARM binary at `dist/retroarch/retroarch`, with a `VERSION` file next to it.

All 18 shared library dependencies are satisfied by stock PSC firmware - no additional libraries need to be bundled.
