# RetroArch and libretro cores for the PlayStation Classic

Docker-based cross-compilation of [RetroArch](https://github.com/libretro/RetroArch) and the
[libretro cores](https://github.com/libretro/libretro-super) for the PlayStation Classic, producing the
binaries [AutoBleem](https://github.com/autobleem/AutoBleem2) installs onto a console's USB stick. One
repository, two products: `retroarch/` (the frontend, four PSC patches, its own Makefile) and `cores/`
(the core list, per-core build fixes, the build script); one `Dockerfile` with a stage per product on a
shared toolchain.

Merged from AutoBleem-NG's `retroarch-psc` and `libretro-cores-psc` (2026-09), whose two Dockerfiles
shared the toolchain stage word for word. The recipe is theirs; what changed is the layout, the shared
stage, the release packaging and the CI.

## Build

```bash
make retroarch            # dist/retroarch/retroarch (+ VERSION)
make cores                # dist/cores/*_libretro.so, every enabled core in cores/cores.txt
make core CORE=snes9x     # one core, log on the terminal
make package              # dist/release/: retroarch-psc-<tag>.zip, libretro-cores-psc-<tag>.tar.gz, manifest.json
make release              # all of the above
make status               # what is built, what is missing
make retry-failed         # rebuild the cores that failed last time
make help                 # the rest
```

Requirements: Docker (BuildKit - any current version) and GNU make. The first build compiles the
crosstool-ng toolchain (about an hour); every later build takes it from the Docker cache. Each core is
built in its own container from the `cores` image, `PARALLEL` at a time (default half the CPUs).

`make cores CORES_IMAGE=ghcr.io/autobleem/retroarch-psc/cores:latest` uses the image the CI pushed instead
of building one locally (`docker pull` it first, or log in to ghcr.io).

### Toolchain

| Component | Value |
|-----------|-------|
| Compiler | crosstool-ng 1.28.0: GCC 9, glibc 2.23, binutils 2.32, Linux 4.4 headers |
| Target | `arm-linux-gnueabihf`, ARMv8-A Cortex-A35 (the MT8167), hard-float, NEON - the console's 32-bit userspace |
| Sysroot libraries | Ubuntu 18.04's armhf `-dev` packages (SDL2, EGL/GLES, ALSA, udev, freetype, wayland, ...) |
| RetroArch flags | `-march=armv8-a -mtune=cortex-a35 -mfpu=neon-vfpv4 -mfloat-abi=hard -O3` (see `retroarch/Makefile.psc`'s header for why `neon-vfpv4`) |
| Core flags | `-march=armv8-a -mtune=cortex-a35 -mfpu=neon-fp-armv8 -mfloat-abi=hard -O3` (`PSC_CFLAGS` in the Dockerfile) |

The console's firmware has glibc 2.24 and libstdc++ 6.0.22 (`GLIBCXX_3.4.22`); glibc 2.23 plus
`-static-libstdc++` on RetroArch keeps everything within that. All of RetroArch's shared library
dependencies are satisfied by the stock firmware.

## RetroArch

`retroarch/docs/building.md` (the build, the version scheme) and `retroarch/docs/psc-configuration.md`
(what `retroarch.cfg` must say on a console: `video_driver = "gl"`, `video_context_driver = "wayland"`,
`input_driver = "udev"`, and why). The patches:

| Patch | Description |
|-------|-------------|
| `alsa_force_s16_psc_mtk.patch` | Forces ALSA S16_LE on the MT8167 (which mis-advertises FLOAT support). |
| `wl_shell_fallback.patch` | Wayland fallback for the console's Weston 1.11 (no `xdg_shell`). |
| `xmb_ribbon_drop_oes_derivatives_ext.patch` | Fixes the XMB ribbon shader on PowerVR Rogue. |
| `xmb_shader_pipeline_psc_limit.patch` | Hides pipeline options too slow for the console; only "Off" and "Ribbon Simplified" are exposed. |
| `xz_core_loading.patch` | Ours (2026-09-20): a core file that is an xz stream - RetroBoot's `km_*` cores, 147 of the 178 on a typical stick - is unpacked with liblzma into `/tmp/retroarch-cores` and loaded from there, kept for the next launch, one core at a time. `HAVE_XZ_CORES=1`, liblzma linked statically (the firmware has none). `tools/check_cores.py` is the report that showed the need. |

`RETROARCH_VERSION` at the top of the Dockerfile is the RetroArch tag built (`make retroarch
RETROARCH_VERSION=v1.23.0` to try another).

## The XMB theme

`theme/`: the AutoBleem 2 look for 1.22.2's XMB - the wallpaper (`make_wallpaper.py` from the ab2
theme's background), Selawik Light, the RetroSystem icons, and `retroarch-psc.cfg` with the keys that
changed meaning since RetroBoot's 1.9.0 (its `xmb_theme = "8"` is Monochrome Inverted now, RetroSystem is
7; `quit_on_close_content = "2"` for Close Content to quit as 1.9.0 did). `theme/README.md` says what
goes where; the installer will apply it.

## Cores

`cores/cores.txt` is the list AutoBleem ships - the cores RetroBoot 1.2 shipped for the console, so they
are known to run on the hardware, in build-priority order (its header has the mapping and what was left
out and why); `cores/cores-full.txt` is AutoBleem-NG's whole list (170), everything known to *build*, to
promote from after a hardware test. A disabled core is left in place with the reason. `cores/scripts/core-fixes/<core>.sh` is a per-core override of the fetch/build
steps (`fetch_core`, `patch_core`, `configure_core_flags`, `build_core`, `core_source_dir`) for the cores
libretro-super's generic rules cannot build for this target. `cores/scripts/core-refs.txt` pins a core to
a tag or a ref (`flycast` and `virtualjaguar` build their latest version tag, `ppsspp` a pinned one, the
rest libretro-super's fetched branch). `LIBRETRO_SUPER_REF` in the Dockerfile pins libretro-super itself;
`make check-version` compares both pins with upstream, `make audit-cores` compares `cores.txt` with the
rules the pinned checkout has.

A built core records where it came from (`build_metadata/commits/<core>_libretro.so.commit`, aggregated
into `COMMITS.txt`), and `make cores` skips a core whose recorded libretro-super commit is the current pin.

### The console's cores, for now

The cores are not built here yet; the console gets **RetroBoot 1.2's** (KMFD's `km_*` builds, which the
RetroArch build loads xz-compressed as they are). `make pack-retroboot-cores RETROBOOT_DIR=F:/retroarch`
(`tools/pack_retroboot_cores.py`) packs a stick's `cores/` + `info/` into `cores-psc-<date>.tar.gz` with a
`cores-psc-<date>.json` listing every core (sizes, sha256, the glibc it needs, GL, display name) and the
ones left out - what `tools/check_cores.py` says cannot run on a stock console, and RetroBoot's own app
launchers; `make publish-cores` puts it at `https://autobleem.retromenele.pl/psc/cores/` (newest kept,
`latest.json`).

## Releases

A release is a git tag `v<RetroArch version>-<build>` (`v1.22.2-1`, `v1.22.2-2`, ...): the frontend's
version is the headline, the build number counts our own changes. `make package` (or the CI on that tag)
produces, in `dist/release/`:

- `retroarch-psc-<tag>.zip` - `retroarch`, `VERSION`, `docs/`
- `libretro-cores-psc-<tag>.tar.gz` - `cores/*_libretro.so`, `info/*.info`, `VERSION`, `COMMITS.txt`
- `libretro-cores-psc-<tag>.md` - release notes
- `manifest.json` - both assets with sizes and sha256, the RetroArch version, the libretro-super commit,
  and every core with its display name, system, extensions and database from its `.info`. **This is what
  AutoBleem's PC installer reads** to download and lay out a RetroArch on a stick.

### Publishing

The repository is private, so its GitHub releases cannot be downloaded anonymously; what the PC installer
fetches is on AutoBleem's download repository instead, `https://autobleem.retromenele.pl/psc/retroarch/`:
`make publish` runs AutoBleem2's `tools/repo_publish.sh psc-retroarch <tag> <zip> manifest.json` (`AB2_DIR`,
`../AutoBleem2` by default - rsync to the build server, `.sha256` sidecars, the index rerun there), which
lands the files in `psc/retroarch/<tag>/` and writes `psc/retroarch/latest.json` (the zip's url, size and
sha256, plus the manifest's url); only the newest tag is kept. The installer reads `latest.json`, or the
manifest by its url. `make package-retroarch` makes a RetroArch-only release (`"cores": null`) when the
cores are not wanted.

## CI (`.github/workflows/build.yml`)

**Off for now** - every job is skipped until the repository variable `CI_ENABLED` is `true`; the builds
are made on the build server with the Makefile. When it is on: a push or pull request builds the cores image (pushed to `ghcr.io/autobleem/retroarch-psc/cores`, with
a registry cache so the toolchain stage is built once) and RetroArch. A `v*` tag, or "Run workflow", also
builds every core - `cores.txt` dealt round-robin over `shards` GitHub-hosted runners (16 by default; a
dispatch can name a few cores instead) - and packages; on a tag the packages go onto a **draft** GitHub
release named after the tag, to be published from the Releases page once checked.

## License

GPL-3.0 (`LICENSE`), as `retroarch-psc` was - it is based on
[retroarch-cross-compile](https://github.com/zoltanvb/retroarch-cross-compile) by Zoltan Baldaszti. The
core build scripts under `cores/` came from `libretro-cores-psc`, released under the MIT license by
AutoBleem-NG. RetroArch and each core carry their own licenses; the release archives are of their
binaries, unmodified beyond the patches listed above.
