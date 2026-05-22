#!/bin/sh

cd "$(dirname "$0")"
export SDL_VIDEODRIVER=wayland
export SDL_AUDIODRIVER=alsa
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir}"
export HOME="$SDCARD_PATH"
export LD_LIBRARY_PATH=/usr/lib:/lib:$LD_LIBRARY_PATH
./DinguxCommander 2>/mnt/SDCARD/.userdata/gkdpixel2/logs/files.log