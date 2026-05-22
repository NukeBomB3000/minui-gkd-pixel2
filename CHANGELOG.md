# Changelog

## Unreleased

### Added
- **Files (DinguxCommander)**: File manager tool, accessible via Tools menu. SDL2 build for aarch64, runs as Wayland client.
- **Music Player (MUS)**: Simple music player based on mpv. Plays MP3, FLAC, OGG and other formats from `Roms/Music (MUS)/`.
- **Extra emulators** via MinUI extras (rgb30, self-contained with bundled cores):
  - Game Boy Advance (MGBA) — mGBA core
  - Super Game Boy (SGB)
  - Sega Game Gear (GG)
  - Sega Master System (SMS)
  - TurboGrafx-16 (PCE)
  - Neo Geo Pocket (NGP) / Neo Geo Pocket Color (NGPC)
  - Pokémon mini (PKM)
  - Super Nintendo Entertainment System (SUPA)
  - Virtual Boy (VB)
  - Pico-8 (P8)

### Changed
- Build script restructured: `create_sd_image.sh` replaces `build_and_image.sh`
- Firmware binaries (`SYSTEM`, `Image`, `DTB`, ELFs) now live in `firmware/` (gitignored)
- MinUI base + extras consolidated into `minui/` (gitignored); updating MinUI requires only replacing the contents of `minui/`
- ROM/Bios directory structure driven entirely from `minui/Roms/` and `minui/Bios/` — no hardcoded lists in build script
- Removed dev ROM bundling mechanism (no space on EMUELEC partition before first-boot resize)

## 2026-05-20 — Initial release

- MinUI port for GKD Pixel 2 (RK3326S, aarch64, ROCKNIX/Wayland)
- Base emulators: GB, GBC, GBA, FC, SFC, MD, PS
- Platform code: keymon, libmsettings, platform.c/h
