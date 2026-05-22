#!/bin/bash
# Erstellt ein flashbares SD-Karten-Image für den GKD Pixel 2 mit MinUI
#
# Verwendung: ./create_sd_image.sh [ausgabe.img]
#
# Flashen: xz -d gkdpixel2-minui.img.xz && dd if=gkdpixel2-minui.img of=/dev/sdX bs=4M status=progress
#          oder: Balena Etcher / Raspberry Pi Imager
#
# Erster Boot: ROMS-Partition wird in richtiger Größe erstellt, MinUI installiert, Reboot
# Zweiter Boot: MinUI startet direkt
#
# Voraussetzungen:
#   - stock_boot_sectors.img   (erste 64 MB der Stock-SD: Bootloader)
#   - Image                    (ARM64-Kernel)
#   - rk3326s-gkd-pixel2.dtb  (Device Tree)
#   - SYSTEM                   (SquashFS-Rootfs, ~415 MB)
#   - firmware/*.elf / *.so    (vorgebaute MinUI-Binaries)
#   - minui/MinUI.zip
#
# Partitionslayout im Image (GPT):
#   p1 EMUELEC  32768–1081343   512MB  FAT32  (Kernel, DTB, SYSTEM, minui.tar)
#   p2 storage  1081344–3178495   1GB  ext4   (leer)
#   ── kein p3 im Image ──
#
# Erster Boot via first_run.txt → install.sh aus SYSTEM:
#   → p3 ROMS auf volle Kartengrö§e erstellen + formatieren
#   → MinUI aus minui.tar auf ROMS extrahieren
#   → Reboot → normaler MinUI-Start

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOOP=""
cleanup() {
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT
OUTPUT="${1:-$SCRIPT_DIR/gkdpixel2-minui.img}"
FIRMWARE="$SCRIPT_DIR/firmware"
STOCK_IMG="$FIRMWARE/stock_boot_sectors.img"
MINUI_DIR="$SCRIPT_DIR/minui"

# Image-Größe: nur EMUELEC + storage (kein ROMS)
IMG_SECTORS=$((3178496 + 34))
IMG_SIZE=$((IMG_SECTORS * 512))

# ─── Voraussetzungen ──────────────────────────────────────────────────────────

for f in "$STOCK_IMG" "$FIRMWARE/Image" "$FIRMWARE/rk3326s-gkd-pixel2.dtb" \
          "$FIRMWARE/SYSTEM" "$FIRMWARE/minui.elf" "$FIRMWARE/keymon.elf"; do
    [ -f "$f" ] || { echo "Fehler: fehlt: $f"; exit 1; }
done
for tool in parted mkfs.fat mkfs.ext4 unsquashfs mksquashfs; do
    command -v $tool >/dev/null || { echo "Fehler: $tool fehlt"; exit 1; }
done

echo "=== GKD Pixel 2 MinUI Image ==="
echo "Ausgabe: $OUTPUT"

# ─── Schritt 1: MinUI-tar für EMUELEC packen ──────────────────────────────────

echo "=== Schritt 1: MinUI-Archiv erstellen ==="
MINUI_TAR="$SCRIPT_DIR/minui.tar"
STAGE="$(mktemp -d)"

mkdir -p "$STAGE/.system/gkdpixel2/bin" \
         "$STAGE/.system/gkdpixel2/lib" \
         "$STAGE/.system/gkdpixel2/paks/MinUI.pak" \
         "$STAGE/.system/gkdpixel2/cores" \
         "$STAGE/.tmp_update"

cp "$FIRMWARE/minui.elf"        "$STAGE/.system/gkdpixel2/bin/"
cp "$FIRMWARE/minarch.elf"     "$STAGE/.system/gkdpixel2/bin/"
cp "$FIRMWARE/say.elf"         "$STAGE/.system/gkdpixel2/bin/"
cp "$FIRMWARE/syncsettings.elf" "$STAGE/.system/gkdpixel2/bin/"
cp "$FIRMWARE/keymon.elf"      "$STAGE/.system/gkdpixel2/bin/"
cp "$FIRMWARE/libmsettings.so" "$STAGE/.system/gkdpixel2/lib/"

# Basis-Cores (aarch64) und Basis-Emus-PAKs aus MinUI.zip
MINUI_ZIP_PATH="$MINUI_DIR/MinUI.zip" python3 -c "
import zipfile, os, stat
with zipfile.ZipFile(os.environ['MINUI_ZIP_PATH']) as z:
    # Cores
    for n in z.namelist():
        if n.startswith('.system/rgb30/cores/') and n.endswith('.so'):
            out = '$STAGE/.system/gkdpixel2/cores/' + os.path.basename(n)
            open(out,'wb').write(z.read(n))
    # Emus PAKs (von gkdpixel)
    for n in z.namelist():
        if not n.startswith('.system/gkdpixel/paks/Emus/'): continue
        rel = n[len('.system/gkdpixel/paks/Emus/'):]
        if not rel: continue
        out = '$STAGE/.system/gkdpixel2/paks/Emus/' + rel
        if n.endswith('/'): os.makedirs(out, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(out), exist_ok=True)
            data = z.read(n)
            open(out,'wb').write(data)
            if n.endswith('.sh'): os.chmod(out, 0o755)
"

# Assets
python3 -c "
import zipfile, os
with zipfile.ZipFile('$MINUI_DIR/MinUI.zip') as z:
    for n in z.namelist():
        if not n.startswith('.system/res/'): continue
        rel = n[len('.system/res/'):]
        if not rel or rel.endswith('/'): continue
        out = '$STAGE/.system/res/' + rel
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out,'wb').write(z.read(n))
"

# launch.sh
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

# updater
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

mkdir -p "$STAGE/Saves"

# ─── Extras ───────────────────────────────────────────────────────────────────

echo "=== Extras einbinden ==="
[ -d "$MINUI_DIR/Emus/rgb30" ] && \
    cp -r "$MINUI_DIR/Emus/rgb30/." "$STAGE/.system/gkdpixel2/paks/Emus/"
FILES_PAK="$SCRIPT_DIR/files-pak"
if [ -d "$FILES_PAK" ] && [ -f "$FILES_PAK/DinguxCommander" ]; then
    mkdir -p "$STAGE/Tools/gkdpixel2/Files.pak"
    cp -r "$FILES_PAK/." "$STAGE/Tools/gkdpixel2/Files.pak/"
else
    echo "WARNING: files-pak/DinguxCommander not found — run build_dinguxcommander.sh first"
fi
[ -d "$MINUI_DIR/Roms" ] && \
    find "$MINUI_DIR/Roms" -mindepth 1 -maxdepth 1 -type d | \
    while read dir; do mkdir -p "$STAGE/Roms/$(basename "$dir")"; done
[ -d "$MINUI_DIR/Bios" ] && \
    find "$MINUI_DIR/Bios" -mindepth 1 -maxdepth 1 -type d | \
    while read dir; do mkdir -p "$STAGE/Bios/$(basename "$dir")"; done
[ -d "$MINUI_DIR/Saves" ] && \
    find "$MINUI_DIR/Saves" -mindepth 1 -maxdepth 1 -type d | \
    while read dir; do mkdir -p "$STAGE/Saves/$(basename "$dir")"; done

# ─── MUS.pak (mpv music player) ───────────────────────────────────────────────

MUS_PAK_SRC="$SCRIPT_DIR/mus-pak"
if [ -d "$MUS_PAK_SRC" ]; then
    echo "=== MUS.pak einbinden ==="
    mkdir -p "$STAGE/.system/gkdpixel2/paks/Emus/MUS.pak"
    cp -r "$MUS_PAK_SRC/." "$STAGE/.system/gkdpixel2/paks/Emus/MUS.pak/"
    mkdir -p "$STAGE/Roms/Music (MUS)"
fi


tar -C "$STAGE" -cf "$MINUI_TAR" .
rm -rf "$STAGE"
echo "minui.tar: $(ls -lh "$MINUI_TAR" | awk '{print $5}')"

# ─── Schritt 2: SYSTEM modifizieren (install.sh ersetzen) ─────────────────────

echo "=== Schritt 2: SYSTEM modifizieren ==="
SYS_DIR="$(mktemp -d)"
unsquashfs -d "$SYS_DIR" "$FIRMWARE/SYSTEM" > /dev/null
echo "SYSTEM extrahiert: $(du -sh "$SYS_DIR" | cut -f1)"

cat > "$SYS_DIR/usr/share/first_run/install.sh" << 'INSTALL'
#!/bin/sh

cd /usr/share/first_run/
mount -o remount,rw /flash
LOG=/flash/minui_boot.log
exec >> "$LOG" 2>&1
echo "=== $(date) === First boot: creating ROMS partition ==="

DISK=/dev/mmcblk0

# first_run.txt sofort entfernen — verhindert Reboot-Loop bei Fehler
rm -f /flash/first_run.txt

# Disk-Device ermitteln und loggen
echo "DISK=$DISK" >> "$LOG"
echo "Disk size: $(cat /sys/block/mmcblk0/size 2>/dev/null) sectors" >> "$LOG"
ls -la /usr/sbin/sgdisk >> "$LOG" 2>&1 || echo "sgdisk not found at /usr/sbin/sgdisk" >> "$LOG"

# Echte Disk-Größe ermitteln, ROMS mit expliziter Endsektor anlegen
DISK_SECTORS=$(cat /sys/block/mmcblk0/size)
LAST_USABLE=$(( DISK_SECTORS - 34 ))
echo "Creating ROMS: sector 3178496 to $LAST_USABLE" >> "$LOG"
# parted -f behebt GPT-Backup-Position automatisch
parted -s -f /dev/mmcblk0 -- mkpart ROMS fat32 3178496s ${LAST_USABLE}s >> "$LOG" 2>&1
echo "parted exit: $?" >> "$LOG"
partprobe /dev/mmcblk0 2>/dev/null || true
sleep 2
echo "Partitions:" >> "$LOG"
cat /proc/partitions | grep mmcblk0 >> "$LOG" 2>&1

# Formatieren
echo "Formatting ROMS as exFAT..."
mkfs.exfat -n ROMS ${DISK}p3 >> "$LOG" 2>&1

# Mounten — erst prüfen ob Partition vorhanden
mkdir -p /storage/games-external /storage/roms
if ! mount ${DISK}p3 /storage/games-external 2>/dev/null; then
    echo "ERROR: /dev/mmcblk0p3 konnte nicht gemountet werden" >> "$LOG"
    echo "Bitte Gerät neu starten." >> "$LOG"
    sync
    exit 1
fi
mount ${DISK}p3 /storage/roms 2>/dev/null || true

# MinUI aus EMUELEC extrahieren
echo "Installing MinUI..."
tar -C /storage/games-external -xf /flash/minui.tar
sync

# minui.tar nach Extraktion löschen — gibt ~40-60 MB auf /flash frei
rm -f /flash/minui.tar
sync

echo "ROMS size: $(df -h /storage/games-external | tail -1)"
echo "EMUELEC free: $(df -h /flash | tail -1)"
echo "Done. Rebooting..."

# first_run.txt entfernen damit normaler Boot startet
rm -f /flash/first_run.txt
sync

systemctl reboot 2>/dev/null || /sbin/reboot 2>/dev/null || echo b > /proc/sysrq-trigger
INSTALL
chmod +x "$SYS_DIR/usr/share/first_run/install.sh"

# SYSTEM neu packen — exakt gleiche Parameter wie Original (b=262144, gzip)
echo "Repacking SYSTEM (gzip, b=262144)..."
SYS_IMG="$(mktemp)"
mksquashfs "$SYS_DIR" "$SYS_IMG" -comp gzip -b 262144 -noappend -quiet
rm -rf "$SYS_DIR"
echo "SYSTEM: $(ls -lh "$SYS_IMG" | awk '{print $5}')"

# ─── Schritt 3: Image erstellen ───────────────────────────────────────────────

echo "=== Schritt 3: Image erstellen ==="
rm -f "$OUTPUT"
truncate -s $IMG_SIZE "$OUTPUT"

parted -s "$OUTPUT" mklabel gpt
parted -s "$OUTPUT" mkpart EMUELEC fat32 $((32768   * 512))B $((1081343 * 512 + 511))B
parted -s "$OUTPUT" mkpart storage ext4  $((1081344 * 512))B $((3178495 * 512 + 511))B

# ─── Schritt 4: Bootloader ────────────────────────────────────────────────────

echo "=== Schritt 4: Bootloader ==="
dd if="$STOCK_IMG" of="$OUTPUT" bs=512 skip=64 seek=64 count=32704 conv=notrunc status=none

# ─── Schritt 5: Dateisysteme ──────────────────────────────────────────────────

echo "=== Schritt 5: Dateisysteme ==="
LOOP=$(losetup --find --show --partscan "$OUTPUT")
sleep 1
mkfs.fat -F 32 -n EMUELEC "${LOOP}p1" -s 8 2>/dev/null
mkfs.ext4 -F -L storage -q "${LOOP}p2"

# ─── Schritt 6: EMUELEC befüllen ──────────────────────────────────────────────

echo "=== Schritt 6: EMUELEC befüllen ==="
BOOT="$(mktemp -d)"
mount "${LOOP}p1" "$BOOT"
cp "$FIRMWARE/Image"                   "$BOOT/"
cp "$FIRMWARE/rk3326s-gkd-pixel2.dtb" "$BOOT/"
cp "$SYS_IMG"                            "$BOOT/SYSTEM"
cp "$MINUI_TAR"                          "$BOOT/minui.tar"
touch "$BOOT/first_run.txt"             # triggert install.sh beim ersten Boot
umount "$BOOT"; rmdir "$BOOT"
rm -f "$SYS_IMG" "$MINUI_TAR"

# ─── Schritt 7: Aufräumen ─────────────────────────────────────────────────────

losetup -d "$LOOP"

# ─── Schritt 8: Komprimieren ──────────────────────────────────────────────────

echo "=== Schritt 8: Komprimieren ==="
xz -T0 -z --keep --force "$OUTPUT"

echo ""
echo "=== Fertig ==="
echo "Image:            $OUTPUT ($(ls -lh "$OUTPUT" | awk '{print $5}'))"
echo "Komprimiert:      ${OUTPUT}.xz ($(ls -lh "${OUTPUT}.xz" | awk '{print $5}'))"
echo ""
echo "Erster Boot:  ROMS wird in voller Kartengröße angelegt, MinUI installiert, Reboot"
echo "Zweiter Boot: MinUI startet direkt"
