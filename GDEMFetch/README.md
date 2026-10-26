# GDEM

GDEM is a cross-platform Delphi FMX project for working with the
**ASTER Global Digital Elevation Model, version 3** (ASTER GDEM V3, NASA
product code `ASTGTM.003`): worldwide elevation data at 1 arc-second
(about 30 m) resolution.

The first program, **GDEMFetch**, lets you pick an area on a world map and
download the elevation tiles that cover it. Later stages will read and use
those tiles.

## About the data

ASTER GDEM V3 is published as one-degree tiles, 3601 x 3601 pixels each,
covering latitudes 83°S to 83°N. Each tile is a pair of GeoTIFF files:

| File | Contents |
|------|----------|
| `ASTGTMV003_N50W002_dem.tif` | Elevation in metres, signed 16-bit. `-9999` marks a void, `0` marks sea-level water. |
| `ASTGTMV003_N50W002_num.tif` | Quality and source for each pixel, unsigned 8-bit (number of ASTER scenes used, or which other DEM filled the gap). |

A tile is named after the **south-west corner** of the area it covers, so
`N50W002` covers latitudes 50°N to 51°N and longitudes 2°W to 1°W. The
edge rows and columns overlap the neighbouring tiles.

The world has 360 x 180 = 64,800 possible tiles, but only about 23,000
exist: there are none over open ocean.

The files are LZW-compressed, tiled (256 x 256), little-endian GeoTIFFs
with 8 lower-resolution overview images, in the WGS 84 coordinate system.
The NASA user guide (`ASTGTM_User_Guide_V3.pdf`) has the full details.

## How GDEMFetch gets the data

1. **NASA CMR** (Common Metadata Repository), a public catalogue that
   needs no login, is used to:
   - build the **tile index**, a record of which tiles exist, by listing
     the whole ASTGTM collection; and
   - look up the download links for each tile.
2. Each file is downloaded from **NASA Earthdata Cloud** using an
   **Earthdata Login bearer token**. NASA redirects to a pre-signed Amazon
   S3 link, and the token is sent only to NASA hosts, never to S3.

The old LP DAAC Data Pool (`e4ftl01.cr.usgs.gov`) stopped serving ASTER
GDEM on 3 December 2025, so older scripts that use it no longer work.

## Requirements

- **Delphi 13** with FireMonkey (FMX).
- **Neon JSON library**, included as a git submodule in `delphi-neon/`.
  Clone with submodules (see below). The project's search path already
  points at `..\delphi-neon\Source`.
- **A free NASA Earthdata Login account**, from
  <https://urs.earthdata.nasa.gov>, and a **bearer token** generated
  there. Tokens expire, so a new one is needed from time to time.
- **Internet access** to:
  - `cmr.earthdata.nasa.gov` (tile index and download links)
  - `data.lpdaac.earthdatacloud.nasa.gov` (the files)
  - `urs.earthdata.nasa.gov` (Earthdata Login)
- **Platforms:** Windows 32 and 64-bit and Linux 64-bit are enabled in the
  project; macOS is set up but switched off until a PAServer and SDK are
  ready.
  - Linux builds need FMX for Linux, and use `xdg-open` to open web links.
- **Disk space:** about 25 MB or more for each land tile.

## Getting started

```
git clone --recurse-submodules https://github.com/peardox/GDEM.git
```

If you already cloned without submodules, run
`git submodule update --init`.

1. Open `GDEM.groupproj` in Delphi 13 and build **GDEMFetch**.
2. On first run the Settings dialog opens. Paste your bearer token and
   press OK.
3. At the same time the tile index is built from CMR in the background.
   This takes about a dozen requests and needs no token.
4. Select tiles on the map and press **Fetch selection**, or type a tile
   name such as `N50W002` and press **Fetch tile**.

### Using the map

| Action | Control |
|--------|---------|
| Select a block of tiles | Left-drag. A left click selects one tile. |
| Move the map | Right-drag, middle-drag, or Shift + left-drag |
| Zoom | Mouse wheel, or the View menu |
| Show or hide tiles that have data | View > Show Available Tiles |

The status bar shows the position and tile under the pointer, and whether
that tile has data.

## Where files are kept

| What | Where |
|------|-------|
| Settings (`settings.json`, holds the bearer token) | Windows: `%APPDATA%\GDEM`<br>macOS: `~/Library/Application Support/GDEM`<br>Linux: `$XDG_CONFIG_HOME/GDEM` or `~/.config/GDEM`<br>Android and iOS: `GDEM` in the app's documents folder |
| Tile index (`tileindex.bin`) | Same folder as the settings |
| Downloaded tiles | `ASTGTM` in your documents folder |

On macOS and Linux `settings.json` is readable by its owner only, because
it contains a credential.

`tileindex.bin` is 14 bytes of header followed by 8,100 bytes: one bit per
tile. The layout is documented in `GDEMTileIndex.pas`. Use **File >
Refresh Tile Index** to rebuild it.

## Repository layout

| Path | Contents |
|------|----------|
| `GDEM.groupproj` | Project group |
| `GDEMFetch/` | The GDEMFetch application |
| `maps/` | World map images, linked into programs as resources |
| `delphi-neon/` | Neon JSON library (git submodule) |
| `docs/` | Ignored for development |
| `models/` | Ignored for development |

### GDEMFetch units

| Unit | Purpose |
|------|---------|
| `MainForm` | Main window: map, toolbar, log, menus |
| `SettingsForm` | Modal settings dialog |
| `GDEMSettings` | Loads and saves `settings.json` with Neon |
| `GDEMBrowser` | Opens web links in the default browser on each platform |
| `GDEMWorldMap` | `TWorldMapView`, the zoomable map with tile selection |
| `GDEMTiles` | Tile names and `TTileRect`, a block of tiles; no FMX |
| `GDEMTileIndex` | `TTileIndex` bitmap of which tiles exist, and its CMR builder |
| `GDEMCMR` | Neon models for CMR search results; no networking |
| `GDEMDownloader` | Finds and downloads tiles |

The world map image `maps/world_1080x540.jpg` is linked into GDEMFetch as
the `WORLDMAP` RCDATA resource, so nothing needs deploying beside the
program. It is an equirectangular projection: 3 pixels per degree,
longitude -180 at the left and latitude 90 at the top.

## Roadmap

- **GeoTIFF reader:** a pure-Pascal reader for the DEM and NUM files, so
  no native library has to be shipped. Older work in
  <https://github.com/peardox/volatile> can be reused. That project uses a
  Windows-only libtiff binding, so only its logic carries over, not the
  binding.
- **High-resolution map:** a 10800 x 5400 world map cut into tiles,
  loaded as the user zooms in.

## Notes for Claude

These are the working rules for this project. Read this whole README
before starting work.

### Delivering work

- **Never supply patches or diffs.** Supply whole files.
- When supplying several files, put them in a **zip containing only the
  new and changed files**, with paths relative to the repository root, so
  it can be unzipped straight over the working copy.
- The owner works from a local copy and pushes when happy with the
  results. **Do not mention that changes are uncommitted or unpushed.**
- **Do not mention being unable to compile.** That is already known.
- The GitHub repository may be behind the owner's working copy. Build on
  the files most recently supplied in the conversation.
- Update this README when features or requirements change, and include it
  in the zip when it does.

### Repository

- Honour `.gitignore`, `.gitmodules` and the other `.git*` files.
- Ignore the `docs/` and `models/` folders.
- Neon is a submodule; never copy its sources into the project.

### Code

- **Delphi 13, FMX, cross-platform** wherever possible: Windows, macOS,
  Linux, and Android and iOS where practical.
  - No Windows-only units or calls without `{$IF}` alternatives for the
    other platforms.
  - Prefer pure Pascal to native libraries that would need deploying.
- **JSON uses Neon**, not hand-written `System.JSON` code. Map keys
  explicitly with `[NeonProperty('...')]` where they differ from the
  Delphi names, and turn on `RaiseExceptions` when reading.
- **Document all code in PasDoc format** (<https://pasdoc.github.io/>):
  every unit, type, field (private ones included), method, property and
  constant, using `@abstract`, `@param`, `@returns`, `@raises` and
  `@link`.
- **Source files are ASCII only.** Delphi reads files without a byte
  order mark as ANSI, so write characters such as the degree sign as
  character codes (`#$00B0`).
- Keep the existing UTF-8 byte order mark on `.dproj` files.
- Naming: fields `F`, parameters `A`, locals `L`; non-visual units
  `GDEM*.pas`; forms `*Form.pas`.
- Keep non-visual logic in its own units, out of forms, so later programs
  can reuse it.
- Long-running work runs on a `TTask`. Controls are only touched through
  `TThread.Queue`. Long-running classes can be cancelled from another
  thread, and the main window waits for them before closing.
- Write files atomically: write a temporary file, then rename it.
- Never put credentials in source code or log output.
- Get download URLs from CMR; do not guess Earthdata Cloud paths. Send
  the bearer token only to `*.earthdata.nasa.gov` and
  `*.earthdatacloud.nasa.gov`.
