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

- **Delphi 13** with FireMonkey (FMX). The build uses RAD Studio's
  `brcc32` and its FMX styles in `Redist\styles\Fmx` (see
  [Themes](#themes)); both come with every RAD Studio install.
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
- **Platforms:** Windows 32 and 64-bit, Linux 64-bit, and macOS on Intel
  (OSX64) and Apple silicon (OSXARM64). See [Deploying](#deploying) for
  what each needs at run time.
- **Disk space:** about 18 MB per tile on average; the whole world is
  roughly 400 GB in about 46,000 files. The data folder can be anywhere,
  including a removable drive, and can be moved later.

## Getting started

```
git clone --recurse-submodules https://github.com/peardox/GDEM.git
```

If you already cloned without submodules, run
`git submodule update --init`.

1. Open `GDEM.groupproj` in Delphi 13 and build **GDEMFetch**.
2. On first run the Settings dialog opens. Paste your bearer token, choose
   where downloaded tiles should go (or keep the default), and press OK.
3. At the same time the tile index is built from CMR in the background.
   This takes about a dozen requests and needs no token.
4. Select tiles on the map and press **Fetch selection**, or type a tile
   name such as `N50W002` and press **Fetch tile**.

### Using the map

| Action | Control |
|--------|---------|
| Select a block of tiles | Left-drag. A left click selects one tile. To reach beyond the screen, drag towards an edge and the map scrolls that way, or use the mouse wheel to zoom while still dragging. |
| Move the map | Right-drag, middle-drag, or Shift + left-drag. The map wraps east to west, so you can keep going past 180°, and selections can cross it (for example around Fiji or the Bering Strait). It stops at the poles, since the world does not wrap north to south. |
| Zoom | Mouse wheel, or the View menu |
| Show or hide tiles that have data (cyan) | View > Show Available Tiles |
| Show or hide downloaded tiles (green) | View > Show Downloaded Tiles |

The status bar shows the position and tile under the pointer, and whether
that tile has data. Progress messages and errors appear in the log on the
**Debug** tab, and serious errors (a failed download or tile index build,
unreadable settings, a missing world map) are also shown in a dialog. The
**3D** tab is reserved for a later stage.

### Menus

| Menu | Item | Does |
|------|------|------|
| File | Settings... | Bearer token, data folder, free-space reserve, theme |
| File | Refresh Tile Index | Rebuilds the list of tiles that exist, from CMR |
| Data | Import Existing Tiles... | Copies tiles you already have, from any folder, into the data folder. The originals are not changed. |
| Data | Rescan Data Folder | Rebuilds the downloaded-tiles bitmap from the files, files any misplaced downloads into place, and removes leftovers and empty folders |
| Data | Delete Selected Downloads... | Deletes the downloaded tiles inside the map selection |
| View | Zoom In / Zoom Out / Whole World / Zoom to Selection | Map view |

**Fetch selection** downloads only tiles that have data and are not yet
downloaded. Free space is checked before every tile, and downloading stops
rather than go below the reserve set in Settings (2 GB by default). The
**Cancel** button stops whatever job is running.

Whenever data is downloaded (tiles, or the tile index from NASA CMR) a
progress dialog shows the step in progress, overall progress, and progress
through the current file, with a Cancel button. The dialog stays until the
download has actually stopped.

### Themes

Choose the program's look under **File > Settings > Theme**:

| Theme | Look |
|-------|------|
| Default | FMX's own platform style, with the system's title bars |
| Dark | RAD Studio's Dark style |
| Aqua Graphite, Ruby Graphite, Golden Graphite | RAD Studio's Graphite styles, with a coloured accent |

The theme is applied as soon as Settings closes with OK, and at start-up.
Where the system allows, title bars are coloured to match: the caption and
border on Windows 11, dark or light on Windows 10, and dark or light
appearance on macOS. Linux leaves title bars to the window manager.

The styles are the `.style` files RAD Studio ships in
`Redist\styles\Fmx`. They are kept in the repository's `styles/` folder
and linked into the program as resources, so nothing needs deploying:

- `styles/GDEMThemes.rc` lists them as RCDATA resources named
  `GDEM<Name>Style`.
- `styles/buildstyles.cmd` runs as the project's pre-build event. It
  copies any missing style from RAD Studio's `Redist\styles\Fmx` (styles
  already in the folder are kept, so one can be replaced by hand), then
  compiles `GDEMThemes.rc` into `GDEMThemes.res` with `brcc32`. If anything
  is missing the build stops with an error saying what.
- `GDEMFetch.dpr` links `..\styles\GDEMThemes.res`.

This is the same arrangement as Sprite3D's themes, so the two projects
look and behave alike.

## Deploying

GDEMFetch needs **no extra files deployed** on any platform. The world map
is linked into the executable as a resource, which Delphi does on Windows,
macOS and Linux alike, and everything else (settings, the tile index, the
data folder) is created at run time. The default Deployment Manager
entries are all that is needed.

**Windows:** the executable on its own.

**macOS:** deployed as an app bundle through PAServer.
- The bundle identifier is `com.peardox.GDEMFetch`.
- `Info.plist` carries only the privacy descriptions GDEMFetch can need:
  the Documents, Desktop and Downloads folders, removable drives and
  network drives. macOS shows these the first time the program uses such
  a location, for example when the data folder is on an external drive.
  The IDE's default descriptions for location, camera, microphone,
  Bluetooth and so on were removed because the program uses none of them.
  If the IDE puts them back after a platform change, remove them again
  under Project > Options > Application > Version Info.
- To run it on Macs other than your own it must be signed and notarised.

**Linux:** these must be installed on the target machine, not deployed
with the program. Desktop distributions usually have them already.

| Needed for | Package (Debian / Ubuntu) | Package (Fedora) |
|------------|---------------------------|------------------|
| Downloads (`THTTPClient` uses libcurl) | `libcurl4` | `libcurl` |
| The FMX user interface | `libgtk-3-0` | `gtk3` |
| Opening web links from Settings (`xdg-open`) | `xdg-utils` | `xdg-utils` |

Removable drives are normally mounted under `/media/<user>/` or
`/run/media/<user>/`; choose the data folder there in Settings.

## Where files are kept

| What | Where |
|------|-------|
| Settings (`settings.json`, holds the bearer token) | Windows: `%APPDATA%\GDEM`<br>macOS: `~/Library/Application Support/GDEM`<br>Linux: `$XDG_CONFIG_HOME/GDEM` or `~/.config/GDEM`<br>Android and iOS: `GDEM` in the app's documents folder |
| Tile index (`tileindex.bin`) | Same folder as the settings |
| Downloaded tiles | The **data folder**, chosen in File > Settings. Default: `ASTGTM` in your documents folder. |

On macOS and Linux `settings.json` is readable by its owner only, because
it contains a credential.

`tileindex.bin` is 14 bytes of header followed by 8,100 bytes: one bit per
tile. The layout is documented in `GDEMTileIndex.pas`. Use **File >
Refresh Tile Index** to rebuild it.

### The data folder

Tiles are grouped into folders by 10 x 10 degree block, named after the
block's south-west corner the same way tiles are:

```
<data folder>/
  gdem-store.json       marks this as a GDEM data folder
  downloaded.bin        bitmap of fully downloaded tiles
  N50/
    W010/
      ASTGTMV003_N50W002_dem.tif
      ASTGTMV003_N50W002_num.tif
      ...
```

Each block folder holds at most 200 files, and the whole world needs about
600 of them. Neighbouring tiles share a folder, so a selection on the map
touches only a few. Folders are created as needed and removed when they
become empty.

The folder describes itself, so it can be moved or copied freely:

- **Changing folder in Settings:** if the old folder holds data, you are
  asked whether to move it. Moving runs in the background, can be
  cancelled, and picks up where it left off if you choose the same folder
  again.
- **Moving or copying it yourself** (for example to another drive): point
  Settings at the new location, then use **Data > Rescan Data Folder** if
  the map does not show your downloads.
- **Removable drives:** once a folder has been used, if it is missing the
  program asks you to connect the drive and press Retry, at start-up and
  before downloading. The status bar shows whether the folder is
  connected and how much space is free, and is refreshed every minute.
- **Downloads from older versions** of GDEMFetch were saved flat in
  `Documents/ASTGTM`. The first rescan of that folder files them into
  blocks.

### Importing tiles you already have

If you already have ASTER GDEM V3 `.tif` files, for example from another
download tool that puts everything in one folder, use **Data > Import
Existing Tiles...** and choose that folder.

- Every `ASTGTMV003_<tile>_dem.tif` and `_num.tif` file in the folder, and
  in any folders inside it, is **copied** into the data folder's blocks.
  The source is only read; nothing in it is changed, moved or deleted.
- Other files are ignored, and so are files that do not start like a TIFF.
- The space needed is worked out first, and the import does not start if
  it would leave less than the reserve set in Settings. Space is checked
  again before every file.
- Each file is copied under a temporary name and size-checked before it
  takes its real name, so a cancelled import leaves no partial tiles.
  Files the data folder already has are skipped, so an import can be
  cancelled and run again to finish.
- A progress dialog shows the file being copied, how many files have been
  dealt with, and how much has been copied out of the total, with the
  copying speed and an estimate of the time left. Its Cancel button stops
  the import after the file in progress.
- When it finishes (or is cancelled) the data folder is rescanned and the
  map shows the imported tiles in green.
- The source folder must not be inside the data folder, or contain it.

## Repository layout

| Path | Contents |
|------|----------|
| `GDEM.groupproj` | Project group |
| `GDEMFetch/` | The GDEMFetch application |
| `styles/` | FMX styles for the themes, with the resource script and the pre-build script that builds them; see [Themes](#themes) |
| `maps/` | World map images. `world_1080x540.jpg` is linked into GDEMFetch as a resource. `8081_earthmap10k.jpg` (10800 x 5400) is kept here locally but is excluded by `maps/.gitignore`, so it is not in the repository. |
| `delphi-neon/` | Neon JSON library (git submodule) |
| `docs/` | Ignored for development |
| `models/` | Ignored for development |

### GDEMFetch units

| Unit | Purpose |
|------|---------|
| `MainForm` | Main window: toolbar and menus over three tabs (Map, 3D, Debug), with progress and status bars |
| `SettingsForm` | Modal settings dialog |
| `ProgressForm` | Modal progress dialog shown while data is downloaded |
| `GDEMThemes` | The themes, and `ApplyTheme` |
| `GDEMStyles` | Switches FMX styles at run time (ported from Sprite3D) |
| `GDEMTitleBar` | Colours title bars to match the style (ported from Sprite3D) |
| `GDEMSettings` | Loads and saves `settings.json` with Neon |
| `GDEMBrowser` | Opens web links in the default browser on each platform |
| `GDEMWorldMap` | `TWorldMapView`, the zoomable map with tile selection |
| `GDEMTiles` | Tile names and `TTileRect`, a block of tiles; no FMX |
| `GDEMTileIndex` | `TTileIndex` bitmap of which tiles exist, and its CMR builder |
| `GDEMCMR` | Neon models for CMR search results; no networking |
| `GDEMDownloader` | Finds and downloads tiles |
| `GDEMStore` | The data folder: block layout, downloaded-tiles bitmap, rescanning, moving, deleting, free space |
| `GDEMCancel` | `TCancelToken`, shared by the Cancel button and background jobs |

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
- **High-resolution map:** `maps/8081_earthmap10k.jpg`, a 10800 x 5400
  world map (30 pixels per degree, so each GDEM tile is 30 x 30 pixels),
  cut into tiles that are loaded as the user zooms in. The image is
  gitignored because of its size, so the tiling step must not assume it is
  in a fresh clone.

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
- Anything the program needs at run time is linked in as a resource
  (an `RcItem` in the `.dproj`, read with `TResourceStream`), so nothing
  has to be deployed beside it. If a file ever cannot be a resource, add
  Deployment entries for every platform and say so in
  [Deploying](#deploying).
- On macOS, every privacy-sensitive location the program touches needs a
  usage description in the Version Info keys; keep them accurate.
- Naming: fields `F`, parameters `A`, locals `L`; non-visual units
  `GDEM*.pas`; forms `*Form.pas`.
- Keep non-visual logic in its own units, out of forms, so later programs
  can reuse it.
- Long-running work runs on a `TTask`. Controls are only touched through
  `TThread.Queue`. Long-running classes can be cancelled from another
  thread, and the main window waits for them before closing.
- Report serious failures with `TfrmMain.ReportError`, which logs them and
  shows a modal error dialog. Cancelling is not an error. Problems that are
  recovered from automatically are logged as `WARNING:` only.
- Anything that downloads external data shows the modal progress dialog:
  pass a title to `RunJob` (its last parameter), or use `BeginProgress`,
  `ShowProgressModal` and `EndProgress` directly, and send updates with
  `ProgressStatus`, `ProgressOverall` and `ProgressItem`, which are safe to
  call from any thread. Importing uses the same dialog, because it can run
  for hours. Other local work (rescanning, moving, deleting) shows progress
  on the main window's bar instead.
- Anything at start-up that may need the user goes in
  `TfrmMain.RunStartup`, in order, so one dialog never opens on top of
  another.
- Forms must not have their own StyleBook, so the theme set through
  `TStyleManager` reaches them. Colours a control paints for itself (the
  map, for example) are fixed and must read well on light and dark themes.
- To add a theme, add the `.style` file name to `buildstyles.cmd` and an
  RCDATA line to `GDEMThemes.rc`, then a value to `TGDEMTheme` and its
  row in `THEMES` in `GDEMThemes.pas`.
- Write files atomically: write a temporary file, then rename it.
- Never put credentials in source code or log output.
- Get download URLs from CMR; do not guess Earthdata Cloud paths. Send
  the bearer token only to `*.earthdata.nasa.gov` and
  `*.earthdatacloud.nasa.gov`.
- All access to downloaded files goes through `TGDEMStore`; never build
  data-folder paths by hand. The folder may be missing (an unplugged
  drive), so check it with `WithStore` before use.
- Work on the data folder runs as a job through `TfrmMain.RunJob`, one at
  a time, cancellable with a `TCancelToken`.
- Anonymous methods capture variables, not values. When queuing work from
  inside a loop, pass the loop's values to a method as parameters (as
  `QueueMarkDownloaded` does) rather than capturing the loop variables.
