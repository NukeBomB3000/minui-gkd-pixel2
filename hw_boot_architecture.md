---
name: hw-boot-architecture
description: "Hardware-Details, Partitionslayout und Boot-Chain des GKD Pixel 2"
metadata: 
  node_type: memory
  type: project
  originSessionId: 203eee94-5278-4bdb-b107-73bc0e577756
---

## Hardware

- **SoC:** Rockchip RK3326S (PX30-kompatibel, aarch64, **Cortex-A35**)
- **GPU:** Mali-G31 (arm_release_ver: g13p0-01eac0, rk_so_ver: 11)
- **Display:** MIPI DSI, Sitronix ST7703, 480×640 physisch (portrait), rotiert → 640×480 effektiv
- **Framebuffer:** `/dev/fb0` — 480×640, **32bpp** (Rotation auf DRM-Ebene)
- **Kein eMMC** — bootet ausschließlich von SD-Karte
- **Input-Events:** `/dev/input/event0` (Power), `event1` (Volume), `event2` (Buttons/Sticks)
- **Backlight:** `/sys/class/backlight/backlight/brightness` (0–255), `bl_power` (0=AN, 4=AUS)

## Button-Keycodes (Linux evdev)

| Button | Keycode | Hex |
|--------|---------|-----|
| D-Pad Up | 544 | BTN_DPAD_UP |
| D-Pad Down | 545 | BTN_DPAD_DOWN |
| D-Pad Left | 546 | BTN_DPAD_LEFT |
| D-Pad Right | 547 | BTN_DPAD_RIGHT |
| A | 305 | BTN_EAST |
| B | 304 | BTN_SOUTH |
| X | 307 | BTN_NORTH |
| Y | 308 | BTN_WEST |
| L1 | 310 | BTN_TL |
| R1 | 311 | BTN_TR |
| L2 | 312 | BTN_TL2 |
| R2 | 313 | BTN_TR2 |
| Select | 314 | BTN_SELECT |
| Start | 315 | BTN_START |
| Menu | **704** | BTN_TRIGGER_HAPPY1 |
| Power | 116 | KEY_POWER |
| Vol Up | **115** | KEY_VOLUMEUP |
| Vol Down | **114** | KEY_VOLUMEDOWN |

## SD-Karten-Partitionslayout (GPT)

| Nr | Name    | Start-Sektor | Ende-Sektor | Größe  | Typ   |
|----|---------|-------------|-------------|--------|-------|
| 1  | EMUELEC | 32768        | 1.081.343   | 512 MB | FAT32 |
| 2  | storage | 1.081.344    | 3.178.495   | 1 GB   | ext4  |
| 3  | ROMS    | 3.178.496    | Ende        | Rest   | exFAT |

Partition 1 beginnt bei Sektor **32768** (16 MB für Bootloader reserviert).

## Laufende System-Pfade

| Pfad | Beschreibung |
|------|-------------|
| `/flash` | Partition 1 (FAT32, read-only by default) |
| `/storage` | Partition 2 (ext4) |
| `/storage/games-external` | Partition 3 (exFAT) — primärer Mount |
| `/storage/roms` | Partition 3 (exFAT) — zweiter Mount |
| `/mnt/SDCARD` | Symlink → `/storage/games-external` |
| `/mnt/SDCARD/.system/gkdpixel2/` | MinUI-System |
| `/mnt/SDCARD/.userdata/gkdpixel2/msettings.bin` | MinUI-Settings |
| `/mnt/SDCARD/minui_boot.log` | Boot-Log (auf ROMS, nicht /flash!) |

## Boot-Chain (ROCKNIX + MinUI)

1. RK3326S-ROM → idbloader (Sektor 64) → U-Boot
2. U-Boot lädt `Image` + DTB + `SYSTEM` (SquashFS) von EMUELEC
3. Kernel → systemd → `sway.service` (Wayland-Compositor, hält KMS/DRM)
4. `launchersway.service` (`Requires=sway.service`) → `start_launcher.sh`
5. `start_launcher.sh` → `/mnt/SDCARD/.tmp_update/updater`
6. Updater: `bl_power=0`, `. /etc/profile`, startet `launch.sh`
7. `launch.sh`: `SDL_VIDEODRIVER=wayland`, `/usr/lib` zuerst in `LD_LIBRARY_PATH`, startet `minui.elf`
8. `minui.elf`: SDL1 → sdl12-compat → SDL2 Wayland-Fenster (fullscreen) → Sway composited

**Wichtig:** Sway NICHT killen! `launchersway.service` hat `Requires=sway.service` — Sway-Tod killt uns mit.

## Dateien im Arbeitsverzeichnis

| Datei/Dir | Beschreibung |
|-----------|-------------|
| `Image` | ARM64-Kernel (19,7 MB) |
| `rk3326s-gkd-pixel2.dtb` | Device Tree Blob |
| `SYSTEM` | SquashFS-Rootfs (~415 MB) |
| `rootfs/` | Extrahierter Inhalt von SYSTEM |
| `stock_boot_sectors.img` | Erste 64 MB der Stock-SD (Bootloader) |
| `spruce/` | Spruce-OS-Plattform-Configs |
| `setup_sd.sh` | SD-Karte vollständig einrichten |
| `minui-src/` | MinUI-Quellcode mit gkdpixel2-Platform |
