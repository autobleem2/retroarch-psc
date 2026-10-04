"""An installer already in the field (autobleem-core 99805c5, InstallerJob::retroarch) meets the new zip.

Its Place list copies theme/Autobleem2.png, theme/selawik-light.ttf and theme/OFL.txt (a missing one is skipped),
reads theme/retroarch-psc.cfg and merges EVERY key of it into the user's retroarch.cfg. It knows nothing of
theme/assets or theme/ab2-theme.cfg. This simulates exactly that against the files make package-retroarch zips
(theme/ as it is in the repo), and proves the result equals what the previous release's theme/ gave."""
import os
import re
import subprocess

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..")
THEME = os.path.join(REPO, "theme")
# the previous release's theme (before the ab2 set): the installer in the field was written against this
NL = chr(10)
OLD_REV = "f97b421"
OLD_PLACES = (("theme/Autobleem2.png", "Retroarch themes/Autobleem2.png"),
              ("theme/selawik-light.ttf", "fonts/selawik-light.ttf"),
              ("theme/OFL.txt", "fonts/OFL.txt"))


def git_show(path):
    return subprocess.run(["git", "-C", REPO, "show", "%s:%s" % (OLD_REV, path)], capture_output=True).stdout


def old_merge(cfg_text, keys_text):
    """installer_job.cpp 99805c5: each key line of the build's cfg replaces the key's line, or is appended."""
    text = cfg_text
    for raw in keys_text.splitlines():
        t = raw.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        key = t.split("=", 1)[0].strip()
        pos, found = 0, False
        while pos < len(text):
            end = text.find(NL, pos)
            end = len(text) if end < 0 else end
            existing = text[pos:end]
            if "=" in existing and existing.split("=", 1)[0].strip() == key:
                text = text[:pos] + t + text[end:]
                found = True
                break
            pos = end + 1
        if not found:
            if text and not text.endswith(NL):
                text += NL
            text += t + NL
    return text


def old_install(stick, theme_dir, existing_cfg=None):
    for src, dst in OLD_PLACES:
        path = os.path.join(theme_dir, src[len("theme/"):])
        if not os.path.exists(path):
            continue  # `if (!exists) continue`
        out = os.path.join(stick, dst)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(path, "rb") as f, open(out, "wb") as g:
            g.write(f.read())
    with open(os.path.join(theme_dir, "retroarch-psc.cfg"), encoding="utf-8") as f:
        keys = f.read()
    return old_merge(existing_cfg if existing_cfg is not None else "", keys)


def tree(root):
    return {os.path.relpath(os.path.join(b, f), root).replace(os.sep, "/"): open(os.path.join(b, f), "rb").read()
            for b, _d, files in os.walk(root) for f in files}


def test_old_places_exist_in_the_new_theme_unchanged():
    for src, _dst in OLD_PLACES:
        path = os.path.join(THEME, src[len("theme/"):])
        assert os.path.isfile(path), src
        assert open(path, "rb").read() == git_show(src), src  # byte for byte what the old release shipped


def test_old_cfg_keys_and_meaning_unchanged():
    new = open(os.path.join(THEME, "retroarch-psc.cfg"), "rb").read()
    assert new == git_show("theme/retroarch-psc.cfg")


@pytest.mark.parametrize("existing", [None, 'video_smooth = "true"\nxmb_theme = "8"\nmenu_driver = "xmb"\n'])
def test_old_installer_with_the_new_zip_gives_what_it_gave_before(tmp_path, existing):
    old_theme = tmp_path / "old"
    for name in ("Autobleem2.png", "selawik-light.ttf", "OFL.txt", "retroarch-psc.cfg"):
        (old_theme / name).parent.mkdir(parents=True, exist_ok=True)
        (old_theme / name).write_bytes(git_show("theme/" + name))
    stick_old, stick_new = str(tmp_path / "stick_old"), str(tmp_path / "stick_new")
    cfg_old = old_install(stick_old, str(old_theme), existing)
    cfg_new = old_install(stick_new, THEME, existing)
    assert tree(stick_new) == tree(stick_old)
    assert cfg_new == cfg_old
    # and none of the new theme's keys reaches a cfg through the old installer
    for key in ("ozone_menu_color_theme", "menu_use_preferred_system_color_theme", "menu_dynamic_wallpaper_enable"):
        assert key not in cfg_new
    assert 'xmb_theme = "6"' not in cfg_new


def test_ab2_keys_live_only_in_their_own_file():
    keys = {}
    for line in open(os.path.join(THEME, "ab2-theme.cfg"), encoding="utf-8"):
        m = re.match(r'\s*([a-z0-9_]+)\s*=\s*"(.*)"\s*$', line)
        if m:
            keys[m.group(1)] = m.group(2)
    assert keys["xmb_theme"] == "6" and keys["xmb_menu_color_theme"] == "10"
    assert keys["ozone_menu_color_theme"] == "1"
    assert keys["menu_use_preferred_system_color_theme"] == "false"
    assert keys["menu_dynamic_wallpaper_enable"] == "false"
    assert keys["menu_wallpaper"] == ":/Retroarch themes/ab2-1280x720.png"
    assert os.path.isfile(os.path.join(THEME, "ab2-1280x720.png"))
    assert keys["xmb_font"].startswith(":/assets/")
    assert os.path.isfile(os.path.join(THEME, keys["xmb_font"][2:]))
