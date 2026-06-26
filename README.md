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

### Music path inside MusicIP

Your music is mounted into the container at `/music`, which Wine automatically maps to `Z:\music`. This is the path MusicIP will use to find your library.

**Fresh setup** — when MusicIP asks for your music folder on first run, enter:
```
Z:\music
```

**Migrating an existing `.m3lib`** — if your file already contains `Z:\music` paths (from a native Windows install or another MusicIP setup), it will work without any changes.

If your existing `.m3lib` contains `C:\music` paths (from an older version of this image), update them with:

```bash
sed -i 's|C:\\music|Z:\\music|g' /path/to/appdata/default.m3lib
```

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

When MusicIP 1.9.b runs under Wine, it stores and returns paths in Windows format (`Z:\music\...`). LMS runs on Linux and expects `/music/...`. Two components need to handle this translation: the MusicMagic plugin patches (for Moods Mixer) and SugarCube's Dynamic Path Conversion (for SugarCube mixing).

> **Switching between 1.8 and 1.9.b is safe.** A standard "Wipe library and rescan all" in LMS is sufficient when switching versions — no container rebuild is required.

### MusicIP Moods Mixer — patch files

The patches are required for **MusicIP Moods Mixer** (LMS's native browse-by-mix / Mood Mix). They are **not** required for SugarCube, which has its own path translation. When running MusicIP 1.8 (native Linux), the patches are a no-op — safe to include but not needed.

This repo includes two patched LMS plugin files in [`lms-patches/`](./lms-patches):

- `Plugin.pm` — replaces `Slim/Plugin/MusicMagic/Plugin.pm`
- `Importer.pm` — replaces `Slim/Plugin/MusicMagic/Importer.pm`

Both add a `Z:\music` → `/music` (and `\` → `/`) translation before paths are used. **If your LMS music path isn't `/music`, edit the regex in both files accordingly.**

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

> These patches address an upstream LMS MusicMagic plugin limitation (no path translation, despite `server.prefs` having an unused `pathmap` setting). If/when this is fixed upstream, these patches and volume mounts can be removed.

### SugarCube — Dynamic Path Conversion

SugarCube has its own path translation pipeline independent of the patches above. When using MusicIP 1.9.b, enable and configure Dynamic Path Conversion in the SugarCube global settings:

```
Enable Dynamic Path Conversion: ✓ checked
DPC (LMS) - Set #1 Destination:  /music
DPC (MusicIP) - Set #1 Source:   Z:\music
```

When running MusicIP 1.8, these settings are a no-op — safe to leave in place.

### ⚠️ MusicIP 1.9.b filter behaviour — stricter than 1.8

MusicIP 1.9.b enforces stricter rules for filter conditions than 1.8. Filters that worked in 1.8 can silently fail in 1.9.b with `MUSICIP RETURNED NOTHING`. **Review all your filters in the MusicIP Mixer GUI after migrating from 1.8.**

Known differences:

- **"Match ALL" with multiple Artist conditions** — no track can match multiple artists simultaneously, so the filter always returns nothing. Change to **"Match ANY"**.
- **Mixing `is` and `is not` conditions** — combining positive and negative conditions in the same filter fails in 1.9.b even when logically valid. Keep filters to either all `is` or all `is not` conditions.

Test a filter directly via the API to verify it works before relying on it in SugarCube:

```bash
curl "http://localhost:10002/api/mix?song=Z%3A%5Cmusic%5C<encoded path>&size=5&filter=<filtername>"
```

### Further documentation

See **[docs/musicip-19b-mixed-systems.md](./docs/musicip-19b-mixed-systems.md)** for a full technical breakdown including log signatures, root cause analysis, and the complete list of configuration layers.
