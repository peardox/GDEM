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

The world has 360 x 180 = 64,800 possible tiles, but only 22,912 exist:
there are none over open ocean.

The files are LZW-compressed, tiled (256 x 256), little-endian GeoTIFFs
with 8 lower-resolution overview images, in the WGS 84 coordinate system.
The NASA user guide (`ASTGTM_User_Guide_V3.pdf`) has the full details.

## How GDEMFetch gets the data

1. **NASA CMR** (Common Metadata Repository), a public catalogue that
   needs no login, is used to:
   - build the **tile index**, a record of which tiles exist, by listing
     the whole ASTGTM collection; and
   - look up the download links for each tile.
2. Each file is requested from **NASA Earthdata Cloud** using an
   **Earthdata Login bearer token**. NASA answers with a redirect (303) to
   a short-lived CloudFront download link, which is fetched without the
   token: the token is sent only to NASA hosts.

The old LP DAAC Data Pool (`e4ftl01.cr.usgs.gov`) stopped serving ASTER
GDEM on 3 December 2025, so older scripts that use it no longer work.

## Requirements

- **Delphi 13** with FireMonkey (FMX). The build uses RAD Studio's
  `brcc32` and its FMX styles in `Redist\styles\Fmx` (see
  [Themes](#themes)); both come with every RAD Studio install.
- **Skia**, which comes with Delphi 13. GDEMFetch draws with it, on the
  GPU by default (`ConfigureDrawing` in `GDEMDrawing`, called from
  `GDEMFetch.dpr`, and the `SKIA` define the IDE adds when Skia is enabled
  for the project); see [Drawing](#drawing).
- **Neon JSON library**, included as a git submodule in `delphi-neon/`.
  Clone with submodules (see below). The project's search path already
  points at `..\delphi-neon\Source`.
- **A free NASA Earthdata Login account**, from
  <https://urs.earthdata.nasa.gov>, and a **bearer token** generated
  there. Tokens last 60 days, so a new one is needed from time to time.
  The token itself records when it expires: Settings shows the date and
  days left as you paste it, the Debug tab logs it at start-up, and a
  dialog warns when fewer than 7 days are left. Fetching is refused once
  it has expired.
- **Internet access** to:
  - `cmr.earthdata.nasa.gov` (tile index and download links)
  - `data.lpdaac.earthdatacloud.nasa.gov` (the files), which redirects
    to `*.cloudfront.net` for the download itself
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
| Select a block of tiles | Left-drag. The size and tile counts update as you drag. A left click selects one tile. To reach beyond the screen, drag towards an edge and the map scrolls that way, or use the mouse wheel to zoom while still dragging. |
| Select a whole country | Right-click it (on a Mac trackpad, click with two fingers). Every tile the country touches is selected and tinted, including tiles along its borders and coasts, so neighbouring countries' tiles are included where they share one. Overseas parts count too: France includes French Guiana, the United States includes Alaska and Hawaii. The selection label then gives the country, its tile count, and how many have data and are downloaded, such as `Germany: 68 tile(s), ...`. Fetch selection and Delete Selected Downloads work on just those tiles. Dragging a new selection or clicking replaces it. |
| Move the map | Right-drag, middle-drag, or Shift + left-drag. A right click that does not move selects a country instead. The map wraps east to west, so you can keep going past 180°, and selections can cross it (for example around Fiji or the Bering Strait). It stops at the poles, since the world does not wrap north to south. |
| Zoom | Mouse wheel, or the View menu |
| Show or hide tiles that have data (cyan) | View > Show Available Tiles |
| Show or hide downloaded tiles (green) | View > Show Downloaded Tiles |
| Show or hide country borders (pink) and coastlines (white) | View > Show Country Borders, View > Show Coastlines |

The status bar shows the position and tile under the pointer, whether
that tile has data, and the country it is in. Progress messages and errors appear in the log on the
**Debug** tab (the file-by-file detail of downloads goes to a
[report file](#how-downloads-work) instead), and serious errors (a failed download or tile index build,
unreadable settings, a missing world map) are also shown in a dialog. The
**3D** tab is reserved for a later stage.

### Menus

On Windows the menus are the usual menu bar, and on macOS they are in the
system menu bar at the top of the screen. On Linux they are drawn by FMX
itself, in the program's theme, because the native GTK menu bar FMX would
otherwise use showed only the first letter of each menu and item.

| Menu | Item | Does |
|------|------|------|
| File | Settings... | Bearer token, data folder, free-space reserve, files copied at once when importing, download speed, theme, drawing (GPU or CPU), and on Windows which graphics processor to use |
| File | Refresh Tile Index | Rebuilds the list of tiles that exist, from CMR |
| Data | Import Existing Tiles... | Copies tiles you already have, from any folder, into the data folder. The originals are not changed. |
| Data | Rescan Data Folder | Rebuilds the downloaded-tiles bitmap from the files, files any misplaced downloads into place, and removes leftovers and empty folders |
| Data | Delete Selected Downloads... | Deletes the downloaded tiles inside the map selection |
| View | Zoom In / Zoom Out / Whole World / Zoom to Selection | Map view |
| View | Show Available Tiles / Show Downloaded Tiles | The cyan and green tile tints |
| View | Show Country Borders / Show Coastlines | The borders and coastlines drawn over the map |
| View | Copy Log / Clear Log | Copy the Debug tab's log to the clipboard, or empty it |

**Fetch selection** downloads only tiles that have data and are not yet
downloaded. Free space is checked before every tile, and downloading stops
rather than go below the reserve set in Settings (2 GB by default). The
**Cancel** button stops whatever job is running.

#### How downloads work

1. Tiles already in the data folder are skipped.
2. NASA CMR is asked where the rest are. For a selection on the map it
   lists every tile in the selected block, 2,000 per request, so even the
   whole world takes only about a dozen requests. Tiles scattered far
   apart are asked for by name instead, 100 per request. Tiles with no
   data (ocean) are left out.
3. The tiles are downloaded, several files at once. A single download
   uses only a small part of a fast connection, so more at once is much
   faster. On a 1 Gbit/s line in the UK, 1 at a time gave about 3 MB/s,
   12 about 26 MB/s and 16 about 56 MB/s (100 tiles, 2.1 GB in 38 s).
   At the Fast setting a 168-tile batch (3.1 GB) ran at 47 MB/s. The
   whole world would take 2 to 2.5 hours at those rates.

**Download speed** in Settings sets how hard GDEMFetch pushes:

| Speed | Starts at | At most | Suits |
|-------|-----------|---------|-------|
| Slow | 1 | 4 | A slow or shared connection |
| Medium (default) | 2 | 8 | Most connections |
| Fast | 4 | 16 | A fast connection |

NASA does not publish a speed limit. When it has had enough it cuts off or
refuses downloads, or answers "Too Many Requests". GDEMFetch copes with
this:

- **Feeling its way.** All downloads in a batch share one limit, which
  works the way TCP shares a network: additive increase, multiplicative
  decrease. It starts at the speed's starting number, and until NASA
  objects each good file allows one more at once, up to the speed's most.
  If downloads are cut off or refused three times within 30 seconds, the
  number at once is halved (down to 1) and everything pauses for 5
  seconds. After that it climbs back carefully: one more after 20 good
  files in a row and a minute without trouble. "Too Many Requests" pauses
  everything for as long as NASA asks. Reaching the most, and every cut or
  raise after a cut, is logged, and the summary says if it had to cut
  back.
- **Resuming.** A file cut off part-way carries on from where it stopped,
  rather than starting again, and such a try is not counted as a failure.
- **Retrying.** Other passing problems are tried three times. A tile that
  still fails is listed on the Debug tab and skipped, and a dialog at the
  end says how many; fetching the same selection again retries them.

A batch only stops early if the bearer token is rejected, free space runs
low, the data folder disappears, or 10 tiles in a row have failed. Failures
with good tiles in between only skip those tiles, so one bad patch in a
long batch does not end it.

**Report file.** Each batch writes everything (every request, redirect
and saved file, with times) to a report file, so the Debug tab stays
short: it shows the report's path, the lookup, the start, any failures or
cut-backs, and the summary. Reports are kept in a `Reports` folder beside
the settings file, named by when the batch started (such as
`download-20261026-231500.log`), and only the newest 50 are kept. The file
is written as the batch goes, so it is complete up to the moment even if
the program stops.

**Staying awake.** While any job runs, GDEMFetch asks the system not to
sleep: `SetThreadExecutionState` on Windows, an `NSProcessInfo` activity on
macOS (which also keeps App Nap from slowing it down when the window is
hidden), and `systemd-inhibit` on Linux where it is installed. The screen
may still turn off. The request ends with the job, or with the program if
it closes or crashes.

Downloading the same tiles again and again in a short time (deleting and
re-fetching them while testing, say) seems to make NASA cut connections
off much sooner. Test on a different area each time.

The summary at the end gives the size saved, the time taken, the speed
and the most downloads at once reached, for example: `Downloaded 100
tile(s), 2.1 GB, in 38 s at 56 MB/s, up to 16 at a time; ...`.

Whenever data is downloaded (tiles, or the tile index from NASA CMR) a
progress dialog shows the step in progress, overall progress, and progress
through the current file, with a Cancel button. The dialog stays until the
download has actually stopped.

### Borders and coastlines

Country borders and coastlines are drawn over the world map, and the
status bar names the country under the pointer. They come from
[Natural Earth](https://www.naturalearthdata.com), which is in the public
domain, so no permission or credit is needed (credit is given anyway).

- Land borders are drawn as lines, so a border shared by two countries is
  drawn once and coasts are not drawn as borders.
- While much of the world is in view the 1:110m data is drawn; once a
  degree is 8 pixels or more across, the more detailed 1:50m data.
- Country names come from Natural Earth's 1:50m country outlines and use
  its `ADMIN` names ("United Kingdom", "Ivory Coast").
- Borders are shown as they are on the ground, which is Natural Earth's
  default for disputed areas.
- Right-clicking a country selects its tiles: every tile its outline
  passes through (found by walking each edge across the tile grid) and
  every tile whose centre lies inside it (found by filling between the
  outline's crossings of each row). An island smaller than a tile still
  gives its tile.

The data is linked into the program as the `WORLDVECTORS` resource, built
from `maps/world_vectors.bin`, so nothing is deployed. That file is made
from Natural Earth's GeoJSON files by `tools/build_vectors.py`; its
comments say which files it needs and how to run it. It holds five layers
(1:110m and 1:50m borders, 1:110m and 1:50m coastlines, and 1:50m country
outlines with names), about 190,000 points in 790 KB. `GDEMVectors.pas`
documents the format.

### Drawing

GDEMFetch draws with Skia, which comes with Delphi, rather than FMX's
own canvases. **File > Settings > Drawing** chooses where:

| Platform | GPU (the default) | CPU |
|----------|-------------------|-----|
| Windows | Vulkan when FMX's `GlobalUseVulkan` is on and the driver supports Vulkan 1.1, otherwise OpenGL; the CPU if neither works | Skia's CPU canvas (`GlobalUseSkiaRasterWhenAvailable`) |
| macOS | Metal (`GlobalUseMetal`) | Skia's CPU canvas |
| Linux | Not offered: Skia only draws on the CPU there | Skia's CPU canvas |

The choice has to be made before the program starts up, so a change takes
effect the next time GDEMFetch starts. The Debug tab says at start-up what
was asked for and which canvas Skia is using, such as `Drawing with Skia:
asked for the GPU, using TVkCanvas`. Choose the CPU if the graphics driver
causes trouble.

**File > Settings > Graphics** (Windows only) is Windows' own choice of
graphics processor for GDEMFetch, the same as Windows Settings > System >
Display > Graphics: **Let Windows decide** (the default), **Power
saving** (usually the graphics built into the processor) or **High
performance** (usually the separate graphics card). It matters on
computers with both, such as most gaming laptops. Windows keeps it in the
registry for each program file, under
`HKEY_CURRENT_USER\Software\Microsoft\DirectX\UserGpuPreferences`, and
reads it as the program starts, so:

- choosing it in Settings writes Windows' setting straight away, and it
  takes effect at the next start;
- the choice is also kept in `settings.json`, and at every start GDEMFetch
  makes Windows' setting match it, so a new build in a different folder
  gets the same choice (from its second start). Let Windows decide leaves
  Windows' setting alone, so a choice made in Windows' own Settings
  stands;
- only the `GpuPreference` part of the registry value is changed; other
  Windows settings in it, such as the windowed games optimisation, are
  kept.

The start-up line on the Debug tab includes it, such as `Drawing with
Skia: asked for the GPU, using TVkCanvas; Windows graphics processor: High
performance`. Task Manager's Processes tab, with the GPU engine column
shown, says which processor GDEMFetch is really using.

Measured on Windows while panning and zooming the map: 14 to 21 frames a
second on the CPU, 34 to 125 on the GPU. On the CPU most of each frame
went on filling pixels (stretching the world image and the tile tints
across the window); on the GPU that takes almost no time.

Borders and coastlines are the costly part of the map on the GPU: the
1:50m coastline alone is about 60,000 points. The first time a layer is
drawn it is cut into 10 x 10 degree squares, each made into a Skia path
in degrees, and each frame draws only the squares on screen, moved and
scaled into place. Zoomed in over the British Isles, that is 2 of the
coastline's 355 squares, about 1,500 of its points. Without Skia each
frame works out every point on screen and builds a new path, as GDEMFetch
did before.

These choices were made from timings taken with two View menu items that
have since been removed: one switched the cached paths off, the other
logged frame times. The map can still time itself:
`TWorldMapView.OnPaintStats` reports each drag, pan or run of wheel zooms
(frames, frame rate, average and worst milliseconds, the share spent on
borders and coastlines, and the canvas class), and
`TWorldMapView.UseSkiaPaths` switches the cached paths off. Set either in
code to measure again. On the GPU much of the work happens after the
map's drawing code returns, so the frame rate is the fairer comparison
there.

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

The world map and its borders and coastlines are linked into the
executable as resources, which Delphi does on Windows, macOS and Linux
alike, and everything else (settings, the tile index, the data folder) is
created at run time. The only file deployed beside the program is
**Skia's library** on Windows and Linux: `sk4d.dll` (from RAD Studio's
`bin` or `bin64`) and `libsk4d.so` (from `binlinux64`). The IDE added
Deployment entries for them when Skia was enabled for the project; leave
those ticked. On macOS Skia is linked into the program. The default
Deployment Manager entries are all that is needed.

The IDE adds files that are part of the project, such as the map image,
`maps/world_vectors.bin` and `styles/buildstyles.cmd`, to the deployment
on its own. These are disabled in `GDEMFetch.dproj` for every platform:
the map and vectors are already inside the program, the script only runs
at build time, and on macOS
anything in the app's `Resources/StartUp` folder is copied out to the
user's folders by `System.StartUpCopy`. If the Deployment Manager ever
shows them ticked again, untick them.

**Windows:** the executable and `sk4d.dll` beside it. Its icon, `GDEMFetch/gdem.ico`
(16 to 256 pixels), is compiled into it, set as the project's main icon
for both Windows targets.

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

**Linux:** the executable and `libsk4d.so` beside it. These must also be
installed on the target machine, not deployed with the program. Desktop distributions usually have them already.

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
| Download reports (`Reports/download-*.log`) | Same folder as the settings |
| Windows' graphics processor choice | Windows only: the registry value named after the program's path in `HKEY_CURRENT_USER\Software\Microsoft\DirectX\UserGpuPreferences`; see [Drawing](#drawing) |
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
- Files are copied one at a time by default. On SSDs, choosing a higher
  number (2, 4, 6, 8, 10, 12 or 16) for **Files copied at once when
  importing** in Settings can be several times faster, because the time
  each file takes to open, flush, check and rename then overlaps. Keep it at 1 for a spinning hard disk, where
  several files at once make the heads jump between them.
- A progress dialog shows the file being copied, how many files have been
  dealt with, and how much has been copied out of the total, with the
  copying speed and an estimate of the time left. Its Cancel button stops
  the import after the file in progress.
- A file that cannot be copied is tried three times, which rides out
  brief problems such as a virus scanner still holding the new file or the
  drive resetting for a moment. If it still fails it is listed on the
  Debug tab and skipped, and the import carries on; a dialog at the end
  says how many were skipped, and running the import again retries them.
  The import only stops early if free space runs low, the data folder
  disappears (a removable drive unplugged), or 20 files have failed.
- When it finishes (or is cancelled) the data folder is rescanned and the
  map shows the imported tiles in green.
- External SSDs often slow down late in a long import: their fast write
  cache fills, or the enclosure gets hot and throttles. That is the drive,
  not the program.
- The source folder must not be inside the data folder, or contain it.

## Repository layout

| Path | Contents |
|------|----------|
| `GDEM.groupproj` | Project group |
| `GDEMFetch/` | The GDEMFetch application: the project files, with its units in `lib/` and `ui/` (see [GDEMFetch units](#gdemfetch-units)) |
| `styles/` | FMX styles for the themes, with the resource script and the pre-build script that builds them; see [Themes](#themes) |
| `maps/` | World map images and vectors. `world_1080x540.jpg` and `world_vectors.bin` (borders and coastlines) are linked into GDEMFetch as resources. `8081_earthmap10k.jpg` (10800 x 5400) is kept here locally but is excluded by `maps/.gitignore`, so it is not in the repository. |
| `delphi-neon/` | Neon JSON library (git submodule) |
| `tools/pasdoc_check.py` | Checks the units follow the PasDoc rules; see [Notes for Claude](#notes-for-claude) |
| `tools/build_vectors.py` | Builds `maps/world_vectors.bin` from Natural Earth; see [Borders and coastlines](#borders-and-coastlines) |
| `CLAUDE.md` | Handover notes: the project's current state, test results and lessons learned, for picking the work up in a new conversation |
| `docs/` | Ignored for development |
| `models/` | Ignored for development |

### GDEMFetch units

The project files (`GDEMFetch.dpr`, `GDEMFetch.dproj`, the icon and the
macOS templates) are in `GDEMFetch/`; the units are in two folders inside
it:

- **`lib/`**: everything that does the work and could serve another
  program: tiles, NASA, downloads, the data folder, settings. These units
  never use FMX or anything in `ui/`; `tools/pasdoc_check.py` reports any
  that do.
- **`ui/`**: everything to do with the user interface: the forms, the
  map, themes and drawing. These use `lib/` freely.

**lib/**

| Unit | Purpose |
|------|---------|
| `GDEMTiles` | Tile names and `TTileRect`, a block of tiles |
| `GDEMTileIndex` | `TTileIndex` bitmap of which tiles exist, and its CMR builder |
| `GDEMCMR` | Neon models for CMR search results; no networking |
| `GDEMDownloader` | Finds and downloads tiles: CMR lookups, single downloads, `TDownloadThrottle` |
| `GDEMDownloadBatch` | `TDownloadBatch`, a whole batch of downloads: lookup, parallel workers, retries and summary, reporting through events |
| `GDEMReport` | `TDownloadReport`, the report file for each batch of downloads; `HideURLQueries` |
| `GDEMStore` | The data folder: block layout, downloaded-tiles bitmap, importing, rescanning, moving, deleting, free space; `FormatByteSize` and `FormatDuration` |
| `GDEMVectors` | `TWorldVectors`: country borders, coastlines and country names |
| `GDEMSettings` | Loads and saves `settings.json` with Neon |
| `GDEMCancel` | `TCancelToken`, shared by the Cancel button and background jobs |
| `GDEMAwake` | `TKeepAwake`, which keeps the computer from sleeping while a job runs |
| `GDEMBrowser` | Opens web links in the default browser on each platform |
| `GDEMGpuPreference` | Reads and sets Windows' graphics processor preference for the program (ported from Sprite3D's `GpuPreference`); does nothing on other platforms |

**ui/**

| Unit | Purpose |
|------|---------|
| `MainForm` | Main window: toolbar and menus over three tabs (Map, 3D, Debug), with progress and status bars; runs the jobs and shows their progress |
| `SettingsForm` | Modal settings dialog |
| `ProgressForm` | Modal progress dialog shown while data is downloaded or imported |
| `GDEMWorldMap` | `TWorldMapView`, the zoomable map with tile selection, borders and coastlines |
| `GDEMDrawing` | `ConfigureDrawing`, called from the `.dpr` before `Application.Initialize`, which tells Skia to draw on the GPU or the CPU and applies the Windows graphics processor choice |
| `GDEMThemes` | The themes, and `ApplyTheme` |
| `GDEMStyles` | Switches FMX styles at run time (ported from Sprite3D) |
| `GDEMTitleBar` | Colours title bars to match the style (ported from Sprite3D) |

The world map image `maps/world_1080x540.jpg` is linked into GDEMFetch as
the `WORLDMAP` RCDATA resource, and `maps/world_vectors.bin` as
`WORLDVECTORS`, so nothing needs deploying beside the program. The image
is an equirectangular projection: 3 pixels per degree, longitude -180 at
the left and latitude 90 at the top.

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
before starting work, then `CLAUDE.md`, which records where the work has
got to, what has been tested and what was learned along the way.

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
    Skia is the exception: it comes with Delphi, and its library is
    deployed by the entries the IDE adds.
- **Drawing goes through Skia** where it matters for speed. Large,
  unchanging shapes (the borders and coastlines) are built into Skia
  objects once and drawn with a matrix each frame, through the Skia
  canvas FMX draws on (`TSkCanvasCustom(Canvas).Canvas`, which already
  holds the control's position and clipping). Cut them into regions with
  bounds and draw only the regions on screen: drawing a whole-world path
  every frame was slower when zoomed in than building just the visible
  part. Keep a fallback through FMX's own canvas for when the canvas is
  not a Skia one, and wrap Skia code in `{$IFDEF SKIA}`.
- Anything Skia or FMX must know before start-up (the GPU or CPU choice)
  goes in `ConfigureDrawing`, which reads the settings file itself, since
  the main window has not loaded the settings yet.
- **JSON uses Neon**, not hand-written `System.JSON` code. Map keys
  explicitly with `[NeonProperty('...')]` where they differ from the
  Delphi names, and turn on `RaiseExceptions` when reading.
- **Document all code in PasDoc format** (<https://pasdoc.github.io/>):
  every unit, type, field (private ones included), method, property and
  constant, using `@abstract`, `@param`, `@returns`, `@raises` and
  `@link`.
  - The comment goes immediately before the item. Attributes such as
    `[NeonProperty('...')]` may sit between them; PasDoc skips them.
  - `@link` only to items declared in this project. Inherited or library
    items (`ShowModal`, `TThread`) are written with `@code` instead, as
    PasDoc cannot resolve them.
  - Things declared only in an implementation section are not in the
    generated docs, but are documented anyway.
  - Before delivering, run `python3 tools/pasdoc_check.py GDEMFetch`. It
    reads `lib/` and `ui/` as well, and reports undocumented interface
    items, `@link` targets that do not exist, unbalanced `@tag(...)`
    brackets, class fields declared after a method or property (which
    Delphi rejects), and `lib/` units that use FMX or a `ui/` unit. It
    prints `No problems found` when all is well.
- **Source files are ASCII only.** Delphi reads files without a byte
  order mark as ANSI, so write characters such as the degree sign as
  character codes (`#$00B0`).
- Keep the existing UTF-8 byte order mark on `.dproj` files.
- Anything the program needs at run time is linked in as a resource
  (an `RcItem` in the `.dproj`, read with `TResourceStream`), so nothing
  has to be deployed beside it. If a file ever cannot be a resource, add
  Deployment entries for every platform and say so in
  [Deploying](#deploying).
- When adding a file to the project (an `RcItem`, or a `None` item such as
  a script), disable its entry for every platform in the `.dproj`'s
  Deployment section (`<Enabled>false</Enabled>`), as is done for the map
  and `buildstyles.cmd`; the IDE otherwise deploys it.
- On Linux, a form's `TMainMenu` is replaced by an FMX `TMenuBar`
  (`TfrmMain.UseFmxMenuBar`): the native GTK menu bar showed only the
  first letter of each item. Copy the items onto the bar, free the
  original items one by one (so FMX rebuilds the GTK bar empty; freeing
  the `TMainMenu` with items in it leaves the GTK bar showing), free the
  `TMainMenu`, then give each copy its original's name, which points the
  form's field at it. Do not move the original items: FMX has already
  given them GTK widgets, which freeing the `TMainMenu` destroys, and the
  next change to a moved item crashes in GTK. A new form with a menu needs
  the same.
- On macOS, every privacy-sensitive location the program touches needs a
  usage description in the Version Info keys; keep them accurate.
- Naming: fields `F`, parameters `A`, locals `L`; non-visual units
  `GDEM*.pas`; forms `*Form.pas`.
- **Units go in `lib/` or `ui/`.** Anything that does the work goes in
  `lib/`, never using FMX or a `ui/` unit, so later programs can reuse it;
  `tools/pasdoc_check.py` reports a `lib/` unit that breaks this. Forms,
  controls, themes and anything else that needs FMX go in `ui/`. Keep
  work out of forms: a form starts a job and shows it, as `MainForm` does
  with `TDownloadBatch`, whose events it points at its progress and log
  methods. A unit that is mostly one but needs a little of the other goes
  where its dependencies put it (`GDEMDrawing` reads settings, but must
  set Skia's FMX switches, so it is in `ui/`). Add a new unit to both the
  `.dpr` (`in 'lib\Name.pas'`) and the `.dproj`.
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
- Never put credentials in source code or log output. Exception messages
  can carry the address that failed, and NASA's signed download addresses
  hold the user name and a signature in their query string, so
  `TfrmMain.AddLog`, `TfrmMain.ReportError` and `TDownloadReport.Add` pass
  everything through `HideURLQueries` (in `GDEMReport`). Write log lines
  only through those.
- Look tiles up in CMR by area (`bounding_box`), not by name, whenever
  there are more than a few: wildcard name searches are slow for CMR to
  answer, and the whole world took 230 of them. `LookUpTiles` chooses;
  see `CMR_BOX_CELLS_PER_TILE`.
- When paging CMR results, a page with fewer results than the page size
  is the last; do not ask for another.
- Get download URLs from CMR; do not guess Earthdata Cloud paths. Send
  the bearer token only to `*.earthdata.nasa.gov` and
  `*.earthdatacloud.nasa.gov`.
- All access to downloaded files goes through `TGDEMStore`; never build
  data-folder paths by hand.
- Tidy folder paths from the user with `NormalizeFolder` (in
  `GDEMSettings`), never `ExcludeTrailingPathDelimiter` alone: that turns
  the drive root `F:\` into `F:`, which Windows reads as the current
  folder on drive F.
- When several threads may create the same folder, create it under a lock:
  `ForceDirectories` gives up without making the folder if another thread
  wins the race to create its parent. The folder may be missing (an unplugged
  drive), so check it with `WithStore` before use.
- Work on the data folder runs as a job through `TfrmMain.RunJob`, one at
  a time, cancellable with a `TCancelToken`. `RunJob` also keeps the
  computer awake (`TKeepAwake`) for as long as the job runs.
- A batch that produces a line per file (downloads) writes that detail to
  a `TDownloadReport`, and sends only the start, problems and summary to
  the Debug tab, which would otherwise grow too large to use.
- Calls into the Objective-C runtime on macOS go through `objc_msgSend`
  declared with the exact argument types of each call (see
  `GDEMTitleBar` and `GDEMAwake`); Apple silicon requires it, so never
  call it through a variadic declaration.
- FMX lays out controls with the same `Align` (all `Bottom`, say) in the
  order of their positions. When resizing one in a `.fmx`, adjust the
  positions of its neighbours to match, or they change order.
- Anonymous methods capture variables, not values. When queuing work from
  inside a loop, pass the loop's values to a method as parameters (as
  `QueueMarkDownloaded` does) rather than capturing the loop variables.
