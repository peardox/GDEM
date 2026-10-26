# GDEM: handover notes

Notes for picking this project up in a new conversation. Read
`README.md` first, the whole of it: it explains the project, and its
**Notes for Claude** section holds the working rules. This file adds what
the README does not: where the work has got to, what has been tested and
how it went, and lessons learned along the way.

Last updated: 26 October 2026.

## Starting a new conversation

1. Fetch the repository (<https://github.com/peardox/GDEM>, branch
   `main`) and its `delphi-neon` submodule.
2. Read `README.md`, then this file.
3. The owner's working copy is often ahead of GitHub. If the owner
   attaches or pastes files, build on those, not on GitHub.
4. Before delivering code, run `python3 tools/pasdoc_check.py GDEMFetch`
   and fix anything it reports.

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

Everything to date is on GitHub as of commit `52a9106` ("The world
overnight"), including the work of the last session:

- Download speed setting (Slow 1 to 4, Medium 2 to 8, Fast 4 to 16)
  replacing a number of downloads at once; `TDownloadThrottle` now starts
  low and climbs (slow start, then additive increase after a cut).
- Token expiry read from the bearer token (a JWT, `exp` claim) and shown
  in Settings, logged, warned about, and checked before fetching.
- Live selection counts while dragging (`OnSelectionChanging`).
- `GDEMReport` (`TDownloadReport`): per-file download detail goes to
  `<settings folder>/Reports/download-yyyymmdd-hhnnss.log`, not the Debug
  tab.
- Downloads stop only after 10 failures in a row, not 10 in total.
- `GDEMAwake` (`TKeepAwake`), used by `RunJob`.
- `CLAUDE.md` (this file) and `tools/pasdoc_check.py`.

Delivered after that commit, in `GDEM-fast-lookup.zip` and the zip that
updated these notes:

- Faster tile lookup: `LookUpTiles` lists the selected block with
  `TCMRGranuleSearch.BoxURL` (`bounding_box`) instead of 230 wildcard
  name searches for the whole world, and stops paging at a short page.
  Changed `GDEMCMR.pas`, `GDEMDownloader.pas`, `MainForm.pas` (progress
  text), `README.md` and this file.

- Borders, coastlines and country names (`GDEM-borders.zip`): new
  `GDEMVectors.pas`, `tools/build_vectors.py` and `maps/world_vectors.bin`;
  changed `GDEMWorldMap.pas` (drawing), `MainForm.pas` and `.fmx` (View
  menu items, status bar name, loading), `GDEMFetch.dpr` and `.dproj`
  (unit, `WORLDVECTORS` RcItem, disabled deploy entries), `README.md` and
  this file. It also carries the fast-lookup files, as both changed
  `MainForm.pas`.

- Right-click country selection (`GDEM-country-select.zip`, which also
  carries everything in `GDEM-borders.zip`): `TGeoLayer.AddFeatureTiles`
  and `TWorldVectors.CountryIndexAt`/`AddCountryTiles`/`CountryName` in
  `GDEMVectors.pas`; `TTileIndex.BoundingRect` in `GDEMTileIndex.pas`
  (takes the short way round, so Russia gives 19E to 169W, not the whole
  world); `SelectTiles`, `SelectionMask`, `SelectionName`, `OnRightClick`
  in `GDEMWorldMap.pas`; `MapRightClick`, `SelectedTileNames` and
  `SelectedTileCount` in `MainForm.pas`, which Fetch and Delete now use.
  Checked by porting the tile algorithm to Python on the real data:
  Germany 68 tiles, United Kingdom 70, France 116 (with overseas parts),
  Lesotho 8, Luxembourg 4, Vatican 1, Fiji 20, Russia 3473.

Anything delivered later still is in the conversation, not here: ask the
owner whether it has been applied before changing the same units.

### Next, as far as is known

1. **Whole-world download on the Mac overnight**, at Fast, started on
   26 October 2026 with the old, slow lookup (it was at 73 of 230 name
   batches after a while). Look at the Debug tab summary and the report
   file (`~/Library/Application Support/GDEM/Reports/`) afterwards:
   speed, cut-backs, failures, and whether App Nap or sleep interfered.
2. **First real run of the block lookup.** It was written without being
   able to reach CMR from the sandbox. The report should show
   "Asking NASA CMR for every tile from ... to ..." then "page N of M"
   lines, and the Debug tab "Looked up ... in ...: N have data" should
   take seconds, not minutes. If it falls back to "asking by name
   instead", the bounding box query needs looking at.
3. **First run of the borders.** Written without a compiler. Check they
   line up with the map, that panning and zooming stay smooth (the 1:50m
   coastline is 60,000 points; only lines on screen are drawn, and points
   under a pixel apart are skipped), and the country name in the status
   bar. Colours: borders pink `$FFFF80AB`, coastlines white at 55%.
   Also check right-click country selection, including a country across
   180 degrees (Fiji, Russia) and that right-drag still pans.
4. **GeoTIFF reader** in pure Pascal for the `_dem` and `_num` files
   (LZW, 256 x 256 tiles, Int16 and UInt8, 3601 x 3601, 8 overviews).
   <https://github.com/peardox/volatile> has older decoding logic to
   reuse, but uses a Windows-only libtiff binding, so take the logic only.
5. **High-resolution map** from `maps/8081_earthmap10k.jpg` (10800 x
   5400, gitignored, so not in a fresh clone), cut into tiles loaded as
   the user zooms. Natural Earth's 1:10m borders and coastlines would suit
   it; add them as more layers in `tools/build_vectors.py`.
6. **3D tab**: content to come once tiles can be read.
7. Smaller ideas offered but not taken up: parallel workers and the
   progress dialog for moving the data folder; a macOS `.icns` and a
   Linux `.desktop` file; a menu item to open the Reports folder.

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
- On macOS, `NSProcessInfo` `beginActivityWithOptions:reason:` with
  `NSActivityUserInitiated` prevents idle sleep and App Nap; the returned
  activity is retained until `endActivity:`.
