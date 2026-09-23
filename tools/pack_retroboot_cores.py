#!/usr/bin/env python3
"""Pack the libretro cores of a RetroBoot stick into the cores tarball the download repository serves.

    pack_retroboot_cores.py F:/retroarch [--out dist/release]

Until AutoBleem builds its own cores, the console gets RetroBoot 1.2's (KMFD's km_* builds, xz-compressed
- the RetroArch build loads them as they are). The tarball holds `cores/*_libretro.so` exactly as they
are on the stick, `info/*.info` for the ones RetroBoot shipped info files for, and `cores.json`: every core
with its packed and unpacked size, sha256, the glibc/GLIBCXX it needs, whether it wants a GL context, and
the info file's display name/system when there is one. Cores that cannot run on a stock console are left
out (check_cores.py's verdict: a wrong architecture, a glibc newer than the firmware's 2.24, a library the
firmware has not got) and so are RetroBoot's own app launchers, which need its scripts; the list of what
was left out and why goes into cores.json too.

Named cores-psc-<YYYYMMDD>.tar.gz, with cores-psc-<YYYYMMDD>.json (the same cores.json) next to it for the
repository - which keeps the newest date only (`make publish-cores`).
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
import check_cores  # noqa: E402

# RetroBoot's own launchers (they run its scripts, not a game) - not cores for a plain RetroArch
RETROBOOT_OWN = {"app_launcher_rb", "drastic_launcher_rb"}


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_info(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r'\s*([A-Za-z0-9_]+)\s*=\s*"(.*)"\s*$', line)
            if m and m.group(1) in ("display_name", "systemname", "supported_extensions", "database", "corename"):
                out[m.group(1)] = m.group(2)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("retroarch_dir", help="the stick's retroarch/ folder (cores/ and info/ inside)")
    ap.add_argument("--out", default="dist/release")
    ap.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d"))
    args = ap.parse_args()

    cores_dir = os.path.join(args.retroarch_dir, "cores")
    info_dir = os.path.join(args.retroarch_dir, "info")
    names = sorted(n for n in os.listdir(cores_dir) if n.endswith("_libretro.so"))
    included, excluded = [], []
    for so in names:
        name = so[:-len("_libretro.so")]
        path = os.path.join(cores_dir, so)
        r = check_cores.analyse(path)
        why = "; ".join(r.get("problems", []))
        if name in RETROBOOT_OWN:
            why = "RetroBoot's own launcher, needs its scripts"
        if why:
            excluded.append({"name": name, "file": so, "why": why})
            continue
        entry = {
            "name": name, "file": so, "size": r["size"], "unpacked_size": r.get("unpacked_size"),
            "packed": r.get("container", "elf") != "elf", "sha256": sha256_of(path),
            "glibc": r.get("glibc", ""), "glibcxx": r.get("glibcxx", ""), "hw_gl": bool(r.get("hw_gl")),
        }
        info = os.path.join(info_dir, "%s_libretro.info" % name)
        if os.path.isfile(info):
            entry["info"] = "%s_libretro.info" % name
            entry.update(read_info(info))
        included.append(entry)

    os.makedirs(args.out, exist_ok=True)
    tar_name = "cores-psc-%s.tar.gz" % args.date
    tar_path = os.path.join(args.out, tar_name)
    manifest = {
        "schema": 1, "target": "psc", "source": "RetroBoot 1.2 (KMFD's km_* builds)", "date": args.date,
        "count": len(included), "cores": included, "excluded": excluded,
    }
    with tarfile.open(tar_path, "w:gz", compresslevel=6) as tar:
        for entry in included:
            tar.add(os.path.join(cores_dir, entry["file"]), arcname="cores/" + entry["file"])
            if "info" in entry:
                tar.add(os.path.join(info_dir, entry["info"]), arcname="info/" + entry["info"])
        text = json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8")
        ti = tarfile.TarInfo("cores.json")
        ti.size = len(text)
        ti.mtime = int(datetime.datetime.now().timestamp())
        tar.addfile(ti, io.BytesIO(text))
    with open(os.path.join(args.out, "cores-psc-%s.json" % args.date), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("%s: %d cores (%d left out), %.0f MB" % (tar_path, len(included), len(excluded), os.path.getsize(tar_path) / 1e6))
    for x in excluded:
        print("  left out: %s - %s" % (x["name"], x["why"]))


if __name__ == "__main__":
    main()
