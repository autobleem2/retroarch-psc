"""Unit tests for tools/pack_retroboot_cores.py: the .info fixes, the no-.info skip, the database check and
--from-tarball, on tiny fake tarballs (the cores are a few bytes; check_cores.analyse is stubbed)."""
import io
import json
import os
import sys
import tarfile

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import check_cores  # noqa: E402
import pack_retroboot_cores as pack  # noqa: E402


@pytest.fixture(autouse=True)
def fake_analyse(monkeypatch):
    def analyse(path):
        return {"file": os.path.basename(path), "size": os.path.getsize(path), "container": "elf",
                "unpacked_size": os.path.getsize(path), "glibc": "2.17", "glibcxx": "", "hw_gl": False,
                "problems": []}
    monkeypatch.setattr(check_cores, "analyse", analyse)


def info(**fields):
    return "".join('%s = "%s"\n' % kv for kv in fields.items()).encode()


def make_tarball(path, cores, infos, manifest=None):
    """cores: {stem: bytes}; infos: {stem: bytes}"""
    with tarfile.open(path, "w:gz") as tar:
        def add(name, data):
            ti = tarfile.TarInfo(name)
            ti.size = len(data)
            tar.addfile(ti, io.BytesIO(data))
        for stem, data in cores.items():
            add("cores/%s_libretro.so" % stem, data)
        for stem, data in infos.items():
            add("info/%s_libretro.info" % stem, data)
        add("cores.json", json.dumps(manifest or {"excluded": []}).encode())
    return path


def repack(tmp_path, cores, infos, manifest=None):
    src = make_tarball(str(tmp_path / "in.tar.gz"), cores, infos, manifest)
    work = str(tmp_path / "x")
    old = pack.extract_tarball(src, work)
    fixes, allow = pack.load_fixes()
    tar_path, man = pack.pack(os.path.join(work, "cores"), os.path.join(work, "info"), str(tmp_path / "out"),
                              "20261003", "test", fixes, allow, old.get("excluded", []))
    return tar_path, man


def tar_text(tar_path, name):
    with tarfile.open(tar_path) as tar:
        return tar.extractfile(name).read().decode()


def test_patch_info_replaces_in_place_and_appends():
    src = b'display_name = "X"\nsystemname = ""\ndatabase = "old"\nlicense = "GPL"\n'
    out = pack.patch_info(src, {"database": "Atari - ST", "systemname": "ST", "extra": "1"}).decode()
    assert out == 'display_name = "X"\nsystemname = "ST"\ndatabase = "Atari - ST"\nlicense = "GPL"\nextra = "1"\n'


def test_patch_info_keeps_crlf_and_no_trailing_newline():
    out = pack.patch_info(b'a = "1"\r\nb = "2"', {"database": "D"})
    assert out == b'a = "1"\r\nb = "2"\r\ndatabase = "D"\r\n'


def test_fixes_json_names_the_requested_databases():
    fixes, _ = pack.load_fixes()
    for stem in ("km_puae_xtreme", "km_puae_xtreme_accuracy", "km_puae_xtreme_amped", "km_uae4arm",
                 "km_uae4arm_xtreme"):
        assert fixes[stem] == {"database": "Commodore - Amiga"}
    assert fixes["km_hatari"]["database"] == "Atari - ST"
    assert fixes["km_quasi88"]["database"] == "NEC - PC-8001 - PC-8801"
    assert fixes["km_jumpnbump"] == {"database": "Jump 'n Bump", "systemname": "Jump 'n Bump"}
    assert fixes["sameduck"]["database"] == "Mega Duck"
    assert fixes["km_superbroswar"]["database"] == "Super Bros War"


def test_repack_applies_fixes_marks_cores_and_keeps_other_lines(tmp_path):
    cores = {"km_hatari": b"so", "km_gambatte": b"so"}
    infos = {"km_hatari": info(display_name="Atari - ST (km_Hatari)", systemid="atari_st"),
             "km_gambatte": info(display_name="GB", database="Nintendo - Game Boy")}
    tar_path, man = repack(tmp_path, cores, infos)
    hatari = tar_text(tar_path, "info/km_hatari_libretro.info")
    assert 'display_name = "Atari - ST (km_Hatari)"\nsystemid = "atari_st"\ndatabase = "Atari - ST"\n' == hatari
    assert tar_text(tar_path, "info/km_gambatte_libretro.info").endswith('database = "Nintendo - Game Boy"\n')
    by = {c["name"]: c for c in man["cores"]}
    assert by["km_hatari"]["info_fixed"] is True and by["km_hatari"]["database"] == "Atari - ST"
    assert "info_fixed" not in by["km_gambatte"]
    assert json.loads(tar_text(tar_path, "cores.json"))["count"] == 2


def test_cores_without_info_are_left_out_with_a_reason(tmp_path):
    cores = {"fceumm": b"so", "km_mame_xtreme_low profile": b"so", "km_gambatte": b"so"}
    infos = {"km_gambatte": info(database="Nintendo - Game Boy")}
    _, man = repack(tmp_path, cores, infos)
    assert [c["name"] for c in man["cores"]] == ["km_gambatte"]
    why = {x["name"]: x["why"] for x in man["excluded"]}
    assert why["fceumm"] == "no .info file; a km_ build of the same core is in the set"
    assert why["km_mame_xtreme_low profile"] == "no .info file and a space in its file name"


def test_earlier_excluded_list_is_carried_over(tmp_path):
    prior = {"excluded": [{"name": "old", "file": "old_libretro.so", "why": "glibc"}]}
    _, man = repack(tmp_path, {"km_gambatte": b"so"}, {"km_gambatte": info(database="GB")}, prior)
    assert [x["name"] for x in man["excluded"]] == ["old"]


def test_a_game_core_without_database_fails_the_pack(tmp_path):
    with pytest.raises(pack.PackError) as e:
        repack(tmp_path, {"km_newcore": b"so"}, {"km_newcore": info(display_name="New", systemname="New Console")})
    assert "km_newcore" in str(e.value)


def test_allowlisted_non_games_pass_without_database(tmp_path):
    cores = {"km_ffmpeg": b"so", "km_2048": b"so", "fbalpha2012_cps1": b"so"}
    infos = {s: info(display_name=s) for s in cores}
    _, man = repack(tmp_path, cores, infos)
    assert man["count"] == 3


def test_check_databases_ignores_km_prefix():
    assert check_cores.check_databases({"km_gme": {}, "x": {}, "y": {"database": "D"}}, {"gme"}) == ["x"]


def test_main_from_tarball(tmp_path, monkeypatch, capsys):
    src = make_tarball(str(tmp_path / "cores-psc-20260920.tar.gz"), {"km_hatari": b"so", "fceumm": b"so"},
                       {"km_hatari": info(display_name="H")})
    out = str(tmp_path / "out")
    monkeypatch.setattr(sys, "argv", ["pack", "--from-tarball", src, "--out", out, "--date", "20261003"])
    pack.main()
    assert os.path.isfile(os.path.join(out, "cores-psc-20261003.tar.gz"))
    assert os.path.isfile(os.path.join(out, "cores-psc-20261003.json"))
    text = capsys.readouterr().out
    assert "1 cores (1 left out)" in text and "left out: fceumm" in text
