#!/usr/bin/env python3
"""Pack the libretro cores of a RetroBoot stick into the cores tarball the download repository serves.

    pack_retroboot_cores.py F:/retroarch [--out dist/release]
    pack_retroboot_cores.py --from-tarball cores-psc-20260920.tar.gz [--out dist/release]

Until AutoBleem builds its own cores, the console gets RetroBoot 1.2's (KMFD's km_* builds, xz-compressed
- the RetroArch build loads them as they are). The tarball holds `cores/*_libretro.so` exactly as they
are on the stick, `info/*.info`, and `cores.json`: every core with its packed and unpacked size, sha256,
the glibc/GLIBCXX it needs, whether it wants a GL context, and the info file's display name/system.
Cores that cannot run on a stock console are left out (check_cores.py's verdict: a wrong architecture, a
glibc newer than the firmware's 2.24, a library the firmware has not got), and so are RetroBoot's own app
launchers, which need its scripts, and the cores that have no .info file (the launcher sees a core only
through its .info); the list of what was left out and why goes into cores.json too.

The .info files are fixed while packing (`info_fixes.json`: the `database` a platform's games live under,
the `systemname` where there is none) - the patched file goes into the tarball, every other line of it
stays, and the core is marked `"info_fixed": true` in cores.json. A core whose .info has no `database`
and is not on the file's `no_database_ok` list fails the pack (check_cores.check_databases).

`--from-tarball` reads the cores/ and info/ of an earlier tarball instead of a RetroBoot stick, so a repack
needs the published tarball only; its cores.json's earlier left-out list is carried over.

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
import shutil
import sys
import tarfile
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_cores  # noqa: E402

# RetroBoot's own launchers (they run its scripts, not a game) - not cores for a plain RetroArch
RETROBOOT_OWN = {"app_launcher_rb", "drastic_launcher_rb"}
FIXES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "info_fixes.json")
INFO_KEYS = ("display_name", "systemname", "supported_extensions", "database", "corename")


class PackError(Exception):
    pass


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_fixes(path=FIXES_FILE):
    """-> (fixes {stem: {field: value}}, the stems allowed to have no database)"""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    allow = set()
    for key, stems in data.get("no_database_ok", {}).items():
        if not key.startswith("_"):
            allow.update(stems)
    return data.get("fixes", {}), allow


def parse_info(data):
    """The fields the manifest carries, from the bytes of a .info file."""
    out = {}
    for line in data.decode("utf-8", errors="replace").splitlines():
        m = re.match(r'\s*([A-Za-z0-9_]+)\s*=\s*"(.*)"\s*$', line)
        if m and m.group(1) in INFO_KEYS:
            out[m.group(1)] = m.group(2)
    return out


def patch_info(data, fields):
    """The .info bytes with `fields` set: an existing `key = "..."` line is replaced in place, a missing key is
    appended; every other line (and the file's line endings) stays as it was."""
    text = data.decode("utf-8", errors="surrogateescape")
    lines = text.splitlines(keepends=True)
    eol = "\r\n" if "\r\n" in text else "\n"
    for key, value in fields.items():
        new = '%s = "%s"' % (key, value)
        for i, line in enumerate(lines):
            if re.match(r"\s*%s\s*=" % re.escape(key), line):
                lines[i] = new + line[len(line.rstrip("\r\n")):]
                break
        else:
            if lines and not lines[-1].endswith(("\n", "\r")):
                lines[-1] += eol
            lines.append(new + eol)
    return "".join(lines).encode("utf-8", errors="surrogateescape")


def extract_tarball(tar_path, dest):
    """Unpack the cores/ and info/ of an earlier tarball into dest; -> its cores.json (or {})."""
    manifest = {}
    with tarfile.open(tar_path, "r:*") as tar:
        for m in tar:
            if not m.isfile():
                continue
            if m.name == "cores.json":
                manifest = json.load(tar.extractfile(m))
                continue
            parts = m.name.split("/")
            if len(parts) != 2 or parts[0] not in ("cores", "info") or parts[1] in ("", ".", ".."):
                continue
            os.makedirs(os.path.join(dest, parts[0]), exist_ok=True)
            with open(os.path.join(dest, parts[0], parts[1]), "wb") as out:
                shutil.copyfileobj(tar.extractfile(m), out)
    return manifest


def pack(cores_dir, info_dir, out_dir, date, source, fixes, allow, prior_excluded=()):
    """Pack cores_dir + info_dir into out_dir; -> (tarball path, manifest). Raises PackError when a core's
    .info has no database and is not allowed to."""
    names = sorted(n for n in os.listdir(cores_dir) if n.endswith("_libretro.so"))
    included, excluded, infos = [], [], {}
    for so in names:
        name = so[:-len("_libretro.so")]
        path = os.path.join(cores_dir, so)
        r = check_cores.analyse(path)
        why = "; ".join(r.get("problems", []))
        if name in RETROBOOT_OWN:
            why = "RetroBoot's own launcher, needs its scripts"
        info_path = os.path.join(info_dir, "%s_libretro.info" % name)
        if not why and not os.path.isfile(info_path):
            if " " in name:
                why = "no .info file and a space in its file name"
            else:
                why = "no .info file; a km_ build of the same core is in the set"
        if why:
            excluded.append({"name": name, "file": so, "why": why})
            continue
        entry = {
            "name": name, "file": so, "size": r["size"], "unpacked_size": r.get("unpacked_size"),
            "packed": r.get("container", "elf") != "elf", "sha256": sha256_of(path),
            "glibc": r.get("glibc", ""), "glibcxx": r.get("glibcxx", ""), "hw_gl": bool(r.get("hw_gl")),
        }
        with open(info_path, "rb") as f:
            data = f.read()
        if name in fixes:
            data = patch_info(data, fixes[name])
            entry["info_fixed"] = True
        entry["info"] = "%s_libretro.info" % name
        entry.update(parse_info(data))
        infos[name] = data
        included.append(entry)

    missing = check_cores.check_databases({e["name"]: e for e in included}, allow)
    if missing:
        raise PackError("no `database` in the .info of: %s - add them to tools/info_fixes.json (\"fixes\", or "
                        "\"no_database_ok\" when they are not games)" % ", ".join(missing))

    seen = {x["name"] for x in excluded}
    excluded += [x for x in prior_excluded if x["name"] not in seen]
    os.makedirs(out_dir, exist_ok=True)
    tar_path = os.path.join(out_dir, "cores-psc-%s.tar.gz" % date)
    manifest = {
        "schema": 1, "target": "psc", "source": source, "date": date,
        "count": len(included), "cores": included, "excluded": excluded,
    }
    now = int(datetime.datetime.now().timestamp())
    with tarfile.open(tar_path, "w:gz", compresslevel=6) as tar:
        for entry in included:
            tar.add(os.path.join(cores_dir, entry["file"]), arcname="cores/" + entry["file"])
            ti = tarfile.TarInfo("info/" + entry["info"])
            ti.size, ti.mtime, ti.mode = len(infos[entry["name"]]), now, 0o644
            tar.addfile(ti, io.BytesIO(infos[entry["name"]]))
        text = json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8")
        ti = tarfile.TarInfo("cores.json")
        ti.size = len(text)
        ti.mtime = now
        tar.addfile(ti, io.BytesIO(text))
    with open(os.path.join(out_dir, "cores-psc-%s.json" % date), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return tar_path, manifest


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("retroarch_dir", nargs="?", help="the stick's retroarch/ folder (cores/ and info/ inside)")
    ap.add_argument("--from-tarball", help="an earlier cores-psc-*.tar.gz to repack instead of a stick")
    ap.add_argument("--out", default="dist/release")
    ap.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d"))
    args = ap.parse_args()
    if bool(args.retroarch_dir) == bool(args.from_tarball):
        ap.error("give either the stick's retroarch/ folder or --from-tarball")

    fixes, allow = load_fixes()
    tmp = None
    try:
        if args.from_tarball:
            tmp = tempfile.mkdtemp(prefix="pack-cores-")
            old = extract_tarball(args.from_tarball, tmp)
            base, prior = tmp, old.get("excluded", [])
            source = old.get("source", "RetroBoot 1.2 (KMFD's km_* builds)")
        else:
            base, prior = args.retroarch_dir, []
            source = "RetroBoot 1.2 (KMFD's km_* builds)"
        try:
            tar_path, manifest = pack(os.path.join(base, "cores"), os.path.join(base, "info"), args.out,
                                      args.date, source, fixes, allow, prior)
        except PackError as e:
            sys.exit("pack failed: %s" % e)
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)
    print("%s: %d cores (%d left out), %.0f MB" % (tar_path, manifest["count"], len(manifest["excluded"]),
                                                   os.path.getsize(tar_path) / 1e6))
    print("  %d .info files fixed" % sum(1 for c in manifest["cores"] if c.get("info_fixed")))
    for x in manifest["excluded"]:
        print("  left out: %s - %s" % (x["name"], x["why"]))


if __name__ == "__main__":
    main()
