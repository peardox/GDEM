# GDEM: handover notes

Notes for picking this project up in a new conversation. Read
`README.md` first, the whole of it: it explains the project, and its
**Notes for Claude** section holds the working rules. This file adds what
the README does not: where the work has got to, what has been tested and
how it went, and lessons learned along the way.

Last updated: 27 October 2026.

## Starting a new conversation

1. Fetch the repository (<https://github.com/peardox/GDEM>, branch
   `main`) and its `delphi-neon` submodule.
2. Read `README.md`, then this file.
3. The owner's working copy is often ahead of GitHub. If the owner
   attaches or pastes files, build on those, not on GitHub.
4. Before delivering code, run `python3 tools/pasdoc_check.py` (it
   checks `GDEMFetch/`, `TileMaker/` and `common/`) and fix anything it
   reports.

## How the owner works

- Delphi 13, FMX. Develops on Windows; also builds and runs on macOS
  (Intel and Apple silicon, through PAServer) and Linux 64-bit, and all
  three are tested.
- Wants whole files in a zip of only the changed files, never patches. Do
  not remark on being unable to compile, or on changes not being
  committed or pushed.
- Tests promptly and pastes the Debug tab log back. Logs are the main
  evidence, so make log lines say exactly what happened.
- Likes measured numbers (speeds, times) and plain explanations of why
  something behaves as it does. Admit mistaken conclusions plainly: an
  early guess that parallel downloads "do not work" was wrong (see below).
- Test set-up: 1 Gbit/s line in the UK. Windows data folder
  `E:\usgs\ASTGDEM` on an external SSD; a complete copy of the world from
  USGS is in `E:\usgs\data\World` (all files in one folder), used to test
  importing. The Mac has an external USB4 SSD with room for the whole
  world.

## Where the work is

GDEMFetch is the first program, and it is feature-complete for fetching:

- World map (`TWorldMapView`) with drag selection, edge auto-scroll, wheel
  zoom mid-drag, east-west wrap, and live "X x Y = Z tiles, N with data,
  D downloaded" while dragging.
- Country borders and coastlines from Natural Earth drawn over the map
  (1:110m zoomed out, 1:50m zoomed in), and the country under the pointer
  named in the status bar (`GDEMVectors`). Right-click a country to
  select every tile it touches (`TWorldMapView.SelectTiles`, a selection
  made of separate tiles rather than a block).
- Tile index of the 22,912 tiles that exist, built from CMR, kept as a
  360 x 180 bitmap.
- Data folder (`TGDEMStore`) in 10-degree blocks, with a downloaded-tiles
  bitmap, rescan, move, delete, removable-drive handling and free-space
  reserve.
- Import from any folder of existing tiles, in parallel, with retries and
  a progress dialog.
- Downloads: CMR lookup by area (about 12 requests for the whole world)
  or by name for scattered tiles, parallel downloads with an AIMD
  throttle (Slow, Medium, Fast), resume with HTTP Range, retries, a
  report file per batch, keep-awake, token expiry warnings.
- Themes ported from Sprite3D; Windows icon; deployment checked on all
  desktop platforms.

The 3D tab is empty, waiting for the next stage.

### What is on GitHub

Everything to date is on GitHub as of commit `23b8d68` ("Borders and
countries - right click to select country"), which the owner built and
pushed. The session of 26 October 2026 added, in order:

- Download speed setting (Slow 1 to 4, Medium 2 to 8, Fast 4 to 16)
  replacing a number of downloads at once; `TDownloadThrottle` starts low
  and climbs (slow start, then additive increase after a cut).
- Token expiry read from the bearer token (a JWT, `exp` claim): shown in
  Settings, logged, warned about, and checked before fetching.
- Live selection counts while dragging (`OnSelectionChanging`).
- `GDEMReport` (`TDownloadReport`): per-file download detail goes to
  `<settings folder>/Reports/download-yyyymmdd-hhnnss.log`, not the Debug
  tab.
- Downloads stop only after 10 failures in a row, not 10 in total.
- `GDEMAwake` (`TKeepAwake`), used by `RunJob`.
- Faster tile lookup: `LookUpTiles` lists the selected block with
  `TCMRGranuleSearch.BoxURL` (`bounding_box`) instead of 230 wildcard
  name searches for the whole world, and stops paging at a short page.
- Borders, coastlines and country names from Natural Earth:
  `GDEMVectors.pas`, `tools/build_vectors.py`, `maps/world_vectors.bin`
  (the `WORLDVECTORS` resource), drawing in `GDEMWorldMap.pas`, View menu
  items and the status bar name in `MainForm`.
- Right-click country selection: `TGeoLayer.AddFeatureTiles` and
  `TWorldVectors.CountryIndexAt`, `AddCountryTiles` and `CountryName`;
  `TTileIndex.BoundingRect` (takes the short way round, so Russia gives
  19E to 169W, not the whole world); `SelectTiles`, `SelectionMask`,
  `SelectionName` and `OnRightClick` on the map; `MapRightClick`,
  `SelectedTileNames` and `SelectedTileCount` in `MainForm`, which Fetch
  and Delete use. The tile algorithm was checked by porting it to Python
  on the real data: Germany 68 tiles, United Kingdom 70, France 116 (with
  overseas parts), Lesotho 8, Luxembourg 4, Vatican 1, Fiji 20, Russia
  3473.
- `CLAUDE.md` (this file), `tools/pasdoc_check.py`.

Two later commits on GitHub, `3f31426` and `e1391d8` ("Handover world"),
hold the last of that session's work and this file.

The session of 27 October 2026 added:

- `MainForm`: Fetch selection now counts the tiles it leaves out because
  they are already downloaded and passes the number down
  (`FetchTiles`, `StartFetch`, `RunDownloads`, parameter `AAlready`), so
  the summary's "were already here" covers the whole selection. Before,
  only tiles the job itself found in the data folder were counted, which
  is how the whole-world run below seemed to have lost a tile.
- `GDEMReport.HideURLQueries`: on macOS a timed-out download's error
  message held the whole signed CloudFront address, user name
  (`A-userid`) and signature included, and it went into the report. The
  query string of any web address is now replaced by `?...` in
  `TDownloadReport.Add`, `TfrmMain.AddLog` and `TfrmMain.ReportError`, and
  at the downloader's two catch points (`DownloadFile` and the CMR
  search), so retry messages and the errors raised from them are clean
  wherever they go. Checked against the whole-world report: one line
  changed, the S81E086 time-out.

The owner then enabled Skia (`8ebe65f` "Added Skia": `FMX.Skia` and
`GlobalUseSkia := True` in the `.dpr`, the `SKIA` define, and Deployment
entries for `sk4d.dll` and `libsk4d.so`), because scrolling the map had
become sluggish. Then:

- `GDEMWorldMap`: borders and coastlines drawn from cached Skia paths
  (`LayerPath`, `PaintLayerSkia`, `FLayerPaths`, `UseSkiaPaths`), built
  once per layer in degrees (x = lon + 180, y = 90 - lat) and drawn per
  map copy with `Concat(Scaling * Translation)` on
  `TSkCanvasCustom(Canvas).Canvas`; stroke width is divided by the scale.
  The old per-frame `TPathData` code is the fallback. Frame timing:
  `TMapPaintStats`, `OnPaintStats`, `BeginMeasuring` and `EndMeasuring`
  around drags, pans and wheel zooms (ended 1 s after the last notch);
  `Paint` times `PaintMap`, the former body.
- `MainForm`: View > Draw Lines from Cached Paths and View > Log Drawing
  Times, used for the timings below and then removed at the owner's
  request, with `MapPaintStats`. The map's `UseSkiaPaths` and
  `OnPaintStats` stay, unused, for measuring again (for the
  high-resolution map, say): assign `OnPaintStats` to a handler that logs
  the `TMapPaintStats`.
- README: Requirements, View menu, a new Drawing section, Deploying (the
  Skia libraries) and the code rules.

Owner's timings (Windows, same moves and zooms each way):

- CPU (`TSkRasterCanvas`): 14 to 21 frames a second; 33 to 50 ms a frame,
  of which only 3 to 21 ms was lines: the rest was pixel filling
  (stretching the world image and the tint bitmap across the window) and,
  outside `Paint`, copying the CPU image to the window. Whole-world cached
  paths were slower than building per frame (13 to 21 ms against 5 to
  9 ms).
- GPU (`TVkCanvas`, after `GlobalUseSkiaRasterWhenAvailable := False`):
  34 to 125 frames a second; everything but the lines about 0.1 ms. Lines
  zoomed out: cached 4.2 to 4.9 ms, built 8 to 11 ms. Zoomed in (1:50m):
  cached 13 to 17 ms, built 5 to 10 ms, because the whole-world path was
  drawn when a few hundred points were on screen.

So, in the same session:

- `GDEMDrawing` (new; in the `.dpr` and `.dproj`): `ConfigureDrawing`,
  called instead of `GlobalUseSkia := True` before
  `Application.Initialize`, reads `TGDEMSettings.Drawing` (`GPU` or `CPU`,
  default `GPU`) and sets `GlobalUseSkiaRasterWhenAvailable` on Windows or
  `GlobalUseMetal` on macOS. `DescribeDrawing` is logged at the start of
  `RunStartup` with `TCanvasManager.DefaultCanvas.ClassName`, which Skia
  sets to the canvas it chose. Settings has a Drawing row under Theme
  (form 24 pixels taller; hidden and shrunk back on Linux, where Skia has
  no GPU canvas). macOS Metal is untested.
- `GDEMWorldMap`: cached paths cut into 10 degree squares
  (`TLinePiece`, `LayerPieces`, `LINE_PIECE_DEGREES`); a segment crossing
  into another square belongs to the square it starts in, whose bounds
  include its end, and the next piece starts there. Checked in Python on
  the real layers: every segment kept (coast50 58,987), bounds always
  hold their segments; coast50 is 355 pieces, and a view of the British
  Isles draws 2 of them (1,514 of 61,428 points).
- The owner's Windows machine is a laptop with an RTX 5090 Mobile and
  the Intel graphics of a Core Ultra 9 275HX. GPU drawing showed no lag;
  CPU drawing lagged. Gorilla3D (planned for the 3D tab) gains a lot
  from the Windows GPU preference. Windows calls the choices High
  performance, Power saving and Let Windows decide.
- `GDEMGpuPreference` (new; in the `.dpr` and `.dproj`): ported from
  Sprite3D's `src/common/GpuPreference.pas`, with these differences:
  scoped `TGpuPreference` (`Automatic`, `PowerSaving`,
  `HighPerformance`) with keys and captions; compiles on every platform
  (read and write return False off Windows); and it changes only the
  `GpuPreference=N` part of the registry value, keeping others such as
  Windows 11's `SwapEffectUpgradeEnable=1`, where Sprite3D overwrote the
  whole value. `TGDEMSettings.GpuPreference` (default `Automatic`).
  Settings has a Graphics row under Drawing (form now 600 high; rows
  hidden and the form shrunk where unavailable); OK writes the registry
  only if the choice changed. `ConfigureDrawing` writes the registry at
  start-up when the setting is Power saving or High performance and
  differs (so a new build path gets it), never for Automatic;
  `DescribeDrawing` adds the preference read at start-up and any change.
  Whether a change written before `Application.Initialize` counts in the
  same run is unknown; the log says "from the next start" to be safe.
  Whether the preference steers Vulkan and OpenGL as well as DirectX is
  for the owner to see in Task Manager's GPU engine column.

Next: the owner's timings of the cut pieces on the GPU, zoomed out and
zoomed in, and a check of the Graphics setting on the laptop.

The View menu's two timing items were then removed (commit `cc5a6c2`
"Mainform" has the final form). The owner is leaving performance testing
until GDEM tiles are drawn, which may change it anyway, and is testing on
macOS and Linux.

### lib and ui (27 October 2026)

At the owner's request the units were split into `GDEMFetch/lib/`
(reusable, no FMX) and `GDEMFetch/ui/` (forms, map, themes, drawing),
with the project files left in `GDEMFetch/`. The owner chose folders
inside `GDEMFetch/` rather than at the repository root. Files were moved
with `git mv`; the `.dpr` `in` paths and `.dproj` `DCCReference`s point
into the folders.

- `lib/GDEMDownloadBatch` (new): `TDownloadBatch` holds what was
  `TfrmMain.RunDownloads` (lookup, report, throttle, worker threads,
  summary), unchanged in logic, reporting through `OnLog`, `OnStatus`,
  `OnOverall`, `OnItem` and `OnTileDownloaded`, and returning a
  `TDownloadBatchResult`. `MAX_DOWNLOAD_FAILURES` moved with it.
  `TfrmMain.RunDownloads` now creates the batch, points its events at
  `AddLog`, `ProgressStatus`, `ProgressOverall`, `ProgressItemText` and
  `QueueMarkDownloaded`, and shows the "N tiles failed" dialog.
- `FormatDuration` moved to `lib/GDEMStore` beside `FormatByteSize`;
  `TfrmMain.FormatDuration` calls it.
- No separate UI helper unit was needed: the only borderline unit,
  `GDEMDrawing` (reads settings, sets Skia's FMX switches), goes in `ui/`
  by its FMX dependency. `GDEMBrowser` and `GDEMGpuPreference` have no
  FMX, so they are in `lib/`.
- `tools/pasdoc_check.py` reads subfolders, prints paths relative to the
  project folder, and reports any `lib/` unit that uses `FMX.*` or a `ui/`
  unit (tested by planting both in a copy).

Not yet built: the first build after the move, and a download to check
`TDownloadBatch` behaves as `RunDownloads` did (a small fresh area is
enough; the report and Debug tab lines should read as before).

Owner's tests the same morning (of the build before the split):

- macOS: fine. Settings offers GPU or CPU; Skia draws with Metal.
- Linux: mostly fine. No GPU or CPU choice (as intended); Skia's CPU
  canvas. The menu bar and its submenus showed only the first letter of
  each item. First fixed with Sprite3D's workaround (move `mnuMain`'s
  items onto an FMX `TMenuBar`, free `mnuMain`), which crashed at
  start-up before the window appeared: access violation in
  `libgobject-2.0` (`g_object_ref` on a stale pointer). FMX has already
  made the GTK menu by `FormCreate`; each `TMenuItem` keeps a handle to its
  GTK widget, freeing `mnuMain` destroys the widgets, and the next
  property change on a moved item (`UpdateButtons` sets several
  `Enabled`) touches a dead one. Sprite3D has the same bug but changes
  only one item, so it gets GTK-CRITICAL warnings at start-up
  (`gtk_menu_item_set_label: assertion 'GTK_IS_MENU_ITEM'`) instead of a
  crash. Runtime error 217 with Skia off was very likely the same crash
  surfacing differently.
- Now `TfrmMain.UseFmxMenuBar` copies each item (Text, Enabled, Visible,
  AutoCheck, IsChecked, RadioItem, GroupIndex, ShortCut, Tag, OnClick,
  and submenus) onto the `TMenuBar` with the form as owner, frees
  `mnuMain` with its originals (FMX tears the GTK menu down normally, and
  `RemoveComponent` sets each original's field to nil), then names each
  copy after its original, which makes `SetReference` point the form's
  field at the copy. The bar gets `Position.Y := -1` before
  `Align := Top`, so it sits above `layTop`. Tried on Linux: no crash,
  menus work, but the GTK bar stayed above the new one showing "F D V":
  freeing a `TMainMenu` with items in it does not make FMX rebuild the GTK
  bar. So the originals are now freed one by one first (each removal
  rebuilds the GTK bar; empty, it goes, as in Sprite3D), then
  `RecreateOSMenu`, then `mnuMain` is freed. Not yet tried.
  Sprite3D would benefit from the same change.

Anything delivered after that is in the conversation, not here: ask the
owner whether it has been applied before changing the same units.

### Next, as far as is known

1. **Skia drawing**: GPU is now the default, with Windows' graphics
   processor choice in Settings (see above). Still to do: timings of the
   cut pieces; the Graphics setting tried on the laptop; macOS with
   Metal.
2. **Borders and country selection in use.** Built and pushed; nothing
   reported wrong yet, except that panning became sluggish, which item 1
   addresses. Things to watch: that the lines match the map (now also
   when drawn from the cached Skia paths), the country name in the status
   bar, right-click
   selection of a country across 180 degrees (Fiji, Russia), and that
   right-drag still pans. Colours: borders pink `$FFFF80AB`, coastlines
   white at 55%.
3. **GeoTIFF reader** in pure Pascal for the `_dem` and `_num` files
   (LZW, 256 x 256 tiles, Int16 and UInt8, 3601 x 3601, 8 overviews).
   <https://github.com/peardox/volatile> has older decoding logic to
   reuse, but uses a Windows-only libtiff binding, so take the logic only.
4. **High-resolution map** from `maps/8081_earthmap10k.jpg` (10800 x
   5400, gitignored, so not in a fresh clone), cut into tiles loaded as
   the user zooms. Natural Earth's 1:10m borders and coastlines would suit
   it; add them as more layers in `tools/build_vectors.py`.
5. **3D tab**: content to come once tiles can be read.
6. Smaller ideas offered but not taken up: parallel workers and the
   progress dialog for moving the data folder; a macOS `.icns` and a
   Linux `.desktop` file; a menu item to open the Reports folder.

### Shift + right-click (27 October 2026)

Shift + right-click adds the country under the pointer to the selection
(`TfrmMain.MapRightClick`, now given the modifier keys: `TMapPointEvent`
has an `AShift` parameter). The current selection's tiles (the map's
`SelectionMask`, or every tile of a dragged block) are put in a
`TTileIndex` and the country's added with the new `TTileIndex.AddIndex`
(a bitwise OR), so a tile shared by two countries is counted once; the
owner expected overlaps to need tidying, but the union removes them.
The selection is named from `FSelectedCountries` (`Germany + France`, or
`Germany + France + 3 more`), which is trusted only while the map's
`SelectionName` is still `FSelectionLabel`; a dragged block is named
`Selected area`. Not yet built.

The download summary now says "1 was already here" and "1 has no data"
for counts of one (`IfThen` in `TDownloadBatch.Run`).

The toolbar's Tile label, tile name box (`edtTile`) and Fetch tile button
(`btnFetch`, `btnFetchClick`) were removed at the owner's request, as
selecting on the map does the same; Fetch selection, Cancel and the
selection label moved left to fill the space. `FetchTiles` stays, used by
Fetch selection.

Fetch selection no longer asks "Download N tile(s), about X?" (it asked
for more than `CONFIRM_TILE_COUNT`, 10, tiles, or when space was short):
the owner found it pointless before the progress dialog, which has Cancel.
`CONFIRM_TILE_COUNT` is gone; a selection too big for the free space
above the reserve now gets a `WARNING:` line on the Debug tab instead.

The free-space reserve is now a percentage of the drive's size, not a
fixed number of megabytes: `TGDEMSettings.MinFreePercent` (JSON
`minFreePercent`, default `DEFAULT_RESERVE_PERCENT` 10, kept to
`MIN_RESERVE_PERCENT` 1 to `MAX_RESERVE_PERCENT` 50; never 0, at the
owner's wish, as SSDs need spare space). The old `minFreeSpaceMB` is
ignored by Neon (it reads only declared members), so old settings start
at 10%. `GDEMStore` gained `DriveSizeAt`, `ReserveAt(path, percent)` and
`Reserve(percent)`, sharing a `MeasureDrive` routine with `FreeSpaceAt`
(`GetDiskFreeSpaceEx` total on Windows, `f_blocks * f_frsize` on POSIX);
an unmeasurable drive gets `FALLBACK_RESERVE_BYTES`, 2 GB.
`TfrmMain.ReserveBytes` uses the data folder's drive; `StartMove` checks
the destination against that drive's own share. Settings reads "Leave at
least [n] % free drive space (N GB on that drive)", updating as the
number or folder changes. The owner asked for "10% of the drive's free
space"; this was taken as 10% of the drive, the usual SSD advice, since a
share of the free space would shrink as the drive filled.

### Move Existing Files (27 October 2026)

Data > Move Existing Files... (`mnuMoveImport`, `mnuMoveImportClick`) is
the import with the originals deleted, for moving the owner's old
downloads (such as `E:\usgs\data\World`, all in one folder) into the
block layout; the owner has them backed up. `TGDEMStore.ImportFrom` has a
new `AMoveSource` parameter (default `False`): after a file's copy is
size-checked and renamed into place the source is deleted, as are sources
the store already has at the same size (deleted after the space check,
before the workers start). Failures to delete only log a `WARNING:` and
count in `TImportResult.SourcesKept`; `SourcesDeleted` counts the rest.
Emptied folders inside the source are removed, never the source itself
(`RemoveEmptyFoldersUpTo`). If the source is on the same drive as the
store (`SameDrive`: `GetVolumePathName` on Windows, `st_dev` on POSIX)
the up-front total-space check is skipped. It still copies and deletes
rather than renaming, as the owner asked for the import's behaviour; a
rename within one drive would be far faster for 400 GB if wanted. Not
yet built.

### The old world download (27 October 2026)

The owner's earlier copy of the whole world, made with NASA's AppEEARS
(which the owner finds a poor tool), held 45,819 tile files, 5 short of
the 45,824 (22,912 x 2) that exist; Move Existing Files moved them all
(0 failed). A whole-world Fetch selection then downloaded just the
missing ones, and counts in WSL gave 22,912 `_dem.tif` and 22,912
`_num.tif`. (A PowerShell count gave 0 for reasons not found; WSL's
`find` is the one to trust.)

### TileMaker (27 October 2026)

The owner planned this layout for a second program. TileMaker
(`TileMaker/`, `lib/` and `ui/`, in `GDEM.groupproj`) cuts an image into
a tile set for GDEMFetch's high-resolution map. Decisions, mostly the
owner's:

- Analysis of 10800 x 5400 by prime factors: three halvings to
  1350 x 675; square tiles must divide 675; **225** chosen (the owner had
  picked it already). Squares over 2:1 rectangles. Levels stop at the
  first that is no wider than 2048 (`DEFAULT_COARSEST_WIDTH`), or when a
  side would stop being whole.
- Shared units in a new root `common/` (owner's choice over
  `TileMaker/lib`): `GDEMFactors` (prime factors, GCD, divisors,
  `LevelSizes`, `TileSizesFor`, `SuggestTileSize` nearest 256 by ratio),
  `GDEMResample`, `GDEMTileSet`. Neon stays at the root; both programs
  reach it as `..\delphi-neon\Source`.
- Resampling for quality, not speed (owner): Lanczos-3 widened by the
  factor, linear light (sRGB tables, 65,536-step encode table),
  premultiplied alpha, every level from the full image, wrapping east to
  west for world maps, edge rows repeated. Skia's own
  `TSkSamplingOptions.High` is a Mitchell cubic with a fixed 4x4
  footprint, which aliases when shrinking, so it is not used for this.
  Ported to Python with numpy and checked: weights sum to 1 (12, 24, 48
  taps for 2, 4, 8), flat colour unchanged, a 1-pixel checkerboard halves
  to sRGB 188 (gamma-space averaging would give 128), wrapping works.
- Tiles: JPEG quality 90 by default (owner), WebP and PNG offered.
  Encoded straight from the level's pixels with
  `TSkImageEncoder.EncodeToFile` (tile's top-left pointer, level's row
  bytes). Source read with `TSkImage.MakeFromEncodedFile` and
  `ReadPixels` as RGBA8888 unpremultiplied, avoiding FMX's `TBitmap` size
  limits. The preview is the smallest level, made by `ReduceImage`, shown
  in a `TSkPaintBox` with a level's grid.
- Save As makes a folder named as typed; it must be new or empty, or
  hold an earlier tile set (replaced after asking). Level folders are
  named `WxH`, tiles `r000_c000.<ext>`, and `tileset.json` (format 1) is
  written last, atomically; see the README's Tile sets.
- `TileMaker.dproj` was made by script from `GDEMFetch.dproj`: new GUID,
  names, no themes pre-build step, the default Delphi icon, `..\common`
  on the search path, TileMaker's own macOS privacy texts, and only the
  RAD Studio and Skia deployment entries (the IDE adds the program's
  own). The macOS templates were copied. No `TileMaker.res`: the IDE
  makes it. No themes or settings yet. The Linux menu fix is a copy of
  GDEMFetch's `UseFmxMenuBar`; once the owner's test of the general
  `ReplaceMainMenu` unit (`LinuxMenuIssues.md`) passes, both could share
  it (it uses FMX, so it would need a shared ui folder, not `common/`).
- `tools/pasdoc_check.py` with no arguments checks all three folders,
  and applies the no-FMX rule to `common/` too.

Built by the owner, after one fix: the default icon is
`$(BDS)\bin\delphi_PROJECTICON.ico` (I first wrote `..._PROJECTICO.ico`,
which BRCC32 could not find). The owner made the tile set and committed
it as `maps/tiles/` (commit `9615c81`, 12 MB: 1152 + 288 + 72 + 18 tiles,
`tileset.json` as designed). Checked in Python: every tile present, 225 x
225 JPEG, nothing extra. Levels 1 and 2 match a numpy Lanczos-3
linear-light reference computed from level 0 to within JPEG noise (mean
difference about 0.5 of 255, max 5 to 7), at the date line too, so the
Pascal resampler and its wrapping are right; level 3 agrees on average
(0.85), with a few larger differences only on sharp high-contrast edges,
not at tile borders. Stitched level 3 shows no seams. The step across the
date line is the same in every level as in the source image itself.

Next: GDEMFetch loads a tile set (chosen in Settings, or
found beside the program) with `TTileSet.Load` and draws the level from
`LevelFor`, decoding tiles on demand with a cache, the coarser level
showing until a tile is ready, and level 0 enlarged past its own detail
(the owner wants zoom beyond 1:1 for accurate selection and, later,
drawing). With no tile set, the 1080 x 540 map stays.

## NASA: what was found by testing

- CMR (`cmr.earthdata.nasa.gov/search/granules.json`, collection
  `ASTGTM` version `003`) needs no login. Paging uses the
  `CMR-Search-After` header, up to 2000 per page; `CMR-Hits` gives the
  total. Many tiles can be looked up at once with repeated
  `readable_granule_name[]=ASTGTMV003_N50W002*` and
  `options[readable_granule_name][pattern]=true`; 100 per request works
  and returns in about a second, but wildcard searches are slow for CMR
  and the whole world took 230 of them (and as many empty follow-up
  pages), many minutes. `LookUpTiles` now lists the selected block with
  `bounding_box=W,S,E,N` instead, 2000 per page, about 12 pages for the
  world, and uses names only for tiles far apart
  (`CMR_BOX_CELLS_PER_TILE`). A page with fewer results than the page
  size is the last, so the empty extra page is no longer fetched.
- A bounding box also returns the granules just outside it, because
  each tile's edges overlap its neighbours by half a pixel; results are
  filtered against the tiles wanted.
- The sandbox cannot reach NASA (CMR or Earthdata) directly: shell
  requests and web fetches to those hosts are refused. Real responses
  come from the owner's logs.
- Downloads: `https://data.lpdaac.earthdatacloud.nasa.gov/...` with
  `Authorization: Bearer <token>` answers **303** to
  `d1nklfio7vscoe.cloudfront.net/...`, fetched **without** the token.
  Redirects are followed by hand (`HandleRedirects := False`) so the token
  never leaves NASA hosts. CloudFront honours `Range` (206).
- The old Data Pool (`e4ftl01.cr.usgs.gov`) was retired on 3 December
  2025.
- NASA cuts connections off (WinHTTP 12152 or 12029, or a short body)
  when the **same files are downloaded again and again** in a short time,
  as happens when deleting and re-fetching while testing. Fresh areas
  download in parallel without trouble. Always test on a new area.
- **Whole world, 26 October 2026, on the Mac at Fast** (old name lookup,
  which alone took many minutes): `Downloaded 22911 tile(s), 383.1 GB, in
  1 h 46 min at 62 MB/s, up to 16 at a time; 0 were already here, 0 have
  no data, 0 failed.` No cut-backs or failures; keep-awake and App Nap
  handling held for the whole run. Twelve HTTP 502s, one 429 and one
  time-out were ridden out by retrying. The index lists 22,912 tiles; the missing one
  was `N50W002`, downloaded earlier by name and so left out of the job by
  Fetch selection, not lost at the selection's edge. Comparing the
  owner's `tileindex.bin` and `downloaded.bin` afterwards showed all
  22,912 present. Both files use the same layout, so comparing them bit
  for bit is the quick way to check a data folder is complete.
- **Block lookup** (`bounding_box`) tested on 27 October 2026 against the
  real CMR, with a whole-world selection into an empty data folder: it
  works, with no fallback to names. The old name lookup took 6 minutes
  for the whole world (230 requests).
- **Slow after the whole world, 27 October 2026.** The day after the
  whole-world run (383 GB from the Mac, which shares the owner's static
  IP and Earthdata account), Windows at Fast fetched Britain and Ireland
  (87 tiles, 1.0 GB) at only 5 MB/s, and a part of Australia was slow
  too. The report showed GDEMFetch working as it should: block lookup of
  all 87 in one request in 1 s, 4 to 16 at once within 9 s, no retries,
  502s, 429s or cut-backs. NASA answered every request and redirect
  promptly, but each file then arrived at 0.3 to 0.6 MB/s (N57W004_dem
  14.1 MB in 23 s, N56W005_dem 22.7 MB in 59 s, N52W004_dem 21.6 MB in
  79 s), against about 3.5 MB/s per connection before. So NASA (or
  CloudFront) was slowing every connection for this account or IP, not
  refusing it, which the throttle cannot see. NASA publishes no limits.
  To be checked: whether speed returns after a day or two. Every tile
  had been downloaded from this IP and account by then, so there is no
  fresh area to compare. Nothing in GDEMFetch was changed for it.
- Measured on the owner's line: 1 at a time about 3 MB/s; 3 about
  12 MB/s; 6 about 15 MB/s; 12 about 26 MB/s (36 tiles); 16 about
  56 MB/s (100 tiles, 2.1 GB in 38 s, no errors, no cut-backs). With the
  AIMD throttle at Fast (starting at 4): 47 MB/s (168 tiles, 3.1 GB in
  1 min 9 s, no errors, no cut-backs). Larger batches and larger files
  both raise the figure, and runs vary by 15% or so, so compare like with
  like. The whole world (about 410 GB) at 47 to 56 MB/s is 2 to 2.5
  hours.
- Tile files vary a lot in size: flat land compresses to about 12 MB for
  the DEM, mountains about 29 MB; NUM files 2 to 6 MB. The average pair is
  close to the 18 MB estimate (`ESTIMATED_TILE_BYTES`).
- Bearer tokens last 60 days and are JWTs.

## Lessons learned

These cost time once; the README's rules cover most of them, and the
reasons are here.

- FMX on Linux shows a `TMainMenu` as a native GTK menu bar that shows
  only the first letter of each item. Sprite3D's fix (in its main form,
  not its README) moves the items onto an FMX `TMenuBar`, but moved items
  keep handles to GTK widgets that freeing the `TMainMenu` destroys, which
  crashed GDEMFetch; copy the items instead (see above). Check Sprite3D's
  source, not just its README, for platform workarounds, and check its
  start-up output for warnings before copying one.

- `<WelcomePageFile Path="..\README.md"/>` in the `.dproj` opens the
  README with the project: the path is relative to the project file.
- `ForceDirectories` is not safe when several threads create folders
  under the same new parent: one gives up. Create folders under a lock.
- `ExcludeTrailingPathDelimiter('F:\')` gives `F:`, the current folder on
  F, not its root; that produced paths like `F:N80\E010\...`. Use
  `NormalizeFolder`.
- FMX bottom-aligned controls are ordered by position; a resized layout in
  the Settings form overlapped the buttons and moved them.
- The IDE adds project files (the map, `buildstyles.cmd`) to every
  platform's deployment; on macOS `System.StartUpCopy` then copies them
  into the user's folders. Their entries are disabled in the `.dproj`.
- `TNumberBox` has no `ValueType` in Delphi 13: use `DecimalDigits := 0`.
  `TForm.Release` is deprecated; desktop uses blocking `ShowModal` and
  Android the callback form.
- A slow import that looked like a program problem was a bad USB cable.
  Check the hardware when numbers look wrong: the owner's USB 3 SSD
  benchmarks about 1050 MB/s read and 950 MB/s write; import reached about
  700 MB/s with 6 at once, about 300 MB/s with 1.
- The Debug tab memo cannot hold a whole-world batch (about 8 lines per
  tile), which is why the report file exists.
- Natural Earth can be fetched from the sandbox with a sparse git clone
  of `https://github.com/nvkelso/natural-earth-vector` (`--filter=blob:none
  --sparse`, then `git sparse-checkout set --no-cone` with the
  `/geojson/...` files); the full repository is several GB. Version used:
  5.2.0-pre.
- Large reference data (the borders) is converted at build time by a
  script in `tools/` into a compact binary resource, rather than parsing
  JSON at start-up; the JSON-uses-Neon rule is about JSON the program
  itself reads.
- Delphi requires every field of a class section before its first method
  or property (E2169). New private methods were once inserted among the
  fields; `tools/pasdoc_check.py` now reports that.
- Delphi's flow analysis is unreliable around `try`/`except`: removing a
  starting value it called unused (H2077) produced "might not have been
  initialized" (W1036). The fix in `DownloadFile` sets the value at the
  top of the loop and lets one path rely on it.
- On macOS, `NSProcessInfo` `beginActivityWithOptions:reason:` with
  `NSActivityUserInitiated` prevents idle sleep and App Nap; the returned
  activity is retained until `endActivity:`.
