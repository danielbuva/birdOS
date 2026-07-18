# Deliberately added muOS cores

These are the only libretro cores added to the fresh 2601.1 image. They were
downloaded from the official MustardOS `extra` repository in July 2026. The ZIP
member timestamps are January 2026, matching the generation of the installed
muOS/RetroArch build.

| Installed file | Official archive | Archive SHA-256 | Installed SHA-256 |
| --- | --- | --- | --- |
| `gw_libretro.so` | <https://github.com/MustardOS/extra/raw/main/core/gw_libretro.so.zip> | `149815b2e422b4c7fd07e65ce007b006d07e7bf0a3de66e9f4bbd116a27c15f3` | `21988b888fd60c6295963de31939d4c993e1f243e86b6dc8ea0603af4e3f67dd` |
| `bluemsx_libretro.so` | <https://github.com/MustardOS/extra/raw/main/core/bluemsx_libretro.so.zip> | `bc8436a7d1d37887134ce72f194041df4078d195a38d5b13f16a5deca36f0d1c` | `b69f9c8fcf3503e8ce3d2da403c1ee6d6af12703e26e8252b9ce9ced0a56b9c5` |
| `fake08_libretro.so` | <https://github.com/MustardOS/extra/raw/main/core/fake08_libretro.so.zip> | `0f015bafb071393830f4b5c11ca22ed965d3025a65955d94a075a70b4fef00b5` | `92ff81b653508136b76707f4c1c57bc6e03e4003c04efa5495ce8b0c2c92e877` |

All three installed files were independently checked as stripped, dynamically
linked AArch64 ELF shared objects before being added. The build revision covers
their exact contents, and user-init copies them into `/opt/muos/share/core`
only when that revision changes.
