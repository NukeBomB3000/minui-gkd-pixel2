#!/bin/sh
SELECTED="$1"
DIR="$(dirname "$SELECTED")"
LOG="/mnt/SDCARD/.userdata/gkdpixel2/logs/music.txt"
PAK_DIR="/mnt/SDCARD/.system/gkdpixel2/paks/Emus/MUS.pak"
mkdir -p "$(dirname "$LOG")"

export SDL_VIDEODRIVER=wayland
export SDL_AUDIODRIVER=alsa
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}"
export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH
export SDL_GAMECONTROLLERCONFIG="19000000010000000221000000010000,GKD Pixel 2,a:b1,b:b0,x:b3,y:b4,back:b10,start:b11,leftshoulder:b6,rightshoulder:b7,lefttrigger:b8,righttrigger:b9,dpup:b13,dpdown:b14,dpleft:b15,dpright:b16,leftx:a0,lefty:a1,platform:Linux,"

TMPLIST="$(mktemp)"
find "$DIR" -maxdepth 1 -type f \( \
    -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" \
    -o -iname "*.wav" -o -iname "*.m4a" -o -iname "*.opus" \) \
    | sort > "$TMPLIST"

START=0
IDX=0
while IFS= read -r line; do
    [ "$line" = "$SELECTED" ] && START=$IDX && break
    IDX=$((IDX + 1))
done < "$TMPLIST"

mpv \
    --force-window=yes \
    --input-gamepad=yes \
    --no-input-default-bindings \
    --input-conf="$PAK_DIR/input.conf" \
    --playlist="$TMPLIST" \
    --playlist-start="$START" \
    --loop-playlist=no \
    --osc=no \
    --osd-level=3 \
    --osd-duration=0 \
    --osd-font-size=40 \
    --osd-align-x=center \
    --osd-align-y=bottom \
    --osd-margin-y=20 \
    '--osd-msg1=${?pause==yes:⏸  }${?pause==no:▶  }${media-title}' \
    '--osd-msg2=${playlist-pos-1} / ${playlist-count}   ${time-pos} / ${duration}' \
    >> "$LOG" 2>&1

rm -f "$TMPLIST"
