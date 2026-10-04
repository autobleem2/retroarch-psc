"""The VERSION file in the RetroArch zip: its FIRST line is the bare release tag (the launcher and the installer
compare that line with the site catalog's "version"), the key=value lines follow. Both writers (retroarch/build.sh
and the Dockerfile's retroarch-out stage) are run for real here, and tools/make_manifest.py must still read the
key=value part."""
import os
import re
import shutil
import subprocess
import sys

import pytest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import make_manifest  # noqa: E402

BASH = shutil.which("bash")


def writer_snippet(relpath, target):
    """The printf ... > <target> command of a file, with its output redirected to $OUT."""
    with open(os.path.join(ROOT, relpath), encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"printf '%s-%s\\n.*?> *" + re.escape(target), text, re.S)
    assert m, "no VERSION writer in " + relpath
    snippet = m.group(0).replace("\\\n", " ")
    return snippet[: snippet.rindex(">")] + '> "$OUT"'


@pytest.mark.skipif(BASH is None, reason="no bash")
@pytest.mark.parametrize("relpath,target", [("retroarch/build.sh", '"$OUT_DIR/VERSION"'),
                                            ("Dockerfile", "/build/output/VERSION")])
def test_first_line_is_the_tag(tmp_path, relpath, target):
    out = tmp_path / "VERSION"
    snippet = writer_snippet(relpath, target)
    env = dict(os.environ, RETROARCH_VERSION="v1.22.2", PSC_BUILD_NUM="7", OUT=out.as_posix())
    subprocess.run([BASH, "-c", snippet], check=True, env=env)
    lines = out.read_text(encoding="utf-8").splitlines()
    assert lines[0] == "v1.22.2-7"
    assert "=" not in lines[0]
    assert "retroarch_version=v1.22.2" in lines
    assert "psc_build=7" in lines
    kv = make_manifest.read_kv(str(out))
    assert kv["retroarch_version"] == "v1.22.2"
    assert kv["psc_build"] == "7"
    assert "v1.22.2-7" not in kv
