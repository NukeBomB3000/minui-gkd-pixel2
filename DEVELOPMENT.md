# Development Guide

## Architecture

The GKD Pixel 2 runs ROCKNIX (a JELOS-based Linux distro). MinUI runs on top of it:

```
RK3326S ROM → U-Boot → Linux Kernel → systemd → Sway (Wayland compositor)
→ launchersway.service → start_launcher.sh
→ /mnt/SDCARD/.tmp_update/updater → launch.sh → minui.elf
```

MinUI uses **SDL2 with Wayland backend** — the same path as the stock ROCKNIX UI.
`/mnt/SDCARD` → `/storage/games-external` → ROMS partition (exFAT).

## Platform files

| File | Purpose |
|------|---------|
| `platform/platform.h` | Screen size (640×480), button keycodes, SDCARD_PATH |
| `platform/platform.c` | SDL2 video init, raw evdev input, backlight, shutdown |
| `platform/makefile.env` | Compiler flags: `SDL = SDL2`, `-mtune=cortex-a35` |
| `keymon/keymon.c` | Volume/brightness key monitoring |
| `libmsettings/msettings.c` | Settings persistence (brightness default=7) |

## Key implementation decisions

### SDL2/Wayland (not kmsdrm)
Sway (Wayland compositor) holds the KMS/DRM device exclusively. We run MinUI as
a Wayland client inside Sway — same approach as the stock `show_msg` binary.
`SDL_VIDEODRIVER=wayland` must be set. `/usr/lib/libSDL2` from ROCKNIX is used
(not a bundled SDL).

### Input via raw evdev
MinUI reads `/dev/input/event0-3` directly (same as rgb30 platform).
Key codes specific to GKD Pixel 2:
- Menu button: `704` (BTN_TRIGGER_HAPPY1)
- Volume Up: `115`, Volume Down: `114`

### Shutdown
`PLAT_powerOff()` writes `/tmp/poweroff` and calls `exit(0)`.
`launch.sh`'s while-loop detects the file and calls `poweroff`.
(The rgb30 approach of `system("shutdown")` + `while(1) pause()` was unreliable.)

### First-boot partition creation
The image contains no ROMS partition. On first boot, the modified `install.sh`
(in the repacked SYSTEM squashfs) creates the ROMS partition at full card size.
`parted -s -f` with explicit sector numbers handles the GPT backup header
mismatch that occurs when a small image is flashed to a large card.

### SYSTEM repacking
The ROCKNIX SYSTEM squashfs must be repacked with `-b 262144 -comp gzip` to
match the original block size. Different parameters cause boot failure.

## Building

```bash
# First time: sets up Docker toolchain (~5 min)
sudo ./build_and_image.sh

# Subsequent builds (toolchain already built):
sudo ./build_and_image.sh
```

The script:
1. Downloads MinUI source and assets (if not cached)
2. Builds all gkdpixel2 binaries inside Docker (rgb30 toolchain)
3. Repacks SYSTEM squashfs with modified install.sh
4. Creates flashable GPT image

## Modifying MinUI

Edit files in `platform/`, `keymon/`, or `libmsettings/`, then rebuild:
```bash
sudo ./build_and_image.sh
```

## Button mapping

From `/dev/input/event2` (EV_KEY events):

```c
RAW_UP=544, RAW_DOWN=545, RAW_LEFT=546, RAW_RIGHT=547  // BTN_DPAD_*
RAW_A=305, RAW_B=304, RAW_X=307, RAW_Y=308
RAW_L1=310, RAW_R1=311, RAW_L2=312, RAW_R2=313
RAW_SELECT=314, RAW_START=315
RAW_MENU=704  // BTN_TRIGGER_HAPPY1
RAW_POWER=116, RAW_PLUS=115, RAW_MINUS=114
```

## Logs

After booting, logs are at:
- `/flash/minui_boot.log` — boot/updater log (on EMUELEC FAT32 partition)
- `/mnt/SDCARD/.userdata/gkdpixel2/logs/minui.txt` — MinUI runtime log
