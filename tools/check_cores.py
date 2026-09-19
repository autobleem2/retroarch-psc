#!/usr/bin/env python3
"""Would these libretro cores load in a RetroArch on the PlayStation Classic? A report over a cores/ folder.

For every *_libretro.so: plain ELF or xz-compressed (KMFD's km_* cores are xz files that only RetroBoot's
patched RetroArch can load - a stock build needs them unpacked first), the ELF class/machine/float ABI,
the highest GLIBC / GLIBCXX symbol version it needs (the console firmware has glibc 2.24 and libstdc++
6.0.22 = GLIBCXX_3.4.22; anything above needs a bundled libstdc++, which RetroBoot ships in retroboot/lib),
the NEEDED libraries against what the firmware provides, the libretro entry points, and whether it asks
for a hardware (GL) context.

    check_cores.py F:/retroarch/cores [--csv out.csv]
"""
import argparse
import csv
import io
import lzma
import os
import re
import sys

from elftools.elf.elffile import ELFFile
from elftools.elf.dynamic import DynamicSection
from elftools.elf.gnuversions import GNUVerNeedSection

# what the console's firmware has in /usr/lib (the set RetroBoot's cores and NG's RetroArch rely on)
FIRMWARE_LIBS = {
    "libc.so.6", "libm.so.6", "libpthread.so.0", "libdl.so.2", "librt.so.1", "libgcc_s.so.1",
    "libstdc++.so.6", "libz.so.1", "libpng16.so.16", "libjpeg.so.8", "libfreetype.so.6",
    "libSDL2-2.0.so.0", "libEGL.so.1", "libGLESv2.so.2", "libGLESv1_CM.so.1", "libGLES_CM.so.1",
    "libwayland-client.so.0", "libwayland-egl.so.1", "libwayland-cursor.so.0", "libxkbcommon.so.0",
    "libasound.so.2", "libudev.so.1", "libusb-1.0.so.0", "libexpat.so.1", "libffi.so.6",
    "libdrm.so.2", "libgbm.so.1",
    # glibc's own pieces and the loader; the GPU vendor's unversioned names (PowerVR ships libEGL.so,
    # libGLESv2.so as plain files, which is what RetroBoot's cores link)
    "ld-linux-armhf.so.3", "libutil.so.1", "libnsl.so.1", "libresolv.so.2", "libcrypt.so.1", "libanl.so.1",
    "libEGL.so", "libGLESv2.so", "libGLESv1_CM.so",
}
# what RetroBoot 1.2 bundles in retroarch/retroboot/lib (LD_LIBRARY_PATH when it launches RetroArch)
RETROBOOT_LIBS = {"liblzma.so.5", "libstdc++.so.6"}
FIRMWARE_GLIBC = (2, 24)
FIRMWARE_GLIBCXX = (3, 4, 22)


def vtuple(s):
    return tuple(int(x) for x in re.findall(r"\d+", s))


def analyse(path):
    r = {"file": os.path.basename(path), "size": os.path.getsize(path)}
    with open(path, "rb") as f:
        head = f.read(6)
    if head.startswith(b"\xfd7zXZ\x00"):
        r["container"] = "xz"
        with lzma.open(path, "rb") as f:
            data = f.read()
        if data.startswith(b"\xfd7zXZ\x00"):  # packed twice (km_nestopia on the owner's stick)
            data = lzma.decompress(data)
            r["container"] = "xz2"
        r["unpacked_size"] = len(data)
        if not data.startswith(b"\x7fELF"):
            r["problems"] = ["the xz file does not hold an ELF object (starts %r)" % data[:8]]
            return r
    elif head.startswith(b"\x7fELF"):
        r["container"] = "elf"
        with open(path, "rb") as f:
            data = f.read()
        r["unpacked_size"] = len(data)
    else:
        r["container"] = "unknown"
        r["problems"] = ["not an ELF nor an xz file"]
        return r

    problems = []
    try:
        elf = ELFFile(io.BytesIO(data))
    except Exception as e:  # noqa: BLE001
        r["problems"] = ["unreadable ELF: %s" % e]
        return r
    r["class"] = elf.elfclass
    r["machine"] = elf["e_machine"]
    flags = elf["e_flags"]
    r["float_abi"] = "hard" if flags & 0x400 else ("soft" if flags & 0x200 else "?")
    if elf.elfclass != 32 or elf["e_machine"] != "EM_ARM":
        problems.append("not a 32-bit ARM object (%s %s)" % (elf.elfclass, elf["e_machine"]))
    if r["float_abi"] != "hard":
        problems.append("float ABI %s, the console is hard-float" % r["float_abi"])

    needed, rpath = [], ""
    for sec in elf.iter_sections():
        if isinstance(sec, DynamicSection):
            for tag in sec.iter_tags():
                if tag.entry.d_tag == "DT_NEEDED":
                    needed.append(tag.needed)
                elif tag.entry.d_tag in ("DT_RPATH", "DT_RUNPATH"):
                    rpath = tag.rpath if tag.entry.d_tag == "DT_RPATH" else tag.runpath
    r["needed"] = needed
    if rpath:
        r["rpath"] = rpath
    missing = [n for n in needed if n not in FIRMWARE_LIBS and n not in RETROBOOT_LIBS]
    from_rb = [n for n in needed if n in RETROBOOT_LIBS and n not in FIRMWARE_LIBS]
    if missing:
        problems.append("needs libraries the console has not got: " + ", ".join(missing))
    if from_rb:
        r["needs_retroboot_lib"] = from_rb

    glibc, glibcxx = (0,), (0,)
    for sec in elf.iter_sections():
        if isinstance(sec, GNUVerNeedSection):
            for _verneed, auxs in sec.iter_versions():
                for aux in auxs:
                    name = aux.name
                    if name.startswith("GLIBCXX_"):
                        glibcxx = max(glibcxx, vtuple(name))
                    elif name.startswith("GLIBC_"):
                        glibc = max(glibc, vtuple(name))
    r["glibc"] = ".".join(map(str, glibc)) if glibc != (0,) else ""
    r["glibcxx"] = ".".join(map(str, glibcxx)) if glibcxx != (0,) else ""
    if glibc > FIRMWARE_GLIBC:
        problems.append("needs GLIBC_%s, the console has 2.24" % r["glibc"])
    if glibcxx > FIRMWARE_GLIBCXX:
        r["needs_retroboot_lib"] = sorted(set(r.get("needs_retroboot_lib", [])) | {"libstdc++.so.6"})

    syms = set()
    dynsym = elf.get_section_by_name(".dynsym")
    if dynsym is not None:
        for s in dynsym.iter_symbols():
            if s.name.startswith("retro_") or s.name in ("glGetString", "eglGetProcAddress"):
                syms.add(s.name)
    for must in ("retro_api_version", "retro_get_system_info", "retro_run", "retro_load_game"):
        if must not in syms:
            problems.append("no %s export - not a libretro core" % must)
    # a core that renders through the frontend's GL context references gl* symbols (or loads them by
    # name); the string check catches the common case
    r["hw_gl"] = bool(re.search(rb"glGetString|eglGetProcAddress|HW_RENDER|retro_hw_get_proc_address", data))

    r["problems"] = problems
    return r


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cores_dir")
    ap.add_argument("--csv")
    args = ap.parse_args()

    names = sorted(n for n in os.listdir(args.cores_dir) if n.endswith(".so"))
    rows = [analyse(os.path.join(args.cores_dir, n)) for n in names]

    xz = [r for r in rows if r.get("container", "").startswith("xz")]
    elf = [r for r in rows if r.get("container") == "elf"]
    bad = [r for r in rows if r.get("problems")]
    rb = [r for r in rows if r.get("needs_retroboot_lib")]
    gl = [r for r in rows if r.get("hw_gl")]
    print("%d cores in %s: %d plain ELF, %d xz-compressed, %d with problems" % (len(rows), args.cores_dir, len(elf), len(xz), len(bad)))
    print("total on disk %.0f MB, unpacked %.0f MB" % (sum(r["size"] for r in rows) / 1e6, sum(r.get("unpacked_size", 0) for r in rows) / 1e6))
    print()
    print("%-36s %-4s %-6s %-7s %-4s %s" % ("core", "pack", "glibc", "glibcxx", "gl", "notes"))
    for r in rows:
        notes = []
        if r.get("needs_retroboot_lib"):
            notes.append("needs retroboot/lib " + "+".join(r["needs_retroboot_lib"]))
        notes += r.get("problems", [])
        print("%-36s %-4s %-6s %-7s %-4s %s" % (r["file"].replace("_libretro.so", ""), r.get("container", "?"), r.get("glibc", ""), r.get("glibcxx", ""), "GL" if r.get("hw_gl") else "", "; ".join(notes)))
    print()
    if rb:
        print("need RetroBoot's bundled libraries (GLIBCXX above the firmware's 3.4.22, or liblzma): %d" % len(rb))
    if gl:
        print("hardware-rendered (need the frontend's GLES context): %d" % len(gl))
    if bad:
        print("problems: %d" % len(bad))
        for r in bad:
            print("  %s: %s" % (r["file"], "; ".join(r["problems"])))
    libs = {}
    for r in rows:
        for n in r.get("needed", []):
            libs[n] = libs.get(n, 0) + 1
    print("\nlibraries needed (count of cores): " + ", ".join("%s (%d)" % kv for kv in sorted(libs.items(), key=lambda kv: -kv[1])))

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["core", "container", "size", "unpacked_size", "float_abi", "glibc", "glibcxx", "hw_gl", "needed", "needs_retroboot_lib", "problems"])
            for r in rows:
                w.writerow([r["file"], r.get("container"), r["size"], r.get("unpacked_size"), r.get("float_abi"), r.get("glibc"), r.get("glibcxx"), r.get("hw_gl"), " ".join(r.get("needed", [])), " ".join(r.get("needs_retroboot_lib", [])), "; ".join(r.get("problems", []))])
        print("wrote", args.csv)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
