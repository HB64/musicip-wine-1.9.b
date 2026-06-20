# MusicIP MusicMagic (Wine / Windows 1.9.b)

Docker image for running MusicIP MusicMagic — the classic music analysis and mix generation server — using the **headless Windows 1.9.b** build under Wine. The native Linux build is stuck at version 1.8; this image runs the newer Windows release instead.

## Before you start

### Permissions

The entrypoint automatically creates the `wineuser` account with the `PUID`/`PGID` you provide and takes ownership of the Wine prefix on startup, so no manual `chown` step is required. Just set `PUID`/`PGID` to match the owner of your music and config directories on the host.

### Seccomp

Wine needs the `personality` syscall to run the legacy 32-bit MusicMagicServer binary, which Docker's default seccomp profile blocks. This image uses a custom seccomp profile that allows only that specific syscall in addition to Docker's defaults — rather than disabling seccomp entirely.

Download `seccomp.json` from this repo into the same directory as your `compose.yaml` before starting:

```bash
wget https://raw.githubusercontent.com/hb64/musicip-wine-1.9.b/main/seccomp.json
```

### First-time setup

`mmm.ini` and `recipes.xml` are bind-mounted directly into MusicIP's install directory so you can edit them on the host. Docker will turn these into directories instead of files if they don't already exist, so download the default files from this repo **before** the first `up`:

```bash
mkdir -p /path/to/config
wget -O /path/to/config/mmm.ini https://raw.githubusercontent.com/hb64/musicip-wine-1.9.b/main/mmm.ini
wget -O /path/to/config/recipes.xml https://raw.githubusercontent.com/hb64/musicip-wine-1.9.b/main/recipes.xml
```

After that, you can edit either file on the host at any time — restart the container for changes to take effect.

## Usage

### docker-compose

```yaml
services:
  musicip:
    image: hb1964/musicip-wine-1.9.b:latest
    container_name: musicip
    restart: unless-stopped
    ports:
      - "10002:10002"
    volumes:
      - /path/to/config:/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP
      - /path/to/music:/music
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
    security_opt:
      - seccomp=./seccomp.json
```

### docker run

```bash
docker run -d \
  --name musicip \
  --security-opt seccomp=./seccomp.json \
  -e PUID=1000 \
  -e PGID=1000 \
  -e WINEARCH=win32 \
  -e WINEPREFIX=/home/wineuser/.wine32 \
  -e XDG_RUNTIME_DIR=/tmp/runtime-root \
  -e LANG=en_US.UTF-8 \
  -e LC_ALL=en_US.UTF-8 \
  -p 10002:10002 \
  -v /path/to/config:"/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP" \
  -v /path/to/music:/music \
  -v /path/to/config/moods:"/home/wineuser/.wine32/drive_c/Program Files/MusicIP/moods" \
  -v /path/to/config/mmm.ini:"/home/wineuser/.wine32/drive_c/Program Files/MusicIP/mmm.ini" \
  -v /path/to/config/recipes.xml:"/home/wineuser/.wine32/drive_c/Program Files/MusicIP/recipes.xml" \
  --restart unless-stopped \
  hb1964/musicip-wine-1.9.b:latest
```

The MusicIP API will be available at `http://localhost:10002`. Check it's up with:

```bash
curl http://localhost:10002/api/version
```

### Music path inside MusicIP

Your music is mounted into the container at `/music`, which Wine automatically maps to `Z:\music`. This is the path MusicIP will use to find your library.

**Fresh setup** — when MusicIP asks for your music folder on first run, enter:
```
Z:\music
```

**Migrating an existing `.m3lib`** — if your file already contains `Z:\music` paths (from a native Windows install or another MusicIP setup), it will work without any changes.

If your existing `.m3lib` contains `C:\music` paths (from an older version of this image), update them with:

```bash
sed -i 's|C:\\music|Z:\\music|g' /path/to/config/default.m3lib
```

## Parameters

| Parameter | Function |
|---|---|
| `PUID` | User ID for file permissions (default: `1000`) |
| `PGID` | Group ID for file permissions (default: `1000`) |
| `LANG` / `LC_ALL` | Locale, e.g. `en_US.UTF-8` |
| `-p 10002:10002` | MusicIP API |
| `-v ...AppData/Roaming/MusicIP` | Persistent database, recipes, and configuration |
| `-v .../music:/music` | Your music library (appears to MusicIP as `Z:\music`) |
| `-v .../MusicIP/moods` | Mood playlists |
| `-v .../mmm.ini` | MusicIP server configuration (user-editable) |
| `-v .../recipes.xml` | Mix generation recipes (user-editable) |
| `--security-opt seccomp=./seccomp.json` | Allows the `personality` syscall required by Wine |

## Troubleshooting

**Permission errors on volumes** — Make sure `PUID`/`PGID` match the owner of the mounted directories on the host.

**Container won't start / seccomp errors** — Make sure `seccomp.json` is present in the same directory as `compose.yaml` and was downloaded from this repo before running `docker compose up`.

**Wine error messages in logs (Vulkan, Bluetooth, RPC/OLE)** — These are harmless. Wine logs errors for Windows subsystems MusicIP doesn't use. As long as `curl http://localhost:10002/api/version` responds, everything is fine.

**Port conflict** — Change the host port, e.g. `-p 10003:10002`.

## Using with Lyrion Music Server (LMS)

If LMS runs on Linux and MusicIP runs on Windows (native or via Wine, locally or on a different machine), MusicIP returns Windows-style paths (`C:\music\...`) everywhere. LMS expects Linux paths (e.g. `/music/...`), and the bundled **MusicMagic** plugin (used by MusicIP Mixer and SugarCube) does **not** translate between the two. This causes two problems:

- **MusicIP Mixer mixes are empty** — every track is logged as "can't be found at that location".
- **Library scans create duplicate, unplayable track entries** — every "MusicIP-import" scan step (including automatic rescans triggered by file changes) adds bogus `C:\music\...`-based entries to the LMS database alongside the correct ones, which can also break SugarCube playback.

### Patch files

This repo includes two patched LMS plugin files in [`lms-patches/`](./lms-patches):

- `Plugin.pm` ? replaces `Slim/Plugin/MusicMagic/Plugin.pm`
- `Importer.pm` ? replaces `Slim/Plugin/MusicMagic/Importer.pm`

Both add a simple `C:\music` ? `/music` (and `\` ? `/`) translation before paths are used. **If your LMS music path isn't `/music`, edit the regex in both files accordingly.**

Mount them into your LMS container (read-only) over the originals:

```yaml
services:
  lms:
    volumes:
      - /path/to/lms-patches/Plugin.pm:/lms/Slim/Plugin/MusicMagic/Plugin.pm:ro
      - /path/to/lms-patches/Importer.pm:/lms/Slim/Plugin/MusicMagic/Importer.pm:ro
```

### One-time database cleanup

If you've been running without these patches, your LMS library database likely already contains bogus entries. After applying the `Importer.pm` patch, remove the old ones once:

```bash
docker stop lms

python3 - <<'EOF'
import sqlite3
conn = sqlite3.connect('/path/to/lms/cache/library.db')
cur = conn.cursor()
cur.execute("DELETE FROM tracks WHERE url LIKE '///./C:%'")
conn.commit()
print('Deleted:', cur.rowcount)
EOF

docker start lms
```

After this, MusicIP-import scans should produce clean `file:///music/...` URLs going forward, and both MusicIP Mixer and SugarCube should queue and play tracks correctly.

> These patches address an upstream LMS MusicMagic plugin limitation (no path translation, despite `server.prefs` having an unused `pathmap` setting). If/when this is fixed upstream, these patches and volume mounts can be removed.