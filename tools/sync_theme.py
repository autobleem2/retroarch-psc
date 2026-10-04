#!/usr/bin/env python3
"""Mirror the designer's RetroArch theme set into theme/ (the folders the release zip carries).

    sync_theme.py <set-dir>       (the set's README.md has the table this follows)

The WHOLE folders are mirrored, not a list of names: a name the designer adds later comes along, and a name
dropped from the set leaves theme/ too.

    <set>/custom/              -> theme/assets/xmb/custom/            (png/ + bg.png + font.ttf)
    <set>/monochrome/png/      -> theme/assets/xmb/monochrome/png/    (Ozone loads only this; overwrites stock)
    <set>/ozone/               -> theme/assets/ozone/                 (png/ + bold.ttf + regular.ttf)
    <set>/wallpaper/ab2-1280x720.png -> theme/ab2-1280x720.png        (the console is 720p)
    <set>/fonts-OFL.txt        -> theme/assets/xmb/custom/OFL.txt and theme/assets/ozone/OFL.txt (next to the fonts)

The installer copies theme/assets over RetroArch's assets folder, keeping each stock file it replaces once as
<name>.prab2 (installer_job.cpp, applyThemeTree).
"""
import argparse
import os
import shutil
import sys

WALLPAPER = "ab2-1280x720.png"
# (source under the set, destination under theme/)
TREES = (("custom", "assets/xmb/custom"),
         ("monochrome/png", "assets/xmb/monochrome/png"),
         ("ozone", "assets/ozone"))
OFL_TO = ("assets/xmb/custom/OFL.txt", "assets/ozone/OFL.txt")


def mirror(src, dst):
    """dst becomes an exact copy of src; returns the number of files copied."""
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    count = 0
    for base, _dirs, files in os.walk(src):
        rel = os.path.relpath(base, src)
        out = dst if rel == "." else os.path.join(dst, rel)
        os.makedirs(out, exist_ok=True)
        for name in sorted(files):
            shutil.copyfile(os.path.join(base, name), os.path.join(out, name))
            count += 1
    return count


def sync(set_dir, theme_dir):
    total = 0
    for src, dst in TREES:
        path = os.path.join(set_dir, src)
        if not os.path.isdir(path):
            sys.exit("missing in the set: %s" % src)
        total += mirror(path, os.path.join(theme_dir, dst))
    wallpaper = os.path.join(set_dir, "wallpaper", WALLPAPER)
    if not os.path.isfile(wallpaper):
        sys.exit("missing in the set: wallpaper/%s" % WALLPAPER)
    shutil.copyfile(wallpaper, os.path.join(theme_dir, WALLPAPER))
    ofl = os.path.join(set_dir, "fonts-OFL.txt")
    if not os.path.isfile(ofl):
        sys.exit("missing in the set: fonts-OFL.txt")
    for dst in OFL_TO:
        shutil.copyfile(ofl, os.path.join(theme_dir, dst))
    return total + 1 + len(OFL_TO)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("set_dir")
    ap.add_argument("--theme-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "theme"))
    args = ap.parse_args()
    print("theme/: %d files from %s" % (sync(args.set_dir, args.theme_dir), args.set_dir))


if __name__ == "__main__":
    main()
