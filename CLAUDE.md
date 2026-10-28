# GDEM: handover notes

Notes for picking this project up in a new conversation. Read
`README.md` first, the whole of it: it explains the project, and its
**Notes for Claude** section holds the working rules. This file adds what
the README does not: where the work has got to, what has been tested and
how it went, and lessons learned along the way.

Last updated: 28 October 2026, 10:35, at the end of a session, as the
owner was about to push the level-of-detail 3D view.

## Where to pick up (28 October 2026)

- GitHub `main` was at `19c8563` ("SystemInfo sync"), checked identical
  to everything delivered before it. The last delivery,
  `gdem-3d-lod.zip`, holds the **level-of-detail 3D view** (new
  `lib/GDEMTerrainLod.pas`; rewritten `lib/GDEMTerrain.pas` and
  `ui/GDEMTerrainView.pas`; `MainForm`, `GDEMViewOptions`, `.dpr`,
  `.dproj`, README, this file). The owner was about to push it,
  **unbuilt**: written without a compiler, checked by `pasdoc_check.py`
  and a Python port of the tree. Fetch GitHub first and check whether the
  push holds it.
- **First job of the next session:** the owner's first build of it. Expect
  compile errors to fix first, then go through "To check first when
  built" at the end of the "Level of detail" section below, and ask for
  the `3D: settled` and `3D: memory with` lines from the Debug tab.
- If the level-of-detail view cannot be made to work, `19c8563` has the
  working single-tile view (the owner chose this stage as a safe point to
  return to).
- Owner's ideas waiting: use the `GDEMSystemInfo` figures to choose CPU
  or GPU drawing (and View layers, 3D detail) on a first run; the
  high-resolution map over the 3D surface. The flying camera has been
  delivered (see "Flying" below), unbuilt.

## State at the end of 27 October 2026

The owner pushed the evening's 3D work on top of `c1096a1` ("Add
FastMM5") as `d25e46b`. Everything since was delivered as zips and is in
that push; before it, the working copy was validated: `pasdoc_check.py` clean
(including `tools/GeoTiffCheck`); every source ASCII; both `.dproj` files
keep their BOM and parse; every unit in `lib/` and `ui/` is in both the
`.dpr` and the `.dproj`, and every path exists; each `RcItem` exists, its
Deployment entries disabled; every form's `.fmx` objects and events match
its unit; `maps/world_vectors.bin` and `maps/tiles.zip` rebuild byte for
byte from their sources (Natural Earth at `ca96624`, and `maps/tiles`);
nothing refers to removed code.

What the push holds, in the order it was done (details in the sections
below):

1. FastMM5 first in both `.dpr`s on Windows, with `REPORT_LEAKS`.
2. `common/GDEMGeoTiff.pas`, the pure-Pascal GeoTIFF reader, and
   `tools/GeoTiffCheck`. **Verified**: all 18 images of the two volatile
   tiles decode identically to libtiff on Windows.
3. The 3D tab (`lib/GDEMTerrain`, `ui/GDEMTerrainView`). **Works** on
   Windows: the Isle of Wight drew correctly first time (windings,
   colours, shading, camera). Full detail (3601) added and timed: 2.49 s
   to build 13 million vertices.
4. The main toolbar moved into the Map tab.
5. Mountains in the search (Natural Earth elevation points,
   `world_vectors.bin` version 3), Show in 3D, the Click for 3D switch.
6. Panning in the 3D view.
7. The search box: "Search" label, arrow button, cleared by a click.
8. Five compiler hints fixed (`System.RTLConsts` in `GDEMTerrainView`;
   `IsClear` in `TWorldMapView.PaintPlaces`).

Then, after that push: `common/GDEMSystemInfo.pas`, the memory and GPU
figures in the log (see "Memory and graphics processors" below), working
on Windows, pushed as `16c109c` and `19c8563`.

Then the 3D view was rebuilt with level of detail over a window of tiles
(see "Level of detail" below): delivered on 28 October, not yet built.

Items 5 to 8 compiled (the owner's build reported only the hints of item
8), but have not been reported on in use. macOS and Linux have not run
any of items 2 to 8. Sections below that say "Not yet built" were written
before the owner's builds. No known bugs.

### Level of detail (28 October 2026, after `19c8563`)

The owner's idea: load the tiles round the camera (3 x 3 at first),
split tiles into finer pieces near the camera and coarser further away,
halving the detail at each doubling of distance, so far fewer triangles
are drawn and updating the tree is faster than building whole tiles. The
owner asked for "any steps that will work properly and particularly ones
that improve speed", with `19c8563` as the point to go back to if it
fails. Not yet built. What was done:

- **Patches** (`lib/GDEMTerrain`, rewritten; no FMX): 75 x 75 cells
  whatever their size (`PATCH_CELLS`). A tile's tree: depth 0 the tile,
  depth 1 its ninths (3 x 3), then quarters, to depth 5 (`NODE_ARCSEC`
  3600, 1200, 600, 300, 150, 75 arc-seconds; 48, 16, 8, 4, 2, 1 between
  samples). 75 was chosen because 3,600 = 75 x 48 and every depth gets a
  whole number of arc-seconds between samples; 64 does not divide 3,600.
  `TTerrainTile` (ref-counted, `ITerrainTile`) reads the coarsest image
  of the `_dem.tif` whose spacing is no wider than wanted, under a lock,
  when first needed, fills voids, and keeps it. `TTerrainLevel.Sample`
  blends the four nearest samples at the place the image's own
  pixel-is-area georeference puts them; checked in Python on the IoW tile
  against box averages of the full image: closer at every overview than
  index x 2 or point mapping (226: 0.80 m against 1.12 and 1.57).
  `BuildTerrainPatch` samples a 78 x 78 grid (a ring beyond the edges,
  from the neighbouring tiles where they have heights, so normals match
  across tiles), positions on a sphere (`TTerrainFrame`: east, down,
  north of a point at sea level; `ToGeo` is its exact inverse on the
  sphere), normals from neighbour differences, shaded height colours,
  then a skirt (each edge again, `SKIRT_CELLS` 1.6 cells x stretch + 20 m
  lower; wound both ways). 6,080 vertices, 12,450 triangles; one shared
  index list (`TerrainPatchIndices`), same winding as the first view.
  Sea and missing tiles are flat at 0, blue or grey, never split.
  Removed: `TTerrainGrid`, `LoadTerrainGrid`, `TerrainChunk` and the rest
  of the single-tile code.
- **Tree** (`lib/GDEMTerrainLod`, new; no FMX): `TTerrainLod`, main
  thread only. Window: tiles whose nearest point is within
  `TERRAIN_WINDOW_KM` (170) of the point looked at, dropped beyond 1.25
  times that; the owner's 3 x 3 in kilometres rather than tiles, because
  tiles are only 108 km wide at the equator (67 km at Manchester), so at
  higher latitudes it takes more tiles east to west. Split when the
  camera is nearer than `Range` (Low 1.5, Medium 2, High 3) times the
  patch's size; put back together beyond 1.15 times that
  (`SPLIT_HYSTERESIS`). A split patch stays on show until all its
  children are ready; a patch being put back together keeps its children
  on show until it is ready. Waiting patches go to `TTask.Run`, at most
  one per processor, ordered in view first, then depth, then distance;
  results come back through `ITerrainResults` (a locked queue that
  outlives the tree), matched by node id and generation, so results for
  freed nodes or an old frame or stretch are dropped. Boxes are
  estimated from the corners and middle at the parent's height range
  until made. Rebase: past `TERRAIN_REBASE_KM` (150) from the frame's
  point, `Start` again at the tile under the point looked at.
  `SurfaceY` gives the ground under a point from the finest heights read,
  without waiting.
- **View** (`ui/GDEMTerrainView`, rewritten): `ShowArea(south, west,
  reset)`, `TileLookup` (MainForm's `TerrainTileInfo`: land if
  downloaded, missing if in the tile index (or no index yet), else sea),
  `MaxDetail` (`TerrainMaxDepth`: 226 to depth 1 ... 3601 to depth 5),
  `Range`, `Exaggeration` (makes every patch again; tiles' heights are
  kept), `OnSettled`, `OnLog`. A 15 ms `TTimer` turns made patches into
  meshes for up to `UPLOAD_BUDGET_MS` (12) a tick, then calls `Update`
  if anything changed. Each mesh: `TGorillaSingletonMesh`, hidden until
  shown, vertices copied straight into the FMX buffer at offsets taken
  from `VerticesPtr[0]`, `NormalsPtr[0]` and a sentinel colour written
  with `Color0[0]` and found by scanning (falls back to the setters for
  whatever cannot be found; the settled line says which), indices moved
  in one go as 16 or 32-bit (found by writing two indices and looking),
  `IsDefOwner := True` (the property exists; whether it was already the
  default is unknown), `TMeshDef` static, one shared
  `TGorillaVertexColorMaterialSource` parented to the viewport.
  `NearPlane` 0.05 and `FarPlane` 3000 (km; Gorilla3D's defaults are 0.1
  and 10000). The centre sits on the ground (`SurfaceY`); the camera is
  kept 30 m above it. Panning has no limit; zoom 0.3 to 600 km.
  Gorilla3D's own frustum culling (on by default, using the mesh
  definition's bounds, which the docs say stay available for static
  meshes) leaves out patches not in view; the tree's own view test only
  orders the work.
- **MainForm**: Show in 3D no longer waits with the hourglass: it calls
  `ShowArea` and opens the tab. A Distance combo (Low, Medium, High) on
  the 3D toolbar, kept as `TViewOptions.TerrainRange` (default 20);
  Detail now defaults to Full and changes only how deep the tree goes
  (nothing is read again); Heights makes every patch again. Logs: `3D:
  showing ...` when asked, `3D: settled in N ms: ...` when the work is
  done, then `3D: memory with ...` a second later.

Checked in Python (no Pascal compiler): a port of the tree on simulated
land and sea tiles with patches finishing in random order, for six camera
positions including pans that bring new tiles in: shown patches never
overlap; holes only before a tile's first patch is made. Counts at
Medium: from 140 km at 35 degrees, 163 patches shown (2.0 M triangles)
over 19 tiles; close to the ground at 2 to 5 km, 570 to 650 (7 to 8 M),
of which roughly a third are in view. Compared with one tile at Full
before: 13 million vertices, 26 M triangles, 2.5 s on the main thread.
Same-depth patches share edges exactly; the gap between depths on the
IoW coast at x2 was up to 0.29 km, which the skirt depth covers.

To check first when built, most likely problems first:

1. Compile errors in the new units (written without a compiler).
2. The settled line's "vertices copied straight" or "through FMX's
   setters"; if a patch looks scrambled, the straight copy found a wrong
   offset: make `FillVertices` always use the setters.
3. Patches missing at the edges of the view while turning: Gorilla3D's
   frustum culling using wrong bounds; set each mesh's
   `FrustumCullingCheck` off (the tree could then hide patches out of
   view itself).
4. One shared material: if the surface goes black or a patch shows
   another's colours, go back to one material per mesh.
5. Leaks with `REPORT_LEAKS`: `TMeshDef`s would mean `IsDefOwner` is not
   what it seems.
6. The settled line's times: how long a patch takes on a worker, and to
   turn into a mesh; memory with all patches made.

### Memory and graphics processors (27 October 2026, after `d25e46b`)

Asked for by the owner as metrics for showing several tiles in 3D, and
put in `common/` as it has many uses: `common/GDEMSystemInfo.pas` (no
FMX; in GDEMFetch's `.dpr` and `.dproj`). **Works on Windows** ("That
worked well"); the owner's start-up lines, laptop with RTX 5090 Mobile
and Core Ultra 9 275HX, GPU drawing, High performance:

```
Memory: 63.4 GB, 43.7 GB available
This program: 251 MB in memory (peak 251 MB), 10 MB allocated
GPU 1: NVIDIA GeForce RTX 5090 Laptop GPU, 23.6 GB own memory, 47.4 GB shared; this program may use 22.8 GB, this program uses 58 MB
GPU 2: Intel(R) Graphics, 128 MB own memory, 47.4 GB shared; this program may use 46.7 GB, this program uses 0 MB
```

Both adapters found, the software renderer left out, DXGI 1.4 budgets
read. FastMM5's 10 MB allocated against 251 MB in RAM: most of the
working set is code, the Skia and Vulkan drivers and the decoded map
tiles held by Skia outside the Delphi heap. Not yet reported: the 3D
memory line (since the level-of-detail view, `3D: memory with ...`, a
second after the `3D: settled` line), and macOS and Linux.

The owner's plan: later, use these figures to choose the CPU or GPU
drawing default (and perhaps the View layers and 3D detail) on a first
run, instead of the fixed defaults.

- `ReadMemoryInfo` (`TMemoryInfo`: Total, Available):
  `GlobalMemoryStatusEx`; macOS `sysctl hw.memsize` and
  `host_statistics64` (free + inactive + speculative pages times
  `hw.pagesize`); Linux `/proc/meminfo` MemTotal, MemAvailable.
- `ReadProgramMemory` (`TProgramMemoryInfo`: Resident, PeakResident,
  Allocated): `K32GetProcessMemoryInfo` working set and peak; macOS
  `task_info` `MACH_TASK_BASIC_INFO` (20) resident size and max; Linux
  `/proc/self/status` VmRSS, VmHWM. Allocated comes from the
  `ProgramHeapReader` variable, which GDEMFetch's `.dpr` sets on Windows
  to `FastMM_GetUsageSummary.AllocatedBytes` (the owner suggested
  FastMM5; it knows only the program's heap, not the system's memory, and
  is Windows only, so the unit cannot use it directly). The summary walks
  the heap, so it is for occasional logging, not every frame.
- `ReadGpuInfo` (`TGpuInfo`: Name, VendorId, DedicatedMemory,
  SharedMemory, Budget, Used, UsedByThisProgram, UnifiedMemory): Windows
  DXGI declared in the unit (`CreateDXGIFactory1`, `EnumAdapters1`,
  `GetDesc1`, software adapter skipped; `IDXGIAdapter3`
  `QueryVideoMemoryInfo` node 0, local group, for Budget and
  CurrentUsage; vtables declared in Microsoft's order up to the last
  method called); macOS Metal `MTLCopyAllDevices` with typed
  `objc_msgSend` (`name`, `hasUnifiedMemory`,
  `recommendedMaxWorkingSetSize`, `currentAllocatedSize`; vendor guessed
  from the name); Linux `/sys/class/drm/cardN/device` vendor and device,
  AMD `mem_info_vram_total`/`_used`/`mem_info_gtt_total`, NVIDIA through
  `nvidia-smi` via `popen` (only if an NVIDIA card is there), Intel 0 own
  memory.
- `DescribeSystem` lines are logged by `TfrmMain.LogSystem` after
  `LogDisplays` in `RunStartup`; `DescribeMemoryUse` is logged
  `MEMORY_MEASURE_DELAY` (1 s) after each 3D build
  (`TThread.ForceQueue` with a delay), as `3D: memory after showing
  <tile>: ...`, so the pieces have been drawn and sent to the GPU. Since
  the level-of-detail view: `3D: memory with <tile> on show: ...`, 1 s
  after the `3D: settled` line (`TfrmMain.TerrainSettled`).
- To check: the start-up lines on macOS (Apple silicon and Intel) and
  Linux; the 3D line at each detail, which gives the memory cost per
  tile for planning several tiles.

### The map jumping while dragging (fixed 27 October 2026)

The owner saw the map jump a long way while dragging. Cause, found by
the owner: dragging off the window onto a display with a different scale
factor. The owner's displays (from the start-up log): 1920 x 1200 at
-1920, 0, scale 1.00; 3440 x 1440 at -5360, 7, scale 1.00; primary 2560
x 1440 at 0, 0, scale 1.50.

- First try, wrong: taking the position from `GetCursorPos` and the
  window's scale instead of FMX's. The owner's log showed both agreeing
  within 2 or 3 pixels and the jump remaining: Windows' own position
  jumps at the border too. Removed.
- The fix, the owner's suggestion: `TWorldMapView.ClipPointer` (Windows
  only) holds the cursor inside the map with `ClipCursor` (the map's
  `AbsoluteRect` times the window's `Scale`, through `ClientToScreen`)
  from the start of a select or pan drag; `ReleasePointer` lets go in
  `MouseUp`, the lost-release path of `MouseMove`, and `Destroy`. The
  `user32` calls are declared in the unit, because `Winapi.Windows`'
  `TBitmap` record would hide FMX's. `EdgeScrollStep` reaches full speed
  at the edge itself. Ctrl + click is not clipped. The owner finds it
  "not as good" as dragging freely, but good enough.
- Also fixed on the way: a wheel zoom during a pan now moves the pan's
  starting origin (`FDragOrigin := FOrigin - (FMousePos - FDragStart)`;
  `FDragStart` is kept for the right-click test), and on Windows a drag
  whose button release was lost (no button in a move's `Shift`) is ended.
- `TfrmMain.LogDisplays` logs each display's size, position and scale at
  start-up.
- Offered and not taken up: let the pointer leave the window and convert
  its position on another display with that display's scale and origin.
  The owner says Sprite3D's `DisplayData` handles Windows scales properly
  where the plain Windows API does not; the GitHub copy read on 27
  October showed no scale on Windows, so ask for the owner's current copy
  first.

## Starting a new conversation

1. Fetch the repository (<https://github.com/peardox/GDEM>, branch
   `main`) and its `delphi-neon` and `FastMM5` submodules.
2. Read `README.md`, then this file.
3. The owner's working copy is often ahead of GitHub. If the owner
   attaches or pastes files, build on those, not on GitHub. When the
   owner says a push is done, fetch it, compare every file delivered
   since the last push with GitHub's, and reset the working copy to
   `origin/main` (removing untracked copies of files GitHub now has).
4. Answer the stop hook's "commit and push" briefly: changes are left
   uncommitted on purpose; the owner applies the zips and pushes. There
   is no push access, and none should be asked for.
5. Before delivering code, run `python3 tools/pasdoc_check.py` (it
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

The 3D tab shows the ground round a tile with Gorilla3D: first one tile
as a single mesh (working on Windows, `d25e46b`), now patches with level
of detail over a window of tiles (delivered, unbuilt; see "Level of
detail").

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

Everything delivered later is described in the sections below and is on
GitHub (see the top of this file).

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
3. **GeoTIFF reader**: done and verified on Windows (see "Gorilla3D,
   first step" below). Worth running `GeoTiffCheck` on macOS and Linux.
4. **High-resolution map**: tile set made and drawn (see the TileMaker
   and high-resolution map sections below); built and working. Search,
   towns and cities, and markers followed (see below). Natural Earth's 1:10m borders and coastlines would suit
   it; add them as more layers in `tools/build_vectors.py`.
5. **3D tab**: one tile as a surface, working on Windows (see "The 3D
   tab" and later sections below). To check: macOS and Linux; FastMM5's
   leak report after switching tiles (a `TMeshDef` leak would mean the
   singleton mesh does not own its definition); the new controls in use.
   Now with level of detail over a window of tiles, made on worker
   threads (see "Level of detail" above); the `3D: settled` and `3D:
   memory with` lines measure it.
   Ideas raised: the high-resolution map laid over the surface; a camera
   that flies over the ground; fog; a checked list of the peaks Natural
   Earth leaves out (Lhotse, Makalu, Cho Oyu, Annapurna...).
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

### High-resolution map in GDEMFetch (27 October 2026)

GDEMFetch now draws the tile set (README, "The high-resolution map").
Not yet built.

- `common/GDEMTileCache` (new, no FMX): `TTileCache` opens a folder with
  `TTileSet.Load`, decodes tiles with `TSkImage.MakeFromEncodedFile` then
  `MakeRasterImage` (so drawing never decodes), keeps up to 400 unpinned
  (least recently used dropped; a scan of the dictionary is enough at
  this size), and remembers failed tiles so they are not retried.
  `Find` only looks in memory, `Load` reads, `Tried` says whether `Load`
  would read, `PreloadLevel` pins a level.
- `lib/GDEMMapTiles` (new): `FindMapTiles(setting)`. The setting alone if
  set; otherwise `tiles` beside the program, the macOS bundle's
  `Resources/tiles`, then `maps/tiles` beside the program and up to 6
  folders above (finds the repository's from `GDEMFetch/Win64/Debug`).
  PAServer runs Mac and Linux builds from its own folder, so there the
  owner must choose the folder in Settings or copy it beside the program.
- `TGDEMSettings.MapTiles` (JSON `mapTiles`, default empty). Settings has
  a "High-resolution map tiles" row at the bottom of the data layout,
  with Browse and a line saying which tile set will be used (form 676
  high; `layData` 236).
- `TfrmMain.LoadMapTiles` (after settings load in `FormCreate`, and again
  when Settings changes the folder) pins the smallest level and logs
  `Map: tile set "...", W x H in N levels of S-pixel tiles, from ...`,
  or a no-tile-set line. View > High-Resolution Map
  (`mnuShowMapTiles`, disabled with no tile set) sets
  `TWorldMapView.ShowMapTiles`.
- `TWorldMapView.PaintMapTiles` (Skia only), after the base map copies
  and before the tints: level from `LevelFor(ScreenPixelsPerDegree *
  Canvas.Scale)` (device pixels, so 150% and Retina get the finer level);
  rows and unwrapped columns of the view, each drawn into the rectangle
  from `GeoToScreen` of its corners; `TSkSamplingOptions.High` (Mitchell)
  when enlarging, linear with mipmaps when reducing. At most
  `MAX_TILE_LOADS_PER_FRAME` (6) reads a frame; a tile not yet read shows
  the matching part of the nearest coarser tile in memory
  (`TSkSrcRectConstraint.Close`, so the part does not sample its
  neighbours), and `FTileTimer` (15 ms) repaints to read more. The
  existing `MAX_PIXELS_PER_DEGREE` of 400 already allows over 13x past
  level 0's 30 pixels a degree, which the owner wanted.
- Simulated in Python on the real `maps/tiles`: levels chosen as
  expected (whole world on level 3, level 0 from 30 device pixels a
  degree), every tile in view exists, ancestors' rows and columns are in
  range, and the date line wraps.

To watch for: a faint step at tile edges when enlarged far past 1:1
(each tile is filtered on its own, so the cubic filter cannot see across
the edge); if it shows, draw each tile 1 pixel larger with a source
inset, or add a 1-pixel overlap in TileMaker. `OnPaintStats` can time
panning with tiles.

The owner built it (after two fixes: `GDEMTileSet` missing from
`GDEMWorldMap`'s uses, and `Exit([...])` read as a set, E2001) and found
it "nice + responsive".

### Search, towns and cities, markers (27 October 2026)

Asked for by the owner: a search box that zooms to a country (whole, with
a margin, as far as zoom allows; Jersey cannot fill the screen) or pans to
a place at the current zoom, fuzzy but fast, with a drop-down; and named
markers (Home, Work) that the search finds. Not yet built.

- `tools/build_vectors.py`: format version 2 adds a places section after
  the layers, from `ne_10m_populated_places_simple.geojson` (7,342 places;
  name, ASCII search name when the name is not ASCII, region, other names
  from `namealt`/`namepar` joined by `|` (634 places), country as an index
  into `countries50` by `ADM0_A3` then `ADMIN` name (3 unlinked:
  Gibraltar, Tokelau, Svalbard), lon/lat, `min_zoom` x 10, capital flag,
  `pop_max`), sorted by min zoom then population. `clean` drops `Cf`
  marks and runs of spaces ("St.  Paul"). The rebuilt
  `maps/world_vectors.bin` is 1.1 MB; the five layers are unchanged (an
  identical rebuild of the old file was confirmed first, from the same
  Natural Earth commit `ca96624`).
- `GDEMVectors`: `TGeoPlace`, `TWorldVectors.Places`, `PlaceText`
  (`London, Ontario, Canada`; a region equal to the name is left out),
  reads versions 1 and 2. `TGeoLayer.FeatureExtent` /
  `TWorldVectors.CountryExtent`: start from the largest part by area
  (shoelace times cos latitude); large parts (25% of the main's area or
  more) join within 4 x reach of the main or another large part; small
  parts join within reach of those, but never of other small parts (so no
  chaining along the Aleutians); reach = max(0.25 x main's larger side,
  3 degrees); parts are shifted by whole turns towards the main part, so
  Russia and Fiji are one piece (east > 180). Tuned in Python on all 242
  countries: France without Guiana, US with Alaska only, Norway with
  Svalbard but not Jan Mayen, Australia without Macquarie, Malaysia and
  Indonesia whole.
- `lib/GDEMSearch` (new): `TPlaceSearch.Fold` (lower-case ASCII words;
  Latin-1 and Latin Extended-A accents through the `FOLD_LATIN` table,
  generated from Unicode decompositions; apostrophes join letters; other
  letters kept), match classes exact, prefix, word prefix, inside (2+
  letters), fuzzy (optimal string alignment distance against the start of
  each word, with an early exit; mistakes 0 below 4 letters, 1 below 7, 2
  below 11, then 3). Ranked by class, mistakes, kind (marker, country,
  place), shorter country name, place importance; one hit per place.
  A Python port on the real data: `lodnon`, `edinbrugh`, `bejing`,
  `kuala lumpar`, `jersy`, `new yrok`, `antioch`, `koln`, `st johns`,
  `ndjamena`, `sao paulo` all find the right place first; Python took 35
  to 150 ms a query, so Delphi should be a few ms.
- `lib/GDEMMarkers` (new): `TMarkerList`, `markers.json` (Neon records,
  format 1, atomic write) in the settings folder; `CleanName`.
- `GDEMWorldMap`: `ZoomToArea` (AREA_FILL 0.85, clamped to
  Min/MaxScale), `CentreOn`, `ShowHighlight`/`ClearHighlight` (yellow
  rings), `ShowPlaces` (labels from Natural Earth's `min_zoom` against
  log2(px per degree x 360 / 256), most important first, greedy overlap
  test, at most 250, widths cached in `FLabelWidths`), `Markers`,
  `ShowMarkers`, `MarkersChanged`, `OnMarkerClick` (Ctrl or Cmd + left
  click that does not move; no selection is started). Labels and markers
  are drawn last. Estimated labels over Europe in a 1400 x 800 view: 16
  at 3 px/degree, 100 at 30, 143 at 60.
- `MainForm`: `edtSearch` at the right of `layTop` (`lblSelection`
  narrowed), `FSearchList` (a `TListBox` created in code over the map,
  `CanFocus` False so clicking it keeps the edit focused, hidden on a map
  mouse-down through `FMap.OnMouseDown`), keys in `edtSearchKeyDown`,
  `GoToHit`; View > Find... (Ctrl+F), Show Towns and Cities, Show Markers;
  new Markers menu (Add Marker at Map Centre..., Edit Markers...);
  `AddMarkerAt` asks with `TDialogService.InputQuery`.
- `ui/MarkersForm` (new): list with Go To, Rename..., Delete... (asks),
  Close; saves at each change; reports back through `TMarkersClosedProc`.
- `tools/pasdoc_check.py` now looks for `@abstract` in the whole unit
  comment (the map's had grown past the 4,000 characters it read).

Built by the owner after one fix (`System.Character` for `Char`'s
`IsLetter`/`ToLower` in `GDEMSearch`). The whole-world screenshot had no
London: it qualifies (min zoom 1.7, like Paris) but its right-hand label
hit Paris's, drawn first. Labels now try right, left, above, below
(`TLabelSide`, `LabelRect`); simulated at that zoom this adds London,
Toronto and Washington, D.C. The owner lives in Manchester (min zoom 5.0,
labelled from about 23 px/degree).

Then, at the owner's request, the View menu is remembered and the layers
start off, since they slow the program without a GPU: `lib/GDEMViewOptions`
(new, `TViewOptions`, Neon class with public properties like
`TGDEMSettings`, `view.json` in the settings folder, atomic write; missing
members keep the constructor's defaults). Off by default: borders,
coastlines, high-resolution map, towns and cities (also the map
control's own defaults and the `.fmx` ticks); on: both tile tints and
markers (my choice: the tints are what the map is for and cost one
bitmap stretch; markers are the user's own). Kept out of `settings.json`
because that file existing means "set up", so writing it on a first run
would skip the first-run Settings dialog. `TfrmMain.LoadViewOptions`
(in `FormCreate` after `LoadMapTiles`) ticks the menu and sets the map;
each View toggle handler calls `SaveViewOptions`.

Easter eggs (owner's idea; owner chose a JSON file): `maps/easter_eggs.json`,
the `EASTEREGGS` RCDATA resource (`RcItem` plus disabled `DeployFile`
entries like `world_vectors.bin`), read by `lib/GDEMEasterEggs`
(`ParseEasterEggs`, `LoadEasterEggs`; Neon records; bad entries skipped
and reported). `TSearchKind.skEgg` (between countries and places); names
and aliases searchable, text gets the country from `CountryAt`; never
drawn. `GoToHit` zooms to a `sizeKm` box (or pans), rings it, and puts
the note on the Debug tab and in `lblHover`; only problems are logged
at start-up, to keep them a surprise. Area 51: 37.2333, -115.8083
(Wikipedia), 12 km. Squid Game island: Seongapdo, 37.0969, 126.0783,
4 km: the owner's Google Maps link, Plus Code `8Q9833WH+Q8`, decoded by
hand (no `openlocationcode` package on pip here); 0.3 km from a
summary site's figure, while latlong.net's 37.2558, 126.3068 is 27 km off
(near Yeongheungdo). Python port of the search: `area 51`, `ufo`,
`groom lake`, `seongapdo`, `squid gaem` and the rest find them first.

All of this was built and pushed by the owner (it compiles, so
`TControl.OnMouseDown` is assignable from `MainForm`). Not yet reported
on: that Ctrl + click on macOS is not
turned into a right click by the system (Cmd + click is the documented
way there), the drop-down's position over the map on all three
platforms, and the label drawing cost on the CPU canvas (`OnPaintStats`).

### Built-in tile set (27 October 2026)

The owner found the high-resolution map missing on macOS and Linux (the
tile set was not deployed; PAServer runs the program from its own
folder, so the search for `maps/tiles` found nothing) and offered two
fixes: link it in as a resource, or deploy it to a sensible folder. It is
now a resource, per the README's rule. Built and tested on all three
platforms.

- `tools/pack_tiles.py` packs `maps/tiles` into `maps/tiles.zip`:
  `tileset.json` and the tiles under their folder names with `/`,
  stored (JPEGs do not compress), sorted, fixed 1980 dates, so it is
  reproducible (packed twice, same MD5); it refuses if a tile is
  missing. 1531 entries, 8.6 MB (the folder's 12 MB was disk blocks).
  Checked in Python: every name the reader asks for is present, no data
  descriptors, extras or compression, and every entry is identical to
  its file. Run it again after changing `maps/tiles`.
- `GDEMFetch.dproj`: `RcItem` `..\maps\tiles.zip`, RCDATA `MAPTILES`
  (linked through `{$R *.dres}`), and Debug and Release `DeployFile`
  entries disabled for every platform, copied from
  `world_vectors.bin`'s. BOM kept; the XML parses.
- `common/GDEMTileSet`: `TileEntryName` (as `TileFileName`, always
  `/`) and `FromJSON(text, where)`, which `Load` now uses.
- `common/GDEMTileCache`: `CreateFromPack(stream, origin, capacity)`
  takes ownership of the stream (kept in `FPackStream` first, so the
  destructor frees it if the constructor raises), opens it with
  `System.Zip`'s `TZipFile` (`zmRead`), indexes the names in a dictionary,
  and reads `tileset.json` from it. `ReadTile` gets a tile's bytes from
  the zip or the folder; `Decode` now uses `TSkImage.MakeFromEncoded`
  on those bytes for both. New `Origin` property (folder, or the
  description); `Folder` is empty for a pack.
- `lib/GDEMMapTiles`: `MAP_TILES_RESOURCE`, `BUILT_IN_MAP_TILES`
  ("built into the program"), `OpenBuiltInMapTiles` (a
  `TResourceStream` handed to `CreateFromPack`). The search for
  `maps/tiles` up to 6 folders above the program was removed
  (`REPOSITORY_MAPS_FOLDER`, `MAX_SEARCH_LEVELS` gone), so every platform
  draws the same built-in tile set unless a folder is chosen in Settings
  or a `tiles` folder sits beside the program (or in the macOS bundle's
  `Resources`).
- `TfrmMain.LoadMapTiles`: a folder found is tried first; a chosen
  folder with no tile set, or one that fails to open, logs a `WARNING:`
  and falls back to the built-in one; only if that fails too is the
  plain map drawn. The start-up line ends `built into the program` or
  `from <folder>`. Settings' line says `Using the tile set built into the
  program` when no folder is found.
- The executable grows by about 8.6 MB. `maps/tiles` stays in the
  repository as the source; the two copies cost about 17 MB of history.

Later the same evening, at the owner's request ("we don't have any
anymore as they're resources"), the folder option went too: the
Settings row (`lblMapTiles`, `edtMapTiles`, `btnBrowseMapTiles`,
`lblMapTilesFound`, their handlers; `layData` 236 to 160 high, the form
676 to 600, `layButtons` and `lblLocation` moved up 76), the
`TGDEMSettings.MapTiles` setting (an old `mapTiles` in `settings.json`
is ignored by Neon), and `FindMapTiles`, `MapTilesCandidates` and
`MAP_TILES_FOLDER_NAME`. `GDEMMapTiles` is now just
`OpenBuiltInMapTiles`, and `LoadMapTiles` opens only that, at start-up.
`TTileCache` keeps its folder constructor in `common/` (TileMaker could
use it); GDEMFetch no longer calls it. Tried on Linux by the owner before
this change: the built-in tile set works there.

To test on all three platforms: the start-up line says `built into the
program`; View > High-Resolution Map is enabled and draws the tiles
sharp when zoomed in; Settings has no tile set row and the
dialog's spacing looks right.

### View options suggested for faster drawing (27 October 2026)

Asked for by the owner: the View defaults suit the CPU or a low-power
GPU, so the first time the user changes Drawing or Graphics in Settings
and closes it with OK, turn on View options suited to the new choice and
say so in a modal dialog, advising turning some off if the map is slow
and listing the options from the most demanding to the least. The owner
fixed one case (GPU with High performance on Windows: everything) and
left the rest to Claude. Built and tested on all three platforms.

- `lib/GDEMViewOptions`: `TViewLayer` / `TViewLayers`,
  `ALL_VIEW_LAYERS`, `VIEW_LAYERS_BY_COST` (coastlines, borders, towns
  and cities, high-resolution map, available tint, downloaded tint,
  markers: estimated for the GPU from the line and fill timings; towns
  and the tile drawing were not measured, so `OnPaintStats` could check
  the order), `SuggestedViewLayers(on GPU, TGpuPreference)`: CPU none;
  Windows GPU + High performance all; Windows GPU + Let Windows decide or
  Power saving borders, coastlines, high-resolution map (not towns);
  macOS GPU all; Linux none. `TViewOptions.DrawingSuggestionMade`
  (`drawingSuggestionMade` in `view.json`, default false).
- `MainForm`: `ShowSettings` remembers Drawing and GpuPreference before
  the dialog and calls `SuggestViewForDrawing` after `LoadMapTiles`. It
  does nothing once the flag is set, if neither setting changed, or if
  the suggestion is empty (so choosing the CPU leaves it for a later
  change). Otherwise it sets the flag, ticks the suggested items that
  are enabled and unticked (never unticks), `ApplyViewMenu` (new, also
  used by `LoadViewOptions`), saves, and if anything was turned on, logs
  a `View: turned on to suit ...` line and shows the dialog: what was
  turned on, that the drawing change takes effect at the next start, and
  the numbered list by cost using the menu items' own captions
  (`ViewLayerItem`).
- On macOS the Drawing default is already the GPU, so the dialog only
  appears there if the user goes to the CPU and back. Offer to run it on
  the first run instead if the owner wants it on the Mac.

To test (Windows): delete `view.json`, open Settings, change Graphics to
High performance, OK: every View option on, the dialog, one log line;
open Settings again and change something: no dialog. With a fresh
`view.json`, Power saving: borders, coastlines and the high-resolution
map. Choosing CPU first: no dialog, and a later GPU choice still gets it.

### Gorilla3D, first step (27 October 2026)

The owner opened the 3D stage: Gorilla3D 1.5.3
(<https://gorilla3d.de/doc/v3/version/v1.5>, PasDoc reference at
<https://peardox.com/G3D/>), and FastMM5. Decided with the owner:

- **First view:** one downloaded tile, as a surface to orbit; stitching
  several comes later.
- **Surface:** our own mesh from the 16-bit elevations, thinned to a grid
  we choose, coloured by height; not `TGorillaTerrain`, which takes
  heights through a greyscale bitmap.
- **Order:** the GeoTIFF reader first, then the 3D tab on real data.
- **FastMM5:** now, as Sprite3D has it.

What the Gorilla3D docs say that matters here:

- `Gorilla.Context.Backend` must be the first unit in the `.dpr`, and
  `GorillaGraphicsBackend` (`gbDefault` = OpenGL / OpenGL ES, `gbOpenGL`,
  `gbVulkan`, Windows x64 only and experimental) must be set before
  `Application.Initialize`; set later it is silently ignored. That is
  where `ConfigureDrawing` sets Skia's GPU choice, so the two go together.
- It works with FMX Skia, raster or GPU canvas
  (`GlobalUseSkiaRasterWhenAvailable := False` gives `TVkCanvas` on
  Delphi 13.2+): it renders into its own image, which FMX paints. Keep
  `TGorillaViewport.UseFixedFrameRate` on, and do not call
  `Invalidate`/`Repaint` on the form every frame under Skia.
- Requirements: OpenGL 4.3+ on Windows and Linux (Mesa/GLX, X11, not
  Wayland; Delphi 12.3+ for Linux); Metal on macOS. The docs say macOS is
  Intel only, with Apple silicon under Rosetta and native ARM64
  "planned", but Sprite3D builds OSXARM64 with Gorilla3D, so the owner's
  copy evidently runs there.
- Custom meshes: `TMeshDef` from a `TMeshData` (`VertexBuffer.Vertices`,
  `.Normals`, `.Color0`; `IndexBuffer.Indices`; counter-clockwise
  triangles) via `ApplyFromMeshData`, then `IsStatic := True`, which
  freezes the vertices (rebuild to change). Or `TVertexCache` with
  `ApplyToMeshDef`. `TGorillaVertexColorMaterialSource`
  (`Gorilla.Material.VertexColor`) colours by vertex. Indices are UInt32
  on desktop, UInt16 on mobile. Then `TGorillaModel.LoadNewModelFromDef`.
- Camera: `TGorillaThirdPersonController` (orbit; needs a
  `TGorillaInputController` with `Viewport` set; `CameraZLimit` for zoom
  distance, `RotationDragMode` with `RButtonDown`), with
  `UsingDesignCamera := False`.

**FastMM5.** The owner added the submodule (`c1096a1`, pinned at
`ff65acc`). Both `.dpr`s now list `FastMM5` first on Windows, and have a
commented-out `{$DEFINE REPORT_LEAKS}`; defined, it sets
`ReportMemoryLeaksOnShutdown` and, on Windows, deletes the last
`<program>_MemoryManager_EventLog.txt` and logs every leak in full to a
new one, as Sprite3D does. `..\FastMM5` is on both `.dproj` search paths.
README: Requirements, "Memory leaks", the layout table, the rule on
submodules.

**The reader, `common/GDEMGeoTiff.pas`** (no FMX; in GDEMFetch's `.dpr`
and `.dproj` so it is compiled, not yet used): `TGeoTiff.Create(file)` or
`CreateFromStream`; `Images[]`/`ImageCount` (`TGeoTiffImage`: size,
bits, sample format, compression, predictor, tiles or strips, offsets,
byte counts, `IsOverview`); `ReadInto(index, pointer)`, `ReadInt16`,
`ReadUInt8`; `Georeference(index)` (`TGeoTiffGeoreference`: scale, tie
point, `PixelIsPoint`, EPSG, GDAL no-data; `West`, `North`, `CentreX`,
`CentreY`; overviews via `Resized`, the full image's edges divided into
the overview's pixels, as GDAL does). Classic TIFF either byte order,
tiles or strips, 8/16-bit integer, one sample per pixel; none, LZW,
Deflate (`System.ZLib.ZDecompress`), PackBits; predictor 2. LZW keeps each
code as a start and length in the output (every string has been decoded
already), widening one code early as libtiff does; KwKwK copied a byte at
a time. Not BigTIFF, not floating point.

The real ASTER files: `peardox/volatile`'s `img/iow_dem.tif` and
`iow_num.tif` (N50W002) are genuine tiles, little-endian, 3601 x 3601
in 256 tiles, LZW, no predictor, sizes as SHORT, offsets as LONG,
`SampleFormat` 2 (DEM) and 1 (NUM), then overviews of 1801, 1201, 901,
451, 401, 226, 57 and 45 in 128 tiles with `NewSubfileType` 1 and no geo
tags of their own. Scale 1/3600; tie point (0, 0) at -2.000138889,
51.000138889; pixel is area; EPSG 4326; no GDAL no-data tag. So the first
pixel's centre is exactly -2, 51 and the last -1, 50.

Tested with no Pascal compiler in the sandbox: a line-for-line Python
port (same names and arithmetic) decoded all 9 images of both files
identically to libtiff (Pillow), and 15 synthetic files covering strips
and tiles, both byte orders, predictor 2 at 8 and 16 bits under LZW and
Deflate, PackBits, no-data and pixel is point. LZW paths reached: 742
table resets and about 1.07 million 12-bit codes and 110,000 KwKwK
strings in the real DEM; 306 resets in random data. The Pascal itself is
unbuilt, so `tools/GeoTiffCheck/GeoTiffCheck.dpr` (console, FMX-free;
open the `.dpr`, the IDE makes the project) prints per image: size, min,
max, -9999 count, FNV-1a of the decoded samples as little-endian bytes,
and milliseconds. Its output for the two volatile files should be (from
libtiff's decoding):

```
iow_dem.tif
  0  3601 x 3601  min     0  max   250  voids      0  fnv1a 993D2602
  1  1801 x 1801  min     0  max   249  voids      0  fnv1a E83AC132
  2  1201 x 1201  min     0  max   247  voids      0  fnv1a 4DACF523
  3   901 x  901  min     0  max   247  voids      0  fnv1a B28E3B63
  4   451 x  451  min     0  max   244  voids      0  fnv1a 266EEB8B
  5   401 x  401  min     0  max   244  voids      0  fnv1a F7002C07
  6   226 x  226  min     0  max   227  voids      0  fnv1a B503B3EF
  7    57 x   57  min     0  max   188  voids      0  fnv1a 03530934
  8    45 x   45  min     0  max   172  voids      0  fnv1a 57493CC3
iow_num.tif
  0  3601 x 3601  min     2  max   250  voids      0  fnv1a D035738E
  1  1801 x 1801  min     2  max   234  voids      0  fnv1a AF3DC3DA
  2  1201 x 1201  min     2  max   231  voids      0  fnv1a 8BC06FBA
  3   901 x  901  min     2  max   148  voids      0  fnv1a 9F51B7D7
  4   451 x  451  min     3  max   126  voids      0  fnv1a 0BF910B5
  5   401 x  401  min     3  max   126  voids      0  fnv1a 961C2CAD
  6   226 x  226  min     3  max    81  voids      0  fnv1a D5DD8E6A
  7    57 x   57  min     4  max    51  voids      0  fnv1a D2D22F6A
  8    45 x   45  min     6  max    51  voids      0  fnv1a AFD9665B
```

**Verified 27 October 2026:** the owner built GeoTiffCheck on Windows and
ran it on both files: all 18 checksums, minimums, maximums, void counts
and the georeference line matched libtiff's exactly. Times (Windows):
full DEM 45 ms, full NUM 22 ms, overviews 12 ms and less. macOS and
Linux not yet run.

Next: the 3D tab: Gorilla3D's backend unit and `GorillaGraphicsBackend` in
the `.dpr` beside `ConfigureDrawing`, a `TGorillaViewport` on `tab3D`, a
`lib` unit that turns a tile into a thinned grid of heights (voids
-9999 filled or dropped, overviews for coarse grids), and a `ui` unit
that builds the mesh and colours it.

### The 3D tab (27 October 2026)

The owner chose the tile: the single downloaded tile selected on the map.
Built and run by the owner on Windows the same evening, after one fix
(`Default(TTerrainGrid)` in `GDEMTerrainView` did not compile: the unit
uses `Gorilla.DefTypes`, which declares an enumeration value `Default`
that hides the intrinsic; now `EmptyTerrainGrid` in `GDEMTerrain`, and
the Gorilla3D units come before `System.Math`). The Isle of Wight tile
showed correctly at Medium, 2x, from the starting view: windings,
colours, shading and camera all right, so items 1 and 2 of the list
below did not arise. The toolbar's Detail caption came out after Reset
View: `AddToBar` set `Align` before `Position.X`; now the other way
round, starting at 8.

Then, at the owner's request, the main toolbar (`layTop`: Fetch
selection, Cancel, `lblSelection`, `edtSearch`) moved from the top of the
form into the Map tab, above `layMap` (`.fmx` only; the search list is
placed in form coordinates from `edtSearch`, so it follows). View > Find
and `GoToHit` (search and Markers > Edit Markers' Go To) switch to the
Map tab first. Cancel for local jobs (rescan, move, delete) is now only on
the Map tab; downloads and imports have Cancel in their progress dialog.

Owner's timing, Windows laptop (RTX 5090 Mobile, GPU drawing, High
performance): Very fine, `3D: N50W002: 1801 x 1801 samples ... 3,268,864
vertices and 6,480,000 triangles in 64 piece(s) ...; read in 23 ms, built
in 649 ms`. At the owner's request Full (3601) was then added to
`TERRAIN_DETAILS` (13 million vertices, 225 pieces; about 2.6 s expected
at that rate, on the main thread). Tried: N53W005 at Full, `13,068,225
vertices and 25,920,000 triangles in 225 piece(s) ...; read in 95 ms,
built in 2492 ms` (Very fine 647 ms).

Units:

- `lib/GDEMTerrain` (no FMX): `LoadTerrainGrid(dem, tile, maxSize)` reads
  the largest image of the `_dem.tif` no wider than `maxSize` (226, 451,
  901, 1801 = overviews 6, 4, 3, 1 of an ASTER tile), converts degrees to
  metres (111,320 m a degree; longitude times cos of the middle latitude),
  fills -9999 voids from the mean of known neighbours pass after pass (64
  at most, then 0). `TerrainChunk(grid, index, exaggeration)` makes one
  piece of at most `TERRAIN_CHUNK_CELLS` (240) cells a side, 58,081
  vertices, so 16-bit indices are enough whatever Gorilla3D's index format
  is; pieces share edge vertices. Kilometres, centred; X east, Z north,
  Y down (FMX's up is -Y, as Sprite3DCamera's notes say), so heights are
  -Y. Normals from central differences of the exaggerated heights,
  pointing -Y. Colours: `HeightColour` stops (blue water at 0 and below,
  greens, yellow, browns, grey 3,000 m, white 4,500 m) times a hillshade
  for a sun in the north-west 45 degrees up (35% ambient), baked in, so
  the relief shows whether or not the vertex-colour material is lit.
  Winding: clockwise seen from above with north up the screen
  (NW, NE, SE; NW, SE, SW). Gorilla3D's guide calls its front faces
  counter-clockwise, and its example quad, worked through with FMX's -Y up,
  is clockwise on screen; `TERRAIN_FLIP_WINDING` reverses it.
  `TERRAIN_DETAILS`, `TERRAIN_HEIGHTS` and defaults (451, 2x).
- `ui/GDEMTerrainView`: `TTerrainView` (a `TLayout`, `HitTest` on) holds
  a `TGorillaViewport` (`HitTest` off, so the layout gets the mouse, as
  Sprite3D's AspectLayout does; `UseFixedFrameRate`, 60 fps, no VSync,
  `UsingDesignCamera` off, dark background), a centre `TDummy`, a terrain
  `TDummy` holding the pieces, a `TGorillaCamera` (FOV 45) with
  `Target` the centre, and a point `TGorillaLight` on the camera (as in
  Sprite3D). Not Sprite3D's camera rig, which the owner pointed out is made
  for that app: the camera is placed from Distance, Azimuth (0 from the
  south) and Elevation (5 to 89) and FMX's `TCamera.Target` aims it.
  Left-drag turns, the wheel zooms (0.88 a notch, 0.5 km to 5 tile sizes),
  double-click resets (south, 35 degrees, 1.25 tile sizes back). Each
  piece follows the guide's "Direct TMeshData Manipulation" example:
  `TGorillaSingletonMesh.Create(nil)`, `Parent` the terrain dummy, fill
  `MeshData.VertexBuffer` (`Vertices`, `Normals`, `Color0`) and
  `IndexBuffer`, `TMeshDef.Create(nil)`, `Mesh.Def := Def`,
  `ApplyFromMeshData`, `IsStatic := True`, `MeshData.Clear`, then a
  `TGorillaVertexColorMaterialSource` owned and parented by the mesh.
  `ClearMesh` is `DeleteChildren` on the terrain dummy.
- `MainForm`: `Build3DTab` (from `FormCreate`, after `LoadViewOptions`)
  makes a toolbar on `tab3D` in code: Detail and Heights combo boxes, Reset
  View, and an information label. `tabMain.OnChange := TabMainChange`
  calls `ShowSelectedTerrain` when the 3D tab is chosen:
  `SelectedTileNames(FDownloaded)` must be one tile; the tile is read
  again only if it or the detail changed; the view is made on first use;
  a new tile resets the view, a new detail keeps it. Logs
  `3D: <tile>: W x H samples, ... image I of N, V vertices and T triangles
  in P piece(s), heights ...; read in X ms, built in Y ms`. Heights
  rebuilds the surface only (`Exaggeration`). Detail and Heights are kept
  in `view.json` (`TViewOptions.TerrainDetail`, `TerrainHeights`).
- README: Requirements (Gorilla3D 1.5.3, OpenGL 4.3, X11 on Linux), "The
  3D view", the unit tables, roadmap; and the stale `GDEMMapTiles` row
  (it still mentioned `FindMapTiles`) put right.

Checked without a compiler: a Python port of `GDEMTerrain` on
`iow_dem.tif` at 226 and 451: sizes 70.67 x 111.10 km at 451 (one degree
at 50.5 N), every vertex covered once, largest piece 58,081, 405,000
triangles as expected, none wound the wrong way, every normal up, no
mismatch where pieces meet; void filling on high ground stays within the
surrounding heights (mean error 33 m on a planted 12 x 16 hole).

Unconfirmed until built, from documentation only, so look here first if
the tab misbehaves:

1. **Nothing visible from above, but visible from below:** the winding is
   the wrong way for Gorilla3D; set `TERRAIN_FLIP_WINDING` to True.
2. **Black or white surface:** `Color0` may not be in the mesh's vertex
   format, or the vertex-colour material may need something else.
3. **Leaks reported for `TMeshDef`:** the singleton mesh may not own the
   definition assigned to `Def`; free it in `ClearMesh`.
4. **Surface cut off near or far:** the camera's clipping planes; the
   scene is in kilometres (a tile is about 111 by 70, the camera up to
   about 550 away).

### Mountains, Show in 3D, Click for 3D (27 October 2026)

Owner's timing at Full: `3D: N53W005: 3601 x 3601 samples ... 13,068,225
vertices and 25,920,000 triangles in 225 piece(s) ...; read in 95 ms,
built in 2492 ms` (Very fine 647 ms; as estimated, four times).

**Mountains** (owner: "Everest ain't in the locations, neither is K2").
Natural Earth's `ne_10m_geography_regions_elevation_points.geojson` (same
commit `ca96624`): 711 points, 644 named (633 mountains, 61 spot heights,
9 depressions, 5 plateaus, 2 passes, 1 cape; the 67 with no name in
`name`, `name_en` or `label` left out). One summit per range: Everest,
K2, Kanchenjunga, Dhaulagiri, Nanga Parbat are there, Lhotse, Makalu, Cho
Oyu, Annapurna are not; a hand-checked supplement could fill gaps.

- `tools/build_vectors.py` writes **version 3**: after the places, a peaks
  section (name, ASCII key, other names from `name_alt`, `name_en` and
  `label`, two countries, lon/lat, Int16 elevation, kind, min zoom x 10),
  sorted by min zoom then height. `nation1`/`nation2` hold ISO alpha-2
  codes for most points (CN, RU, US) and names for a few (France, Italy),
  so both are matched (`ADMIN`, `NAME`, `NAME_LONG`, `ISO_A2`,
  `ISO_A2_EH`, `WB_A2`); with neither, the country whose outline holds the
  point (even-odd ray test on the quantised rings). 33 on a border, 5 in
  no country (offshore: Krakatau, Sakurajima, Gibraltar...). A rebuild at
  version 2 first matched the repository's file byte for byte; version 3
  is that file plus the version number and the section (1,130,340 bytes),
  decoded back in Python to the last byte. Everest: 8,848 m, Nepal (by
  outline); Mont Blanc France / Italy; Denali aka Mt. McKinley; Death
  Valley -86 m, kind depression.
- `GDEMVectors`: `VECTORS_VERSION` 3 (reads 1 to 3), `TGeoPeakKind`,
  `TGeoPeak`, `ReadPeaks`, `Peaks`, `PeakText` (`Mount Everest, 8,848 m,
  Nepal`), `Describe` counts peaks.
- `GDEMSearch`: `skPeak` between `skEgg` and `skPlace` (a peak before a
  town of the same name); entries for the name (or ASCII key) and each
  other name. `Fold` keeps digits, so `k2` finds K2.
- `MainForm.GoToHit`: a peak zooms to `PEAK_VIEW_KM` (40 km) round it,
  rings it, selects its tile (`SelectTileAt` -> `FMap.SelectTiles`, named
  after the peak, so the label reads `Mount Everest: 1 tile(s), ...`) and
  puts `PeakText` in the status bar.

**Show in 3D** (owner: build it from the map and switch tabs when ready;
then "the left click is used for selection as well as triggering 3D -
confusing"). The 3D tab no longer follows the selection: `TabMainChange`
is gone, and `ShowSelectedTerrain` became `ShowTerrainTile(tile, force)`.
`btnShow3D` on the Map tab's toolbar (enabled when exactly one downloaded
tile is selected, in `UpdateButtons`) builds the selected tile with the
hourglass (`IFMXCursorService`), then switches to the 3D tab. The 3D tab
keeps its tile until Show in 3D sends another; Detail re-reads the tile on
show.

**Click for 3D** (owner: "possibly a switch control to choose what it
does?"): `swClick3D` (`TSwitch`, with `lblClick3D`) beside Show in 3D,
off by default, kept as `TViewOptions.ClickShows3D`. `MapMouseDown` sets
`FMapLeftClick` for a plain left press (not Shift, which pans, nor Ctrl
or Cmd, which marks); `MapSelectionChanged` clears it and, if it was set
and the switch is on and Show in 3D is enabled, does what the button does.
So finding a mountain (a selection by the program) never jumps to the 3D
tab. `lblSelection` moved right to make room (X 468, 344 wide).

**Panning the 3D view** (owner: "I can't seem to pan the 3D"; it had only
turn and zoom). `TTerrainView`: right-drag, middle-drag or Shift +
left-drag move the centre (`FPanX` east, `FPanZ` north, km), as the map
pans. The ground follows the pointer: a pixel is 2 tan(FOV/2) x distance /
height km across, and divided by sin(elevation) up the screen; across
moves against the camera's right (cos az, sin az), down moves along its
way ahead (-sin az, cos az). Limited to half a tile beyond the edges;
`ResetView` centres it again. `PlaceCamera` offsets both the centre and
the camera.

**Search box** (owner: clicking in it should clear it; a "Search" label
to its left; an arrow to its right, drawn as Sprite3D draws its buttons).
`.fmx`: `lblSearch` (X 760, 52 wide), `edtSearch` narrowed to 236,
`btnSearchGo` (X 1060, 32 x 26), all anchored right; `lblSelection`
narrowed to 284. `BuildSearchGoIcon` (from `FormCreate`) puts an
`FMX.Objects.TPath` with `SEARCH_GO_ICON` (Sprite3D's Play triangle,
`M8 5v14l11-7z`, `WrapMode` Fit, 18 x 18) on the button as its
`TagObject`; `btnSearchGoApplyStyleLookup` colours it with the button's
`ResultingTextSettings.FontColor`, as Sprite3D's
`TransportButtonApplyStyle` does. `FMX.Objects` is in the implementation
uses and its TPath always written in full (`System.IOUtils` has one too).
Enter and the button share `GoToSearchChoice`. Clearing: `edtSearchEnter`
empties the box whenever it gains the focus; `edtSearchClick` empties it
only while it shows the text `GoToHit` put there (`FSearchChosen`), so a
click while typing still just moves the cursor. Emptying goes through the
normal typing path, so the list closes and the ring goes.

Built by the owner (the build reported only hints, see below); not yet
reported on in use.

**Hints** from that build, fixed: H2443 four times in `GDEMTerrainView`
(FMX's `TVertexBuffer` and `TIndexBuffer` setters not expanded inline
without `System.RTLConsts` in the uses; now listed), and H2077 in
`TWorldMapView.PaintPlaces` (`LFree := False` before a loop that always
set it first). The overlap tests there became a nested `IsClear`, with
`LFound` set only when a side is found, so no value is unused and none
can be left unset (W1036, see Lessons learned).

### Instruments over the 3D view (28 October 2026)

Asked for by the owner while the level-of-detail view was still unbuilt
(after the first compile fixes): height above the ground (the
heightmap), a compass turning with the heading, both over the viewport;
then altitude, then frames a second. Not yet built.

- `ui/GDEMTerrainHud` (new; in the `.dpr` and `.dproj`):
  `TTerrainAltimeter` (above ground large, altitude, then the ground's
  height above sea level and `(heights xN)` when stretched),
  `TTerrainFrameRate`, `TTerrainCompass` (card turns, fixed orange mark at
  the top, N in orange, letters kept upright, heading as `045` plus the
  degree sign in the middle). Painted with FMX's canvas (not speed
  critical), fixed colours on a dark see-through panel, `HitTest` off.
  Each repaints only when its value changes by a step (0.05 degrees,
  0.5 m, 0.05 fps).
- `GDEMTerrain`: `TTerrainFrame.ToGeoHeight` (exact inverse of `ToLocal`,
  height included) and `Directions` (east and north at a place, as local
  unit vectors; private `FromGlobe` is `ToLocal`'s rotation). Checked in
  Python: round trip within 1e-12; directions match finite differences;
  heading 0 at azimuth 0, 270.5 at azimuth 90 at the frame's point (the
  camera 50 km off sits where north has turned), 2.6 degrees at azimuth 0
  with the centre 140 km east (the frame's Z is that far off true north
  there, which is why heading is not just 360 - azimuth).
- `GDEMTerrainLod`: `GroundHeight(lat, lon, metres)` (true metres, sea and
  missing tiles 0, as drawn), which `SurfaceY` now uses; behaviour of
  `SurfaceY` unchanged.
- `TTerrainView`: the three controls are made after the viewport (so drawn
  over it), placed by `PlaceInstruments` from an overridden `Resize`;
  `UpdateInstruments` at the end of `PlaceCamera` and after each
  `FLod.Update` in `TimerTick` (finer ground changes the height above
  it). Altitude = the camera's sphere height / exaggeration; above
  ground = altitude - ground, shown as 0 if below (the camera is kept
  30 m of scene above `SurfaceY`, which samples a slightly different
  place). Frame rate: `FViewport.FPS` every 250 ms in `TimerTick`; the
  Gorilla3D docs (v1.1 viewport page) say that with `UseFixedFrameRate`
  it is the current frames a second, otherwise an estimate; the type is
  not documented (`%n` in their example), so it is assigned to a Single.

To check when built: the controls show over the viewport (if Gorilla3D
draws its viewport above FMX's other controls, they would be hidden; then
put them on a layout over the view instead); the compass reads 0 from the
starting view and 90 looking east; the heights look right over the sea
(ground 0) and over a known peak; the frame rate is not stuck at the
fixed 60 when the view is slow.

### Flying (28 October 2026)

Asked for by the owner right after the instruments, still before the
level-of-detail view had been run: the frame rate to follow the display's
refresh rate (as Sprite3D does); Up/Down speed (0 = hover, never
negative), Left/Right heading, PgUp/PgDn height with a crash below the
ground, the camera looking down a little ahead, Q/A to tilt it, and a
start at the starting position + 10000 m, set in `settings.json`. Not
yet built. The orbit camera (azimuth, elevation, distance, pan) is gone.

- `lib/GDEMFlight` (new): `TFlight` keeps latitude, longitude, true
  altitude (m), true heading, speed (m/s), tilt (degrees down), crashed.
  `Step(controls held, seconds)` (seconds kept to 0.1): speed +- max(20,
  0.6 x speed) a second, 0 to 3000 m/s; turn 45/s; tilt 30/s, -30 to 89;
  height +- max(50, 0.5 x height above ground) a second; then moves along a
  great circle (`MoveOn`, the heading turned to the arrival bearing, at
  radius R + altitude); then below `GroundHeight` = crash (altitude to the
  ground, speed 0, nothing moves until `Start`). `Start` puts it
  `StartHeight` above sea level and marks the start pending: the first
  `Step` that knows the ground there lifts it to ground + `StartHeight`
  (a height key or the wheel first cancels that). `Climb(notches)` (the
  wheel: a tenth of the height above ground, at least 20 m), `Look`
  (drag), `Stop` (Space). Checked in Python: 66,666 steps of 15 ms at
  3000 m/s end 0.13 m from one 3000 km jump, same heading; north and east
  on the equator and across the date line right; holding PgDn from
  10,000 m crashes in 11.2 s, from 300 m in 4.2 s; Up reaches 500 km/h in
  4.1 s, the most in 9.2 s.
- `ui/GDEMDisplays` (new): `DisplayOfForm(form, read rate)`, a cut-down
  port of Sprite3D's `DisplayData` (`TPeardoxDisplays.IndexOfForm` /
  `RefreshRateFor`): Windows `MonitorFromWindow` device name, then
  `EnumDisplaySettings` current `dmDisplayFrequency` (0 and 1 = unknown);
  macOS `Screen.DisplayFromForm`, CoreGraphics rate (main for primary,
  others in `CGGetActiveDisplayList` order, as Sprite3D matches them);
  Linux 0. Naming is cheap; the rate is read only when the name changes.
- `GDEMSettings`: `FlightStartHeight` (`flightStartHeight`, default
  `DEFAULT_FLIGHT_START_METRES` 10000). Not in the Settings dialog; the
  owner asked for `settings.json` for now. Written to the file the next
  time Settings is closed with OK.
- `GDEMTerrainView` (rewritten round the flight; mesh code unchanged):
  `PlaceCamera` puts the camera at `Frame.ToLocal(lat, lon, altitude x
  exaggeration / 1000)`, and the target 1 km along heading and tilt using
  `Directions` (up = east x north). The flight is drawn stretched with the
  heights, so it is the same height above the drawn ground; the
  instruments show true heights. `NearPlane` follows the flight down: a
  quarter of the height above ground, 5 to 50 m (changed only when it
  moves by 10%); unconfirmed that Gorilla3D takes a new `NearPlane` while
  running. `TimerTick`: every 250 ms `CheckFrameRate` (reads `FPS`; if
  the window's display changed, `FixedFrameRate` := its rate, 60 if
  unknown or under 24, logged); then `FFlight.Step(FHeld, seconds since
  last tick)`; a crash shows `TTerrainBanner` and logs; rebase when the
  camera is past `TERRAIN_REBASE_KM`, at the tile under the flight.
  Keys: `KeyDown`/`KeyUp` keep `FHeld` (`KeyControl` maps `vkUp` ...
  `vkNext`, `vkQ`/`vkA`, and the characters Q and A for systems that send
  letters only as characters); R = `ResetView`, Space = `Stop`; `DoExit`
  clears `FHeld`, as the key's release would go elsewhere. `CanFocus`
  on; `MouseDown` takes the focus. Left-drag = look (right turns right,
  down tilts down), wheel = height, double-click = start again. Right
  and middle drag do nothing now.
- `GDEMTerrainHud`: `TTerrainSpeedPanel` (km/h or Hovering; Camera N
  degrees down/up), `TTerrainBanner` (crash, dark red, hidden until
  shown), `TTerrainFrameRate.Limit` (`frames a second, of 144`).
- `MainForm`: `StartHeight` from settings in `ShowTerrainTile` (logged in
  the `3D: showing` line); `FocusTerrainView` after Show in 3D, Start
  Again (was Reset View) and the three combo boxes, which take the
  keyboard when used; the help line lists the keys.
- README: the 3D section's table and instruments rewritten; units table.

To check when built, most likely first: the view gets the keys (click
it; if FMX's form or a toolbar control keeps them, the keys do nothing);
letters Q, A, R on each platform (both the key code and the character are
tried); the start lifts to ground + 10,000 m once the tile is read; the
compass and Left/Right agree (Right turns the card anticlockwise, the
heading number up); a crash on PgDn; the frame rate panel shows "of N"
matching each display, and the log line on dragging the window across;
patches still split ahead of the flight (the tree's window centres on the
target, 1 km ahead).

### Licence and credits (28 October 2026)

The owner asked for a licence file and a list of credits, first naming
MIT, then asking for the least restrictive non-commercial licence, then
for the licence allowing the best imagery, and settling on "the least
restrictive that [is compatible] with other licenses". That is MIT:
Neon (MIT), Skia (BSD 3-clause) and Skia4Delphi (MIT) allow anything;
the owner holds a Gorilla3D licence, and its commercial runtime may be
compiled into an MIT program (not into a GPL one); the EOX imagery's
non-commercial terms bind whoever uses the imagery, not the code.
PolyForm Noncommercial 1.0.0 was written in briefly and replaced.

- `LICENSE`: MIT, "Copyright (c) 2026 peardox" (the owner's name was not
  known; offer to put it in), plus a line pointing to `CREDITS.md`.
- `CREDITS.md`: a table (ASTER GDEM V3 with its citation and DOI
  10.5067/ASTER/ASTGTM.003, NASA Earthdata, Natural Earth, the two world
  map images, Sentinel-2 cloudless (planned), Neon, FastMM5, Gorilla3D,
  Skia and Skia4Delphi, RAD Studio and its styles, Sprite3D) and notes.
- **FastMM5** is GPL v3 or commercial. Under the GPL, GDEMFetch's Windows
  builds cannot be given out at all (the GPL cannot cover the Gorilla3D
  runtime in them). The owner will buy the commercial licence, "just not
  today"; then update `CREDITS.md` note 2 and the README's Licence
  section. Offered meanwhile: link FastMM5 only when `REPORT_LEAKS` is
  defined.
- **The high-resolution map's image**, `8081_earthmap10k`, is Planet Pixel
  Emporium's (James Hastings-Trew). Its terms (read 28 October 2026)
  allow it as a resource for rendering, a simulator or game included, but
  not redistributing it as is, nor including it in a distributed program
  without permission; `maps/tiles/` and the `MAPTILES` resource are it,
  resampled. Permission to be confirmed by the owner, or the image
  replaced (NASA Blue Marble is unrestricted). Where
  `maps/world_1080x540.jpg` came from is not recorded: ask.
- The RAD Studio styles in `styles/` are `Redist` files; shipping them in
  a program is allowed, keeping them in the public repository is less
  clear, and `buildstyles.cmd` fetches missing ones anyway.
- Imagery for the Realistic option, discussed and not yet built: the
  owner wants the best images; Sentinel-2 cloudless (EOX, 10 m,
  cloud-free) recent years are CC BY-NC-SA 4.0 (non-commercial, credit
  shown in the map); 2016 is CC BY 4.0; NASA GIBS Blue Marble (500 m) and
  MODIS/VIIRS (250 m, daily, cloudy) need only an acknowledgement; HLS
  (30 m) is per-pass with gaps and clouds; Esri, Google and Bing ruled
  out by their terms. Proposed and awaiting the owner: per-patch 256 x 256
  textures (about 9 m a pixel at the finest depth), a disk cache with a
  size limit (least recently used suggested over the owner's FIFO; 2 GB
  in the data folder suggested), background downloads as an agreed
  exception to the progress dialog rule, plain imagery without hillshade,
  the credit drawn in a corner. Whether EOX's public tile service allows
  caching by a desktop program was not found; check before building.
- README: Licence section, layout rows, and a Notes for Claude rule to
  add anything new to `CREDITS.md`.

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
- A `const` block added among the types needs `type` again after it;
  without it the next class is read as a constant and Delphi fails with
  dozens of errors starting with E2029 "Expression expected but 'CLASS'
  found" (`GDEMViewOptions`, 27 October 2026). `tools/pasdoc_check.py`
  now reports a type declared in a `const` or `var` section.
- Delphi requires every field of a class section before its first method
  or property (E2169). New private methods were once inserted among the
  fields; `tools/pasdoc_check.py` now reports that.
- Delphi's flow analysis is unreliable around `try`/`except`: removing a
  starting value it called unused (H2077) produced "might not have been
  initialized" (W1036). The fix in `DownloadFile` sets the value at the
  top of the loop and lets one path rely on it.
- `Exit([A])` for a dynamic array result does not compile (E2001
  "Ordinal type required"): the brackets are read as a set. Assign
  `Result := [A]` and then `Exit`.
- A `}` inside a `{ ... }` comment ends it, so JSON examples (or
  `{$IFDEF}`) cannot go in PasDoc comments; describe the layout in words.
- On macOS, `NSProcessInfo` `beginActivityWithOptions:reason:` with
  `NSActivityUserInitiated` prevents idle sleep and App Nap; the returned
  activity is retained until `endActivity:`.
- Delphi anonymous methods capture variables, not their values: tasks
  started in a loop from the same locals would all see the last values.
  `GDEMTerrainLod.MakeBuildTask` copies its parameters into its own locals
  and returns the method, so each task gets its own.
- Gorilla3D facts found for the 3D view (v1.5 docs): the viewport's
  `NearPlane` and `FarPlane` default to 0.1 and 10000 scene units (FMX's
  own are 1 and 1000); `FrustumCulling` is on by default; a static mesh's
  definition keeps its vertex data, so its bounds work after
  `MeshData.Clear`; desktop index buffers are 32-bit, mobile 16-bit.
  FMX's `TVertexBuffer` has `Buffer`, `VertexSize`, `VerticesPtr` and
  `NormalsPtr`, but no pointer for colours.
- The Python checks (ports of the reader, the terrain and the tree) live
  only in a session's scratch folder and are lost with it; rewrite them
  from the Pascal when needed. The real tiles for them are
  `peardox/volatile`'s `img/iow_dem.tif` and `iow_num.tif`; Pillow reads
  every overview with `Image.seek`.
- First build of the level-of-detail view (28 October 2026): in
  `GDEMTerrainView`, `TMaterialSource` was not declared by the units in
  its uses, so the field is now `TGorillaVertexColorMaterialSource`
  (`Gorilla.Material.VertexColor` moved to the interface uses); and
  `Move(...)` gave E2034 "Too many actual parameters", most likely because
  a unit used after `System` (probably `Gorilla.DefTypes`, as with
  `Default`) declares something called `Move`. Write `System.Move` in any
  unit that uses Gorilla3D.
- FMX canvas in Delphi 13 (first build of `GDEMTerrainHud`, 28 October
  2026): `TPolygon` is declared in `System.Math.Vectors`, not in
  `FMX.Graphics`; `TCanvas.StrokeThickness` is gone, use
  `Canvas.Stroke.Thickness`.
- `TTerrainView` could not have a property called `Flight` (E2004
  "Identifier redeclared", 28 October 2026): something already in scope
  has the name, not found without the compiler. The property was not
  needed and was removed; choose another name if one is wanted.
