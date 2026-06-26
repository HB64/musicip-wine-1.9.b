# MusicIP → LMS path translation: substitution order bug

**Status:** Resolved (current deployment is correct). Documented for future reference in case it resurfaces.

## Symptom

LMS's native MusicIP `getMix()` (`Slim::Plugin::MusicMagic::Plugin`) would silently drop tracks from a mix. No crash, no visible error to the user — tracks simply never made it into the player queue. SugarCube's own Dynamic Shuffle Track Mixing pipeline was unaffected (see "Scope" below), but the native LMS MusicIP "Mix"/Mood Mix path was hit.

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

This only works if the prefix-stripping regex runs **first**, while the path still contains literal backslashes (`Z:\music\...`). If the order is reversed — backslash-to-slash conversion first — the string becomes `Z:/music/...` before the prefix regex ever runs. At that point `s|^Z:\\music|/music|i` is looking for a literal backslash that no longer exists, so it silently fails to match, and the `Z:` prefix is left permanently attached.

The resulting malformed path (`Z:/music/Artist/...` instead of `/music/Artist/...`) then fails the `-e $songs[$j]` filesystem existence check in `getMix()`, so the track is dropped from the mix before it's ever pushed onto `@mix` / queued in LMS.

## Log signature reference

| Pattern in log | Meaning |
|---|---|
| `Z:\music\Artist\...` (raw, unconverted) | Patch not applied / not deployed at all |
| `Z:/music/Artist/...` (slashes converted, `Z:` prefix survives) | **Substitution order bug** — backslash conversion ran before prefix strip |
| `/music/Artist/...` (clean) | Working correctly |

## Correct order

```perl
$song =~ s|^Z:\\music|/music|i;   # MUST run first
$song =~ s|\\|/|g;                # then this
```

Same ordering requirement applies to the equivalent block in `Importer.pm`'s `processSong`.

## Scope — what this bug does and doesn't affect

- **Affected:** LMS's native MusicIP integration — `Slim::Plugin::MusicMagic::Plugin::getMix()` (browse-by-mix, Mood Mix, instant mix) and the library scan/import path in `Importer.pm`. **Only relevant when running MusicIP 1.9.b under Wine.** When running MusicIP 1.8 (native Linux), both MusicIP and LMS use `/music/...` paths natively and no translation is needed — the patches are a no-op but do not cause harm.
- **Not affected:** SugarCube's own Dynamic Shuffle Track Mixing (DSTM) queueing. SugarCube has its own independent path-translation logic, configured via its own plugin settings (`localmediapath`/`nasconvertpath`/"Dynamic" variants — visible in `Plugins::SugarCube::Plugin::buildMIPReq` log output), and does not route through the `Plugin.pm`/`Importer.pm` code above. SugarCube continuing to work while native MusicIP mixing silently failed is consistent with this separation, not contradictory.

## How this was found

Confirmed via direct MusicIP API testing (`/api/version`, `/api/mix?song=...`) showing MusicIP itself returning correct, well-formed `Z:\music\...` paths, combined with LMS server log analysis showing the `Z:/music/...` partial-conversion signature on the native mix path, and a clean run with no such errors after redeployment in a new bare-Debian Docker host (June 2026 environment migration).

---

## ⚠️ Warning: MusicIP 1.9.b on mixed systems — known issues and required configuration

> **This applies to any setup combining MusicIP 1.9.b (Wine/Docker) with Lyrion Music Server on Linux.**

### The core problem

MusicIP 1.9.b is a Windows binary running under Wine. It stores paths internally in Windows format (`Z:\music\Artist\Album\Track.flac`). LMS runs on Linux and expects `file:///music/Artist/Album/Track.flac`. Between those two worlds sits a number of layers that must all be correct:

| Layer | What can go wrong | Required for |
|---|---|---|
| Wine drive mapping | `Z:` symlink does not point to `/` | Both SugarCube and Moods Mixer |
| Docker volume mount | Music not mounted at `/music` | Both |
| `Plugin.pm` regex order | Prefix strip runs after backslash conversion → `Z:/music/...` | Moods Mixer only |
| `Importer.pm` regex order | Same problem | Moods Mixer only |
| SugarCube DPC enabled + configured | `localmediapath`/`nasconvertpath` wrong or not set | SugarCube only |
| MusicIP filter conditions | See filter behaviour section below | Both |

### What requires the patched Plugin.pm / Importer.pm

The patches are **only required for the MusicIP Moods Mixer** (LMS's native MusicIP browse-by-mix / Mood Mix / instant mix). SugarCube has its own path translation pipeline and does not use these files for its mixing.

When running MusicIP **1.8** (native Linux), both MusicIP and LMS use `/music/...` paths natively — the patches are a no-op and can safely be left in place or omitted.

### What requires SugarCube DPC configuration

SugarCube's Dynamic Path Conversion must be **enabled and configured** when using MusicIP 1.9.b:

```
Enable Dynamic Path Conversion: ✓ checked
DPC (LMS) - Set #1 Destination:  /music
DPC (MusicIP) - Set #1 Source:   Z:\music
```

When running MusicIP **1.8**, these settings are a no-op — SugarCube converts `/music` → `Z:\music` and back, ending up at `/music` again with no net effect.

### Switching between 1.8 and 1.9.b

Switching between the 1.8 and 1.9.b containers is safe. A standard **"Wipe library and rescan all"** in LMS is sufficient — no database corruption occurs and no container rebuild is required. The earlier warning about unrecoverable database corruption applied specifically to running 1.9.b with an incorrect volume mount (e.g. music mounted at `/mnt/2TB1/Muziek` instead of `/music`), not to switching between versions.

### Required configuration for 1.9.b

```yaml
# compose.yaml MusicIP container
volumes:
  - /path/to/music:/music          # /music — not the host path!

# compose.yaml LMS container
volumes:
  - /path/to/music:/music          # Same internal path as the MusicIP container
  - /path/to/Plugin.pm:/usr/share/squeezeboxserver/Slim/Plugin/MusicMagic/Plugin.pm
  - /path/to/Importer.pm:/usr/share/squeezeboxserver/Slim/Plugin/MusicMagic/Importer.pm
```

```perl
# Plugin.pm and Importer.pm — order is critical
$song =~ s|^Z:\\music|/music|i;   # FIRST — prefix strip
$song =~ s|\\|/|g;                # THEN — backslash conversion
```

### Why 1.8 does not have path translation issues

MusicIP 1.8 is a native Linux binary. It communicates directly in Linux paths — no Wine, no Windows path notation, no translation layer needed anywhere.

---

## ⚠️ MusicIP 1.9.b filter behaviour — stricter than 1.8

MusicIP 1.9.b enforces stricter rules for filter conditions than 1.8. Filters that worked fine in 1.8 can silently fail in 1.9.b with `MUSICIP RETURNED NOTHING`. The failure is silent — no error message distinguishes a "filter returned zero results" from a "filter syntax rejected" response.

### Known differences

**1. "Match all" vs "Match any"**

A filter set to **"Match ALL of the following conditions"** requires every condition to be true simultaneously. A filter with multiple `Artist is X` conditions can never match any track (no track can be by all artists at once) — MusicIP returns nothing.

Always verify filters use **"Match ANY"** unless you specifically intend strict AND logic.

**2. Mixing positive and negative conditions**

A filter combining `is` and `is not` conditions (e.g. `Genre is Ambient` + `Artist is not Aphex Twin`) fails in 1.9.b even when the logic is valid. In 1.8 this worked without issues.

Keep filters to either all positive (`is`) or all negative (`is not`) conditions — do not mix the two in the same filter when using 1.9.b.

**3. General recommendation**

After migrating from 1.8 to 1.9.b, **review all filters in the MusicIP Mixer GUI** and test each one via the API before relying on them in SugarCube:

```bash
curl "http://localhost:10002/api/mix?song=Z%3A%5Cmusic%5C<encoded path>&size=5&filter=<filtername>"
```

If the response is `MusicIP API error - invalid request or internal error` or returns nothing, the filter needs adjustment.

---

## Verification — confirmed

The order dependency is confirmed in practice: when the patched `Plugin.pm` and `Importer.pm` are absent, MusicIP Moods Mixer fails with exactly the `Z:/music/...` path pattern described above. Restoring the patches with the correct substitution order resolves it. No deliberate bug-reintroduction test is needed — the absence of the patches produces the identical failure mode.
