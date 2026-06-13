# MusicIP MusicMagic (Wine / Windows 1.9.b)

Docker image for running MusicIP MusicMagic — the classic music analysis and mix generation server — using the **headless Windows 1.9.b** build under Wine. The native Linux build is stuck at version 1.8; this image runs the newer Windows release instead.

## Before you start

### Permissions

The entrypoint automatically creates the `wineuser` account with the `PUID`/`PGID` you provide and takes ownership of the Wine prefix on startup, so no manual `chown` step is required. Just set `PUID`/`PGID` to match the owner of your music and config directories on the host.

### Seccomp

This image requires `seccomp:unconfined`. Wine needs broader syscall access than Docker's default seccomp profile allows to run the legacy 32-bit MusicMagicServer binary.

### First-time setup

`mmm.ini` and `recipes.xml` are bind-mounted directly into MusicIP's install directory so you can edit them on the host. Docker will turn these into directories instead of files if they don't already exist, so download the default files from this repo **before** the first `up`:

```bash
mkdir -p /path/to/config
wget -O /path/to/config/mmm.ini https://raw.githubusercontent.com/youruser/yourrepo/main/mmm.ini
wget -O /path/to/config/recipes.xml https://raw.githubusercontent.com/youruser/yourrepo/main/recipes.xml
```

After that, you can edit either file on the host at any time — restart the container for changes to take effect.

## Usage

### docker-compose

```yaml
services:
  musicip:
    image: youruser/musicip-wine:latest
    container_name: musicip
    restart: unless-stopped
    ports:
      - "10002:10002"
    volumes:
      - /path/to/config:/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP
      - /path/to/music:/home/wineuser/.wine32/drive_c/music
      - /path/to/config/moods:/home/wineuser/.wine32/drive_c/Program Files/MusicIP/moods
      - /path/to/config/mmm.ini:/home/wineuser/.wine32/drive_c/Program Files/MusicIP/mmm.ini
      - /path/to/config/recipes.xml:/home/wineuser/.wine32/drive_c/Program Files/MusicIP/recipes.xml
    environment:
      - PUID=1000
      - PGID=1000
      - WINEARCH=win32
      - WINEPREFIX=/home/wineuser/.wine32
      - XDG_RUNTIME_DIR=/tmp/runtime-root
      - LANG=en_US.UTF-8
      - LC_ALL=en_US.UTF-8
    cap_add:
      - SYS_PTRACE
    security_opt:
      - seccomp:unconfined
```

### docker run

```bash
docker run -d \
  --name musicip \
  --cap-add SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -e PUID=1000 \
  -e PGID=1000 \
  -e WINEARCH=win32 \
  -e WINEPREFIX=/home/wineuser/.wine32 \
  -e XDG_RUNTIME_DIR=/tmp/runtime-root \
  -e LANG=en_US.UTF-8 \
  -e LC_ALL=en_US.UTF-8 \
  -p 10002:10002 \
  -v /path/to/config:"/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP" \
  -v /path/to/music:/home/wineuser/.wine32/drive_c/music \
  -v /path/to/config/moods:"/home/wineuser/.wine32/drive_c/Program Files/MusicIP/moods" \
  -v /path/to/config/mmm.ini:"/home/wineuser/.wine32/drive_c/Program Files/MusicIP/mmm.ini" \
  -v /path/to/config/recipes.xml:"/home/wineuser/.wine32/drive_c/Program Files/MusicIP/recipes.xml" \
  --restart unless-stopped \
  youruser/musicip-wine:latest
```

The MusicIP API will be available at `http://localhost:10002`. Check it's up with:

```bash
curl http://localhost:10002/api/version
```

## Parameters

| Parameter | Function |
|---|---|
| `PUID` | User ID for file permissions (default: `1000`) |
| `PGID` | Group ID for file permissions (default: `1000`) |
| `LANG` / `LC_ALL` | Locale, e.g. `en_US.UTF-8` |
| `-p 10002:10002` | MusicIP API |
| `-v ...AppData/Roaming/MusicIP` | Persistent database, recipes, and configuration |
| `-v .../drive_c/music` | Your music library (appears to MusicIP as `C:\music`) |
| `-v .../MusicIP/moods` | Mood playlists |
| `-v .../mmm.ini` | MusicIP server configuration (user-editable) |
| `-v .../recipes.xml` | Mix generation recipes (user-editable) |
| `--cap-add SYS_PTRACE` | Required by Wine |
| `--security-opt seccomp=unconfined` | Required by Wine to run the legacy 32-bit binary |

## Troubleshooting

**Permission errors on volumes** — Make sure `PUID`/`PGID` match the owner of the mounted directories on the host.

**Container won't start / seccomp errors** — Make sure `seccomp:unconfined` is set; MusicMagicServer cannot start under Docker's default seccomp profile.

**`mmm.ini` or `recipes.xml` became a directory** — This happens if the file didn't exist on the host before the first start. Stop the container, remove the directory, re-download the file with `wget` as shown in First-time setup, and start again.

**Wine error messages in logs (Vulkan, Bluetooth, RPC/OLE)** — These are harmless. Wine logs errors for Windows subsystems MusicIP doesn't use. As long as `curl http://localhost:10002/api/version` responds, everything is fine.

**Port conflict** — Change the host port, e.g. `-p 10003:10002`.

## Using with Lyrion Music Server (LMS)

If LMS and MusicIP run in separate containers or hosts, MusicIP returns Windows-style paths (`C:\music\...`) in its API responses. LMS plugins (MusicIP Mixer, SugarCube) need to translate these to your actual Linux music path (e.g. `/music/...`) — check the plugin's settings for path mapping options.
