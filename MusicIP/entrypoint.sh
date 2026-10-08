#!/bin/bash
set -e

groupadd -g ${PGID} winegroup 2>/dev/null || true
useradd -u ${PUID} -g ${PGID} -d /home/wineuser -m -s /bin/bash wineuser 2>/dev/null || true

mkdir -p /tmp/runtime-root && chmod 700 /tmp/runtime-root
chown ${PUID}:${PGID} /tmp/runtime-root
rm -f /tmp/.X99-lock

# Mount targets for the host volumes.
mkdir -p "/home/wineuser/.wine32/drive_c/users/wineuser/AppData/Roaming/MusicIP/"
mkdir -p "/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP/"

# /config holds mmm.ini, recipes.xml and moods/ (symlinked in at build time).
# Seed it from /opt/defaults only when it is completely empty, so files the
# user deleted or changed are never overwritten.
if [ -z "$(ls -A /config 2>/dev/null)" ]; then
    cp -a /opt/defaults/. /config/
fi
mkdir -p /config/moods
chown -R ${PUID}:${PGID} /config

chown -R ${PUID}:${PGID} /home/wineuser

Xvfb :99 -screen 0 1024x768x24 &
sleep 3

setpriv --reuid=${PUID} --regid=${PGID} --init-groups env HOME=/home/wineuser DISPLAY=:99 WINEARCH=win32 WINEPREFIX=/home/wineuser/.wine32 XDG_RUNTIME_DIR=/tmp/runtime-root wineboot --init
sleep 5

setpriv --reuid=${PUID} --regid=${PGID} --init-groups env HOME=/home/wineuser DISPLAY=:99 WINEARCH=win32 WINEPREFIX=/home/wineuser/.wine32 XDG_RUNTIME_DIR=/tmp/runtime-root wine "C:\\Program Files\\MusicIP\\MusicMagicServer.exe" start

tail -f /dev/null
