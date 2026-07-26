#!/bin/bash
set -e

groupadd -g ${PGID} winegroup 2>/dev/null || true
useradd -u ${PUID} -g ${PGID} -d /home/wineuser -m -s /bin/bash wineuser 2>/dev/null || true

mkdir -p /tmp/runtime-root && chmod 700 /tmp/runtime-root
chown ${PUID}:${PGID} /tmp/runtime-root
rm -f /tmp/.X99-lock

# Create required directories (volumes are already mounted at this point)
mkdir -p "/home/wineuser/.wine32/drive_c/Program Files/MusicIP"
mkdir -p "/home/wineuser/.wine32/drive_c/users/wineuser/AppData/Roaming/MusicIP/"
mkdir -p "/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP/"

# Copy MusicIP binaries and default config from the image into the install
# directory. -n (no-clobber) skips anything already there. This directory is
# never bind-mounted as a whole, so mipcore.exe, MusicMagicServer.exe, the
# dlls and the client.pem/root.pem certs always come fresh from the image and
# are never host-writable.
cp -rn /opt/MusicIP/. "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/"

# /config is the only persistent, user-editable location, holding just
# mmm.ini, recipes.xml and moods/. Seed it from the image defaults on first
# run, then symlink it into the install directory so MusicMagicServer reads
# and writes the host copies directly - no sync step, so nothing it writes at
# runtime can ever be lost on the next restart.
mkdir -p /config/moods
[ -f /config/mmm.ini ] || cp "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/mmm.ini" /config/mmm.ini
[ -f /config/recipes.xml ] || cp "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/recipes.xml" /config/recipes.xml
chown -R ${PUID}:${PGID} /config

rm -f "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/mmm.ini"
rm -f "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/recipes.xml"
rm -rf "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/moods"
ln -s /config/mmm.ini "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/mmm.ini"
ln -s /config/recipes.xml "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/recipes.xml"
ln -s /config/moods "/home/wineuser/.wine32/drive_c/Program Files/MusicIP/moods"

# Fix ownership of everything
chown -R ${PUID}:${PGID} /home/wineuser

Xvfb :99 -screen 0 1024x768x24 &
sleep 3

setpriv --reuid=${PUID} --regid=${PGID} --init-groups env HOME=/home/wineuser DISPLAY=:99 WINEARCH=win32 WINEPREFIX=/home/wineuser/.wine32 XDG_RUNTIME_DIR=/tmp/runtime-root wineboot --init
sleep 5

setpriv --reuid=${PUID} --regid=${PGID} --init-groups env HOME=/home/wineuser DISPLAY=:99 WINEARCH=win32 WINEPREFIX=/home/wineuser/.wine32 XDG_RUNTIME_DIR=/tmp/runtime-root wine "C:\\Program Files\\MusicIP\\MusicMagicServer.exe" start

tail -f /dev/null
