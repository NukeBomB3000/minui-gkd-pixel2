---
name: project-minui-pixel2
description: Ziel und aktueller Stand des MinUI-Ports für den GKD Pixel 2
metadata: 
  node_type: memory
  type: project
  originSessionId: 203eee94-5278-4bdb-b107-73bc0e577756
---

## Status: FERTIG ✓

MinUI läuft auf dem GKD Pixel 2. Flashbares Image (`gkdpixel2-minui.img.xz`) wird mit `create_sd_image.sh` gebaut.

## Was funktioniert

- Display 640×480 ✓
- Backlight ✓
- Buttons, D-Pad, Schultertasten, Menu (704), Power (116) ✓
- Lautstärke (Vol Up=115, Vol Down=114) ✓
- Ton (ALSA) ✓
- Sleep / Wake ✓
- Shutdown (via `/tmp/poweroff` + `exit(0)`) ✓
- Alle Emulatoren inkl. PS1 ✓
- Flashbares Image mit automatischer ROMS-Partition-Erstellung beim ersten Boot ✓

## Image erstellen

```bash
cd /home/norman/GKDPIXEL2
sudo ./create_sd_image.sh
# Ausgabe: gkdpixel2-minui.img.xz (~200-400MB)
```

## Boot-Flow

**Erster Boot** (via `first_run.txt` → modifiziertes `install.sh` im SYSTEM):
1. ROMS-Partition anlegen: `parted -s -f ... mkpart ROMS fat32 3178496s ${LAST_USABLE}s`
   - `-f` flag behebt GPT-Backup-Header-Position automatisch
   - Explizite Sektornummer statt `100%` (wegen GPT-Backup-Problem beim Image-Flash)
2. exFAT formatieren
3. MinUI aus `minui.tar` (auf EMUELEC) extrahieren
4. Reboot

**Normaler Boot:**
- systemd → Sway → launchersway.service → `start_launcher.sh`
- `start_launcher.sh` findet `/mnt/SDCARD/.tmp_update/updater` → ausführen
- Updater: `bl_power=0`, brightness=96, `. /etc/profile`, startet `launch.sh`
- `launch.sh`: `SDL_VIDEODRIVER=wayland`, startet `minui.elf`

## Build-Konfiguration

- Source: `minui-src/workspace/gkdpixel2/`
- Toolchain: Docker `rgb30-toolchain`
- `makefile.env`: `SDL = SDL2`, `-mtune=cortex-a35 -march=armv8-a`
- `platform.c`: rgb30-Basis, RAW_MENU=704, `PLAT_enableBacklight(1)` in initVideo, Shutdown via `/tmp/poweroff`+`exit(0)`
- `keymon.c`: CODE_MENU=704, CODE_PLUS=115, CODE_MINUS=114
- `libmsettings.c`: Default brightness=7 (raw=96)
- Settings-Datei: `msettings.bin` (nicht settings.bin!)

## Wichtige Erkenntnisse

- SDL2/Wayland (nicht kmsdrm) — gleicher Weg wie Stock-`show_msg`
- System-SDL aus `/usr/lib` nutzen (nicht die gebundelte)
- `LD_LIBRARY_PATH=/usr/lib:$SYSTEM_PATH/lib:...`
- `bl_power=4` persistiert über Neustart → im Updater auf 0 setzen
- SYSTEM-Squashfs muss mit `-b 262144 -comp gzip` gepackt werden
- GPT-Backup-Problem: `parted -f` mit expliziten Sektoren löst es
- ROMS-Partition NICHT im Image anlegen — erst beim ersten Boot erstellen
- MinUI-Files in `minui.tar` auf EMUELEC-Partition, install.sh extrahiert sie

## Dateien

| Datei | Zweck |
|-------|-------|
| `create_sd_image.sh` | Flashbares Image bauen |
| `gkdpixel2-minui.img.xz` | Fertiges Image |
| `minui-src/workspace/gkdpixel2/` | MinUI-Plattform-Code |
| `stock_boot_sectors.img` | Bootloader (erste 64MB) |
| `Image`, `rk3326s-gkd-pixel2.dtb`, `SYSTEM` | Kernel, DTB, Rootfs |
