"""Tests for the RetroArch theme: tools/sync_theme.py mirrors a set whole (idempotent, new names come along,
dropped names go), and the theme/ in the repo is complete (the cfg keys and the old-installer check: test_theme_compat.py)."""
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
THEME = os.path.join(HERE, "..", "theme")
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import sync_theme  # noqa: E402


def put(root, rel, data=b"x"):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def make_set(root):
    for rel in ("custom/png/bg.png", "custom/png/setting.png", "custom/font.ttf", "monochrome/png/setting.png",
                "ozone/png/sidebar/settings.png", "ozone/png/dark/check.png", "ozone/regular.ttf", "ozone/bold.ttf",
                "wallpaper/ab2-1280x720.png", "wallpaper/ab2-1920x1080.png", "fonts-OFL.txt"):
        put(root, rel)


def tree(root):
    return sorted(os.path.relpath(os.path.join(b, f), root).replace(os.sep, "/")
                  for b, _d, files in os.walk(root) for f in files)


def test_sync_places_everything_where_the_installer_looks(tmp_path):
    src, out = str(tmp_path / "set"), str(tmp_path / "theme")
    make_set(src)
    sync_theme.sync(src, out)
    got = tree(out)
    for rel in ("assets/xmb/custom/png/bg.png", "assets/xmb/custom/font.ttf", "assets/xmb/custom/OFL.txt",
                "assets/xmb/monochrome/png/setting.png", "assets/ozone/png/sidebar/settings.png",
                "assets/ozone/png/dark/check.png", "assets/ozone/regular.ttf", "assets/ozone/bold.ttf",
                "assets/ozone/OFL.txt", "ab2-1280x720.png"):
        assert rel in got
    assert not any("1920" in g for g in got)  # the console is 720p


def test_sync_takes_the_whole_folder_and_is_idempotent(tmp_path):
    src, out = str(tmp_path / "set"), str(tmp_path / "theme")
    make_set(src)
    sync_theme.sync(src, out)
    first = tree(out)
    assert sync_theme.sync(src, out) == len(first)
    assert tree(out) == first
    # phase 2: new names in the same folders come along, a dropped one goes
    put(src, "custom/png/menu_overlay.png")
    put(src, "monochrome/png/menu_overlay.png")
    os.remove(os.path.join(src, "custom/png/setting.png"))
    sync_theme.sync(src, out)
    got = tree(out)
    assert "assets/xmb/custom/png/menu_overlay.png" in got
    assert "assets/xmb/monochrome/png/menu_overlay.png" in got
    assert "assets/xmb/custom/png/setting.png" not in got


def test_sync_stops_on_an_incomplete_set(tmp_path):
    src = str(tmp_path / "set")
    make_set(src)
    os.remove(os.path.join(src, "fonts-OFL.txt"))
    with pytest.raises(SystemExit):
        sync_theme.sync(src, str(tmp_path / "theme"))


def test_repo_theme_is_the_ab2_set():
    for rel in ("ab2-1280x720.png", "assets/xmb/custom/font.ttf", "assets/xmb/custom/png/bg.png",
                "assets/xmb/custom/OFL.txt", "assets/xmb/monochrome/png/setting.png", "assets/ozone/regular.ttf",
                "assets/ozone/bold.ttf", "assets/ozone/OFL.txt", "assets/ozone/png/cursor_border.png"):
        assert os.path.isfile(os.path.join(THEME, rel)), rel
