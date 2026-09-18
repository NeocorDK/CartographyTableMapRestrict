# Cartography Table Map Restrict — updated for Valheim 1.0.x

Hides the minimap and the map keybind. The world map can only be opened by using
a **cartography table**. Rebuilt from
[aedenthorn/ValheimMods](https://github.com/aedenthorn/ValheimMods/tree/master/CartographyTableMapRestrict)
against Valheim **1.0.15** and BepInEx 5.4.23.

## Why the original stopped working

Two things in the original broke on current Valheim:

1. **`Minimap.instance` became a property.** It used to be a public static field. A DLL compiled
   against the old game still looks for a *field*, so the plugin threw `MissingFieldException`
   the moment a cartography table was used.
2. **The map toggle was rewritten.** `Minimap.Update` now re-opens the small map on its own
   (`if (m_mode == MapMode.None) SetMapMode(MapMode.Small);`) and gates the toggle behind
   `m_shownFrames` / `m_hiddenFrames` counters that did not exist before. The original mod fought
   this every frame by forcing `MapMode.None` and calling `SetActive(false)` in an `Update` postfix.

## What changed in this version

The mod no longer patches `Minimap.Update` at all. `m_smallRoot` is touched by exactly two methods
in the game (`Minimap.Awake` and `Minimap.SetMapMode`), so a single `SetMapMode` patch covers
everything, with no per-frame work:

| Patch | Purpose |
|---|---|
| `Minimap.SetMapMode` **prefix** | Rewrites any switch to `MapMode.Large` into `MapMode.Small`, unless the cartography table asked for it. This is what blocks the map keybind. |
| `Minimap.SetMapMode` **postfix** | Keeps `m_smallRoot` deactivated, hiding the minimap. |
| `MapTable.OnRead(Switch, Humanoid, ItemData)` **postfix** | Opens the large map. This is the 3-argument overload wired to the table's *read* switch — the original patched the 4-argument one, which `OnWrite` also calls, so saving to the table opened the map too. |
| `MapTable.OnRead(..., bool showMessage)` **prefix** | Suppresses the "map synced" message. |
| `Minimap.ShowPointOnMap` **prefix** | Stops `Minimap.DiscoverLocation` from throwing the map open when you find a boss stone. |

Closing still works normally: with the large map open, the map key and `Escape` both route through
`SetMapMode(MapMode.Small)`, which the prefix leaves alone.

## Dedicated server / multiplayer

**The mod is client-side only.** It is marked `[BepInProcess("valheim.exe")]`, so it will not load
into `valheim_server.exe` even if the DLL ends up in the server's plugin folder.

* It patches nothing but local UI. It registers no RPCs and touches no ZDO, so it does **not**
  change the network protocol and will **not** cause a version mismatch or a kick.
* It does not need to be installed on the dedicated server.
* Every player who should have the restriction must install it themselves — a client-side mod
  cannot enforce this on anyone else. See `BypassServerNoMap` below for the enforceable route.
* Map exploration is still recorded while the minimap is hidden (`Minimap.UpdateExplore` runs
  regardless of map mode), and sharing map data through the table is untouched.

### Enforcing it for everyone

Valheim's own **No Map** world modifier *is* server-enforced, but on its own it also kills the
cartography table: `Minimap.SetMapMode` clamps every mode to `None` while `Game.m_noMap` is set.

With `BypassServerNoMap = true` (the default) this mod lifts that clamp for the duration of the
table's call, so you can run the server with the `nomap` modifier **and** still read the table:

* players **without** the mod get vanilla no-map — enforced by the server;
* players **with** the mod additionally get a working cartography table.

`Game.UpdateNoMap` only runs on spawn and when world modifiers change, so nothing re-closes the map
behind you.

If you are *not* using the server modifier, leave the modifier off and just have everyone install
the mod — that is the simpler setup.

## Config

`BepInEx/config/aedenthorn.CartographyTableMapRestrict.cfg`

| Key | Default | Meaning |
|---|---|---|
| `Enabled` | `true` | Master switch. Can be toggled at runtime. |
| `HideMinimap` | `true` | Hide the corner minimap. |
| `SuppressMessage` | `true` | Hide the "map synced" message when reading the table. |
| `PreventAutoOpen` | `true` | Stop the map force-opening on location discovery. |
| `BypassServerNoMap` | `true` | Let the table work under the server's No Map modifier. |
| `IsDebug` | `false` | Log what is blocked and opened. |

The plugin GUID is unchanged, so an existing config file is picked up. `IsDebug` replaces the
hardcoded `isDebug = true` in the original, which logged on every use.

## Building

No .NET SDK required — `build.ps1` falls back to the .NET Framework compiler already on Windows
(the source is kept inside the C# 5 subset for this reason):

```powershell
powershell -ExecutionPolicy Bypass -File CartographyTableMapRestrict\build.ps1 `
    -ValheimPath "G:\Steam\steamapps\common\Valheim"
```

With the SDK installed, `dotnet build -c Release -p:ValheimPath="..."` also works.

## Install

**r2modman / Thunderstore Mod Manager** (this is what is used here): the manager only lists mods it
installed itself, so a DLL dropped into the profile folder by hand never shows up in its UI. Install
the packaged zip instead:

> Settings -> Import local mod -> select `dist/neocor-CartographyTableMapRestrict-0.5.0.zip`

Rebuild that zip with `CartographyTableMapRestrict\package.ps1`.

The same zip is attached to each [GitHub release](https://github.com/NeocorDK/CartographyTableMapRestrict/releases).
Download it and import it the same way. Note that mod managers cannot install from GitHub on their
own -- r2modman and Thunderstore Mod Manager only read the Thunderstore package index, so a GitHub
release means manual import and no automatic update notifications.

**Plain BepInEx install:** copy `dist\CartographyTableMapRestrict.dll` into `Valheim\BepInEx\plugins\`.

## Compatibility

No patch overlap with **NomapPrinter**, which is also installed here — it hooks `Minimap.IsOpen`,
`Minimap.ShowPinNameInput` and `MapTable.OnWrite`; this mod hooks `Minimap.SetMapMode`,
`Minimap.ShowPointOnMap` and `MapTable.OnRead`.
