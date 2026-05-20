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

### Firmware files (from your stock GKD Pixel 2 SD card)

You must extract these yourself from your stock SD card:

```bash
# Insert your stock SD card, then:
mkdir firmware

# Bootloader (first 64MB of the raw card)
sudo dd if=/dev/sdX bs=1M count=64 of=firmware/stock_boot_sectors.img

# Copy from the boot partition (FAT32, labeled EMUELEC)
cp /media/EMUELEC/Image                   firmware/
cp /media/EMUELEC/rk3326s-gkd-pixel2.dtb firmware/
cp /media/EMUELEC/SYSTEM                  firmware/
```

### Tools (Linux)

```bash
sudo pacman -S parted dosfstools e2fsprogs exfatprogs squashfs-tools docker curl
# or: sudo apt install ...
```

Docker must be running and your user must be in the `docker` group.

## Quick Start — Pre-built Image

Download `gkdpixel2-minui.img.xz` from the [Releases](https://github.com/NukeBomB3000/minui-gkd-pixel2/releases) page and flash it:

```bash
xz -d gkdpixel2-minui.img.xz
sudo dd if=gkdpixel2-minui.img of=/dev/sdX bs=4M status=progress
```

Or use [Balena Etcher](https://etcher.balena.io/) / Raspberry Pi Imager directly with the `.img.xz` file.

> **Note:** The pre-built image contains the GKD Pixel 2 firmware. You do not need to extract anything from your stock SD card — just flash and go.

## Build from Source

Only needed if you want to modify MinUI or rebuild the image yourself.

```bash
git clone https://github.com/NukeBomB3000/minui-gkd-pixel2
cd minui-gkd-pixel2

# Place firmware files in ./firmware/ (see Requirements above)

sudo ./build_and_image.sh
# Output: gkdpixel2-minui.img.xz (~400MB)
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
| `Nintendo Entertainment System (FC)` | NES/Famicom | |
| `Super Nintendo Entertainment System (SFC)` | SNES | |
| `Sega Genesis (MD)` | Mega Drive | |
| `Sony PlayStation (PS)` | PS1 | `Bios/PS/psxonpsp660.bin` (required) |
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
