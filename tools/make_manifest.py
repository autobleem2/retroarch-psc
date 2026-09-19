#!/usr/bin/env python3
"""Write dist/release/manifest.json - what a release of this repository contains.

The PC installer (AutoBleem's) reads this file from wherever the release is published (the GitHub release,
or autobleem.github.io/resources/retroarch-psc/ - the asset names are relative to the manifest's own URL)
to know which assets to download, their hashes, and which cores are inside the cores tarball (with each
core's display name, system and extensions from its .info file, so it can offer a picker without
unpacking anything first). "cores" is null for a RetroArch-only release.

    make_manifest.py --tag v1.22.2-1 --release-dir dist/release \
        --retroarch-version-file dist/retroarch/VERSION --cores-version-file build_metadata/VERSION \
        --cores-dir dist/cores --cores-file cores/cores.txt --info-dir dist/info
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import sys

SCHEMA = 1
INFO_KEYS = ("display_name", "systemname", "manufacturer", "categories", "supported_extensions", "database",
             "firmware_count", "notes")


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_kv(path):
    """A `key=value` file (the VERSION files) as a dict."""
    out = {}
    if not path or not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    return out


def read_info(path):
    """A libretro .info file: `key = "value"` lines."""
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r'\s*([A-Za-z0-9_]+)\s*=\s*"(.*)"\s*$', line)
            if m and m.group(1) in INFO_KEYS:
                out[m.group(1)] = m.group(2)
    return out


def enabled_cores(cores_file):
    names = []
    with open(cores_file, encoding="utf-8") as f:
        for line in f:
            name = line.split("#", 1)[0].strip()
            if name:
                names.append(name)
    return names


def asset(release_dir, name):
    path = os.path.join(release_dir, name)
    return {"file": name, "size": os.path.getsize(path), "sha256": sha256_of(path)}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--tag", required=True)
    ap.add_argument("--release-dir", required=True)
    ap.add_argument("--retroarch-version-file")
    ap.add_argument("--cores-version-file")
    ap.add_argument("--cores-dir", default="dist/cores")
    ap.add_argument("--cores-file", default="cores/cores.txt")
    ap.add_argument("--info-dir", default="dist/info")
    args = ap.parse_args()

    ra_zip = "retroarch-psc-%s.zip" % args.tag
    cores_tar = "libretro-cores-psc-%s.tar.gz" % args.tag
    if not os.path.isfile(os.path.join(args.release_dir, ra_zip)):
        sys.exit("missing release asset: %s" % os.path.join(args.release_dir, ra_zip))
    # A RetroArch-only release (make package-retroarch) has no cores tarball: "cores" is null then.
    with_cores = os.path.isfile(os.path.join(args.release_dir, cores_tar))

    ra_version = read_kv(args.retroarch_version_file)
    cores_version = read_kv(args.cores_version_file)

    cores = []
    for name in enabled_cores(args.cores_file) if with_cores else []:
        so = "%s_libretro.so" % name
        path = os.path.join(args.cores_dir, so)
        if not os.path.isfile(path):
            continue  # packaged with ALLOW_MISSING=1
        entry = {"name": name, "file": so, "size": os.path.getsize(path), "sha256": sha256_of(path)}
        entry.update(read_info(os.path.join(args.info_dir, "%s_libretro.info" % name)))
        cores.append(entry)

    manifest = {
        "schema": SCHEMA,
        "target": "psc",
        "tag": args.tag,
        "built": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "toolchain": cores_version.get("toolchain") or ra_version.get("toolchain") or "crosstool-ng-gcc9-glibc2.23",
        "retroarch": dict(
            {"version": ra_version.get("retroarch_version", ""), "psc_build": ra_version.get("psc_build", "")},
            **asset(args.release_dir, ra_zip)),
        "cores": None,
    }
    if with_cores:
        manifest["cores"] = dict(
            {"libretro_super_commit": cores_version.get("libretro_super_commit_full", ""),
             "libretro_super_date": cores_version.get("libretro_super_date", ""),
             "count": len(cores)},
            **asset(args.release_dir, cores_tar))
        manifest["cores"]["list"] = cores

    out = os.path.join(args.release_dir, "manifest.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("wrote %s: RetroArch %s, %s" % (out, manifest["retroarch"]["version"],
                                         "%d cores" % len(cores) if with_cores else "no cores"))


if __name__ == "__main__":
    main()
