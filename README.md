# MusicIP MusicMagic (Wine / Windows 1.9.b)

Docker image for running MusicIP MusicMagic — the classic music analysis and mix generation server — using the **headless Windows 1.9.b** build under Wine. The native Linux build is stuck at version 1.8; this image runs the newer Windows release instead.

## Before you start

### Permissions

The entrypoint automatically creates the `wineuser` account with the `PUID`/`PGID` you provide and takes ownership of the Wine prefix on startup, so no manual `chown` step is required. Just set `PUID`/`PGID` to match the owner of your music (and, if used, config) directory on the host.

The container also runs with all Linux capabilities dropped except the handful actually needed for that setup step (`CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE`, `FOWNER`) — see the compose/run examples below.

### Seccomp

Wine needs the `personality`, `modify_ldt`, `get_thread_area` and `set_thread_area` syscalls to run the 32-bit MusicMagicServer binary, which a from-scratch minimal seccomp profile would block. This image ships a seccomp profile based on Docker's own default profile, trimmed of syscalls that are either architecture-irrelevant on x86_64 or definitely unused by this workload (legacy DOS virtual-mode syscalls, unconditional `ptrace`). It's used together with `cap_drop: ALL`, which is what actually neutralizes the profile's capability-gated entries (`mount`, `bpf`, `reboot`, etc.) rather than the syscall list alone.

Download `seccomp.json` from this repo into the same directory as your `compose.yaml` before starting:

```bash
wget https://raw.githubusercontent.com/hb64/musicip-wine-1.9.b/main/seccomp.json
```

### mmm.ini / recipes.xml (optional)

The image ships with working defaults for `mmm.ini` and `recipes.xml`, and creates them inside the container automatically — **no setup needed for a standard installation.**

You only need to do anything here if you want to customize these files and have your changes survive container restarts/recreates — most commonly to edit `recipes.xml` and add your own mix filters. In that case, mount a `/config` volume (see "Customizing mmm.ini / recipes.xml" below); the entrypoint then seeds it with the default files on first run, symlinks them into MusicIP's install directory, and never touches them again once they exist.

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
      - /path/to/appdata:/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP
      - /path/to/music:/music:ro
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
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
      - DAC_OVERRIDE
      - FOWNER
```

### docker run

```bash
docker run -d \
  --name musicip \
  --security-opt seccomp=./seccomp.json \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-add DAC_OVERRIDE \
  --cap-add FOWNER \
  -e PUID=1000 \
  -e PGID=1000 \
  -e WINEARCH=win32 \
  -e WINEPREFIX=/home/wineuser/.wine32 \
  -e XDG_RUNTIME_DIR=/tmp/runtime-root \
  -e LANG=en_US.UTF-8 \
  -e LC_ALL=en_US.UTF-8 \
  -p 10002:10002 \
  -v /path/to/appdata:"/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP" \
  -v /path/to/music:/music:ro \
  --restart unless-stopped \
  hb1964/musicip-wine-1.9.b:latest
```

The MusicIP API will be available at `http://localhost:10002`. Check it's up with:

```bash
curl http://localhost:10002/api/version
```
### Music path inside MusicIP

Your music is mounted into the container at `/music`, which Wine automatically maps to `Z:\music`. This is the path MusicIP will use to find your library.

**Fresh setup**  — when on the MusicIP interface you see a part ""Add music folder", type:
```
Z:\music

```
And hit the "Add" button on the right side of it.


**Migrating an existing `.m3lib`** — if your file already contains `Z:\music` paths (from a native Windows install or another MusicIP setup), it will work without any changes.

If your existing `.m3lib` contains `C:\music` paths (from an older version of this image), update them with:

```bash
sed -i 's|C:\\music|Z:\\music|g' /path/to/appdata/default.m3lib
```

### Customizing mmm.ini / recipes.xml

By default, `mmm.ini` and `recipes.xml` live only inside the container and reset to the image defaults on every recreate. To edit them yourself — for example to add new mix filters to `recipes.xml` — mount a `/config` volume:

```yaml
    volumes:
      - /path/to/appdata:/home/wineuser/.wine32/drive_c/users/root/AppData/Roaming/MusicIP
      - /path/to/music:/music:ro
      - /path/to/config:/config
```

(or `-v /path/to/config:/config` for `docker run`)

On first start with an empty `/config`, the container copies the default `mmm.ini` and `recipes.xml` there for you to edit; `moods/` is created alongside them. From then on, edit the files on the host at any time — MusicMagicServer reads and writes them directly (they're symlinked in, not copied), so nothing you or the app change is ever lost on restart, and the container only ever touches them if they don't already exist.


## Parameters

| Parameter | Function |
|---|---|
| `PUID` | User ID for file permissions (default: `1000`) |
| `PGID` | Group ID for file permissions (default: `1000`) |
| `LANG` / `LC_ALL` | Locale, e.g. `en_US.UTF-8` |
| `-p 10002:10002` | MusicIP API |
| `-v ...AppData/Roaming/MusicIP` | Persistent database and MusicIP user data |
| `-v .../music:/music:ro` | Your music library, read-only (appears to MusicIP as `Z:\music`) |
| `-v .../config:/config` | *(optional)* Persistent, editable `mmm.ini`, `recipes.xml` and `moods/` |
| `--security-opt seccomp=./seccomp.json` | Allows the syscalls Wine needs (`personality`, `modify_ldt`, etc.) |
| `--security-opt no-new-privileges:true` | Blocks privilege escalation via setuid binaries inside the container |
| `--cap-drop ALL` + `--cap-add ...` | Restricts the container to only the capabilities its setup steps actually use |

## Troubleshooting

**Permission errors on volumes** — Make sure `PUID`/`PGID` match the owner of the mounted directories on the host.

**Container won't start / seccomp errors** — Make sure `seccomp.json` is present in the same directory as `compose.yaml` and was downloaded from this repo before running `docker compose up`.

**Container won't start / "Operation not permitted" in logs** — Usually means one of the dropped capabilities is needed after all. Check which syscall or operation failed in the log and add the matching `--cap-add` back; the five listed above cover a stock setup.

**Wine error messages in logs (Vulkan, Bluetooth, RPC/OLE)** — These are harmless. Wine logs errors for Windows subsystems MusicIP doesn't use. As long as `curl http://localhost:10002/api/version` responds, everything is fine.

**Port conflict** — Change the host port, e.g. `-p 10003:10002`.

## Using with Lyrion Music Server (LMS)

If LMS runs on Linux and MusicIP runs on Windows (native or via Wine, locally or on a different machine), MusicIP returns Windows-style paths (`Z:\music\...`) everywhere. LMS expects Linux paths (e.g. `/music/...`), and the bundled **MusicMagic** plugin (used by MusicIP Mixer and SugarCube) does **not** translate between the two. This causes two problems:

- **MusicIP Mixer mixes are empty** — every track is logged as "can't be found at that location".
- **Library scans create duplicate, unplayable track entries** — every "MusicIP-import" scan step (including automatic rescans triggered by file changes) adds bogus `Z:\music\...`-based entries to the LMS database alongside the correct ones, which can also break SugarCube playback.

### Patch files

This repo includes two patched LMS plugin files in [`lms-patches/`](./lms-patches):

- `Plugin.pm` — replaces `Slim/Plugin/MusicMagic/Plugin.pm`
- `Importer.pm` — replaces `Slim/Plugin/MusicMagic/Importer.pm`

Both add a simple `Z:\music` → `/music` (and `\` → `/`) translation before paths are used. **If your LMS music path isn't `/music`, edit the regex in both files accordingly.**

Download them into a directory on the host before starting your LMS container:

```bash
mkdir -p /path/to/lms-patches
wget -O /path/to/lms-patches/Plugin.pm https://raw.githubusercontent.com/hb64/musicip-wine-1.9.b/main/lms-patches/Plugin.pm
wget -O /path/to/lms-patches/Importer.pm https://raw.githubusercontent.com/hb64/musicip-wine-1.9.b/main/lms-patches/Importer.pm
```

Then mount them into your LMS container (read-only) over the originals:

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
cur.execute("DELETE FROM tracks WHERE url LIKE '///./Z:%'")
conn.commit()
print('Deleted:', cur.rowcount)
EOF

docker start lms
```

After this, MusicIP-import scans should produce clean `file:///music/...` URLs going forward, and both MusicIP Mixer and SugarCube should queue and play tracks correctly.

> These patches address an upstream LMS MusicMagic plugin limitation (no path translation, despite `server.prefs` having an unused `pathmap` setting). If/when this is fixed upstream, these patches and volume mounts can be removed.
