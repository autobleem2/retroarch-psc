# The AutoBleem 2 theme for RetroArch 1.22.2 (XMB and Ozone)

The ab2.0.0 look (the designer's set): tiles with a cyan glyph on the XMB tabs, white glyphs on the rows, Red Hat
Text, the circuit-board "mozaika" wallpaper. Ozone gets the same glyphs, tinted.

| In the zip | Goes to (on the stick, under `RetroArch/bin/`) |
|---|---|
| `assets/xmb/custom/` (`png/`, `bg.png`, `font.ttf`, `OFL.txt`) | `assets/xmb/custom/` - XMB, `xmb_theme = "6"` (Custom) |
| `assets/xmb/monochrome/png/` | `assets/xmb/monochrome/png/` - Ozone loads only this folder; the stock files are kept once as `<name>.prab2` |
| `assets/ozone/` (`png/`, `bold.ttf`, `regular.ttf`, `OFL.txt`) | `assets/ozone/` (stock files kept as `.prab2`) |
| `ab2-1280x720.png` | `Retroarch themes/ab2-1280x720.png` - the wallpaper (the console is 720p) |
| `retroarch-psc.cfg` | the keys to set in `retroarch.cfg` |

The installer (autobleem-core, `installer_job.cpp`) does it on install and on an update of a stick, when the
RetroArch zip is new to it: the `assets` tree goes over RetroArch's own assets AFTER libretro's assets bundle
(a folder of ours first would make a fresh install skip the bundle), every file of it - nothing is listed by name;
in `retroarch.cfg` of an existing stick only the keys of `retroarch-psc.cfg` are replaced, everything else the
user set stays. A stick with the same RetroArch version already on it is not touched: a theme change needs a new
release tag.

`tools/sync_theme.py <set-dir>` fills `theme/` from the designer's set folder (the whole folders, so phase 2
icons added to the set come along); `tests/test_theme.py` checks it and that the cfg points at files that exist.

`retroarch-psc.cfg` also holds the keys that changed meaning since RetroBoot's 1.9.0: `xmb_theme` ("8" was
RetroSystem there, it is Monochrome Inverted now), and `quit_on_close_content = "2"` for Close Content to return
to the launcher as 1.9.0 did.
