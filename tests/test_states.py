"""The save-state keys (theme/ab2-states.cfg) and the safe-write patch (retroarch/patches/safe_state_writes.patch)."""
import os
import re

import pytest

from test_theme_compat import THEME, old_install

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def keys_of(path):
    keys = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r'\s*([a-z0-9_]+)\s*=\s*"(.*)"\s*$', line)
        if m:
            keys[m.group(1)] = m.group(2)
    return keys


def test_the_state_keys():
    keys = keys_of(os.path.join(THEME, "ab2-states.cfg"))
    assert keys["savestate_auto_save"] == "true"
    assert keys["savestate_thumbnail_enable"] == "true"
    assert keys["savestate_directory"] == ":/savestates"
    for sort in ("sort_savestates_enable", "sort_savestates_by_content_enable", "savestates_in_content_dir"):
        assert keys[sort] == "false"
    # the launcher decides per launch whether a state is loaded
    assert "savestate_auto_load" not in keys


def test_other_keys_of_the_build_are_not_touched():
    # the state keys live in their own file: retroarch-psc.cfg (what an installer in the field merges) has none
    assert not [k for k in keys_of(os.path.join(THEME, "retroarch-psc.cfg")) if "savestate" in k]
    assert not [k for k in keys_of(os.path.join(THEME, "ab2-theme.cfg")) if "savestate" in k]


@pytest.mark.parametrize("existing", [None, 'savestate_auto_save = "false"\n'])
def test_an_installer_that_predates_the_file_leaves_the_state_keys_alone(tmp_path, existing):
    cfg = old_install(str(tmp_path / "stick"), THEME, existing)
    assert cfg.count("savestate_auto_save") == (0 if existing is None else 1)
    assert 'savestate_auto_save = "true"' not in cfg


def test_patch_is_applied_by_the_build_and_writes_beside_the_name():
    build = open(os.path.join(REPO, "retroarch", "build.sh"), encoding="utf-8").read()
    assert "safe_state_writes" in build
    patch = open(os.path.join(REPO, "retroarch", "patches", "safe_state_writes.patch"), encoding="utf-8").read()
    # both writers of a state, and the picture: written to .tmp and renamed over the name
    assert "a/tasks/task_save.c" in patch and "a/tasks/task_screenshot.c" in patch
    assert patch.count("save_task_commit_tmp(") >= 4          # the task, and the auto save's two ends
    assert '"%s.tmp"' in patch and "filestream_rename" in patch
    assert "filestream_delete(tmp)" in patch                   # a failed write leaves the old state as it was
