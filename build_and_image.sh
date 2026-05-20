#!/bin/bash
# build_and_image.sh — Builds MinUI for GKD Pixel 2 and creates a flashable SD image
#
# Usage: sudo ./build_and_image.sh [output.img]
#
# Requirements (not included, see README.md):
#   firmware/stock_boot_sectors.img   — first 64MB of stock SD card (bootloader)
#   firmware/Image                    — ARM64 kernel
#   firmware/rk3326s-gkd-pixel2.dtb  — Device Tree Blob
#   firmware/SYSTEM                   — ROCKNIX SquashFS rootfs (~415MB)
#
# MinUI assets are downloaded automatically if MinUI.zip is not present.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:-$SCRIPT_DIR/gkdpixel2-minui.img}"
FIRMWARE="$SCRIPT_DIR/firmware"
MINUI_BASE_DIR="$SCRIPT_DIR/../MinUI-20251127-1-base"
MINUI_EXTRAS_DIR="$SCRIPT_DIR/../MinUI-20251127-1-extras"
MINUI_ZIP="$MINUI_BASE_DIR/MinUI.zip"
MINUI_RELEASE_URL="https://github.com/shauninman/MinUI/releases/download/MinUI-20251127-1/MinUI-20251127-1-base.zip"
TOOLCHAIN_REPO="https://github.com/shauninman/union-rgb30-toolchain"

LOOP=""
cleanup() { [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT

# ─── Check requirements ───────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root: sudo $0"; exit 1
fi

for f in "$FIRMWARE/stock_boot_sectors.img" "$FIRMWARE/Image" \
          "$FIRMWARE/rk3326s-gkd-pixel2.dtb" "$FIRMWARE/SYSTEM"; do
    [ -f "$f" ] || { echo "Missing: $f (see README.md)"; exit 1; }
done

for tool in parted mkfs.fat mkfs.ext4 mkfs.exfat unsquashfs mksquashfs docker; do
    command -v $tool >/dev/null || { echo "Missing tool: $tool"; exit 1; }
done

# ─── Download MinUI assets if needed ─────────────────────────────────────────

if [ ! -f "$MINUI_ZIP" ]; then
    echo "=== MinUI-20251127-1-base not found, downloading ==="
    TMP_ZIP="$(mktemp)"
    curl -L --progress-bar -o "$TMP_ZIP" "$MINUI_RELEASE_URL"
    mkdir -p "$MINUI_BASE_DIR"
    python3 -c "
import zipfile, os
with zipfile.ZipFile('$TMP_ZIP') as z:
    z.extractall('$MINUI_BASE_DIR')
print('MinUI base extracted to $MINUI_BASE_DIR')
"
    rm -f "$TMP_ZIP"
fi

# ─── Step 1: Build MinUI binaries ─────────────────────────────────────────────

echo "=== Step 1: Building MinUI for gkdpixel2 ==="

# Clone toolchain if not present
TOOLCHAIN_DIR="$SCRIPT_DIR/.toolchain"
if [ ! -d "$TOOLCHAIN_DIR/.build" ]; then
    echo "Setting up Docker toolchain..."
    mkdir -p "$TOOLCHAIN_DIR"
    git clone --depth=1 "$TOOLCHAIN_REPO" "$TOOLCHAIN_DIR"
    cd "$TOOLCHAIN_DIR" && make .build && cd "$SCRIPT_DIR"
fi

# Clone MinUI source if not present
MINUI_SRC="$SCRIPT_DIR/.minui-src"
if [ ! -d "$MINUI_SRC" ]; then
    echo "Cloning MinUI source..."
    git clone --depth=1 https://github.com/shauninman/MinUI.git "$MINUI_SRC"
fi

# Copy our gkdpixel2 platform into MinUI workspace
cp -r "$SCRIPT_DIR/platform"     "$MINUI_SRC/workspace/gkdpixel2/platform/"
cp -r "$SCRIPT_DIR/keymon"       "$MINUI_SRC/workspace/gkdpixel2/keymon/"
cp -r "$SCRIPT_DIR/libmsettings" "$MINUI_SRC/workspace/gkdpixel2/libmsettings/"

# Also copy gkdpixel workspace structure (show, makefile, other)
if [ ! -d "$MINUI_SRC/workspace/gkdpixel2/show" ]; then
    cp -r "$MINUI_SRC/workspace/rgb30/show"  "$MINUI_SRC/workspace/gkdpixel2/show"
    cp -r "$MINUI_SRC/workspace/rgb30/other" "$MINUI_SRC/workspace/gkdpixel2/other"
fi

# Write workspace makefile (no DinguxCommander)
cat > "$MINUI_SRC/workspace/gkdpixel2/makefile" << 'MAKEFILE'
ifeq (,$(PLATFORM))
PLATFORM=$(UNION_PLATFORM)
endif
ifeq (,$(PLATFORM))
$(error please specify PLATFORM)
endif
REQUIRES_SDLCOMPAT=other/sdl12-compat
all: readmes
	cd show && make
early: $(REQUIRES_SDLCOMPAT)/build
	cd $(REQUIRES_SDLCOMPAT) && cmake --build build
clean:
	cd $(REQUIRES_SDLCOMPAT) && rm -rf build
$(REQUIRES_SDLCOMPAT):
	git clone --depth 1 --branch minui-rgb30 https://github.com/shauninman/sdl12-compat.git $(REQUIRES_SDLCOMPAT)
$(REQUIRES_SDLCOMPAT)/build: $(REQUIRES_SDLCOMPAT)
	cd $(REQUIRES_SDLCOMPAT) && cmake --toolchain ./toolchain.cmake -Bbuild -DCMAKE_BUILD_TYPE=Release .
include ../all/readmes/makefile
MAKEFILE

# Build inside Docker
docker run --rm \
    -v "$MINUI_SRC/workspace":/root/workspace \
    rgb30-toolchain /bin/bash -c \
    ". ~/.bashrc && cd /root/workspace && make UNION_PLATFORM=gkdpixel2 2>&1 | tail -5"

echo "Build complete."
WS="$MINUI_SRC/workspace"

# ─── Step 2: Pack MinUI tar ────────────────────────────────────────────────────

echo "=== Step 2: Packing MinUI archive ==="
MINUI_TAR="$SCRIPT_DIR/minui.tar"
STAGE="$(mktemp -d)"

mkdir -p "$STAGE/.system/gkdpixel2/bin" \
         "$STAGE/.system/gkdpixel2/lib" \
         "$STAGE/.system/gkdpixel2/paks/MinUI.pak" \
         "$STAGE/.system/gkdpixel2/cores" \
         "$STAGE/.tmp_update"

cp "$WS/all/minui/build/gkdpixel2/minui.elf"               "$STAGE/.system/gkdpixel2/bin/"
cp "$WS/all/minarch/build/gkdpixel2/minarch.elf"           "$STAGE/.system/gkdpixel2/bin/"
cp "$WS/all/say/build/gkdpixel2/say.elf"                   "$STAGE/.system/gkdpixel2/bin/"
cp "$WS/all/syncsettings/build/gkdpixel2/syncsettings.elf" "$STAGE/.system/gkdpixel2/bin/"
cp "$WS/gkdpixel2/keymon/keymon.elf"                       "$STAGE/.system/gkdpixel2/bin/"
cp "$WS/gkdpixel2/libmsettings/libmsettings.so"            "$STAGE/.system/gkdpixel2/lib/"

# Cores (rgb30/aarch64) und Emus-PAKs aus MinUI.zip
python3 -c "
import zipfile, os
with zipfile.ZipFile('$MINUI_ZIP') as z:
    for n in z.namelist():
        if n.startswith('.system/rgb30/cores/') and n.endswith('.so'):
            out = '$STAGE/.system/gkdpixel2/cores/' + os.path.basename(n)
            open(out,'wb').write(z.read(n))
    for n in z.namelist():
        if not n.startswith('.system/gkdpixel/paks/Emus/'): continue
        rel = n[len('.system/gkdpixel/paks/Emus/'):]
        if not rel: continue
        out = '$STAGE/.system/gkdpixel2/paks/Emus/' + rel
        if n.endswith('/'): os.makedirs(out, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(out), exist_ok=True)
            open(out,'wb').write(z.read(n))
            if n.endswith('.sh'): os.chmod(out, 0o755)
"

# Assets from MinUI.zip
python3 -c "
import zipfile, os
with zipfile.ZipFile('$MINUI_ZIP') as z:
    for n in z.namelist():
        if not n.startswith('.system/res/'): continue
        rel = n[len('.system/res/'):]
        if not rel or rel.endswith('/'): continue
        out = '$STAGE/.system/res/' + rel
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out,'wb').write(z.read(n))
"

cat > "$STAGE/.system/gkdpixel2/paks/MinUI.pak/launch.sh" << 'LAUNCH'
#!/bin/sh
export PLATFORM="gkdpixel2"
export SDCARD_PATH="/mnt/SDCARD"
export BIOS_PATH="$SDCARD_PATH/Bios"
export SAVES_PATH="$SDCARD_PATH/Saves"
export SYSTEM_PATH="$SDCARD_PATH/.system/$PLATFORM"
export CORES_PATH="$SYSTEM_PATH/cores"
export USERDATA_PATH="$SDCARD_PATH/.userdata/$PLATFORM"
export SHARED_USERDATA_PATH="$SDCARD_PATH/.userdata/shared"
export LOGS_PATH="$USERDATA_PATH/logs"
export DATETIME_PATH="$SHARED_USERDATA_PATH/datetime.txt"
mkdir -p "$LOGS_PATH" "$SHARED_USERDATA_PATH/.minui"
export PATH=$SYSTEM_PATH/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib:$SYSTEM_PATH/lib:/lib:$LD_LIBRARY_PATH
export SDL_VIDEODRIVER=wayland
export SDL_AUDIODRIVER=alsa
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}"
echo "$(date) launch.sh started" >> "$LOGS_PATH/minui.txt"
keymon.elf >> "$LOGS_PATH/keymon.txt" 2>&1 &
cd "$(dirname "$0")"
EXEC_PATH=/tmp/minui_exec
NEXT_PATH=/tmp/next
touch "$EXEC_PATH" && sync
while [ -f "$EXEC_PATH" ]; do
    minui.elf >> "$LOGS_PATH/minui.txt" 2>&1
    echo "$(date +'%F %T')" > "$DATETIME_PATH"
    sync
    if [ -f "$NEXT_PATH" ]; then
        CMD=$(cat "$NEXT_PATH")
        rm -f "$NEXT_PATH"
        eval "$CMD"
        echo "$(date +'%F %T')" > "$DATETIME_PATH"
        sync
    fi
    [ -f /tmp/poweroff ] && break
done
poweroff
LAUNCH
chmod +x "$STAGE/.system/gkdpixel2/paks/MinUI.pak/launch.sh"

cat > "$STAGE/.tmp_update/updater" << 'UPDATER'
#!/bin/sh
mount -o remount,rw /flash
LOG=/flash/minui_boot.log
exec >> "$LOG" 2>&1
echo "=== $(date) === updater started"
echo 0  > /sys/class/backlight/backlight/bl_power  2>/dev/null || true
echo 96 > /sys/class/backlight/backlight/brightness 2>/dev/null || true
. /etc/profile
LAUNCH=/mnt/SDCARD/.system/gkdpixel2/paks/MinUI.pak/launch.sh
[ -f "$LAUNCH" ] && exec "$LAUNCH" || { echo "ERROR: $LAUNCH not found"; sleep 10; poweroff; }
UPDATER
chmod +x "$STAGE/.tmp_update/updater"

for dir in "Game Boy (GB)" "Game Boy Color (GBC)" "Game Boy Advance (GBA)" \
           "Nintendo Entertainment System (FC)" "Super Nintendo Entertainment System (SFC)" \
           "Sega Genesis (MD)" "Sony PlayStation (PS)" "Native Games (PAK)"; do
    mkdir -p "$STAGE/Roms/$dir"
done
for bios in FC GB GBA GBC MD PS SFC; do mkdir -p "$STAGE/Bios/$bios"; done
mkdir -p "$STAGE/Saves"

# ─── Extras: additional Emu PAKs, Tools, Roms/Bios/Saves dirs ────────────────

if [ -d "$MINUI_EXTRAS_DIR" ]; then
    echo "=== Including MinUI extras ==="

    # Extra Emu PAKs for gkdpixel (binary-compatible with gkdpixel2 / RK3326S)
    if [ -d "$MINUI_EXTRAS_DIR/Emus/gkdpixel" ]; then
        cp -r "$MINUI_EXTRAS_DIR/Emus/gkdpixel/." "$STAGE/.system/gkdpixel2/paks/Emus/"
    fi

    # Extra Tools for gkdpixel
    if [ -d "$MINUI_EXTRAS_DIR/Tools/gkdpixel" ]; then
        mkdir -p "$STAGE/.system/gkdpixel2/paks/Tools"
        cp -r "$MINUI_EXTRAS_DIR/Tools/gkdpixel/." "$STAGE/.system/gkdpixel2/paks/Tools/"
    fi

    # Extra Roms, Bios, Saves directory structures
    if [ -d "$MINUI_EXTRAS_DIR/Roms" ]; then
        find "$MINUI_EXTRAS_DIR/Roms" -mindepth 1 -maxdepth 1 -type d | while read dir; do
            mkdir -p "$STAGE/Roms/$(basename "$dir")"
        done
    fi
    if [ -d "$MINUI_EXTRAS_DIR/Bios" ]; then
        find "$MINUI_EXTRAS_DIR/Bios" -mindepth 1 -maxdepth 1 -type d | while read dir; do
            mkdir -p "$STAGE/Bios/$(basename "$dir")"
        done
    fi
    if [ -d "$MINUI_EXTRAS_DIR/Saves" ]; then
        find "$MINUI_EXTRAS_DIR/Saves" -mindepth 1 -maxdepth 1 -type d | while read dir; do
            mkdir -p "$STAGE/Saves/$(basename "$dir")"
        done
    fi
else
    echo "WARNING: MinUI extras not found at $MINUI_EXTRAS_DIR, skipping"
fi

# ─── Dev ROMs: bundle ROMs from dev/<TAG>/ into the image ────────────────────
#
# Place up to a few ROMs in dev/GBA/, dev/PS/, dev/GB/ etc. for quick testing.
# Supported tags match the Roms folder suffixes: GB GBC GBA FC SFC MD PS PAK
# plus extras: GG MGBA NGPC NGP PCE PKM SGB SMS SUPA VB P8

DEV_DIR="$SCRIPT_DIR/dev"
declare -A ROMS_FOLDER=(
    [GB]="Game Boy (GB)"
    [GBC]="Game Boy Color (GBC)"
    [GBA]="Game Boy Advance (GBA)"
    [FC]="Nintendo Entertainment System (FC)"
    [SFC]="Super Nintendo Entertainment System (SFC)"
    [MD]="Sega Genesis (MD)"
    [PS]="Sony PlayStation (PS)"
    [PAK]="Native Games (PAK)"
    [GG]="Sega Game Gear (GG)"
    [MGBA]="Game Boy Advance (MGBA)"
    [NGPC]="Neo Geo Pocket Color (NGPC)"
    [NGP]="Neo Geo Pocket (NGP)"
    [PCE]="TurboGrafx-16 (PCE)"
    [PKM]="Pokémon mini (PKM)"
    [SGB]="Super Game Boy (SGB)"
    [SMS]="Sega Master System (SMS)"
    [SUPA]="Super Nintendo Entertainment System (SUPA)"
    [VB]="Virtual Boy (VB)"
    [P8]="Pico-8 (P8)"
)

if [ -d "$DEV_DIR" ]; then
    bundled=0
    for tag in $(ls "$DEV_DIR"); do
        src="$DEV_DIR/$tag"
        [ -d "$src" ] || continue
        folder="${ROMS_FOLDER[$tag]:-}"
        if [ -z "$folder" ]; then
            echo "WARNING: dev/$tag — unknown tag, skipping"
            continue
        fi
        count=$(find "$src" -maxdepth 1 -type f | wc -l)
        [ "$count" -eq 0 ] && continue
        mkdir -p "$STAGE/Roms/$folder"
        cp "$src"/* "$STAGE/Roms/$folder/"
        echo "  bundled $count ROM(s) from dev/$tag → Roms/$folder"
        bundled=$((bundled + count))
    done
    [ "$bundled" -gt 0 ] && echo "=== Dev ROMs: $bundled file(s) bundled ===" || true
fi

tar -C "$STAGE" -cf "$MINUI_TAR" .
rm -rf "$STAGE"
echo "minui.tar: $(ls -lh "$MINUI_TAR" | awk '{print $5}')"

# ─── Step 3: Modify SYSTEM (replace install.sh) ───────────────────────────────

echo "=== Step 3: Modifying SYSTEM ==="
SYS_DIR="$(mktemp -d)"
unsquashfs -d "$SYS_DIR" "$FIRMWARE/SYSTEM" > /dev/null

cat > "$SYS_DIR/usr/share/first_run/install.sh" << 'INSTALL'
#!/bin/sh
mount -o remount,rw /flash
LOG=/flash/minui_boot.log
exec >> "$LOG" 2>&1
echo "=== $(date) === First boot: creating ROMS partition ==="
rm -f /flash/first_run.txt

DISK=/dev/mmcblk0
DISK_SECTORS=$(cat /sys/block/mmcblk0/size)
LAST_USABLE=$(( DISK_SECTORS - 34 ))
echo "Creating ROMS: sector 3178496 to $LAST_USABLE"
parted -s -f "$DISK" -- mkpart ROMS fat32 3178496s ${LAST_USABLE}s >> "$LOG" 2>&1
echo "parted exit: $?" >> "$LOG"
partprobe "$DISK" 2>/dev/null || true
sleep 2
cat /proc/partitions | grep mmcblk0 >> "$LOG"

echo "Formatting ROMS as exFAT..."
mkfs.exfat -n ROMS ${DISK}p3 >> "$LOG" 2>&1

mkdir -p /storage/games-external /storage/roms
if ! mount ${DISK}p3 /storage/games-external 2>/dev/null; then
    echo "ERROR: could not mount ${DISK}p3" >> "$LOG"
    sync; exit 1
fi
mount ${DISK}p3 /storage/roms 2>/dev/null || true

echo "Installing MinUI..."
tar -C /storage/games-external -xf /flash/minui.tar
sync

echo "ROMS size: $(df -h /storage/games-external | tail -1)"
echo "Done. Rebooting..."
systemctl reboot 2>/dev/null || /sbin/reboot 2>/dev/null || echo b > /proc/sysrq-trigger
INSTALL
chmod +x "$SYS_DIR/usr/share/first_run/install.sh"

echo "Repacking SYSTEM (gzip, b=262144)..."
SYS_IMG="$(mktemp)"
mksquashfs "$SYS_DIR" "$SYS_IMG" -comp gzip -b 262144 -noappend -quiet
rm -rf "$SYS_DIR"
echo "SYSTEM: $(ls -lh "$SYS_IMG" | awk '{print $5}')"

# ─── Step 4: Create image ─────────────────────────────────────────────────────

echo "=== Step 4: Creating image ==="
IMG_SECTORS=$((3178496 + 34))
rm -f "$OUTPUT"
truncate -s $((IMG_SECTORS * 512)) "$OUTPUT"

parted -s "$OUTPUT" mklabel gpt
parted -s "$OUTPUT" mkpart EMUELEC fat32 $((32768   * 512))B $((1081343 * 512 + 511))B
parted -s "$OUTPUT" mkpart storage ext4  $((1081344 * 512))B $((3178495 * 512 + 511))B

dd if="$FIRMWARE/stock_boot_sectors.img" of="$OUTPUT" \
   bs=512 skip=64 seek=64 count=32704 conv=notrunc status=none

LOOP=$(losetup --find --show --partscan "$OUTPUT")
sleep 1
mkfs.fat -F 32 -n EMUELEC "${LOOP}p1" -s 8 2>/dev/null
mkfs.ext4 -F -L storage -q "${LOOP}p2"

BOOT="$(mktemp -d)"
mount "${LOOP}p1" "$BOOT"
cp "$FIRMWARE/Image"                   "$BOOT/"
cp "$FIRMWARE/rk3326s-gkd-pixel2.dtb" "$BOOT/"
cp "$SYS_IMG"                          "$BOOT/SYSTEM"
cp "$MINUI_TAR"                        "$BOOT/minui.tar"
touch "$BOOT/first_run.txt"
umount "$BOOT"; rmdir "$BOOT"

rm -f "$SYS_IMG" "$MINUI_TAR"
losetup -d "$LOOP"; LOOP=""

# ─── Step 5: Compress ─────────────────────────────────────────────────────────

echo "=== Step 5: Compressing ==="
xz -T0 -z --keep --force "$OUTPUT"

echo ""
echo "=== Done ==="
echo "Image:       $OUTPUT ($(ls -lh "$OUTPUT" | awk '{print $5}'))"
echo "Compressed:  ${OUTPUT}.xz ($(ls -lh "${OUTPUT}.xz" | awk '{print $5}'))"
echo ""
echo "Flash with:  dd if=$OUTPUT of=/dev/sdX bs=4M status=progress"
echo "             or Balena Etcher / Raspberry Pi Imager"
echo ""
echo "First boot:  ROMS partition is created at full card size, MinUI installed, reboot"
echo "Second boot: MinUI starts directly"
