# The AutoBleem 2 theme for RetroArch's XMB

What RetroBoot did for RetroArch 1.9.0 (its `Autobleem.png` wallpaper, the RetroSystem icons, Oswald),
redone for 1.22.2 with the ab2 theme's look: its circuit-board background and logo, Selawik Light, white
text with shadows over the dimmed wallpaper.

| File | Goes to (on the stick) |
|---|---|
| `Autobleem2.png` | `retroarch/Retroarch themes/Autobleem2.png` - the wallpaper, 1280x720, made by `make_wallpaper.py` from AutoBleem2's `payload/themes/ab2/images/AB-EvoBack.jpg` |
| `selawik-light.ttf`, `OFL.txt` | `retroarch/fonts/` - the ab2 theme's font (Microsoft's Selawik, SIL OFL) |
| `retroarch-theme.cfg` | the keys to set in `retroarch/retroarch.cfg` |

Icons: RetroArch's own **RetroSystem** set (`retroarch/assets/xmb/retrosystem/`, `xmb_theme = "7"` in
1.22.2), which a RetroBoot stick already has - 2020's copy, though, which lacks 19 icons 1.22.2 asks for
(`disc.png`, `movie.png`/`movies.png`, and system icons such as `Sega - Mega Drive - Genesis.png`, `Sega -
Master System - Mark III.png`, `NEC - PC Engine SuperGrafx.png`); they come from
[retroarch-assets](https://github.com/libretro/retroarch-assets) `xmb/retrosystem/png/` (`disc.png` from
`xmb/monochrome/png/`). A fresh install takes the whole current set from there.

Why RetroBoot's theme came out wrong on 1.22.2: the icon-theme enum lost two entries (RetroActive,
NeoActive), so its `xmb_theme = "8"` - RetroSystem in 1.9.0 - selects Monochrome Inverted now, dark icons
on a dark wallpaper; and `menu_swap_ok_cancel_buttons` was renamed `input_menu_swap_ok_cancel_buttons`,
so Circle became OK. `retroarch-theme.cfg` has the 1.22.2 values.
