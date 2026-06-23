# MusicIP → LMS path translation: substitution order bug

**Status:** Resolved (current deployment is correct). Documented for future reference in case it resurfaces.

## Symptom

LMS's native MusicIP `getMix()` (`Slim::Plugin::MusicMagic::Plugin`) would silently drop tracks from a mix. No crash, no visible error to the user â€” tracks simply never made it into the player queue. SugarCube's own Dynamic Shuffle Track Mixing pipeline was unaffected (see "Scope" below), but the native LMS MusicIP "Mix"/Mood Mix path was hit.

The only trace was a default-level (`ERROR`) log line:

```
Slim::Plugin::MusicMagic::Plugin::getMix MIP attempted to mix in a song at Z:/music/Artist/Album/Track.flac that can't be found at that location
```

## Root cause

Both `Plugin.pm` (`getMix`) and `Importer.pm` (`processSong`) translate MusicIP's Windows-style path into the Linux path LMS expects, using two sequential regex substitutions:

```perl
$song =~ s|^Z:\\music|/music|i;   # strip the Z:\music prefix
$song =~ s|\\|/|g;                # convert remaining backslashes to forward slashes
```

This only works if the prefix-stripping regex runs **first**, while the path still contains literal backslashes (`Z:\music\...`). If the order is reversed â€” backslash-to-slash conversion first â€” the string becomes `Z:/music/...` before the prefix regex ever runs. At that point `s|^Z:\\music|/music|i` is looking for a literal backslash that no longer exists, so it silently fails to match, and the `Z:` prefix is left permanently attached.

The resulting malformed path (`Z:/music/Artist/...` instead of `/music/Artist/...`) then fails the `-e $songs[$j]` filesystem existence check in `getMix()`, so the track is dropped from the mix before it's ever pushed onto `@mix` / queued in LMS.

## Log signature reference

| Pattern in log | Meaning |
|---|---|
| `Z:\music\Artist\...` (raw, unconverted) | Patch not applied / not deployed at all |
| `Z:/music/Artist/...` (slashes converted, `Z:` prefix survives) | **Substitution order bug** â€” backslash conversion ran before prefix strip |
| `/music/Artist/...` (clean) | Working correctly |

## Correct order

```perl
$song =~ s|^Z:\\music|/music|i;   # MUST run first
$song =~ s|\\|/|g;                # then this
```

Same ordering requirement applies to the equivalent block in `Importer.pm`'s `processSong`.

## Scope â€” what this bug does and doesn't affect

- **Affected:** LMS's native MusicIP integration â€” `Slim::Plugin::MusicMagic::Plugin::getMix()` (browse-by-mix, Mood Mix, instant mix) and the library scan/import path in `Importer.pm`.
- **Not affected:** SugarCube's own Dynamic Shuffle Track Mixing (DSTM) queueing. SugarCube has its own independent path-translation logic, configured via its own plugin settings (`localmediapath`/`nasconvertpath`/"Dynamic" variants â€” visible in `Plugins::SugarCube::Plugin::buildMIPReq` log output), and does not route through the `Plugin.pm`/`Importer.pm` code above. SugarCube continuing to work while native MusicIP mixing silently failed is consistent with this separation, not contradictory.

## How this was found

Confirmed via direct MusicIP API testing (`/api/version`, `/api/mix?song=...`) showing MusicIP itself returning correct, well-formed `Z:\music\...` paths, combined with LMS server log analysis showing the `Z:/music/...` partial-conversion signature on the native mix path, and a clean run with no such errors after redeployment in a new bare-Debian Docker host (June 2026 environment migration).

---

## âš ï¸ Warning: MusicIP 1.9.b on mixed systems â€” silent LMS database corruption

> **This applies to any setup combining MusicIP 1.9.b (Wine/Docker) with Lyrion Music Server on Linux.**

### The core problem

MusicIP 1.9.b is a Windows binary running under Wine. It stores paths internally in Windows format (`Z:\music\Artist\Album\Track.flac`). LMS runs on Linux and expects `file:///music/Artist/Album/Track.flac`. Between those two worlds sits a large number of layers that must **all be correct simultaneously**:

| Layer | What can go wrong |
|---|---|
| Wine drive mapping | `Z:` symlink does not point to `/` |
| Docker volume mount | Music not mounted at `/music` but e.g. `/mnt/2TB1/Muziek` |
| `Plugin.pm` regex order | Prefix strip runs after backslash conversion â†’ `Z:/music/...` |
| `Importer.pm` regex order | Same problem |
| SugarCube `localmediapath`/`nasconvertpath` | Wrong path or not configured |
| LMS database after rescan | Built with incorrect paths |
| Playlists written by LMS | Permanently contain the incorrect paths |
| WinSCP transfer mode | Text mode adds `\r` to `.pm` files |

### Why this is so dangerous

**The failures are completely silent.** There is no crash, no visible error message to the user. Tracks are simply never added to the queue. The only traces are buried deep in the LMS server log at ERROR level:

```
Slim::Plugin::MusicMagic::Plugin::getMix MIP attempted to mix in a song at
Z:/music/Artist/Album/Track.flac that can't be found at that location
```

Meanwhile LMS continues writing undisturbed:
- The database gets filled with incorrect `file:///mnt/2TB1/Muziek/...` or `file:///Z:/music/...` paths
- Playlists are saved containing those incorrect paths
- SugarCube may continue working simultaneously (it has its own path translation pipeline), making it appear as though the problem is only partial

### The damage is unrecoverable without a full rebuild

There is no "undo" or "fix paths" function in LMS. Once the database and playlists have been populated with incorrect paths, the only solution is:

1. Completely remove the LMS container
2. Wipe the LMS database (or delete the volume)
3. Delete all playlists written by LMS
4. Rebuild the container with the correct configuration
5. Run a full library rescan
6. Run the MusicIP import again

This has been confirmed in practice by multiple users â€” a partial fix or database repair does not work reliably.

### Required configuration â€” all or nothing

For a working setup, **all** of the following must be correct before LMS starts for the first time:

```yaml
# compose.yaml MusicIP container
volumes:
  - /mnt/2TB1/Muziek:/music          # /music â€” not the host path!

# compose.yaml LMS container
volumes:
  - /mnt/2TB1/Muziek:/music          # Same internal path as the MusicIP container
  - /path/to/Plugin.pm:/usr/share/squeezeboxserver/Slim/Plugin/MusicMagic/Plugin.pm
  - /path/to/Importer.pm:/usr/share/squeezeboxserver/Slim/Plugin/MusicMagic/Importer.pm
```

```perl
# Plugin.pm and Importer.pm â€” order is critical
$song =~ s|^Z:\\music|/music|i;   # FIRST â€” prefix strip
$song =~ s|\\|/|g;                # THEN â€” backslash conversion
```

```
# SugarCube plugin settings (per player)
localmediapath:   /music
nasconvertpath:   Z:\music
```

**Only after** verifying all of the above should LMS be started for the first time and the library scan begun.

### Why 1.8 does not have this problem

MusicIP 1.8 is a native Linux binary. It communicates directly in Linux paths â€” no Wine, no Windows path notation, no translation layer. On a pure Linux setup with 1.8, none of this applies.

---

## Verification test (not yet run)

To confirm definitively (optional, deliberately reintroduces the bug â€” revert immediately after):

```perl
# Swap order to reproduce:
$song =~ s|\\|/|g;
$song =~ s|^Z:\\music|/music|i;
```

If this reintroduces `Z:/music/...`-pattern failures in the log, that's conclusive proof of the order dependency.
