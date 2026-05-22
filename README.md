# MinUI Port for GKD Pixel 2

MinUI running on the GKD Pixel 2 (Rockchip RK3326S).

## Device

| | |
|---|---|
| **SoC** | Rockchip RK3326S (Cortex-A35, aarch64) |
| **GPU** | Mali-G31 |
| **Display** | 640×480 (MIPI DSI, ST7703) |
| **RAM** | 1GB |
| **Storage** | SD card only (no eMMC) |

## Requirements

### 1. Firmware files — `firmware/`

Extract from your stock GKD Pixel 2 SD card:

```bash
mkdir firmware

# Bootloader — first 64MB of the raw SD card
sudo dd if=/dev/sdX bs=1M count=64 of=firmware/stock_boot_sectors.img

# Kernel, Device Tree, Rootfs — from the EMUELEC FAT32 partition
cp /run/media/$USER/EMUELEC/Image                   firmware/
cp /run/media/$USER/EMUELEC/rk3326s-gkd-pixel2.dtb firmware/
cp /run/media/$USER/EMUELEC/SYSTEM                  firmware/
```

Pre-built MinUI binaries for gkdpixel2 also go into `firmware/`:

```
firmware/minui.elf
firmware/minarch.elf
firmware/say.elf
firmware/syncsettings.elf
firmware/keymon.elf
firmware/libmsettings.so
```

Build these from the [MinUI source](https://github.com/shauninman/MinUI) targeting the `gkdpixel2` platform, or copy them from an existing build.

### 2. MinUI assets — `minui/`

Download [MinUI-20251127-1-base](https://github.com/shauninman/MinUI/releases/tag/MinUI-20251127-1) and [MinUI-20251127-1-extras](https://github.com/shauninman/MinUI/releases/tag/MinUI-20251127-1), then assemble:

```bash
mkdir minui

# From base archive:
cp MinUI-20251127-1-base/MinUI.zip minui/

# From extras archive:
cp -r MinUI-20251127-1-extras/Emus  minui/
cp -r MinUI-20251127-1-extras/Tools minui/
cp -r MinUI-20251127-1-extras/Roms  minui/
cp -r MinUI-20251127-1-extras/Bios  minui/
cp -r MinUI-20251127-1-extras/Saves minui/
```

For future MinUI updates, replace the contents of `minui/` with the new release.

### 3. Host tools

```bash
# Arch
sudo pacman -S parted dosfstools e2fsprogs exfatprogs squashfs-tools python xz

# Debian/Ubuntu
sudo apt install parted dosfstools e2fsprogs exfat-utils squashfs-tools python3 xz-utils
```

## Quick Start — Pre-built Image

Download `gkdpixel2-minui.img.xz` from the [Releases](https://github.com/NukeBomB3000/minui-gkd-pixel2/releases) page and flash it:

```bash
xz -d gkdpixel2-minui.img.xz
sudo dd if=gkdpixel2-minui.img of=/dev/sdX bs=4M status=progress
```

Or use [Balena Etcher](https://etcher.balena.io/) / Raspberry Pi Imager directly with the `.img.xz` file.

> **Note:** The pre-built image contains the GKD Pixel 2 firmware. You do not need to extract anything from your stock SD card — just flash and go.

## Build from Source

```bash
git clone https://github.com/NukeBomB3000/minui-gkd-pixel2
cd minui-gkd-pixel2

# Provide firmware/ and minui/ as described above, then:
sudo ./create_sd_image.sh
# Output: gkdpixel2-minui.img + gkdpixel2-minui.img.xz
```

## First Boot

The ROMS partition is created at full card size on first boot (~30 seconds), then the device reboots into MinUI.

## Adding ROMs

Copy ROMs to the `Roms/` folders on the exFAT ROMS partition:

| Folder | System | BIOS |
|--------|--------|------|
| `Game Boy (GB)` | Game Boy | `Bios/GB/gb_bios.bin` (optional) |
| `Game Boy Color (GBC)` | GBC | `Bios/GBC/gbc_bios.bin` (optional) |
| `Game Boy Advance (GBA)` | GBA | `Bios/GBA/gba_bios.bin` (recommended) |
| `Game Boy Advance (MGBA)` | GBA (mGBA core) | `Bios/MGBA/gba_bios.bin` (optional) |
| `Super Game Boy (SGB)` | Super Game Boy | `Bios/SGB/sgb_bios.bin` (required) |
| `Nintendo Entertainment System (FC)` | NES/Famicom | |
| `Super Nintendo Entertainment System (SFC)` | SNES | |
| `Super Nintendo Entertainment System (SUPA)` | SNES (Supa core) | |
| `Sega Master System (SMS)` | Master System | |
| `Sega Game Gear (GG)` | Game Gear | |
| `Sega Genesis (MD)` | Mega Drive | |
| `Sony PlayStation (PS)` | PS1 | `Bios/PS/psxonpsp660.bin` (required) |
| `TurboGrafx-16 (PCE)` | PC Engine | `Bios/PCE/syscard3.pce` (required) |
| `Neo Geo Pocket (NGP)` | Neo Geo Pocket | |
| `Neo Geo Pocket Color (NGPC)` | Neo Geo Pocket Color | |
| `Pokémon mini (PKM)` | Pokémon mini | `Bios/PKM/bios.min` (required) |
| `Virtual Boy (VB)` | Virtual Boy | |
| `Pico-8 (P8)` | Pico-8 | |
| `Music (MUS)` | Music player (mpv) | |
| `Native Games (PAK)` | MinUI native | |

## Controls

| Button | Function |
|--------|----------|
| D-Pad | Navigate |
| A | Confirm |
| B | Back |
| Menu (back button) | In-game menu |
| Menu + Vol Up/Down | Brightness |
| Power | Sleep/Wake |

## Credits

- [MinUI](https://github.com/shauninman/MinUI) by shauninman
- [ROCKNIX](https://github.com/ROCKNIX/distribution) — base firmware
- Port by Norman Steinmeier
