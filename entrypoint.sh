#!/bin/bash
set -e

groupadd -g ${PGID} winegroup 2>/dev/null || true
useradd -u ${PUID} -g ${PGID} -d /home/wineuser -m -s /bin/bash wineuser 2>/dev/null || true

mkdir -p /tmp/runtime-root && chmod 700 /tmp/runtime-root
chown ${PUID}:${PGID} /tmp/runtime-root
rm -f /tmp/.X99-lock

# Create all dirs (volumes are already mounted at this point)
mkdir -p "/home/wineuser/.wine32/drive_c/Program Files/MusicIP"
mkdir -p "/home/wineuser/.wine32/drive_c/users/wineuser/AppData/Roaming/MusicIP/"
mkdir -p "/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP/"

# Copy MusicIP binaries (skip if already there)
cp -rn /opt/MusicIP/. "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/"

mkdir -p "/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP/"

# Fix ownership of everything
chown -R ${PUID}:${PGID} /home/wineuser



echo "=== Directory tree under /home/wineuser/.wine32/drive_c ==="
find /home/wineuser/.wine32/drive_c -type d
echo "=== Looking for m3lib files ==="
find / -name "*.m3lib" 2>/dev/null

Xvfb :99 -screen 0 1024x768x24 &
sleep 3

gosu wineuser env DISPLAY=:99 WINEARCH=win32 WINEPREFIX=/home/wineuser/.wine32 XDG_RUNTIME_DIR=/tmp/runtime-root wineboot --init
sleep 5

gosu wineuser env DISPLAY=:99 WINEARCH=win32 WINEPREFIX=/home/wineuser/.wine32 XDG_RUNTIME_DIR=/tmp/runtime-root wine "C:\\Program Files\\MusicIP\\MusicMagicServer.exe" start

tail -f /dev/null