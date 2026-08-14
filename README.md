# MusicIP MusicMagic (Wine / Windows 1.9.b)

Docker image for running MusicIP MusicMagic — the classic music analysis and mix generation server — using the **headless Windows 1.9.b** build under Wine. The native Linux build is stuck at version 1.8; this image runs the newer Windows release instead.

## Before you start

### Permissions

The entrypoint automatically creates the `wineuser` account with the `PUID`/`PGID` you provide and takes ownership of the Wine prefix on startup, so no manual `chown` step is required. Just set `PUID`/`PGID` to match the owner of your music (and, if used, config) directory on the host.

The container also runs with all Linux capabilities dropped except the handful actually needed for that setup step (`CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE`, `FOWNER`) — see the compose/run examples below. The entrypoint uses `setpriv` (part of `util-linux`, already present in the base image) to drop from root to `wineuser` before launching Wine and MusicMagicServer. Unlike an earlier version of this image, no custom seccomp profile is required — Wine's `personality` syscall runs fine under Docker's own default seccomp profile when `setpriv` handles the privilege drop, so there's no `seccomp.json` to download or maintain.

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

Your music is mounted into the container at `/music`, which Wine automatically maps to `Z:\music`. This is the path MusicIP will use to find your library, and the "Add music folder" button on the web UI (`http://localhost:10002`) is pre-filled with it — just click **Add music**, no typing required for a standard setup.

**If your setup differs** — for example if you mounted your music volume to a different container path instead of `/music` — you'll need to change it in two places so they stay in sync:

1. **`compose.yaml`** — change the container-side path in the volume mount, e.g. `/path/to/music:/mymusic:ro`.
2. **Web UI** — tick **"Music folder differs from Z:\music"** under Add music folder, and enter the matching Wine path yourself (e.g. `Z:\mymusic`, since Wine's `Z:` drive always maps to the container's `/`).

**Fresh setup** — for a standard `/music` mount, just click **Add music** in the web UI; the field is already filled with   `Z:\music`.

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
| `--security-opt no-new-privileges:true` | Blocks privilege escalation via setuid binaries inside the container |
| `--cap-drop ALL` + `--cap-add ...` | Restricts the container to only the capabilities its setup steps actually use |

## Troubleshooting

**Permission errors on volumes** — Make sure `PUID`/`PGID` match the owner of the mounted directories on the host.

**Container won't start / "Operation not permitted" in logs** — Usually means one of the dropped capabilities is needed after all. Check which syscall or operation failed in the log and add the matching `--cap-add` back; the five listed above cover a stock setup.

**Wine error messages in logs (Vulkan, Bluetooth, RPC/OLE)** — These are harmless. Wine logs errors for Windows subsystems MusicIP doesn't use. As long as `curl http://localhost:10002/api/version` responds, everything is fine.

**Port conflict** — Change the host port, e.g. `-p 10003:10002`.

**Music folder not found / "Add music folder" fails** — Confirm the container-side path in your volume mount (`compose.yaml`) matches what you enter in the web UI (see "Music path inside MusicIP" above). They must point to the same folder.

## Using with Lyrion Music Server (LMS)

When MusicIP 1.9.b runs under Wine, it stores and returns paths in Windows format (`Z:\music\...`). LMS runs on Linux and expects `/music/...`. Two components need to handle this translation: the MusicMagic plugin patches (for Moods Mixer) and SugarCube's Dynamic Path Conversion (for SugarCube mixing).

> **Switching between 1.8 and 1.9.b is safe.** A standard "Wipe library and rescan all" in LMS is sufficient when switching versions — no container rebuild is required.

### MusicIP Moods Mixer — MusicMagicCE plugin (required)

LMS's native MusicMagic plugin has no way to translate the Windows-style paths (`Z:\music\...`) that MusicIP reports under Wine into the Linux paths (`/music/...`) LMS expects, so **MusicIP Moods Mixer** (LMS's native browse-by-mix / Mood Mix) won't find any tracks without this. Install **[MusicMagicCE](https://github.com/HB64/Lyrion-MusicMagic)** — a drop-in replacement for LMS's stock MusicMagic plugin (for LMS 9.1.x) that adds a configurable **Dynamic Path Conversion** setting for exactly this, plus a configurable host and genre filters.

In LMS, go to **Settings → Plugins → Additional Repositories** and add:

\`\`\`
https://raw.githubusercontent.com/HB64/Lyrion-MusicMagic/main/public.xml
\`\`\`

Install **MusicMagicCE** from the plugin list, then in its settings enable Dynamic Path Conversion:

\`\`\`
Enable Dynamic Path Conversion: ✓ checked
MusicIP path (source):      Z:\music
Lyrion path (destination):  /music
\`\`\`

When running MusicIP 1.8, this is unnecessary — leave Dynamic Path Conversion disabled, or don't install the plugin at all.

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

#### ⚠️ "Match ANY" + a single `is not` condition can silently return your whole library

This one isn't a 1.9.b-specific regression — it's how AND/OR always worked in MusicIP — but it's very easy to trip over, and the result looks like the filter is simply being ignored.

**Match ANY** is an OR across every condition in the filter. Adding even one `Artist is not X` (or `Genre is not X`) condition to an otherwise well-targeted Match ANY filter can undo it almost entirely: `NOT(X)` is true for nearly every track in your library except X's own, so under OR logic that single condition alone lets nearly everything through, regardless of how narrow the other conditions are.

Confirmed example: a Match ANY filter with 9 inclusive `is` conditions (a curated set of genres/artists) correctly returned tracks spanning 6 genres. Adding one `Artist is not <name>` condition to the same filter — still Match ANY — widened the result to 26 genres and 3,633 artists: essentially the entire library.

MusicIP's filter only has one match mode for its whole condition list, so there's no way to express "(any of these) AND (not this)" inside a single filter. Two practical workarounds:

- **Keep exclusions out of Match ANY filters.** If you need both inclusion and exclusion logic, split it into two filters (one Match ANY for inclusions, one Match ALL for exclusions) and combine them at the recipe level, if your recipe setup supports AND-ing filters together.
- **Use SugarCube's artist weighting instead of a MIP exclusion filter.** SugarCube can assign a negative weight to specific artists (up to 3 per weighting slot) to make them play less often, without needing to exclude them via a filter condition at all. For "I basically never want to hear artist X" this sidesteps the Match ANY/`is not` trap entirely, since the filter itself never needs a negative condition.

Test a filter directly via the API to verify it works before relying on it in SugarCube:

```bash
curl "http://localhost:10002/api/mix?song=Z%3A%5Cmusic%5C<encoded path>&size=5&filter=<filtername>"
```

### Further documentation

See **[docs/musicip-19b-mixed-systems.md](./docs/musicip-19b-mixed-systems.md)** for a full technical breakdown including log signatures, root cause analysis, and the complete list of configuration layers.
