#!/usr/bin/env python3
"""Pack RetroBoot's runtime libraries - what its apps and AutoBleem's Apps need beyond the console firmware.

    pack_retroboot_libs.py F:/retroarch/retroboot [--out dist/release]

RetroBoot's `init_libs.sh` links `retroboot/assets/lib/*` into /tmp/rblib (LD_LIBRARY_PATH for
EmulationStation and the apps: SDL2_image/mixer/net/ttf, SDL 1.2, FLAC, GL/GLU, boost, curl, freetype,
jpeg, png16, tiff, vlc, vorbis, lzma) and `retroboot/lib/*` (liblzma, a GLIBCXX 3.4.25 libstdc++) onto
every RetroArch launch. None of the cores needs either, but the Apps on a stick do (eduke32,
shadowwarrior, opentyrian, sdlpop, wolf4sdl launch into RetroBoot's apps/; amiberry and doom want
SDL2_image/ttf the firmware has not got) - so a stick without RetroBoot gets them from this tarball:
`lib/` (assets/lib, with the unversioned and soname links init_libs.sh would make) and `lib-retroarch/`
(retroboot/lib), plus libs-psc-<date>.json listing every file with its soname, size, sha256 and what it
needs. Named libs-psc-<YYYYMMDD>.tar.gz; the repository keeps the newest.
"""
import argparse
import datetime
import hashlib
import io
import json
import os
import re
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from elftools.elf.elffile import ELFFile  # noqa: E402
from elftools.elf.dynamic import DynamicSection  # noqa: E402
from elftools.elf.gnuversions import GNUVerNeedSection  # noqa: E402


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def elf_facts(path):
    facts = {"soname": "", "needed": [], "glibc": "", "glibcxx": ""}
    with open(path, "rb") as f:
        try:
            elf = ELFFile(f)
        except Exception:  # noqa: BLE001
            return facts
        glibc, glibcxx = (0,), (0,)
        for sec in elf.iter_sections():
            if isinstance(sec, DynamicSection):
                for tag in sec.iter_tags():
                    if tag.entry.d_tag == "DT_NEEDED":
                        facts["needed"].append(tag.needed)
                    elif tag.entry.d_tag == "DT_SONAME":
                        facts["soname"] = tag.soname
            elif isinstance(sec, GNUVerNeedSection):
                for _v, auxs in sec.iter_versions():
                    for aux in auxs:
                        t = tuple(int(x) for x in re.findall(r"\d+", aux.name))
                        if aux.name.startswith("GLIBCXX_"):
                            glibcxx = max(glibcxx, t)
                        elif aux.name.startswith("GLIBC_"):
                            glibc = max(glibc, t)
        facts["glibc"] = ".".join(map(str, glibc)) if glibc != (0,) else ""
        facts["glibcxx"] = ".".join(map(str, glibcxx)) if glibcxx != (0,) else ""
    return facts


def link_names(filename):
    """The shorter names init_libs.sh links to a versioned library: libfoo.so.1.2.3 -> libfoo.so.1.2, libfoo.so.1, libfoo.so"""
    names = []
    name = filename
    while re.search(r"\.[0-9]+$", name):
        name = re.sub(r"\.[0-9]+$", "", name)
        names.append(name)
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("retroboot_dir", help="the stick's retroarch/retroboot folder")
    ap.add_argument("--out", default="dist/release")
    ap.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d"))
    args = ap.parse_args()

    groups = (("lib", os.path.join(args.retroboot_dir, "assets", "lib"), "init_libs.sh's /tmp/rblib - EmulationStation and the apps"),
              ("lib-retroarch", os.path.join(args.retroboot_dir, "lib"), "retroboot/lib - on LD_LIBRARY_PATH for every RetroArch launch"))
    entries = []
    os.makedirs(args.out, exist_ok=True)
    tar_name = "libs-psc-%s.tar.gz" % args.date
    tar_path = os.path.join(args.out, tar_name)
    with tarfile.open(tar_path, "w:gz", compresslevel=6) as tar:
        for arc, src, what in groups:
            for name in sorted(os.listdir(src)):
                path = os.path.join(src, name)
                if not os.path.isfile(path):
                    continue
                e = {"group": arc, "file": name, "size": os.path.getsize(path), "sha256": sha256_of(path)}
                e.update(elf_facts(path))
                e["links"] = link_names(name)
                entries.append(e)
                tar.add(path, arcname="%s/%s" % (arc, name))
                for link in e["links"]:
                    ti = tarfile.TarInfo("%s/%s" % (arc, link))
                    ti.type = tarfile.SYMTYPE
                    ti.linkname = name
                    tar.addfile(ti)
        manifest = {"schema": 1, "target": "psc", "source": "RetroBoot 1.2", "date": args.date,
                    "groups": {arc: what for arc, _s, what in groups}, "count": len(entries), "libs": entries}
        text = json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8")
        ti = tarfile.TarInfo("libs.json")
        ti.size = len(text)
        ti.mtime = int(datetime.datetime.now().timestamp())
        tar.addfile(ti, io.BytesIO(text))
    with open(os.path.join(args.out, "libs-psc-%s.json" % args.date), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("%s: %d libraries, %.1f MB" % (tar_path, len(entries), os.path.getsize(tar_path) / 1e6))
    for e in entries:
        print("  %-14s %-34s %-28s glibc<=%-5s %s" % (e["group"], e["file"], e["soname"], e["glibc"], "GLIBCXX<=" + e["glibcxx"] if e["glibcxx"] else ""))


if __name__ == "__main__":
    main()
