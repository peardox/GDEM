{ @abstract(Main window of GDEMFetch.)

  Shows a world map (@link(TWorldMapView)) on which the user selects ASTER
  GDEM V3 tiles by dragging a box, then downloads them with
  @link(TGDEMDownloader) into the data folder (@link(TGDEMStore)). A single
  tile can also be typed in by name.

  The window has three tabs: @bold(Map) holds the world map, @bold(3D) is
  reserved for a 3D view to come, and @bold(Debug) holds the log. The
  toolbar, progress bar and status bar stay visible on every tab.

  @bold(Tile bitmaps.) Two @link(TTileIndex) bitmaps are shown on the map:
  @unorderedList(
    @item(tiles that have data, built from NASA CMR and kept in the
      settings folder (@bold(File > Refresh Tile Index) rebuilds it);)
    @item(tiles already downloaded, kept in the data folder itself
      (@bold(Data > Rescan Data Folder) rebuilds it from the files).)
  )
  @bold(Fetch selection) downloads only tiles that have data and are not
  yet downloaded.

  @bold(Borders.) Country borders and coastlines from Natural Earth
  (@link(TWorldVectors)) are drawn over the map, and the status bar names
  the country under the pointer. @bold(View) has items to hide them. A
  right click on a country selects every tile it touches, for fetching or
  deleting like any other selection.

  @bold(Finding places.) The search box at the right of the toolbar
  (@bold(View > Find...)) finds countries, towns and cities and the user's
  markers as the user types, forgiving spelling mistakes (see
  @link(TPlaceSearch)), in a list under the box. Choosing a country zooms
  to show all of it; choosing a place or marker moves the map to it at the
  same zoom and rings it. Up and Down move through the list, Enter goes
  to the chosen one, Escape closes the list.

  @bold(Markers.) Ctrl + click on the map (Cmd + click on a Mac), or
  @bold(Markers > Add Marker at Map Centre...), adds a named marker, such
  as Home; @bold(Markers > Edit Markers...) renames and deletes them. They
  are kept in the settings folder (@link(TMarkerList)) and can be searched
  for.

  @bold(Data folder.) Chosen in @bold(File > Settings) and may be on a
  removable drive. When the user picks a new folder and the old one holds
  data, they are asked whether to move it. Once a folder has been used, a
  missing folder means its drive is not connected, and the user is asked to
  connect it. Free space is shown in the status bar, checked every minute
  and before every tile; downloads stop rather than go below the reserve
  set in Settings.

  @bold(Jobs.) Work on the data folder (downloading, rescanning, moving,
  deleting) runs one job at a time on a background task, through
  @link(TfrmMain.RunJob); the Cancel button stops it. Building the tile
  index from CMR runs separately. All updates to controls are queued back
  to the main thread.

  @bold(Themes.) The look chosen in Settings (see @link(GDEMThemes)) is
  applied at start-up and as soon as Settings closes with OK.

  @bold(Progress.) Whenever external data is fetched (downloading tiles,
  or building the tile index from NASA CMR), and while existing tiles are
  imported, a modal @link(TfrmProgress) dialog shows what is happening,
  with two progress bars and a Cancel button. For an import the second bar
  shows the amount copied, with the speed and an estimate of the time left.
  See @link(TfrmMain.BeginProgress).

  @bold(Start-up.) Everything that may need the user is done in one
  sequence once the window is showing (@link(TfrmMain.RunStartup)): the
  settings dialog if there are no settings, then the tile index download
  if there is no index, then the request to connect the data folder's
  drive. Running them in turn stops one dialog opening on top of another.

  Serious problems are written to the log and also shown in a modal error
  dialog (see @link(TfrmMain.ReportError)). Cancelling is not treated as an
  error.

  The world map image is linked into the program as the @code(WORLDMAP)
  RCDATA resource, so nothing has to be deployed alongside the program on
  any platform. }
unit MainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  System.Threading, FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Edit, FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Layouts,
  FMX.Controls.Presentation, FMX.Menus, FMX.TabControl, FMX.ListBox,
  GDEMCancel, GDEMSettings, GDEMDownloader, GDEMWorldMap, GDEMTileIndex,
  GDEMStore, GDEMThemes, GDEMReport, GDEMVectors, GDEMTileCache, GDEMMarkers,
  GDEMSearch, GDEMViewOptions, GDEMEasterEggs, GDEMTerrainLod, GDEMTerrainView, GDEMImagery,
  GDEMBookmarks, GDEMFlightPath, System.Generics.Collections, ProgressForm;

const
  { The window's title, before the mode. }
  APP_TITLE = 'ASTER GDEM V3 Fetch';

  { The mode switch's caption when on. }
  LAUNCH_MODE_CAPTION = 'Launch Mode';

  { The mode switch's caption when off. }
  FETCH_MODE_CAPTION = 'Tile Fetch Mode';

  { Name of the RCDATA resource holding the world map image. }
  WORLD_MAP_RESOURCE = 'WORLDMAP';

  { How often the data folder and its free space are checked, in
    milliseconds. }
  STORAGE_CHECK_INTERVAL = 60000;

  { Height of a row in the list of search matches, in pixels. }
  SEARCH_ITEM_HEIGHT = 22;

  { Width of the list of search matches, in pixels: wider than the search
    box, as a place's full name can be long. }
  SEARCH_LIST_WIDTH = 460;

  { Kilometres in a degree of latitude, near enough, for sizing the view
    round an easter egg. }
  KM_PER_DEGREE = 111.32;

  { The search's go button's icon, a right-pointing triangle: an SVG path
    in a 24 x 24 box, the same as Sprite3D's Play button. }
  SEARCH_GO_ICON = 'M8 5v14l11-7z';

  { Kilometres shown round a mountain found by the search. }
  PEAK_VIEW_KM = 40;

  { The least area, kilometres across, the map shows round a flight path
    in flight when switching to the Map tab. }
  FLIGHT_PATH_VIEW_KM = 30;

  { Milliseconds after the 3D view has made all its patches before its
    memory use is logged, so the frames drawn meanwhile have sent them to
    the graphics processor. }
  MEMORY_MEASURE_DELAY = 1000;

type
  { The work done by a job, run on a background thread.
    @param(AToken Check this at safe points; cancelling the job sets it.) }
  TJobWork = reference to procedure(AToken: TCancelToken);

  { Called on the main thread when a job has finished.
    @param(ASucceeded @true if the work ran to the end; @false if it failed
      or was cancelled.) }
  TJobDone = reference to procedure(ASucceeded: Boolean);

  { @abstract(The application's main form.) }
  TfrmMain = class(TForm)
    { Application menu. On macOS this becomes the system menu bar. }
    mnuMain: TMainMenu;
    { The File menu. }
    mnuFile: TMenuItem;
    { File > Settings: opens the settings dialog. }
    mnuSettings: TMenuItem;
    { File > Refresh Tile Index: rebuilds the tile index from CMR. }
    mnuRefreshIndex: TMenuItem;
    { Separator above the flight path items. }
    mnuFlightSep: TMenuItem;
    { File > Save Flight Path: saves the current flight's path. }
    mnuSaveFlightPath: TMenuItem;
    { File > Save All Flight Paths: saves every flight's path since the
      program started. }
    mnuSaveAllFlightPaths: TMenuItem;
    { Separator above @link(mnuExit). Hidden on macOS. }
    mnuFileSep: TMenuItem;
    { File > Exit. Hidden on macOS, where Quit is in the application menu. }
    mnuExit: TMenuItem;
    { The Data menu. }
    mnuData: TMenuItem;
    { Data > Import Existing Tiles: copies tiles from another folder into
      the data folder. }
    mnuImport: TMenuItem;
    { Data > Move Existing Files: like @link(mnuImport), but deletes each
      original once it is safely in the data folder. }
    mnuMoveImport: TMenuItem;
    { Data > Rescan Data Folder: rebuilds the downloaded-tiles bitmap from
      the files and tidies the folder. }
    mnuRescan: TMenuItem;
    { Data > Delete Selected Downloads: removes downloaded tiles in the
      map selection. }
    mnuDeleteSelected: TMenuItem;
    { The View menu. }
    mnuView: TMenuItem;
    { View > Zoom In. }
    mnuZoomIn: TMenuItem;
    { View > Zoom Out. }
    mnuZoomOut: TMenuItem;
    { View > Whole World. }
    mnuZoomFit: TMenuItem;
    { View > Zoom to Selection. }
    mnuZoomSelection: TMenuItem;
    { Separator above the tint options. }
    mnuViewSep: TMenuItem;
    { View > Show Available Tiles: toggles the tint on tiles with data. }
    mnuShowTiles: TMenuItem;
    { View > Show Downloaded Tiles: toggles the tint on downloaded tiles. }
    mnuShowDownloaded: TMenuItem;
    { View > Show Country Borders. }
    mnuShowBorders: TMenuItem;
    { View > Show Coastlines. }
    mnuShowCoastlines: TMenuItem;
    { View > High-Resolution Map: draws the tile set, if one was found,
      instead of the plain map image. }
    mnuShowMapTiles: TMenuItem;
    { Separator above the log commands. }
    mnuLogSep: TMenuItem;
    { View > Copy Log: puts the whole log on the clipboard. }
    mnuCopyLog: TMenuItem;
    { View > Clear Log: empties the log. }
    mnuClearLog: TMenuItem;
    { Toolbar above the tabs. }
    layTop: TLayout;
    { Fetches every tile in the map selection that has data and is not
      downloaded yet. }
    btnFetchSelection: TButton;
    { Stops the running job. Enabled only while one is running. }
    btnCancel: TButton;
    { Shows the selected tile in 3D, then switches to the 3D tab. Enabled
      while exactly one downloaded tile is selected. }
    btnShow3D: TButton;
    { Names the mode @link(swClick3D) is in: Launch Mode or Tile Fetch
      Mode. }
    lblClick3D: TLabel;
    { Launch Mode (on, as every start): a left click on the map that
      selects a single tile with data prepares for flight there and shows
      it in 3D, as @link(btnShow3D) does, but only with a bearer token
      (without one, File > Settings opens). Tile Fetch Mode (off): a click
      only selects, for Fetch selection. The window's title says which. }
    swClick3D: TSwitch;
    { Describes the map selection. }
    lblSelection: TLabel;
    { Search box for countries, places and markers; matches show in
      @link(FSearchList) under it. }
    edtSearch: TEdit;
    { "Search", before @link(edtSearch). }
    lblSearch: TLabel;
    { Goes to the best match, or the one picked in the list, as Enter
      does; shows a right-pointing triangle drawn as a vector path. }
    btnSearchGo: TButton;
    { View > Find...: puts the cursor in @link(edtSearch). }
    mnuFind: TMenuItem;
    { Separator under @link(mnuFind). }
    mnuFindSep: TMenuItem;
    { View > Show Towns and Cities. }
    mnuShowPlaces: TMenuItem;
    { View > Show Markers. }
    mnuShowMarkers: TMenuItem;
    { View > Show Flight Path. }
    mnuShowFlightPath: TMenuItem;
    { The Markers menu. }
    mnuMarkers: TMenuItem;
    { Markers > Add Marker at Map Centre... }
    mnuAddMarker: TMenuItem;
    { Markers > Edit Markers... }
    mnuEditMarkers: TMenuItem;
    { The Bookmarks menu: Add Bookmark, then the bookmarks and their
      folders, built from @code(bookmarks.json) by
      @link(BuildBookmarksMenu). }
    mnuBookmarks: TMenuItem;
    { Bookmarks > Add Bookmark...: the 3D view's place, or typed
      coordinates. }
    mnuAddBookmark: TMenuItem;
    { Bookmarks > the line under Add Bookmark. }
    mnuBookmarksSep: TMenuItem;
    { The tabs filling the window between the toolbar and the status bar. }
    tabMain: TTabControl;
    { First tab: the world map. }
    tabMap: TTabItem;
    { Holds the map view, which is created in code. }
    layMap: TLayout;
    { Second tab: 3D view. Empty for now. }
    tab3D: TTabItem;
    { Third tab: the log. }
    tabDebug: TTabItem;
    { Read-only log of what the program is doing. }
    memLog: TMemo;
    { Progress of the current file or job, from 0 to 100. }
    pbDownload: TProgressBar;
    { Status bar under the tabs. }
    layStatus: TLayout;
    { Shows the position and tile under the mouse pointer. }
    lblHover: TLabel;
    { Shows the data folder, its free space and how many tiles it holds,
      or that it is not connected. }
    lblStorage: TLabel;
    { Checks the data folder and its free space every
      @link(STORAGE_CHECK_INTERVAL) milliseconds. }
    tmrStorage: TTimer;

    { Creates the map, loads the settings and both tile bitmaps, and queues
      the settings dialog if there are no settings.
      @param(Sender The form.) }
    procedure FormCreate(Sender: TObject);

    { Frees what the form owns.
      @param(Sender The form.) }
    procedure FormDestroy(Sender: TObject);

    { Lets the window close only when nothing is running. If something is,
      it is cancelled and the window closes once it has stopped, so no
      queued update can reach a freed form.
      @param(Sender The form.)
      @param(CanClose Set to @false while work is still stopping.) }
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);

    { Fetches the tiles in the map selection that still need downloading.
      It starts at once, without asking: the progress dialog that opens has
      a Cancel button. If the drive looks too full for them all, the Debug
      tab says so; downloading stops at the free-space reserve anyway.
      @param(Sender The button.) }
    procedure btnFetchSelectionClick(Sender: TObject);

    { Asks the running job to stop.
      @param(Sender The button.) }
    procedure btnCancelClick(Sender: TObject);

    { Builds the selected tile's 3D view while the map is still showing,
      then switches to the 3D tab once it is ready.
      @param(Sender The button.) }
    procedure btnShow3DClick(Sender: TObject);

    { Shows the mode chosen with the switch, beside it and in the title.
      @param(Sender The switch.) }
    procedure swClick3DSwitch(Sender: TObject);

    { Opens the settings dialog.
      @param(Sender The menu item.) }
    procedure mnuSettingsClick(Sender: TObject);

    { Closes the application.
      @param(Sender The menu item.) }
    procedure mnuExitClick(Sender: TObject);

    { Asks for a folder of existing tile files and copies them into the
      data folder, leaving the originals untouched.
      @param(Sender The menu item.) }
    procedure mnuImportClick(Sender: TObject);

    { Asks for a folder of existing tile files and moves them into the
      data folder: each original is deleted once its copy is safely there,
      and so is each one the data folder already has. Asks first, saying
      plainly that the originals are deleted.
      @param(Sender The menu item.) }
    procedure mnuMoveImportClick(Sender: TObject);

    { Rebuilds the downloaded-tiles bitmap from the data folder.
      @param(Sender The menu item.) }
    procedure mnuRescanClick(Sender: TObject);

    { Deletes the downloaded tiles in the map selection, after asking.
      @param(Sender The menu item.) }
    procedure mnuDeleteSelectedClick(Sender: TObject);

    { Zooms the map in.
      @param(Sender The menu item.) }
    procedure mnuZoomInClick(Sender: TObject);

    { Zooms the map out.
      @param(Sender The menu item.) }
    procedure mnuZoomOutClick(Sender: TObject);

    { Shows the whole world.
      @param(Sender The menu item.) }
    procedure mnuZoomFitClick(Sender: TObject);

    { Zooms to the selected tiles.
      @param(Sender The menu item.) }
    procedure mnuZoomSelectionClick(Sender: TObject);

    { Rebuilds the tile index from CMR.
      @param(Sender The menu item.) }
    procedure mnuRefreshIndexClick(Sender: TObject);

    { Shows or hides the tint on tiles with data.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowTilesClick(Sender: TObject);

    { Shows or hides the tint on downloaded tiles.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowDownloadedClick(Sender: TObject);

    { Shows or hides country borders on the map.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowBordersClick(Sender: TObject);

    { Shows or hides coastlines on the map.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowCoastlinesClick(Sender: TObject);

    { Switches between the high-resolution map and the plain map image.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowMapTilesClick(Sender: TObject);

    { Puts the whole log on the clipboard, ready to paste.
      @param(Sender The menu item.) }
    procedure mnuCopyLogClick(Sender: TObject);

    { Empties the log, so the next job's messages are easy to copy.
      @param(Sender The menu item.) }
    procedure mnuClearLogClick(Sender: TObject);

    { Periodic check of the data folder and its free space.
      @param(Sender The timer.) }
    procedure tmrStorageTimer(Sender: TObject);

    { Searches again as the user types in @link(edtSearch).
      @param(Sender The search box.) }
    procedure edtSearchChangeTracking(Sender: TObject);

    { Up and Down move through the matches, Enter goes to the chosen one,
      Escape closes the list.
      @param(Sender The search box.)
      @param(Key The key; set to 0 when handled here.)
      @param(KeyChar The character typed.)
      @param(Shift The modifier keys held.) }
    procedure edtSearchKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);

    { Empties the search box as it gains the focus, ready for a new
      search.
      @param(Sender The search box.) }
    procedure edtSearchEnter(Sender: TObject);

    { Empties the search box when it is clicked while it shows a place
      already gone to; text being typed is left alone, so a click can
      still move the cursor in it.
      @param(Sender The search box.) }
    procedure edtSearchClick(Sender: TObject);

    { Goes to the best match, as Enter does.
      @param(Sender The button.) }
    procedure btnSearchGoClick(Sender: TObject);

    { Colours the button's triangle like the button's text, so it shows
      on every theme, light or dark.
      @param(Sender The button.) }
    procedure btnSearchGoApplyStyleLookup(Sender: TObject);

    { Puts the cursor in the search box.
      @param(Sender The menu item.) }
    procedure mnuFindClick(Sender: TObject);

    { Shows or hides the labels of towns and cities.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowPlacesClick(Sender: TObject);

    { Shows or hides the markers.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowMarkersClick(Sender: TObject);

    { Shows or hides the flight path on the map.
      @param(Sender The menu item, which checks itself.) }
    procedure mnuShowFlightPathClick(Sender: TObject);

    { Saves the current flight's path to a @code(.flt) file.
      @param(Sender The menu item.) }
    procedure mnuSaveFlightPathClick(Sender: TObject);

    { Saves every flight's path since the program started to one
      @code(.flt) file.
      @param(Sender The menu item.) }
    procedure mnuSaveAllFlightPathsClick(Sender: TObject);

    { Asks for a name and adds a marker in the middle of the map.
      @param(Sender The menu item.) }
    procedure mnuAddMarkerClick(Sender: TObject);

    { Opens the list of markers, to rename, delete or go to them.
      @param(Sender The menu item.) }
    procedure mnuEditMarkersClick(Sender: TObject);

    { Bookmarks > Add Bookmark...: as B in the 3D view.
      @param(Sender The menu item.) }
    procedure mnuAddBookmarkClick(Sender: TObject);
  private
    { The user's saved settings, loaded at start-up. }
    FSettings: TGDEMSettings;

    { The world map, created in @link(FormCreate). }
    FMap: TWorldMapView;

    { The user's markers, loaded at start-up. Owned by the form and shown
      on @link(FMap). }
    FMarkers: TMarkerList;

    { What the View menu shows, remembered between runs; loaded at
      start-up and saved whenever a View item is ticked or unticked. }
    FViewOptions: TViewOptions;

    { Finds countries, places, markers and easter eggs by name; rebuilt when
      the markers change. }
    FSearch: TPlaceSearch;

    { Hidden places only the search finds, from the
      @code(EASTER_EGGS_RESOURCE) resource; empty if it could not be
      read. }
    FEasterEggs: TArray<TEasterEgg>;

    { The matches for what is in @link(edtSearch), in the order shown in
      @link(FSearchList). }
    FSearchHits: TArray<TSearchHit>;

    { The list of matches under @link(edtSearch), over the map; created in
      @link(FormCreate) and hidden until there is something to show. }
    FSearchList: TListBox;

    { @true while the program itself changes @link(edtSearch), so that is
      not taken as typing. }
    FSearchUpdating: Boolean;

    { The text @link(GoToHit) last put in @link(edtSearch): a place gone
      to, which a click on the box clears. }
    FSearchChosen: string;

    { Which tiles have data. Owned by the form and shown on @link(FMap).
      Empty until loaded or built. Only touched on the main thread. }
    FTileIndex: TTileIndex;

    { The tile index build in progress, or @nil when idle. Created and freed
      on the main thread. }
    FIndexBuilder: TTileIndexBuilder;

    { The current data folder. Replaced only while no job is running. }
    FStore: TGDEMStore;

    { Which tiles are fully downloaded in @link(FStore). Owned by the form
      and shown on @link(FMap). Only touched on the main thread. }
    FDownloaded: TTileIndex;

    { Country borders, coastlines and names, from the
      @code(WORLD_VECTORS_RESOURCE) resource. Owned by the form and shown on
      @link(FMap); empty if they could not be loaded. }
    FVectors: TWorldVectors;

    { The high-resolution map's tiles, shown on @link(FMap); @nil when no
      tile set was found. Owned by the form. }
    FMapTiles: TTileCache;

    { The 3D view of the ground round a tile, made the first time a tile
      is shown in 3D; @nil before that. Owned by the form. }
    FTerrainView: TTerrainView;

    { The 3D tab's toolbar, made in @link(Build3DTab). }
    FTerrainBar: TLayout;

    { The 3D tab's choice of detail, in the order of
      @code(TERRAIN_DETAILS). }
    FTerrainDetailBox: TComboBox;

    { The 3D tab's choice of height stretch, in the order of
      @code(TERRAIN_HEIGHTS). }
    FTerrainHeightsBox: TComboBox;

    { The 3D tab's choice of distance detail, in the order of
      @code(TERRAIN_RANGES). }
    FTerrainRangeBox: TComboBox;

    { The 3D tab's Realistic switch: satellite imagery instead of height
      colours. }
    FTerrainRealisticBox: TCheckBox;

    { Makes the imagery for the 3D view's Realistic option; made when it
      is first needed, and made again after Settings, as the data folder
      it caches in may have changed. Owned by the form. }
    FImagery: TImageryService;

    { The user's bookmarks of 3D views, from @code(bookmarks.json). Owned
      by the form. }
    FBookmarks: TBookmarkList;

    { The folder the last bookmark went in, offered for the next. }
    FLastBookmarkFolder: Integer;

    { The 3D tab's Flags box: place names on poles. }
    FTerrainLabelsBox: TCheckBox;

    { The 3D tab's Autopilot box: keeps the flight clear of the ground. }
    FTerrainAutopilotBox: TCheckBox;

    { The 3D tab's Hug ground box: the autopilot keeps 25 to 75 m above
      the ground; ticking it ticks @link(FTerrainAutopilotBox) too. }
    FTerrainHugBox: TCheckBox;

    { @true while @link(FFlightTargetLatitude) and
      @link(FFlightTargetLongitude) hold the place last chosen on the map,
      by a search or a click: Show in 3D starts the flight looking at it
      when it is in the tile shown. }
    FFlightTargetSet: Boolean;
    { The place last chosen on the map, latitude. }
    FFlightTargetLatitude: Double;
    { The place last chosen on the map, longitude. }
    FFlightTargetLongitude: Double;
    { The easter egg last found in the search, flagged in the 3D view;
      the others stay hidden. @code(-1) before one is found. }
    FFoundEgg: Integer;
    { Where the last plain left press on the map was, latitude. }
    FPressLatitude: Double;
    { Where the last plain left press on the map was, longitude. }
    FPressLongitude: Double;
    { @true if @link(FPressLatitude) and @link(FPressLongitude) are on the
      map. }
    FPressOnMap: Boolean;

    { The work of Preparing for flight: its cancellation token while
      tiles download; @nil afterwards. }
    FPrepareToken: TCancelToken;
    { Watches the 3D view settle while Preparing for flight. }
    FPrepareTimer: TTimer;
    { @true once Abort has been pressed in Preparing for flight. }
    FPrepareCancelled: Boolean;
    { @true once Preparing for flight has finished and the 3D tab may be
      shown. }
    FPrepareDone: Boolean;
    { Run when Preparing for flight has finished and the view is ready;
      see @link(PrepareFlight). }
    FPrepareFinish: TProc;
    { Ticks of @link(FPrepareTimer) since the 3D view was given its tile,
      so it is not taken as settled before it has started. }
    FPrepareTicks: Integer;

    { Tiles the last Preparing for flight had to download; -1 before the
      first. }
    FLastFetchTiles: Integer;
    { When the last Preparing for flight checked the tiles. }
    FLastFetchAt: TDateTime;
    { Keeps the status bar's "ago" current on the 3D tab, once a second,
      and looks for tiles needed ahead of the flight. }
    FStatusTimer: TTimer;
    { The flight log: the 3D view's working detail (settled and memory
      lines, imagery, fetching ahead), kept out of the Debug tab; made at
      the first line, one file per run of the program; @nil until then. }
    FFlightLog: TDownloadReport;
    { Every flight's path since the program started, oldest first; the
      last is the current flight's. }
    FFlights: TObjectList<TFlightPath>;
    { @true if the Preparing for flight under way starts a new flight
      (and so a new path); @false when it only makes the view again. }
    FPrepareNewFlight: Boolean;
    { The name the path started by the Preparing for flight under way gets. }
    FPrepareFlightName: string;
    { The name for the next flight's path, set before
      @link(PrepareFlight) by what starts it; used once. }
    FNextFlightName: string;
    { Ticks of @link(FStatusTimer) since the last look ahead. }
    FAheadTicks: Integer;
    { The download of tiles ahead of the flight running now; @nil when
      none is. It is also @link(FJob) while it runs. }
    FAheadToken: TCancelToken;
    { Tiles being downloaded ahead of the flight now. }
    FAheadTiles: Integer;
    { No look ahead before this, after a download ahead failed or was
      cancelled, or with an expired token. }
    FAheadRetryAt: TDateTime;

    { The 3D tab's search box: as the Map tab's, but a match is flown to
      (Preparing for flight) instead of shown on the map. }
    FTerrainSearch: TEdit;
    { The arrow after @link(FTerrainSearch): flies to the match chosen. }
    FTerrainSearchGo: TButton;
    { The search box being typed in, @link(edtSearch) or
      @link(FTerrainSearch): the one @link(FSearchList) is under and that
      the matches are for. }
    FSearchEdit: TEdit;
    { The match last chosen, whose text is @link(FSearchChosen). }
    FChosenHit: TSearchHit;
    { @true once Up or Down has picked a match in the list since the last
      typing, so Enter or an arrow takes that one. }
    FSearchPicked: Boolean;

    { The tile the 3D tab is centred on; empty when none. }
    FTerrainTile: string;

    { @true while the program itself sets the 3D tab's choices, so that is
      not taken as the user choosing. }
    FTerrainUpdating: Boolean;

    { @true from a plain left press on the map until the selection next
      changes, so @link(MapSelectionChanged) can tell a click from a
      selection made by the program (such as finding a mountain). }
    FMapLeftClick: Boolean;

    { @true once @link(FDownloaded) has been loaded or rebuilt for the
      current data folder. Cleared when the folder becomes unavailable, so
      it is reloaded when the drive is connected again. }
    FStoreOpen: Boolean;

    { Whether the data folder was available at the last check, so that
      its bitmap is reloaded only when the folder appears, not retried after
      every failure. }
    FStoreWasAvailable: Boolean;

    { Cancellation token of the running job, or @nil when no job is
      running. Created and freed on the main thread. }
    FJob: TCancelToken;

    { Set when the user tries to close the window while work is running, so
      it closes once the work has stopped. }
    FCloseWhenIdle: Boolean;

    { The progress dialog being shown, or @nil. Only touched on the main
      thread; background work updates it through the @code(Progress...)
      methods. }
    FProgress: TfrmProgress;

    { Whether settings were loaded at start-up; if not,
      @link(RunStartup) opens the settings dialog. }
    FHaveSettings: Boolean;

    { Set at start-up when there is no usable tile index, so
      @link(RunStartup) downloads one. }
    FNeedIndexBuild: Boolean;

    { The names of the countries in a selection made by right-clicking,
      in the order they were added, so Shift+right-click can add to them.
      Only meaningful while the map's @code(SelectionName) is
      @link(FSelectionLabel). }
    FSelectedCountries: TArray<string>;

    { The name @link(MapRightClick) last gave the map's selection; if the
      map's @code(SelectionName) is now something else, the selection has
      changed since and @link(FSelectedCountries) no longer describes it. }
    FSelectionLabel: string;

    { Adds a line to @link(memLog). Safe to call from any thread. Query
      strings in web addresses are hidden first (see @link(HideURLQueries)),
      as error messages can carry signed download addresses.
      @param(Msg The line to add.) }
    procedure AddLog(const Msg: string);

    { Reports a serious problem: logs it and shows it in a modal error
      dialog. Safe to call from any thread. The dialog is queued, so it
      appears once the main thread is free (after the window has been shown,
      when called during start-up). Nothing is shown while the window is
      closing. Query strings in web addresses are hidden from both (see
      @link(HideURLQueries)).
      @param(AMessage Description of the problem.) }
    procedure ReportError(const AMessage: string);

    { Logs when the bearer token expires, and warns with a dialog if it has
      expired or has fewer than @code(TOKEN_WARN_DAYS) days left. Does
      nothing when no token has been entered.
      @returns(@false if the token is known to have expired.) }
    function CheckTokenExpiry: Boolean;

    { Shows job progress on the progress bar. Safe to call from any thread.
      @param(ADone Items processed so far.)
      @param(ATotal Total items; nothing is shown when 0.) }
    procedure ShowProgress(ADone, ATotal: Integer);

    { Formats a number of bytes for display, such as @code(12.3 GB); see
      @link(FormatByteSize).
      @param(ABytes The size; negative means unknown.)
      @returns(The formatted size.) }
    class function FormatBytes(ABytes: Int64): string; static;

    { Starts a job that imports tiles from a folder, then rescans the data
      folder so the map shows them.
      @param(ASourceFolder The folder to import from.)
      @param(AMove @true to delete each original once it is safely in the
        data folder (Data > Move Existing Files); @false to leave the
        originals untouched.) }
    procedure StartImport(const ASourceFolder: string; AMove: Boolean = False);

    { The free-space reserve for the data folder's drive: the percentage
      in the settings, of that drive's size (see
      @code(TGDEMStore.Reserve)).
      @returns(Bytes that must be left free.) }
    function ReserveBytes: Int64;

    { Loads the world map image from the @link(WORLD_MAP_RESOURCE)
      resource into @link(FMap), reporting any failure, then the borders and
      coastlines. The map works without the borders, so failing to load them
      is only logged as a warning. }
    procedure LoadWorldMap;

    { Opens the tile set built into the program for the high-resolution
      map (see @code(GDEMMapTiles)) and shows it on @link(FMap). Reads the
      smallest level at once, so there is always something to draw. If it
      cannot be read, the plain map image is drawn, and the log says so. }
    procedure LoadMapTiles;

    { Reads the remembered View choices into @link(FViewOptions), or keeps
      the defaults (with a warning if the file cannot be read), then ticks
      the View menu and sets up the map to match. }
    procedure LoadViewOptions;

    { Copies the View menu's ticks into @link(FViewOptions) and writes
      them, logging a warning if they cannot be written. }
    procedure SaveViewOptions;

    { Makes the 3D tab's toolbar: Detail and Heights choices, set from
      @link(FViewOptions), a Start Again button and a line of information.
      The view itself is made when first needed. }
    procedure Build3DTab;

    { Shows the ground round a tile on the 3D tab, starting again only if
      it is a different tile, or when asked to. The 3D tab keeps showing it
      until another is sent with Show in 3D, whatever is selected on the
      map meanwhile. The surface sharpens over the next moments, as its
      patches are made; @link(TerrainSettled) logs when they are done.
      @param(ATile The tile, such as @code(N50W002).)
      @param(AForce @true to start again even if it is already shown.) }
    procedure ShowTerrainTile(const ATile: string; AForce: Boolean);

    { What a tile holds, for the 3D view: land if downloaded (with its
      file), missing if it exists but is not downloaded, sea otherwise.
      @param(ASouth Latitude of its south edge.)
      @param(AWest Longitude of its west edge.)
      @returns(Its kind and file.) }
    function TerrainTileInfo(ASouth, AWest: Integer): TTerrainTileInfo;

    { Logs what the 3D view did once its patches are all made, says it on
      the 3D tab, and logs the memory in use a moment later.
      @param(Sender The view.)
      @param(AText The report.) }
    procedure TerrainSettled(Sender: TObject; const AText: string);

    { Logs the 3D view's lines to the flight log, and crashes and problems
      to the Debug tab too.
      @param(Sender The view.)
      @param(AText The line.) }
    procedure TerrainLog(Sender: TObject; const AText: string);

    { Writes a line to the flight log, @code(flight-yyyymmdd-hhnnss.log) in
      the Reports folder, made at the first line (the Debug tab says where);
      lines starting @code(WARNING) or @code(ERROR) go to the Debug tab too.
      Safe from any thread: other threads' lines are queued to the main
      thread. If the file cannot be made, lines go to the Debug tab.
      @param(AText The line.) }
    procedure FlightLog(const AText: string);

    { The current flight's path; @nil before the first flight.
      @returns(The path.) }
    function CurrentFlightPath: TFlightPath;

    { Starts a new flight path where the flight is, ending the current one
      (as Flight Ended) if it has not ended.
      @param(AName Where it starts.) }
    procedure StartFlightPath(const AName: string);

    { Ends the current flight path as crashed.
      @param(Sender The view.) }
    procedure TerrainCrash(Sender: TObject);

    { Starts a new flight path when the user starts the flight again.
      @param(Sender The view.) }
    procedure TerrainRestart(Sender: TObject);

    { Shows the current flight's path on the map. }
    procedure ShowFlightPathOnMap;

    { Asks where to save flight paths and saves them.
      @param(AFlights The paths.)
      @param(AWhat What is saved, for the log, such as @code(1 flight path).) }
    procedure SaveFlightPathsAs(const AFlights: TArray<TFlightPathRecord>; const AWhat: string);

    { The distance detail chosen on the 3D tab.
      @returns(Tenths, from @code(TERRAIN_RANGES).) }
    function ChosenTerrainRange: Integer;

    { Applies the new distance detail, and remembers the choice.
      @param(Sender The combo box.) }
    procedure TerrainRangeChange(Sender: TObject);

    { The detail chosen on the 3D tab.
      @returns(The most samples across, from @code(TERRAIN_DETAILS).) }
    function ChosenTerrainDetail: Integer;

    { The height stretch chosen on the 3D tab.
      @returns(Times true scale, from @code(TERRAIN_HEIGHTS).) }
    function ChosenTerrainHeights: Integer;

    { Selects the one tile holding a point, naming the selection, so the
      selection label and the 3D tab use it.
      @param(ALat Latitude.)
      @param(ALon Longitude.)
      @param(AName The selection's name, such as a mountain's.) }
    procedure SelectTileAt(ALat, ALon: Double; const AName: string);

    { Applies the new detail, and remembers the choice.
      @param(Sender The combo box.) }
    procedure TerrainDetailChange(Sender: TObject);

    { Makes the surface again at the new height stretch, and remembers
      the choice.
      @param(Sender The combo box.) }
    procedure TerrainHeightsChange(Sender: TObject);

    { Flies to the match chosen in the 3D tab's search box.
      @param(Sender The arrow button.) }
    procedure TerrainSearchGoClick(Sender: TObject);

    { Hides the search list when the 3D view is clicked.
      @param(Sender The view.)
      @param(Button The mouse button.)
      @param(Shift The keys held.)
      @param(X Where, across.)
      @param(Y Where, down.) }
    procedure TerrainMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);

    { Makes the 3D view again where the flight is, behind Preparing for
      flight, after Detail, Heights, Distance or Realistic has changed: the
      flight is put back as it was and carries on at its speed once the
      dialog has closed. Queued, so the control that changed has finished
      first. Nothing without a 3D view. }
    procedure RelaunchTerrain;

    { Gives the 3D view the keyboard, for flying, after a control on the
      3D toolbar has taken it. }
    procedure FocusTerrainView;

    { Turns the 3D view's imagery on or off as the Realistic box says, and
      remembers it.
      @param(Sender The check box.) }
    procedure TerrainRealisticChange(Sender: TObject);

    { The imagery service, made if there is none yet, caching in the data
      folder when it is available.
      @returns(The service.) }
    function ImageryService: TImageryService;

    { Frees the imagery service, taking it from the 3D view first; the
      next @link(ImageryService) makes another, from the settings and data
      folder then. }
    procedure CloseImagery;

    { Gives the 3D view the imagery service and the Realistic choice. }
    procedure ApplyTerrainRealistic;

    { Reads @code(bookmarks.json); a file that cannot be read is logged
      and left as it is, and the menu starts empty. }
    procedure LoadBookmarks;

    { Writes @code(bookmarks.json).
      @returns(@false if it could not be written; the error has been
        shown.) }
    function SaveBookmarks: Boolean;

    { Builds the Bookmarks menu's folders and bookmarks again from
      @link(FBookmarks), under Add Bookmark, and gives the 3D view the
      bookmarks' flags again. }
    procedure BuildBookmarksMenu;

    { Adds a folder's folders (as submenus) and bookmarks to a menu.
      @param(AParent The menu item they go in.)
      @param(AFolder The folder; @code(BOOKMARK_ROOT) for the top level.) }
    procedure AddBookmarkItems(AParent: TMenuItem; AFolder: Integer);

    { Goes to the bookmark a menu item stands for.
      @param(Sender The menu item; its Tag is the bookmark's index.) }
    procedure BookmarkMenuClick(Sender: TObject);

    { Goes to a bookmark: its heights and imagery, the ground round it,
      and the flight exactly as it was.
      @param(AIndex The bookmark's index.) }
    procedure GoToBookmark(AIndex: Integer);

    { The 3D view's bookmark key, and Bookmarks > Add Bookmark: pauses the
      view, asks for the bookmark's name, place (the view's, or typed
      coordinates) and folder, saves it, and carries on as before.
      @param(Sender The view, or @nil.) }
    procedure TerrainBookmark(Sender: TObject);

    { Remembers whether the 3D view's controls panel is collapsed.
      @param(Sender The view.) }
    procedure TerrainControlsToggle(Sender: TObject);

    { The tile Show in 3D would show: the only tile with data selected,
      or the only one downloaded when there is no tile index yet.
      @returns(Its name, or empty if there is none.) }
    function Show3DTile: string;

    { Remembers a place chosen on the map, to start the flight looking at.
      @param(ALatitude Its latitude.)
      @param(ALongitude Its longitude.) }
    procedure SetFlightTarget(ALatitude, ALongitude: Double);

    { Makes the 3D view ready to fly, in a modal dialog titled Preparing
      for flight with an Abort button: downloads the tiles the view will
      load round the place that are not downloaded yet (if there is a
      bearer token), gives the view the tile and places the flight, waits
      for the ground (and, with Realistic on, its imagery) to be made, then
      shows the 3D tab. Aborted, the 3D tab is not shown.
      @param(ATile The tile to show.)
      @param(ALatitude Where the flight will be, latitude, for the tiles
        round it.)
      @param(ALongitude Where the flight will be, longitude.)
      @param(APlace Places the flight once the view has the tile, such as
        @code(StartLookingAt) or @code(JumpTo).)
      @param(AFinish Run once the dialog has closed and the view is ready,
        not if aborted, such as to set the flight moving; may be @nil.)
      @param(ANewFlight @true (the default) if this starts a new flight, and
        so a new flight path (named @link(FNextFlightName), or the tile);
        @false when it only makes the view again for the same flight.) }
    procedure PrepareFlight(const ATile: string; ALatitude, ALongitude: Double;
      const APlace: TProc; const AFinish: TProc = nil; ANewFlight: Boolean = True);

    { Ends Preparing for flight once its dialog has closed: uncovers the
      view and, if it is ready, shows the 3D tab and runs what
      @link(PrepareFlight) was given to finish with. }
    procedure FinishPreparing;

    { Shows how far Preparing for flight has got while the 3D view is
      made, and closes the dialog once it has settled or Abort is pressed.
      @param(Sender The timer.) }
    procedure PrepareTimerTick(Sender: TObject);

    { Gives the 3D view the places to label: towns and cities, mountains
      and markers. }
    procedure UpdateTerrainLabels;

    { Turns the 3D view's place names on or off as the Flags box says,
      and remembers it.
      @param(Sender The check box.) }
    procedure TerrainLabelsChange(Sender: TObject);

    { Turns the 3D view's autopilot on or off as the Autopilot box says,
      and remembers it.
      @param(Sender The check box.) }
    procedure TerrainAutopilotChange(Sender: TObject);

    { Turns ground hugging on or off as the Hug ground box says (on turns
      the autopilot on too), and remembers it.
      @param(Sender The check box.) }
    procedure TerrainHugChange(Sender: TObject);

    { The 3D view's L key turned the place names on or off: ticks the box
      to match and remembers it.
      @param(Sender The view.) }
    procedure TerrainLabelsToggle(Sender: TObject);

    { The flight moved: on the 3D tab, its latitude and longitude go in
      the status bar, where the map shows the tile under the pointer.
      @param(Sender The view.) }
    procedure TerrainFlightMoved(Sender: TObject);

    { Another tab was chosen: on the 3D tab the status bar shows the
      flight's position; elsewhere it is cleared for the map to fill.
      @param(Sender The tabs.) }
    procedure TabMainChange(Sender: TObject);

    { Refreshes the 3D tab's status bar, so its "ago" stays current.
      @param(Sender The timer.) }
    procedure StatusTimerTick(Sender: TObject);

    { While flying on the 3D tab, downloads quietly the tiles that exist
      but are not here, round the flight and round the place it will be in
      @link(TILES_AHEAD_SECONDS) (at most @link(TILES_AHEAD_KM) ahead):
      at most @link(TILES_AHEAD_MAX) at a time, nearest first, as a job
      without a dialog, logged on the Debug tab. Each tile's ground is made
      again as it lands. Does nothing while another job runs, with no
      bearer token or an expired one, or with no tile index. }
    procedure FetchTilesAhead;

    { Downloads tiles ahead of the flight in the background, for
      @link(FetchTilesAhead).
      @param(ATiles The tiles' names, nearest first.) }
    procedure StartTilesAhead(const ATiles: TArray<string>);

    { What the last Preparing for flight had to download, and how long
      ago, for the status bar.
      @returns(Such as @code(last fetch 3 tiles, 2 min ago); empty before
        the first.) }
    function LastFetchText: string;

    { The View menu item that shows a layer.
      @param(ALayer The layer.)
      @returns(Its menu item.) }
    function ViewLayerItem(ALayer: TViewLayer): TMenuItem;

    { Shows on the map what the View menu has ticked. }
    procedure ApplyViewMenu;

    { The first time Settings closes with OK after the user changed how
      GDEMFetch draws (Drawing, or on Windows Graphics), turns on the View
      menu layers that suit the new choice (see
      @code(SuggestedViewLayers)) and says so in a dialog, listing the
      layers from the most demanding to the least for turning off if the
      map is slow. Choosing the CPU changes nothing and leaves this for a
      later change; once layers have been suggested it never happens
      again, as @code(TViewOptions.DrawingSuggestionMade) records.
      @param(AOldDrawing The Drawing setting before the dialog opened.)
      @param(AOldGpuPreference The Graphics setting before the dialog
        opened.) }
    procedure SuggestViewForDrawing(const AOldDrawing, AOldGpuPreference: string);

    { Reads the markers file into @link(FMarkers), logging how many, or a
      warning if it cannot be read. }
    procedure LoadMarkers;

    { Writes @link(FMarkers) to its file, then refreshes the search and
      the map.
      @returns(@true if saved; a failure is reported.) }
    function SaveMarkers: Boolean;

    { Reads the easter eggs into @link(FEasterEggs), logging only what goes
      wrong, so they stay a surprise. }
    procedure LoadEasterEggs;

    { Refills @link(FSearch) from the countries, places, markers and
      easter eggs. }
    procedure RebuildSearch;

    { Searches for what is in @link(FSearchEdit) and shows the matches. }
    procedure RunSearch;

    { Goes to (or, from the 3D tab, flies to) the match picked in the
      search list, or the best one, searching first if the list is not
      showing; for Enter and the arrow buttons. }
    procedure GoToSearchChoice;

    { The one match the search box means, if it means only one: the match
      last chosen while the box still shows it, one picked with Up or Down,
      or the only match (or the only exact one).
      @param(AHit The match.)
      @returns(@false if there is none, or several and none picked.) }
    function UniqueSearchHit(out AHit: TSearchHit): Boolean;

    { Flies to what the search box means, for the arrow buttons and Enter
      on the 3D tab: @link(LaunchHit) if it means one place, otherwise the
      list is shown to choose from. }
    procedure LaunchSearchChoice;

    { Goes to a match on the map, or flies to it from the 3D tab's search
      box, as @link(FSearchEdit) says.
      @param(AHit The match.) }
    procedure ChooseHit(const AHit: TSearchHit);

    { Flies to a match: Preparing for flight there, then the 3D view looks
      at it, as Launch Mode does from the map; a country at its middle.
      The view moves only once the dialog has closed.
      @param(AHit The match.) }
    procedure LaunchHit(const AHit: TSearchHit);

    { Puts a right-pointing triangle, drawn as a vector path as Sprite3D
      draws its buttons, on a search arrow button.
      @param(AButton @link(btnSearchGo) or @link(FTerrainSearchGo).) }
    procedure BuildSearchGoIcon(AButton: TButton);

    { Empties the search box, which closes the list and removes the ring,
      as emptying it by hand does. }
    procedure ClearSearchBox;

    { Shows @link(FSearchList) under @link(FSearchEdit), sized to the
      matches. }
    procedure ShowSearchList;

    { Hides @link(FSearchList). }
    procedure HideSearchList;

    { Goes to a match: zooms to a country, or moves to a place or marker
      and rings it.
      @param(AHit The match.) }
    procedure GoToHit(const AHit: TSearchHit);

    { Goes to the match clicked in @link(FSearchList).
      @param(Sender The list.)
      @param(Item The item clicked.) }
    procedure SearchListItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);

    { Hides the search list when the map is clicked.
      @param(Sender The map view.)
      @param(Button The mouse button.)
      @param(Shift The modifier keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MapMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);

    { Logs each display FMX knows of, with its size, position and scale
      factor, so a problem that depends on the display (as the map once
      jumped when dragged onto a display with another scale) can be told
      from the log. }
    procedure LogDisplays;

    { Logs the computer's memory, this program's use of it, and each
      graphics processor with its memory, from @link(DescribeSystem), at
      start-up. }
    procedure LogSystem;

    { Adds a marker where the map was Ctrl + clicked (Cmd + clicked).
      @param(Sender The map view.)
      @param(ALat Latitude clicked.)
      @param(ALon Longitude clicked.)
      @param(AShift The modifier keys held.) }
    procedure MapMarkerClick(Sender: TObject; ALat, ALon: Double; AShift: TShiftState);

    { Asks the user for a name and adds a marker.
      @param(ALat Latitude, in degrees.)
      @param(ALon Longitude, in degrees.) }
    procedure AddMarkerAt(ALat, ALon: Double);

    { Updates the selection label and buttons after the map selection or a
      tile bitmap changes.
      @param(Sender The map view.) }
    procedure MapSelectionChanged(Sender: TObject);

    { Keeps the selection label up to date while a selection is being
      dragged, so the size and tile counts show before the mouse is
      released.
      @param(Sender The map view.) }
    procedure MapSelectionChanging(Sender: TObject);

    { Shows the selection's size, and how many of its tiles have data and
      are downloaded, in @link(lblSelection). }
    procedure UpdateSelectionText;

    { Shows the position and tile under the pointer in the status bar.
      @param(Sender The map view.)
      @param(ALat Latitude under the pointer.)
      @param(ALon Longitude under the pointer.)
      @param(AOnMap @false when the pointer is off the map.) }
    procedure MapHover(Sender: TObject; ALat, ALon: Double; AOnMap: Boolean);

    { Selects every tile of the country under a right click, ready to fetch
      or delete. With Shift held, adds them to the current selection
      instead, whether that is a country or countries, or a block dragged
      on the map; a tile already selected stays selected once. Does
      nothing over the sea.
      @param(Sender The map view.)
      @param(ALat Latitude clicked.)
      @param(ALon Longitude clicked.)
      @param(AShift The modifier keys held.) }
    procedure MapRightClick(Sender: TObject; ALat, ALon: Double; AShift: TShiftState);

    { Names a selection of countries for the selection label, such as
      @code(Germany + France), or @code(Germany + France + 3 more) when
      there are more than three.
      @param(ANames The countries, in the order they were added.)
      @returns(The name.) }
    class function DescribeCountries(const ANames: TArray<string>): string; static;

    { Names the selected tiles: every tile of the map's selection block, or
      only those in its @code(SelectionMask) when it is a country.
      @param(AOnlyIn If not @nil, only tiles also in this bitmap.)
      @returns(Tile names, north-west first, row by row.) }
    function SelectedTileNames(AOnlyIn: TTileIndex): TArray<string>;

    { Counts the selected tiles, as @link(SelectedTileNames) names them.
      @param(AOnlyIn If not @nil, only tiles also in this bitmap.)
      @returns(The number of tiles.) }
    function SelectedTileCount(AOnlyIn: TTileIndex): Integer;

    { Enables and disables controls to match what is running. }
    procedure UpdateButtons;

    { Shows the data folder's state in @link(lblStorage), and loads the
      downloaded-tiles bitmap if the folder has become available since the
      last check, for example because its drive was connected. }
    procedure RefreshStorageStatus;

    { Opens the settings dialog.
      @param(AOnSaved Called after the dialog closes, only if new settings
        were saved. May be @nil.) }
    procedure ShowSettings(const AOnSaved: TProc);

    { Gives the program the theme saved in the settings.
      @param(AReport @true to report a failure with @link(ReportError);
        @false to log it only, as at start-up.) }
    procedure ApplyThemeSetting(AReport: Boolean);

    { Loads the tile index from its default file. If there is none, or it
      cannot be read, sets @link(FNeedIndexBuild) so that
      @link(RunStartup) downloads one. }
    procedure LoadTileIndex;

    { Does, in turn, everything at start-up that may need the user: the
      settings dialog if there were no settings, the tile index download if
      there is no index, and the request to connect the data folder's drive
      if it is missing. Queued by @link(FormCreate) so it runs once the
      window is showing. }
    procedure RunStartup;

    { Creates the progress dialog, ready to be shown with
      @link(ShowProgressModal).
      @param(ATitle Window title.)
      @param(AOnCancel Called when the user cancels; it should only ask the
        work to stop.)
      @param(AShowItem @true to show the per-file progress bar.) }
    procedure BeginProgress(const ATitle: string; const AOnCancel: TProc;
      AShowItem: Boolean);

    { Shows the progress dialog created by @link(BeginProgress). On desktop
      platforms this blocks until @link(EndProgress) is called (updates
      queued by the background work are still processed meanwhile) and
      then frees the dialog. Call it straight after starting the background
      work. }
    procedure ShowProgressModal;

    { Lets the progress dialog close because the work has stopped. Called
      on the main thread by the work's clean-up. Does nothing if there is no
      dialog. }
    procedure EndProgress;

    { Shows the step in progress in the progress dialog. Safe to call from
      any thread.
      @param(AText The text to show.) }
    procedure ProgressStatus(const AText: string);

    { Shows overall progress in the progress dialog. Safe to call from any
      thread.
      @param(ADone Items finished, or the number of the current item.)
      @param(ATotal Total items.)
      @param(AText Description shown above the bar.) }
    procedure ProgressOverall(ADone, ATotal: Integer; const AText: string);

    { Shows any progress, with a description, on the progress dialog's
      second bar. Safe to call from any thread.
      @param(ADone How far through.)
      @param(ATotal The end.)
      @param(AText Description shown above the bar.) }
    procedure ProgressItemText(ADone, ATotal: Int64; const AText: string);

    { Formats a duration, such as @code(1 h 20 min), @code(3 min 12 s) or
      @code(45 s).
      @param(ASeconds The duration in seconds.)
      @returns(The formatted duration.) }
    class function FormatDuration(ASeconds: Double): string; static;

    { Builds a new tile index from CMR on a background task. On success it
      replaces the current index, is saved, and the map is updated. Does
      nothing if a build is already running. }
    procedure StartIndexBuild;

    { Closes the window if a close was deferred and nothing is running any
      more. }
    procedure CloseIfIdle;

    { Runs work on the data folder as a background job. Only one job runs
      at a time. Cancellation is logged; any other failure is reported
      with @link(ReportError).
      @param(AName Short name of the job, used in messages.)
      @param(AWork The work, run on a background thread.)
      @param(AOnDone Called on the main thread when the job has finished,
        whether or not it succeeded. May be @nil.)
      @param(AProgressTitle When not empty, a modal progress dialog with
        this title is shown while the job runs, and on desktop platforms
        this call returns only once the job has finished. Use it for jobs
        that fetch external data.)
      @returns(@false if another job is already running.) }
    function RunJob(const AName: string; const AWork: TJobWork;
      const AOnDone: TJobDone; const AProgressTitle: string = ''): Boolean;

    { Replaces @link(FStore) with the folder from the settings, and loads
      its downloaded-tiles bitmap if the folder is available. Must only be
      called while no job is running.
      @param(APromptIfMissing @true to ask the user to connect a folder that
        has been used before but is missing. @false at start-up, where
        @link(RunStartup) asks instead.) }
    procedure OpenStore(APromptIfMissing: Boolean = True);

    { Loads @link(FDownloaded) for the current data folder, rebuilding it
      with a rescan if its file is missing or damaged.
      @param(AThen Called once the bitmap is ready. May be @nil.) }
    procedure LoadDownloaded(const AThen: TProc);

    { Makes sure the data folder can be used, then runs AAction. Creates a
      new folder if needed. If a folder that has been used before is
      missing, asks the user to connect its drive and try again.
      @param(AAction What to do once the folder is ready. May be @nil.) }
    procedure WithStore(const AAction: TProc);

    { Records in the settings that the data folder has been set up. }
    procedure MarkStoreUsed;

    { Starts a job that rescans the data folder and rebuilds
      @link(FDownloaded).
      @param(AThen Called after a successful rescan. May be @nil.) }
    procedure StartRescan(const AThen: TProc);

    { Records that a tile is fully downloaded and saves the bitmap. Main
      thread only.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.) }
    procedure MarkDownloaded(ASouth, AWest: Integer);

    { Queues @link(MarkDownloaded) on the main thread. Safe to call from
      any thread. The tile is passed as parameters, so each call keeps its
      own values; an anonymous method in a loop would otherwise see the
      loop variables' later values.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.) }
    procedure QueueMarkDownloaded(ASouth, AWest: Integer);

    { Handles the user choosing a different data folder in the settings:
      offers to move existing data, or switches straight away.
      @param(ANewFolder The folder chosen.) }
    procedure ChangeDataFolder(const ANewFolder: string);

    { Starts using a different data folder without moving anything.
      @param(ANewFolder The folder to use.)
      @param(AForceRescan @true to rebuild the downloaded-tiles bitmap even
        if the folder has one, for example after data was moved into it.) }
    procedure SwitchDataFolder(const ANewFolder: string; AForceRescan: Boolean);

    { Starts a job that moves all downloaded data to another folder, then
      switches to it.
      @param(ANewFolder The destination folder.) }
    procedure StartMove(const ANewFolder: string);

    { Downloads tiles, asking for a bearer token first if none is saved,
      and making sure the data folder is available.
      @param(ATiles Tile names such as @code(N50W002).)
      @param(AAlready Tiles the caller left out of @code(ATiles) because
        they were already downloaded, counted in the summary's "already
        here".) }
    procedure FetchTiles(const ATiles: TArray<string>; AAlready: Integer = 0);

    { Starts a job that downloads tiles one after another into the data
      folder. Tiles with no data are logged and skipped, and so are tiles
      already downloaded. The job stops at the first error, when cancelled,
      or before free space would fall below the reserve.
      @param(ATiles Tile names such as @code(N50W002).)
      @param(AAlready Tiles the caller left out of @code(ATiles) because
        they were already downloaded, counted in the summary's "already
        here".) }
    procedure StartFetch(const ATiles: TArray<string>; AAlready: Integer = 0);

    { The work of a download job, run on its background thread by
      @link(StartFetch): runs a @link(TDownloadBatch), showing its progress
      in the progress dialog, its summary on the Debug tab and its tiles on
      the map, and reports any tiles that failed in a dialog.
      @param(AToken The job's cancellation token.)
      @param(ATiles Tile names such as @code(N50W002).)
      @param(ABearer The Earthdata Login bearer token.)
      @param(AStore The data folder.)
      @param(AReserve Bytes that must be left free on the data drive.)
      @param(ASpeed How hard to push NASA's servers; sets how many files
        download at once to begin with and at most.)
      @param(AAlready Tiles left out of @code(ATiles) before the job began
        because they were already downloaded. They are added to the tiles
        this job finds already downloaded, so the summary's "already here"
        accounts for the whole selection.)
      @raises(EGDEMError if the job had to stop early.)
      @raises(EOperationCancelled if cancelled.) }
    procedure RunDownloads(AToken: TCancelToken; const ATiles: TArray<string>;
      const ABearer: string; AStore: TGDEMStore; AReserve: Int64; ASpeed: TDownloadSpeed;
      AAlready: Integer);
  {$IF defined(LINUX) and not defined(ANDROID)}
  private
    { Linux only: the menu bar FMX draws itself, holding the menus of
      @link(mnuMain) (see @link(UseFmxMenuBar)). }
    FFmxMenuBar: TMenuBar;

    { Replaces @link(mnuMain) with @link(FFmxMenuBar), a menu bar FMX
      draws itself in the theme. On Linux FMX shows a @code(TMainMenu) as a
      native GTK menu bar, which showed only the first letter of each menu
      and item.

      The items are copied, not moved. By the time the form is created FMX
      has already built the GTK menu, and each item keeps a handle to its
      GTK widget; moving the items and freeing @link(mnuMain), as Sprite3D
      does, leaves those handles pointing at destroyed widgets, so the next
      change to an item (such as @code(Enabled)) crashed in GTK. So the
      copies are made first, then the original items are freed one by one,
      so FMX rebuilds the GTK menu bar without each and it ends up empty
      (freeing @link(mnuMain) with its items still in it left a GTK bar of
      first letters above the new one), then @link(mnuMain) is freed, and
      then each copy takes its original's name, which points the form's field (such as
      @link(mnuShowTiles)) at the copy. Handlers, ticks and enabled states
      carry on as before. }
    procedure UseFmxMenuBar;
  {$ENDIF}
  end;

var
  { The application's main form instance. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  System.Math, System.StrUtils, System.Diagnostics, System.Rtti, FMX.DialogService, FMX.Platform,
  // Only for FMX.Objects.TPath, always written in full: System.IOUtils
  // has a TPath too
  FMX.Objects, GDEMAwake,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  GDEMTiles, GDEMDownloadBatch, GDEMDrawing, GDEMMapTiles, GDEMTileSet, GDEMGpuPreference,
  GDEMTerrain, GDEMSystemInfo, GDEMTerrainHud, SettingsForm, MarkersForm, BookmarkForm,
  System.DateUtils, System.Generics.Defaults, GDEMFlight;

const
  { Ticks of the status timer (a second each) between looks for tiles
    needed ahead of the flight. }
  TILES_AHEAD_TICKS = 3;
  { Tiles ahead are those round where the flight will be in this many
    seconds at its speed now, up to @link(TILES_AHEAD_KM). }
  TILES_AHEAD_SECONDS = 90;
  { The farthest ahead the tiles needed are looked for, kilometres. }
  TILES_AHEAD_KM = 150;
  { The most tiles downloaded ahead at a time. }
  TILES_AHEAD_MAX = 6;
  { Minutes before looking ahead again after a download ahead failed or
    was cancelled. }
  TILES_AHEAD_BACKOFF_MINUTES = 2;

type
  { @abstract(A tile that may be downloaded ahead of the flight.) }
  TAheadCandidate = record
    { Its name, such as @code(N53W003). }
    Name: string;
    { Roughly how far it is from the flight, degrees. }
    Distance: Double;
  end;

{ TfrmMain }

{$IF defined(LINUX) and not defined(ANDROID)}
procedure TfrmMain.UseFmxMenuBar;
var
  LCopies: TArray<TMenuItem>;
  LNames: TArray<string>;
  LIndex: Integer;

  { Copies a menu item and its submenus onto a new parent, noting the
    original's name for later.
    @param(AItem The item to copy.)
    @param(AParent The menu bar or menu item the copy goes in.) }
  procedure CopyItem(AItem: TMenuItem; AParent: TFmxObject);
  var
    LCopy: TMenuItem;
    LSub: Integer;
  begin
    // Owned by the form, so naming it later sets the form's field
    LCopy := TMenuItem.Create(Self);
    LCopy.Text := AItem.Text;
    LCopy.Enabled := AItem.Enabled;
    LCopy.Visible := AItem.Visible;
    LCopy.AutoCheck := AItem.AutoCheck;
    LCopy.IsChecked := AItem.IsChecked;
    LCopy.RadioItem := AItem.RadioItem;
    LCopy.GroupIndex := AItem.GroupIndex;
    LCopy.ShortCut := AItem.ShortCut;
    LCopy.Tag := AItem.Tag;
    LCopy.OnClick := AItem.OnClick;
    LCopy.Parent := AParent;
    LCopies := LCopies + [LCopy];
    LNames := LNames + [AItem.Name];
    for LSub := 0 to AItem.ItemsCount - 1 do
      CopyItem(AItem.Items[LSub], LCopy);
  end;

begin
  FFmxMenuBar := TMenuBar.Create(Self);
  FFmxMenuBar.Parent := Self;
  // Top-aligned controls are laid out in the order of their positions, so
  // this puts the menu bar above everything else at the top
  FFmxMenuBar.Position.Y := -1;
  FFmxMenuBar.Align := TAlignLayout.Top;
  for LIndex := 0 to mnuMain.ItemsCount - 1 do
    if mnuMain.Items[LIndex] is TMenuItem then
      CopyItem(TMenuItem(mnuMain.Items[LIndex]), FFmxMenuBar);

  // Empty mnuMain item by item: each removal makes FMX rebuild the GTK menu
  // bar without that item, so it ends up empty and goes. Freeing mnuMain
  // with items still in it left a GTK bar showing their first letters.
  // Each original's field on the form is set to nil as it goes.
  while mnuMain.ItemsCount > 0 do
    mnuMain.Items[0].Free;
  mnuMain.RecreateOSMenu;
  FreeAndNil(mnuMain);

  // Naming a copy points the form's field of that name at it
  for LIndex := 0 to High(LCopies) do
    if LNames[LIndex] <> '' then
      LCopies[LIndex].Name := LNames[LIndex];
end;
{$ENDIF}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  {$IF defined(MACOS) and not defined(IOS)}
  mnuFileSep.Visible := False;
  mnuExit.Visible := False;
  {$ENDIF}
  {$IF defined(LINUX) and not defined(ANDROID)}
  UseFmxMenuBar;
  {$ENDIF}


  FMap := TWorldMapView.Create(Self);
  FMap.Parent := layMap;
  FMap.Align := TAlignLayout.Client;
  FMap.OnSelectionChanged := MapSelectionChanged;
  FMap.OnSelectionChanging := MapSelectionChanging;
  FMap.OnHover := MapHover;
  FMap.OnRightClick := MapRightClick;
  FMap.OnMarkerClick := MapMarkerClick;
  FMap.OnMouseDown := MapMouseDown;
  FVectors := TWorldVectors.Create;
  LoadWorldMap;

  FTileIndex := TTileIndex.Create;
  FDownloaded := TTileIndex.Create;
  FMap.TileIndex := FTileIndex;
  FMap.DownloadedIndex := FDownloaded;

  FSettings := TGDEMSettings.Create;
  try
    FHaveSettings := FSettings.Load;
  except
    on E: Exception do
    begin
      ReportError(E.Message);
      FHaveSettings := False;
    end;
  end;

  // Before anything is shown, so no window appears in the wrong look
  if ThemeFromKey(FSettings.Theme) <> thDefault then
    ApplyThemeSetting(False);

  LoadMapTiles;
  FViewOptions := TViewOptions.Create;
  LoadViewOptions;
  Build3DTab;
  FMarkers := TMarkerList.Create;
  LoadMarkers;
  FMap.Markers := FMarkers;
  // After the menu bar is in place (on Linux, the copy), so the items go
  // under the Bookmarks menu in use
  FBookmarks := TBookmarkList.Create;
  FFlights := TObjectList<TFlightPath>.Create(True);
  LoadBookmarks;
  BuildBookmarksMenu;
  LoadEasterEggs;
  FSearch := TPlaceSearch.Create;
  RebuildSearch;
  // Over the map, under the search box; not focusable, so clicking it
  // leaves the cursor in the box
  FSearchList := TListBox.Create(Self);
  FSearchList.Parent := Self;
  FSearchList.Visible := False;
  FSearchList.CanFocus := False;
  FSearchList.ItemHeight := SEARCH_ITEM_HEIGHT;
  FSearchList.OnItemClick := SearchListItemClick;
  FSearchEdit := edtSearch;
  BuildSearchGoIcon(btnSearchGo);
  LoadTileIndex;
  OpenStore(False);
  MapSelectionChanged(FMap);

  tmrStorage.Interval := STORAGE_CHECK_INTERVAL;
  tmrStorage.Enabled := True;

  // The form is not visible yet, so ask the user anything once it is
  TThread.ForceQueue(nil, RunStartup);
end;

procedure TfrmMain.RunStartup;
begin
  AddLog(DescribeDrawing);
  LogDisplays;
  LogSystem;
  // Each of these waits for the user (or the download) before the next
  if not FHaveSettings then
    ShowSettings(nil)
  else
    CheckTokenExpiry;
  if FNeedIndexBuild then
  begin
    FNeedIndexBuild := False;
    StartIndexBuild;
  end;
  if not FStore.IsAvailable and FSettings.DataFolderUsed then
    WithStore(nil);
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  tmrStorage.Enabled := False;
  // Taken from the 3D view before it goes, and its workers waited for
  CloseImagery;
  if FTerrainView <> nil then
  begin
    FTerrainView.OnBookmark := nil;
    FTerrainView.OnControlsToggle := nil;
    FTerrainView.OnLabelsToggle := nil;
    FTerrainView.OnFlightMoved := nil;
    FTerrainView.OnCrash := nil;
    FTerrainView.OnRestart := nil;
  end;
  FreeAndNil(FBookmarks);
  FreeAndNil(FFlightLog);
  FreeAndNil(FFlights);
  FMap.Vectors := nil;
  FVectors.Free;
  FMap.MapTiles := nil;
  FMapTiles.Free;
  FMap.Markers := nil;
  FMarkers.Free;
  FSearch.Free;
  FViewOptions.Free;
  FStore.Free;
  FSettings.Free;
  FTileIndex.Free;
  FDownloaded.Free;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := (FJob = nil) and (FIndexBuilder = nil);
  if not CanClose then
  begin
    FCloseWhenIdle := True;
    if FJob <> nil then
      FJob.Cancel;
    if FIndexBuilder <> nil then
      FIndexBuilder.Cancel;
    AddLog('Stopping before closing...');
  end;
end;

procedure TfrmMain.CloseIfIdle;
begin
  if FCloseWhenIdle and (FJob = nil) and (FIndexBuilder = nil) then
    Close;
end;

{ Logging and reporting }

procedure TfrmMain.AddLog(const Msg: string);
var
  LMsg: string;
begin
  // Error messages may hold a signed download address
  LMsg := HideURLQueries(Msg);
  TThread.Queue(nil,
    procedure
    begin
      memLog.Lines.Add(LMsg);
      memLog.GoToTextEnd;
    end);
end;

function TfrmMain.CheckTokenExpiry: Boolean;
var
  LExpires: TDateTime;
  LText: string;
begin
  Result := True;
  LText := DescribeTokenExpiry(FSettings.BearerToken);
  if LText = '' then
    Exit;
  AddLog(LText);
  if not TokenExpiry(FSettings.BearerToken, LExpires) then
    Exit;
  if LExpires <= Now then
  begin
    Result := False;
    ReportError(LText + '. Generate a new one at https://urs.earthdata.nasa.gov ' +
      'and paste it into File > Settings.');
  end
  else if LExpires - Now < TOKEN_WARN_DAYS then
    ReportError(LText + '. Generate a new one soon at https://urs.earthdata.nasa.gov ' +
      'and paste it into File > Settings.');
end;

procedure TfrmMain.ReportError(const AMessage: string);
var
  LMsg: string;
begin
  LMsg := HideURLQueries(AMessage);
  AddLog('ERROR: ' + LMsg);
  if FCloseWhenIdle then
    Exit;
  TThread.ForceQueue(nil,
    procedure
    begin
      if FCloseWhenIdle then
        Exit;
      TDialogService.MessageDialog(LMsg, TMsgDlgType.mtError,
        [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0,
        procedure(const AResult: TModalResult)
        begin
          // Nothing to do; the dialog only informs
        end);
    end);
end;

procedure TfrmMain.ShowProgress(ADone, ATotal: Integer);
begin
  if ATotal <= 0 then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      pbDownload.Value := ADone * 100 / ATotal;
    end);
end;

class function TfrmMain.FormatBytes(ABytes: Int64): string;
begin
  Result := FormatByteSize(ABytes);
end;

function TfrmMain.ReserveBytes: Int64;
begin
  if FStore = nil then
    Result := TGDEMStore.ReserveAt(FSettings.DataFolder, FSettings.MinFreePercent)
  else
    Result := FStore.Reserve(FSettings.MinFreePercent);
end;

{ Map }

procedure TfrmMain.LoadWorldMap;
var
  LStream: TResourceStream;
begin
  try
    LStream := TResourceStream.Create(HInstance, WORLD_MAP_RESOURCE, RT_RCDATA);
    try
      FMap.LoadMapFromStream(LStream);
    finally
      LStream.Free;
    end;
  except
    on E: Exception do
      ReportError('Could not load the world map: ' + E.Message);
  end;

  try
    FVectors.LoadFromResource;
    FMap.Vectors := FVectors;
    AddLog('Borders and coastlines: ' + FVectors.Describe +
      ' (Natural Earth, public domain)');
  except
    on E: Exception do
      AddLog('WARNING: could not load the borders and coastlines (' +
        E.Message.TrimRight(['.']) + '); the map is shown without them');
  end;
end;

procedure TfrmMain.LoadMapTiles;
var
  LLevels: TArray<TTileSetLevel>;
begin
  FMap.MapTiles := nil;
  FreeAndNil(FMapTiles);
  // Nothing to switch to without a tile set
  mnuShowMapTiles.Enabled := False;
  try
    FMapTiles := OpenBuiltInMapTiles;
    LLevels := FMapTiles.TileSet.Levels;
    FMapTiles.PreloadLevel(High(LLevels));
    FMap.MapTiles := FMapTiles;
    mnuShowMapTiles.Enabled := True;
    AddLog(Format('Map: tile set "%s", %d x %d in %d levels of %d-pixel tiles, %s',
      [FMapTiles.TileSet.Name, FMapTiles.TileSet.SourceWidth,
       FMapTiles.TileSet.SourceHeight, Length(LLevels), FMapTiles.TileSet.TileSize,
       FMapTiles.Origin]));
    if FMapTiles.Failures > 0 then
      AddLog(Format('WARNING: %d tile(s) of the smallest level could not be read',
        [FMapTiles.Failures]));
  except
    on E: Exception do
    begin
      FMap.MapTiles := nil;
      FreeAndNil(FMapTiles);
      AddLog('WARNING: could not read the high-resolution map (' +
        E.Message.TrimRight(['.']) + '); the plain map is drawn');
    end;
  end;
end;

{ View choices }

procedure TfrmMain.LoadViewOptions;
begin
  try
    FViewOptions.Load;
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message.TrimRight(['.']) + '; using the default view');
  end;
  mnuShowTiles.IsChecked := FViewOptions.ShowAvailableTiles;
  mnuShowDownloaded.IsChecked := FViewOptions.ShowDownloadedTiles;
  mnuShowBorders.IsChecked := FViewOptions.ShowBorders;
  mnuShowCoastlines.IsChecked := FViewOptions.ShowCoastlines;
  mnuShowMapTiles.IsChecked := FViewOptions.ShowMapTiles;
  mnuShowPlaces.IsChecked := FViewOptions.ShowPlaces;
  mnuShowMarkers.IsChecked := FViewOptions.ShowMarkers;
  mnuShowFlightPath.IsChecked := FViewOptions.ShowFlightPath;
  ApplyViewMenu;
end;

procedure TfrmMain.ApplyViewMenu;
begin
  FMap.ShowAvailableTiles := mnuShowTiles.IsChecked;
  FMap.ShowDownloadedTiles := mnuShowDownloaded.IsChecked;
  FMap.ShowBorders := mnuShowBorders.IsChecked;
  FMap.ShowCoastlines := mnuShowCoastlines.IsChecked;
  FMap.ShowMapTiles := mnuShowMapTiles.IsChecked;
  FMap.ShowPlaces := mnuShowPlaces.IsChecked;
  FMap.ShowMarkers := mnuShowMarkers.IsChecked;
  FMap.ShowFlightPath := mnuShowFlightPath.IsChecked;
end;

function TfrmMain.ViewLayerItem(ALayer: TViewLayer): TMenuItem;
begin
  case ALayer of
    vlCoastlines: Result := mnuShowCoastlines;
    vlBorders: Result := mnuShowBorders;
    vlPlaces: Result := mnuShowPlaces;
    vlMapTiles: Result := mnuShowMapTiles;
    vlAvailableTiles: Result := mnuShowTiles;
    vlDownloadedTiles: Result := mnuShowDownloaded;
  else
    Result := mnuShowMarkers;
  end;
end;

procedure TfrmMain.SuggestViewForDrawing(const AOldDrawing, AOldGpuPreference: string);
var
  LOnGpu: Boolean;
  LPreference: TGpuPreference;
  LSuggested, LTurnedOn: TViewLayers;
  LLayer: TViewLayer;
  LItem: TMenuItem;
  LChoice, LOn, LByCost, LMsg: string;
  I: Integer;
begin
  if FViewOptions.DrawingSuggestionMade then
    Exit;
  if SameText(FSettings.Drawing, AOldDrawing) and
     SameText(FSettings.GpuPreference, AOldGpuPreference) then
    Exit;
  LOnGpu := GPU_DRAWING_AVAILABLE and
    (DrawingModeFromKey(FSettings.Drawing) = TDrawingMode.GPU);
  LPreference := GpuPreferenceFromKey(FSettings.GpuPreference);
  LSuggested := SuggestedViewLayers(LOnGpu, LPreference);
  // The CPU keeps the light defaults; a later change may still suggest
  if LSuggested = [] then
    Exit;

  FViewOptions.DrawingSuggestionMade := True;
  LTurnedOn := [];
  for LLayer in LSuggested do
  begin
    LItem := ViewLayerItem(LLayer);
    // The high-resolution map's item is greyed out without a tile set
    if LItem.Enabled and not LItem.IsChecked then
    begin
      LItem.IsChecked := True;
      Include(LTurnedOn, LLayer);
    end;
  end;
  ApplyViewMenu;
  // Saves the flag too, even when nothing needed turning on
  SaveViewOptions;
  if LTurnedOn = [] then
    Exit;

  LChoice := 'drawing on the GPU';
  {$IFDEF MSWINDOWS}
  case LPreference of
    TGpuPreference.HighPerformance:
      LChoice := LChoice + ' with the High performance graphics processor';
    TGpuPreference.PowerSaving:
      LChoice := LChoice + ' with the Power saving graphics processor';
  end;
  {$ENDIF}
  LOn := '';
  LByCost := '';
  for I := Low(VIEW_LAYERS_BY_COST) to High(VIEW_LAYERS_BY_COST) do
  begin
    LItem := ViewLayerItem(VIEW_LAYERS_BY_COST[I]);
    if VIEW_LAYERS_BY_COST[I] in LTurnedOn then
      LOn := LOn + sLineBreak + '    ' + LItem.Text;
    LByCost := LByCost + sLineBreak + Format('    %d. %s', [I + 1, LItem.Text]);
  end;
  LMsg := 'You chose ' + LChoice + ', so these View menu options have been turned on:' +
    LOn + sLineBreak + sLineBreak +
    'The new drawing setting takes effect the next time GDEMFetch starts; until then ' +
    'the map may be slower than it will be.' + sLineBreak + sLineBreak +
    'If the map is slow with these options on, turn some of them off in the View menu ' +
    'until you are happy with it. From the most demanding to the least:' + LByCost;
  AddLog('View: turned on to suit ' + LChoice + ':' +
    LOn.Replace(sLineBreak + '    ', ', ').TrimLeft([',', ' ']));
  TDialogService.MessageDialog(LMsg, TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0,
    procedure(const AResult: TModalResult)
    begin
      // Nothing to do; the dialog only informs
    end);
end;

procedure TfrmMain.SaveViewOptions;
begin
  FViewOptions.ShowAvailableTiles := mnuShowTiles.IsChecked;
  FViewOptions.ShowDownloadedTiles := mnuShowDownloaded.IsChecked;
  FViewOptions.ShowBorders := mnuShowBorders.IsChecked;
  FViewOptions.ShowCoastlines := mnuShowCoastlines.IsChecked;
  FViewOptions.ShowMapTiles := mnuShowMapTiles.IsChecked;
  FViewOptions.ShowPlaces := mnuShowPlaces.IsChecked;
  FViewOptions.ShowMarkers := mnuShowMarkers.IsChecked;
  FViewOptions.ShowFlightPath := mnuShowFlightPath.IsChecked;
  try
    FViewOptions.Save;
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message.TrimRight(['.']) + '; the View menu will not be remembered');
  end;
end;

{ 3D tab }

procedure TfrmMain.Build3DTab;
var
  LX: Single;

  { Adds a control to the toolbar, left to right.
    @param(AControl The control.)
    @param(AWidth Its width.)
    @param(AGap Space after it.) }
  procedure AddToBar(AControl: TControl; AWidth, AGap: Single);
  begin
    AControl.Parent := FTerrainBar;
    // Left-aligned controls are laid out in the order of their positions,
    // so each goes to its place before it is aligned; set the other way
    // round, FMX had already moved the first one
    AControl.Position.X := LX;
    AControl.Width := AWidth;
    AControl.Align := TAlignLayout.Left;
    AControl.Margins.Right := AGap;
    LX := LX + AWidth + AGap;
  end;

  { A caption for the toolbar.
    @param(AText The caption.)
    @returns(The label.) }
  function BarLabel(const AText: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Text := AText;
    Result.TextSettings.HorzAlign := TTextAlign.Trailing;
  end;

var
  I: Integer;
begin
  FTerrainUpdating := True;
  try
    // Every start is in Launch Mode
    swClick3D.IsChecked := True;
    swClick3DSwitch(swClick3D);
    tabMain.OnChange := TabMainChange;
    FLastFetchTiles := -1;
    FFoundEgg := -1;
    FStatusTimer := TTimer.Create(Self);
    FStatusTimer.Interval := 1000;
    FStatusTimer.OnTimer := StatusTimerTick;
    FStatusTimer.Enabled := True;
    FTerrainBar := TLayout.Create(Self);
    FTerrainBar.Parent := tab3D;
    FTerrainBar.Align := TAlignLayout.Top;
    FTerrainBar.Height := 40;
    FTerrainBar.Padding.Rect := RectF(8, 6, 8, 6);
    LX := 8;

    AddToBar(BarLabel('Detail'), 44, 6);
    FTerrainDetailBox := TComboBox.Create(Self);
    for I := 0 to High(TERRAIN_DETAILS) do
      FTerrainDetailBox.Items.Add(Format('%s (%d)', [TERRAIN_DETAIL_NAMES[I], TERRAIN_DETAILS[I]]));
    FTerrainDetailBox.ItemIndex := 1;
    for I := 0 to High(TERRAIN_DETAILS) do
      if TERRAIN_DETAILS[I] = FViewOptions.TerrainDetail then
        FTerrainDetailBox.ItemIndex := I;
    FTerrainDetailBox.OnChange := TerrainDetailChange;
    AddToBar(FTerrainDetailBox, 150, 16);

    AddToBar(BarLabel('Heights'), 52, 6);
    FTerrainHeightsBox := TComboBox.Create(Self);
    for I := 0 to High(TERRAIN_HEIGHTS) do
      FTerrainHeightsBox.Items.Add(Format('%d' + #$00D7, [TERRAIN_HEIGHTS[I]]));
    FTerrainHeightsBox.ItemIndex := 1;
    for I := 0 to High(TERRAIN_HEIGHTS) do
      if TERRAIN_HEIGHTS[I] = FViewOptions.TerrainHeights then
        FTerrainHeightsBox.ItemIndex := I;
    FTerrainHeightsBox.OnChange := TerrainHeightsChange;
    AddToBar(FTerrainHeightsBox, 70, 16);

    AddToBar(BarLabel('Distance'), 60, 6);
    FTerrainRangeBox := TComboBox.Create(Self);
    for I := 0 to High(TERRAIN_RANGES) do
      FTerrainRangeBox.Items.Add(TERRAIN_RANGE_NAMES[I]);
    FTerrainRangeBox.ItemIndex := 1;
    for I := 0 to High(TERRAIN_RANGES) do
      if TERRAIN_RANGES[I] = FViewOptions.TerrainRange then
        FTerrainRangeBox.ItemIndex := I;
    FTerrainRangeBox.OnChange := TerrainRangeChange;
    AddToBar(FTerrainRangeBox, 90, 16);

    FTerrainRealisticBox := TCheckBox.Create(Self);
    FTerrainRealisticBox.Text := 'Realistic';
    FTerrainRealisticBox.IsChecked := FViewOptions.TerrainRealistic;
    FTerrainRealisticBox.OnChange := TerrainRealisticChange;
    AddToBar(FTerrainRealisticBox, 84, 16);

    FTerrainLabelsBox := TCheckBox.Create(Self);
    FTerrainLabelsBox.Text := 'Flags';
    FTerrainLabelsBox.IsChecked := FViewOptions.TerrainLabels;
    FTerrainLabelsBox.OnChange := TerrainLabelsChange;
    AddToBar(FTerrainLabelsBox, 70, 16);

    FTerrainAutopilotBox := TCheckBox.Create(Self);
    FTerrainAutopilotBox.Text := 'Autopilot';
    FTerrainAutopilotBox.Hint := 'Keeps you at least 50 m above the ground ahead';
    FTerrainAutopilotBox.IsChecked := FViewOptions.TerrainAutopilot;
    FTerrainAutopilotBox.OnChange := TerrainAutopilotChange;
    AddToBar(FTerrainAutopilotBox, 84, 4);

    FTerrainHugBox := TCheckBox.Create(Self);
    FTerrainHugBox.Text := 'Hug ground';
    FTerrainHugBox.Hint := 'Keeps you 25 to 75 m above the ground, aiming at 50 m';
    FTerrainHugBox.IsChecked := FViewOptions.TerrainGroundHug and FViewOptions.TerrainAutopilot;
    FTerrainHugBox.OnChange := TerrainHugChange;
    AddToBar(FTerrainHugBox, 96, 16);

    // A copy of the Map tab's search, whose matches are flown to
    AddToBar(BarLabel('Search'), 52, 6);
    FTerrainSearch := TEdit.Create(Self);
    FTerrainSearch.TextPrompt := 'Place, mountain or marker';
    FTerrainSearch.OnChangeTracking := edtSearchChangeTracking;
    FTerrainSearch.OnKeyDown := edtSearchKeyDown;
    FTerrainSearch.OnEnter := edtSearchEnter;
    FTerrainSearch.OnClick := edtSearchClick;
    AddToBar(FTerrainSearch, 236, 4);
    FTerrainSearchGo := TButton.Create(Self);
    FTerrainSearchGo.OnClick := TerrainSearchGoClick;
    FTerrainSearchGo.OnApplyStyleLookup := btnSearchGoApplyStyleLookup;
    FTerrainSearchGo.Hint := 'Fly there';
    AddToBar(FTerrainSearchGo, 32, 16);
    BuildSearchGoIcon(FTerrainSearchGo);
  finally
    FTerrainUpdating := False;
  end;
end;

function TfrmMain.ChosenTerrainDetail: Integer;
begin
  if InRange(FTerrainDetailBox.ItemIndex, 0, High(TERRAIN_DETAILS)) then
    Result := TERRAIN_DETAILS[FTerrainDetailBox.ItemIndex]
  else
    Result := DEFAULT_TERRAIN_DETAIL;
end;

function TfrmMain.ChosenTerrainHeights: Integer;
begin
  if InRange(FTerrainHeightsBox.ItemIndex, 0, High(TERRAIN_HEIGHTS)) then
    Result := TERRAIN_HEIGHTS[FTerrainHeightsBox.ItemIndex]
  else
    Result := DEFAULT_TERRAIN_HEIGHTS;
end;

procedure TfrmMain.ShowTerrainTile(const ATile: string; AForce: Boolean);
var
  LSouth, LWest: Integer;
begin
  if not AForce and (FTerrainView <> nil) and FTerrainView.HasTerrain and
     (ATile = FTerrainTile) then
    Exit;
  if not FStore.IsAvailable or not TryParseTileName(ATile, LSouth, LWest) then
  begin
    AddLog('WARNING: 3D: the data folder is not available, so ' + ATile +
      ' cannot be shown');
    Exit;
  end;
  try
    if FTerrainView = nil then
    begin
      FTerrainView := TTerrainView.Create(Self);
      FTerrainView.Parent := tab3D;
      FTerrainView.Align := TAlignLayout.Client;
      FTerrainView.TileLookup := TerrainTileInfo;
      FTerrainView.OnSettled := TerrainSettled;
      FTerrainView.OnLog := TerrainLog;
      FTerrainView.OnBookmark := TerrainBookmark;
      FTerrainView.OnControlsToggle := TerrainControlsToggle;
      FTerrainView.ControlsCollapsed := FViewOptions.TerrainControlsCollapsed;
      FTerrainView.OnLabelsToggle := TerrainLabelsToggle;
      FTerrainView.OnFlightMoved := TerrainFlightMoved;
      FTerrainView.OnMouseDown := TerrainMouseDown;
      FTerrainView.OnCrash := TerrainCrash;
      FTerrainView.OnRestart := TerrainRestart;
      FTerrainView.ShowLabels := FViewOptions.TerrainLabels;
      FTerrainView.Autopilot := FViewOptions.TerrainAutopilot;
      FTerrainView.GroundHug := FViewOptions.TerrainGroundHug;
      UpdateTerrainLabels;
    end;
    FTerrainView.MaxDetail := ChosenTerrainDetail;
    FTerrainView.Range := ChosenTerrainRange;
    FTerrainView.Exaggeration := ChosenTerrainHeights;
    FTerrainView.StartHeight := FSettings.FlightStartHeight;
    ApplyTerrainRealistic;
    // A new tile starts the flight again; the same one again keeps it
    FTerrainView.ShowArea(LSouth, LWest, ATile <> FTerrainTile);
    FTerrainTile := ATile;
    mnuAddBookmark.Enabled := True;
    AddLog(Format('3D: showing %s and the tiles round it; detail %d, distance detail %s, ' +
      'heights x %d; the flight starts %d m above the ground', [ATile, ChosenTerrainDetail,
       TERRAIN_RANGE_NAMES[Max(FTerrainRangeBox.ItemIndex, 0)], ChosenTerrainHeights,
       FTerrainView.StartHeight]));
  except
    on E: Exception do
    begin
      AddLog('WARNING: could not show ' + ATile + ' in 3D (' + E.ClassName + ': ' +
        E.Message.TrimRight(['.']) + ')');
    end;
  end;
end;

function TfrmMain.TerrainTileInfo(ASouth, AWest: Integer): TTerrainTileInfo;
var
  LDem, LNum: string;
begin
  Result.DemFile := '';
  if FStore.IsAvailable and FDownloaded.Has(ASouth, AWest) then
  begin
    FStore.TileFiles(ASouth, AWest, LDem, LNum);
    if TFile.Exists(LDem) then
    begin
      Result.Kind := tkLand;
      Result.DemFile := LDem;
      Exit;
    end;
  end;
  // With no tile index yet, any tile might exist
  if FTileIndex.Has(ASouth, AWest) or FTileIndex.IsEmpty then
    Result.Kind := tkMissing
  else
    Result.Kind := tkSea;
end;

procedure TfrmMain.TerrainSettled(Sender: TObject; const AText: string);
var
  LTile: string;
begin
  // Working detail, for the flight log rather than the Debug tab
  FlightLog(AText);
  LTile := FTerrainTile;
  // Measured a moment later, once the meshes have been drawn and so sent
  // to the graphics processor
  TThread.ForceQueue(nil,
    procedure
    begin
      FlightLog('3D: memory with ' + LTile + ' on show: ' + DescribeMemoryUse);
    end, MEMORY_MEASURE_DELAY);
end;

procedure TfrmMain.TerrainLog(Sender: TObject; const AText: string);
begin
  FlightLog(AText);
  // A crash is news; problems are copied by FlightLog
  if AText.StartsWith('3D: crashed') then
    AddLog(AText);
end;

procedure TfrmMain.FlightLog(const AText: string);
var
  LText: string;
begin
  if TThread.CurrentThread.ThreadID <> MainThreadID then
  begin
    LText := AText;
    TThread.Queue(nil,
      procedure
      begin
        FlightLog(LText);
      end);
    Exit;
  end;
  if AText.StartsWith('WARNING') or AText.StartsWith('ERROR') then
    AddLog(AText);
  if FFlightLog = nil then
    try
      FFlightLog := TDownloadReport.Create('flight');
      AddLog('3D: the flight log (settled and memory lines, imagery, tiles fetched ahead) ' +
        'is ' + FFlightLog.FileName);
    except
      on E: Exception do
      begin
        AddLog('WARNING: the flight log could not be made (' + E.Message.TrimRight(['.']) +
          '), so its lines go here');
        FFlightLog := nil;
      end;
    end;
  if FFlightLog <> nil then
    FFlightLog.Add(AText)
  else if not (AText.StartsWith('WARNING') or AText.StartsWith('ERROR')) then
    AddLog(AText);
end;

function TfrmMain.ChosenTerrainRange: Integer;
begin
  if InRange(FTerrainRangeBox.ItemIndex, 0, High(TERRAIN_RANGES)) then
    Result := TERRAIN_RANGES[FTerrainRangeBox.ItemIndex]
  else
    Result := DEFAULT_TERRAIN_RANGE;
end;

procedure TfrmMain.TerrainRangeChange(Sender: TObject);
begin
  if FTerrainUpdating then
    Exit;
  FViewOptions.TerrainRange := ChosenTerrainRange;
  SaveViewOptions;
  RelaunchTerrain;
end;

procedure TfrmMain.SelectTileAt(ALat, ALon: Double; const AName: string);
var
  LTiles: TTileIndex;
begin
  LTiles := TTileIndex.Create;
  try
    LTiles.Add(Floor(ALat), Floor(ALon));
    // Fires OnSelectionChanged, which updates the label and buttons
    FMap.SelectTiles(LTiles, AName);
  finally
    LTiles.Free;
  end;
end;

procedure TfrmMain.btnShow3DClick(Sender: TObject);
var
  LTile: string;
  LSouth, LWest: Integer;
  LLatitude, LLongitude: Double;
begin
  // Only this sends a tile to the 3D tab: selecting on the map only
  // selects, so a click is never taken as asking for 3D
  LTile := Show3DTile;
  if not TryParseTileName(LTile, LSouth, LWest) then
    Exit;
  // The place chosen on the map, when it is in this tile, is where the
  // flight looks at first; otherwise the tile's middle
  if FFlightTargetSet and (Floor(FFlightTargetLatitude) = LSouth) and
     (Floor(FFlightTargetLongitude) = LWest) then
  begin
    LLatitude := FFlightTargetLatitude;
    LLongitude := FFlightTargetLongitude;
    PrepareFlight(LTile, LLatitude, LLongitude,
      procedure
      begin
        FTerrainView.StartLookingAt(LLatitude, LLongitude);
      end);
  end
  else
    PrepareFlight(LTile, LSouth + 0.5, LWest + 0.5,
      procedure
      begin
        FTerrainView.ResetView;
      end);
end;

function TfrmMain.Show3DTile: string;
var
  LNames: TArray<string>;
begin
  Result := '';
  if (FTileIndex <> nil) and not FTileIndex.IsEmpty then
    LNames := SelectedTileNames(FTileIndex)
  else
    LNames := SelectedTileNames(FDownloaded);
  if Length(LNames) = 1 then
    Result := LNames[0];
end;

procedure TfrmMain.PrepareFlight(const ATile: string; ALatitude, ALongitude: Double;
  const APlace: TProc; const AFinish: TProc; ANewFlight: Boolean);
var
  LMissing: TArray<string>;
  LTile: TPoint;
  LDownload: Boolean;
  LBearer: string;
  LStore: TGDEMStore;
  LReserve: Int64;
  LSpeed: TDownloadSpeed;
  LTileName: string;
  LPlace: TProc;
  LToFetch: Integer;
  LTileArg: string;
  LLatitude, LLongitude: Double;
  LPlaceArg, LFinishArg: TProc;
  LNewFlightArg: Boolean;
begin
  // Tiles being fetched ahead of the flight give way: stopped, and this
  // tried again once they have
  if (FJob <> nil) and (FJob = FAheadToken) then
  begin
    FAheadToken.Cancel;
    LTileArg := ATile;
    LLatitude := ALatitude;
    LLongitude := ALongitude;
    LPlaceArg := APlace;
    LFinishArg := AFinish;
    LNewFlightArg := ANewFlight;
    TThread.ForceQueue(nil,
      procedure
      begin
        PrepareFlight(LTileArg, LLatitude, LLongitude, LPlaceArg, LFinishArg, LNewFlightArg);
      end, 200);
    Exit;
  end;
  if FJob <> nil then
  begin
    ReportError('Please wait for the current job to finish, or cancel it, first.');
    Exit;
  end;
  if not FStore.IsAvailable then
  begin
    ReportError('The data folder is not available, so there is no ground to fly over.');
    Exit;
  end;
  LTileName := ATile;
  LPlace := APlace;

  // The tiles the view will load round the place that exist but are not
  // here yet
  LMissing := nil;
  if not FTileIndex.IsEmpty then
    for LTile in TerrainWindowTiles(ALatitude, ALongitude) do
      if FTileIndex.Has(LTile.Y, LTile.X) and not FDownloaded.Has(LTile.Y, LTile.X) then
        LMissing := LMissing + [TileName(LTile.Y, LTile.X)];
  LDownload := Length(LMissing) > 0;
  if LDownload and (FSettings.BearerToken = '') then
  begin
    AddLog(Format('WARNING: %d tile(s) round %s are not downloaded, and there is no bearer ' +
      'token to download them with (File > Settings); they are drawn flat', [Length(LMissing),
       ATile]));
    LDownload := False;
  end
  else if LDownload and not CheckTokenExpiry then
    LDownload := False;
  if LDownload then
    LToFetch := Length(LMissing)
  else
    LToFetch := 0;
  AddLog(Format('3D: preparing for flight at %s %s: %d tile(s) to download', [
    FormatLat(ALatitude), FormatLon(ALongitude), LToFetch]));

  LBearer := FSettings.BearerToken;
  LStore := FStore;
  LReserve := ReserveBytes;
  LSpeed := DownloadSpeedFromKey(FSettings.DownloadSpeed);
  FPrepareCancelled := False;
  FPrepareDone := False;
  FPrepareFinish := AFinish;
  FPrepareNewFlight := ANewFlight;
  if FNextFlightName <> '' then
    FPrepareFlightName := FNextFlightName
  else
    FPrepareFlightName := ATile;
  FNextFlightName := '';
  // The view is hidden until it is ready, so the new place and its
  // imagery are not seen coming in, even behind the dialog
  if FTerrainView <> nil then
    FTerrainView.Covered := True;
  FPrepareToken := TCancelToken.Create;
  // A job, so no other work on the data folder starts meanwhile
  FJob := FPrepareToken;
  TKeepAwake.Acquire('Preparing for flight');
  UpdateButtons;
  BeginProgress('Preparing for flight',
    procedure
    begin
      FPrepareCancelled := True;
      if FPrepareToken <> nil then
        FPrepareToken.Cancel;
      AddLog('Preparing for flight: aborted');
    end,
    True);
  if LDownload then
    ProgressStatus(Format('Downloading %d tile(s) round %s...', [Length(LMissing), ATile]))
  else
    ProgressStatus('Every tile is here.');

  TTask.Run(
    procedure
    var
      LError: string;
    begin
      LError := '';
      try
        if LDownload then
          RunDownloads(FPrepareToken, LMissing, LBearer, LStore, LReserve, LSpeed, 0);
      except
        on E: EOperationCancelled do
          ;
        on E: Exception do
          LError := E.Message;
      end;
      // Queued after the tiles' own marks, so the view finds them
      // downloaded
      TThread.Queue(nil,
        procedure
        begin
          FJob := nil;
          TKeepAwake.Release;
          FreeAndNil(FPrepareToken);
          UpdateButtons;
          RefreshStorageStatus;
          if LError <> '' then
            AddLog('WARNING: preparing for flight: ' + LError +
              '; the tiles not downloaded are drawn flat');
          if not FPrepareCancelled then
          begin
            FLastFetchTiles := LToFetch;
            FLastFetchAt := Now;
          end;
          if FPrepareCancelled then
          begin
            EndProgress;
            CloseIfIdle;
            Exit;
          end;
          // The ground, and its imagery with Realistic on
          ProgressStatus('Making the ground...');
          ShowTerrainTile(LTileName, True);
          if (FTerrainView = nil) or not FTerrainView.HasTerrain then
          begin
            EndProgress;
            Exit;
          end;
          // Made just now on a first flight
          FTerrainView.Covered := True;
          if Assigned(LPlace) then
            LPlace();
          if FPrepareTimer = nil then
          begin
            FPrepareTimer := TTimer.Create(Self);
            FPrepareTimer.Interval := 100;
            FPrepareTimer.OnTimer := PrepareTimerTick;
          end;
          FPrepareTicks := 0;
          FPrepareTimer.Enabled := True;
        end);
    end);

  // Blocks until the dialog closes (on desktop platforms)
  ShowProgressModal;
  {$IFNDEF ANDROID}
  FinishPreparing;
  {$ENDIF}
end;

procedure TfrmMain.FinishPreparing;
var
  LFinish: TProc;
begin
  LFinish := FPrepareFinish;
  FPrepareFinish := nil;
  // Ready or aborted, the view shows again
  if FTerrainView <> nil then
    FTerrainView.Covered := False;
  if not FPrepareDone then
    Exit;
  // A new flight, and its path, from where it now is; so also when the
  // last one crashed and the view was only made again
  if FPrepareNewFlight or (CurrentFlightPath = nil) or CurrentFlightPath.Ended then
    StartFlightPath(FPrepareFlightName);
  tabMain.ActiveTab := tab3D;
  FocusTerrainView;
  if Assigned(LFinish) then
    LFinish();
end;

procedure TfrmMain.PrepareTimerTick(Sender: TObject);
var
  LDone, LTotal: Integer;
  LText: string;
begin
  if FPrepareCancelled or (FTerrainView = nil) then
  begin
    FPrepareTimer.Enabled := False;
    EndProgress;
    {$IFDEF ANDROID}
    FinishPreparing;
    {$ENDIF}
    Exit;
  end;
  Inc(FPrepareTicks);
  FTerrainView.WorkProgress(LDone, LTotal, LText);
  ProgressOverall(LDone, Max(LTotal, 1), LText);
  // Settled, and not straight away: the view needs a tick or two to start
  if (FPrepareTicks > 3) and FTerrainView.Settled then
  begin
    FPrepareTimer.Enabled := False;
    FPrepareDone := True;
    AddLog('3D: ready for flight; ' + LText);
    EndProgress;
    {$IFDEF ANDROID}
    // Android does not block on the dialog, so the tab is shown here
    FinishPreparing;
    {$ENDIF}
  end;
end;

procedure TfrmMain.UpdateTerrainLabels;
var
  LLabels: TArray<TTerrainPlaceLabel>;
  LLabel: TTerrainPlaceLabel;
  I: Integer;
begin
  if FTerrainView = nil then
    Exit;
  LLabels := nil;
  // The easter egg found, if any, before everything: it was looked for
  if InRange(FFoundEgg, 0, High(FEasterEggs)) then
  begin
    LLabel.Name := FEasterEggs[FFoundEgg].Name;
    LLabel.Latitude := FEasterEggs[FFoundEgg].Lat;
    LLabel.Longitude := FEasterEggs[FFoundEgg].Lon;
    LLabel.Kind := tlkFound;
    LLabel.Rank := -2;
    LLabels := LLabels + [LLabel];
  end;
  // Bookmarks, where each was made (the camera's place), then markers,
  // then mountains, then towns and cities by how important Natural Earth
  // makes them
  for I := 0 to FBookmarks.Count - 1 do
  begin
    LLabel.Name := FBookmarks[I].Name;
    LLabel.Latitude := FBookmarks[I].Latitude;
    LLabel.Longitude := FBookmarks[I].Longitude;
    LLabel.Kind := tlkBookmark;
    LLabel.Rank := -1.5;
    LLabels := LLabels + [LLabel];
  end;
  for I := 0 to FMarkers.Count - 1 do
  begin
    LLabel.Name := FMarkers[I].Name;
    LLabel.Latitude := FMarkers[I].Lat;
    LLabel.Longitude := FMarkers[I].Lon;
    LLabel.Kind := tlkMarker;
    LLabel.Rank := -1;
    LLabels := LLabels + [LLabel];
  end;
  if FVectors <> nil then
  begin
    for I := 0 to High(FVectors.Peaks) do
    begin
      LLabel.Name := Format('%s %s m', [FVectors.Peaks[I].Name,
        FormatFloat('#,##0', FVectors.Peaks[I].Elevation)]);
      LLabel.Latitude := FVectors.Peaks[I].Lat;
      LLabel.Longitude := FVectors.Peaks[I].Lon;
      LLabel.Kind := tlkPeak;
      LLabel.Rank := FVectors.Peaks[I].MinZoom - 0.5;
      LLabels := LLabels + [LLabel];
    end;
    for I := 0 to High(FVectors.Places) do
    begin
      LLabel.Name := FVectors.Places[I].Name;
      LLabel.Latitude := FVectors.Places[I].Lat;
      LLabel.Longitude := FVectors.Places[I].Lon;
      LLabel.Kind := tlkPlace;
      LLabel.Rank := FVectors.Places[I].MinZoom;
      LLabels := LLabels + [LLabel];
    end;
  end;
  FTerrainView.PlaceLabels := LLabels;
end;

procedure TfrmMain.TerrainAutopilotChange(Sender: TObject);
begin
  if FTerrainUpdating then
    Exit;
  FViewOptions.TerrainAutopilot := FTerrainAutopilotBox.IsChecked;
  // No hugging without the autopilot
  if not FTerrainAutopilotBox.IsChecked and FTerrainHugBox.IsChecked then
  begin
    FTerrainUpdating := True;
    try
      FTerrainHugBox.IsChecked := False;
    finally
      FTerrainUpdating := False;
    end;
    FViewOptions.TerrainGroundHug := False;
  end;
  SaveViewOptions;
  if FTerrainView <> nil then
  begin
    FTerrainView.Autopilot := FTerrainAutopilotBox.IsChecked;
    FTerrainView.GroundHug := FTerrainHugBox.IsChecked;
  end;
  AddLog(IfThen(FTerrainAutopilotBox.IsChecked, '3D: autopilot on, keeping 50 m clear of ' +
    'the ground', '3D: autopilot off'));
  FocusTerrainView;
end;

procedure TfrmMain.TerrainHugChange(Sender: TObject);
begin
  if FTerrainUpdating then
    Exit;
  FViewOptions.TerrainGroundHug := FTerrainHugBox.IsChecked;
  // Hugging is the autopilot's
  if FTerrainHugBox.IsChecked and not FTerrainAutopilotBox.IsChecked then
  begin
    FTerrainUpdating := True;
    try
      FTerrainAutopilotBox.IsChecked := True;
    finally
      FTerrainUpdating := False;
    end;
    FViewOptions.TerrainAutopilot := True;
  end;
  SaveViewOptions;
  if FTerrainView <> nil then
  begin
    FTerrainView.Autopilot := FTerrainAutopilotBox.IsChecked;
    FTerrainView.GroundHug := FTerrainHugBox.IsChecked;
  end;
  AddLog(IfThen(FTerrainHugBox.IsChecked, '3D: hugging the ground, 25 to 75 m above it',
    '3D: no longer hugging the ground'));
  FocusTerrainView;
end;

procedure TfrmMain.TerrainLabelsChange(Sender: TObject);
begin
  if FTerrainUpdating then
    Exit;
  FViewOptions.TerrainLabels := FTerrainLabelsBox.IsChecked;
  SaveViewOptions;
  if FTerrainView <> nil then
    FTerrainView.ShowLabels := FTerrainLabelsBox.IsChecked;
  FocusTerrainView;
end;

procedure TfrmMain.TerrainFlightMoved(Sender: TObject);
var
  LState: TTerrainFlightState;
  LPath: TFlightPath;
begin
  if (FTerrainView = nil) or not FTerrainView.HasTerrain then
    Exit;
  LState := FTerrainView.FlightState;
  // The path follows the flight whichever tab is showing
  LPath := CurrentFlightPath;
  if (LPath <> nil) and not LPath.Ended then
    LPath.Update(LState.Latitude, LState.Longitude, LState.Heading);
  // How far it has come, on the speed panel
  if LPath <> nil then
    FTerrainView.FlownKm := LPath.DistanceKm
  else
    FTerrainView.FlownKm := -1;
  if tabMain.ActiveTab <> tab3D then
    Exit;
  lblHover.Text := FormatLat(LState.Latitude) + '  ' + FormatLon(LState.Longitude);
  if LastFetchText <> '' then
    lblHover.Text := lblHover.Text + '   ' + LastFetchText;
end;

function TfrmMain.LastFetchText: string;
var
  LSeconds: Int64;
  LAgo: string;
begin
  Result := '';
  if FAheadTiles > 0 then
    Exit(Format('fetching %d tile(s) ahead', [FAheadTiles]));
  if FLastFetchTiles < 0 then
    Exit;
  LSeconds := SecondsBetween(Now, FLastFetchAt);
  if LSeconds < 10 then
    LAgo := 'just now'
  else if LSeconds < 60 then
    LAgo := Format('%d s ago', [LSeconds])
  else if LSeconds < 3600 then
    LAgo := Format('%d min ago', [LSeconds div 60])
  else
    LAgo := Format('%d h %d min ago', [LSeconds div 3600, (LSeconds mod 3600) div 60]);
  if FLastFetchTiles = 0 then
    Result := 'no fetch needed, ' + LAgo
  else if FLastFetchTiles = 1 then
    Result := 'last fetch 1 tile, ' + LAgo
  else
    Result := Format('last fetch %d tiles, %s', [FLastFetchTiles, LAgo]);
end;

procedure TfrmMain.StatusTimerTick(Sender: TObject);
begin
  if tabMain.ActiveTab <> tab3D then
    Exit;
  TerrainFlightMoved(FTerrainView);
  Inc(FAheadTicks);
  if FAheadTicks >= TILES_AHEAD_TICKS then
  begin
    FAheadTicks := 0;
    FetchTilesAhead;
  end;
end;

procedure TfrmMain.FetchTilesAhead;
var
  LState: TTerrainFlightState;
  LAheadLat, LAheadLon, LDistance: Double;
  LSeen: TDictionary<string, Boolean>;
  LCandidates: TList<TAheadCandidate>;
  LTiles: TArray<string>;
  LExpires: TDateTime;
  I: Integer;

  { Adds the tiles of the window round a place that exist but are not
    here, with their distance from the flight.
    @param(ALatitude The place's latitude.)
    @param(ALongitude Its longitude.) }
  procedure AddWindow(ALatitude, ALongitude: Double);
  var
    LName: string;
    LLat, LLon: Double;
    LTile: TPoint;
    LCandidate: TAheadCandidate;
  begin
    for LTile in TerrainWindowTiles(ALatitude, ALongitude) do
    begin
      if not FTileIndex.Has(LTile.Y, LTile.X) or FDownloaded.Has(LTile.Y, LTile.X) then
        Continue;
      LName := TileName(LTile.Y, LTile.X);
      if LSeen.ContainsKey(LName) then
        Continue;
      LSeen.Add(LName, True);
      // From the flight to the tile's middle, roughly, for the order
      LLat := LTile.Y + 0.5 - LState.Latitude;
      LLon := LTile.X + 0.5 - LState.Longitude;
      if LLon > 180 then
        LLon := LLon - 360
      else if LLon < -180 then
        LLon := LLon + 360;
      LLon := LLon * Cos(DegToRad(LState.Latitude));
      LCandidate.Name := LName;
      LCandidate.Distance := Sqrt(Sqr(LLat) + Sqr(LLon));
      LCandidates.Add(LCandidate);
    end;
  end;

begin
  if (FTerrainView = nil) or not FTerrainView.HasTerrain or FTerrainView.Paused or
     (FJob <> nil) or (FAheadToken <> nil) or (Now < FAheadRetryAt) or
     (FSettings.BearerToken = '') or FTileIndex.IsEmpty or not FStore.IsAvailable then
    Exit;
  if TokenExpiry(FSettings.BearerToken, LExpires) and (LExpires <= Now) then
  begin
    // Said once an hour, not every look
    AddLog('WARNING: tiles ahead of the flight are not downloaded, as the bearer token has ' +
      'expired (File > Settings); they are drawn flat');
    FAheadRetryAt := Now + 1 / 24;
    Exit;
  end;

  LState := FTerrainView.FlightState;
  LDistance := Min(LState.Speed * TILES_AHEAD_SECONDS, TILES_AHEAD_KM * 1000);
  DestinationPoint(LState.Latitude, LState.Longitude, LState.Heading, LDistance, LAheadLat,
    LAheadLon);
  LSeen := TDictionary<string, Boolean>.Create;
  LCandidates := TList<TAheadCandidate>.Create;
  try
    // Round the flight too, in case it has outrun the looks ahead
    AddWindow(LState.Latitude, LState.Longitude);
    if LDistance > 1000 then
      AddWindow(LAheadLat, LAheadLon);
    if LCandidates.Count = 0 then
      Exit;
    LCandidates.Sort(TComparer<TAheadCandidate>.Construct(
      function(const A, B: TAheadCandidate): Integer
      begin
        Result := CompareValue(A.Distance, B.Distance);
      end));
    LTiles := nil;
    for I := 0 to Min(LCandidates.Count, TILES_AHEAD_MAX) - 1 do
      LTiles := LTiles + [LCandidates[I].Name];
  finally
    LCandidates.Free;
    LSeen.Free;
  end;

  StartTilesAhead(LTiles);
end;

procedure TfrmMain.StartTilesAhead(const ATiles: TArray<string>);
var
  LTiles: TArray<string>;
  LBearer: string;
  LStore: TGDEMStore;
  LReserve: Int64;
  LSpeed: TDownloadSpeed;
  LToken: TCancelToken;
begin
  LTiles := ATiles;
  FlightLog(Format('3D: downloading %d tile(s) ahead of the flight: %s', [Length(LTiles),
    string.Join(', ', LTiles)]));
  LBearer := FSettings.BearerToken;
  LStore := FStore;
  LReserve := ReserveBytes;
  LSpeed := DownloadSpeedFromKey(FSettings.DownloadSpeed);
  LToken := TCancelToken.Create;
  FAheadToken := LToken;
  FAheadTiles := Length(LTiles);
  // A job, so no other work on the data folder starts meanwhile; the
  // Cancel button on the Map tab stops it
  FJob := LToken;
  UpdateButtons;
  TerrainFlightMoved(FTerrainView);
  TTask.Run(
    procedure
    var
      LBatch: TDownloadBatch;
      LResult: TDownloadBatchResult;
      LError: string;
      LCancelled: Boolean;
    begin
      LError := '';
      LCancelled := False;
      LResult := Default(TDownloadBatchResult);
      try
        LBatch := TDownloadBatch.Create(LBearer, LStore, LReserve, LSpeed);
        try
          // No dialog: the log only, and each tile marked (and its ground
          // made again) as it lands
          LBatch.OnLog := FlightLog;
          LBatch.OnTileDownloaded := QueueMarkDownloaded;
          LResult := LBatch.Run(LToken, LTiles, 0);
        finally
          LBatch.Free;
        end;
      except
        on E: EOperationCancelled do
          LCancelled := True;
        on E: Exception do
          LError := E.Message;
      end;
      // Queued after the tiles' own marks
      TThread.Queue(nil,
        procedure
        begin
          if FJob = LToken then
            FJob := nil;
          FAheadToken := nil;
          FAheadTiles := 0;
          LToken.Free;
          UpdateButtons;
          RefreshStorageStatus;
          if LCancelled then
          begin
            FlightLog('3D: downloading tiles ahead of the flight: cancelled');
            FAheadRetryAt := Now + TILES_AHEAD_BACKOFF_MINUTES / MinsPerDay;
          end
          else if (LError <> '') or (LResult.Failed > 0) then
          begin
            if LError = '' then
              LError := Format('%d tile(s) could not be downloaded', [LResult.Failed]);
            AddLog(Format('WARNING: downloading tiles ahead of the flight: %s; trying again ' +
              'in %d min, and meanwhile they are drawn flat', [HideURLQueries(LError),
               TILES_AHEAD_BACKOFF_MINUTES]));
            FAheadRetryAt := Now + TILES_AHEAD_BACKOFF_MINUTES / MinsPerDay;
          end;
          if LResult.Downloaded > 0 then
          begin
            FLastFetchTiles := LResult.Downloaded;
            FLastFetchAt := Now;
          end;
          if tabMain.ActiveTab = tab3D then
            TerrainFlightMoved(FTerrainView);
          CloseIfIdle;
        end);
    end);
end;

procedure TfrmMain.TabMainChange(Sender: TObject);
begin
  // It belongs to the other tab's box
  HideSearchList;
  // The current flight's path, as it is now, on the map
  if tabMain.ActiveTab = tabMap then
    ShowFlightPathOnMap;
  if tabMain.ActiveTab = tab3D then
    TerrainFlightMoved(FTerrainView)
  else
    lblHover.Text := '';
end;

procedure TfrmMain.TerrainLabelsToggle(Sender: TObject);
begin
  if FTerrainView = nil then
    Exit;
  // The box follows; its handler remembers it
  FTerrainLabelsBox.IsChecked := FTerrainView.ShowLabels;
end;

procedure TfrmMain.TerrainRealisticChange(Sender: TObject);
begin
  if FTerrainUpdating then
    Exit;
  FViewOptions.TerrainRealistic := FTerrainRealisticBox.IsChecked;
  SaveViewOptions;
  if FTerrainRealisticBox.IsChecked then
    AddLog('3D: realistic, with ' + ImageryCredit(ImageryService.Layer))
  else
    AddLog('3D: height colours');
  RelaunchTerrain;
end;

function TfrmMain.ImageryService: TImageryService;
var
  LLayer, LRoot: string;
begin
  if FImagery = nil then
  begin
    LLayer := Trim(FSettings.ImageryLayer);
    if LLayer = '' then
      LLayer := DEFAULT_IMAGERY_LAYER;
    // Cached in the data folder when it is there; otherwise downloaded
    // each time, and kept only in memory
    if FStore.IsAvailable then
      LRoot := FStore.ImageryFolder(IMAGERY_FOLDER_NAME)
    else
    begin
      LRoot := '';
      AddLog('WARNING: the data folder is not available, so imagery is not kept on disk');
    end;
    FImagery := TImageryService.Create(LLayer, LRoot, FSettings.ImageryCacheMB);
  end;
  Result := FImagery;
end;

procedure TfrmMain.CloseImagery;
begin
  if FTerrainView <> nil then
    FTerrainView.Imagery := nil;
  FreeAndNil(FImagery);
end;

procedure TfrmMain.ApplyTerrainRealistic;
begin
  if FTerrainView = nil then
    Exit;
  // The service is made only once imagery is first wanted
  if FViewOptions.TerrainRealistic then
    FTerrainView.Imagery := ImageryService;
  FTerrainView.Realistic := FViewOptions.TerrainRealistic;
end;

procedure TfrmMain.FocusTerrainView;
begin
  if (FTerrainView <> nil) and (tabMain.ActiveTab = tab3D) then
    FTerrainView.SetFocus;
end;

procedure TfrmMain.swClick3DSwitch(Sender: TObject);
begin
  if swClick3D.IsChecked then
    lblClick3D.Text := LAUNCH_MODE_CAPTION
  else
    lblClick3D.Text := FETCH_MODE_CAPTION;
  Caption := APP_TITLE + ' - ' + lblClick3D.Text;
end;

procedure TfrmMain.TerrainDetailChange(Sender: TObject);
begin
  if FTerrainUpdating then
    Exit;
  FViewOptions.TerrainDetail := ChosenTerrainDetail;
  SaveViewOptions;
  RelaunchTerrain;
end;

procedure TfrmMain.TerrainHeightsChange(Sender: TObject);
begin
  if FTerrainUpdating then
    Exit;
  FViewOptions.TerrainHeights := ChosenTerrainHeights;
  SaveViewOptions;
  AddLog(Format('3D: heights x %d', [ChosenTerrainHeights]));
  RelaunchTerrain;
end;

procedure TfrmMain.RelaunchTerrain;
begin
  if (FTerrainView = nil) or not FTerrainView.HasTerrain then
    Exit;
  TThread.ForceQueue(nil,
    procedure
    var
      LState: TTerrainFlightState;
      LSpeed: Double;
    begin
      if (FTerrainView = nil) or not FTerrainView.HasTerrain then
        Exit;
      // Hovering while it is made again, then off at the same speed
      LState := FTerrainView.FlightState;
      LSpeed := LState.Speed;
      LState.Speed := 0;
      PrepareFlight(TileNameAt(LState.Latitude, LState.Longitude), LState.Latitude,
        LState.Longitude,
        procedure
        begin
          FTerrainView.JumpTo(LState);
        end,
        procedure
        begin
          if LSpeed > 0 then
            FTerrainView.FlightSpeed := LSpeed;
        end, False);
    end);
end;

procedure TfrmMain.TerrainSearchGoClick(Sender: TObject);
begin
  FSearchEdit := FTerrainSearch;
  LaunchSearchChoice;
end;

procedure TfrmMain.TerrainMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  HideSearchList;
end;

{ Markers and search }

{ Bookmarks }

procedure TfrmMain.LoadBookmarks;
begin
  try
    if FBookmarks.Load then
      AddLog(Format('Bookmarks: %d in %d folder(s), from %s', [FBookmarks.Count,
        FBookmarks.FolderCount, FBookmarks.FileName]));
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message.TrimRight(['.']) +
        '; starting with no bookmarks, and the file is left as it is until one is added');
  end;
end;

function TfrmMain.SaveBookmarks: Boolean;
begin
  try
    FBookmarks.Save;
    Result := True;
  except
    on E: Exception do
    begin
      ReportError('The bookmark could not be saved: ' + E.Message);
      Result := False;
    end;
  end;
end;

procedure TfrmMain.BuildBookmarksMenu;
var
  I: Integer;
  LNone: TMenuItem;
begin
  // Every change to the bookmarks comes here, so their flags in the 3D
  // view follow too
  UpdateTerrainLabels;
  if mnuBookmarks = nil then
    Exit;
  // Everything under the line, made last time
  for I := mnuBookmarks.ItemsCount - 1 downto 0 do
    if mnuBookmarks.Items[I].TagString <> '' then
      mnuBookmarks.Items[I].Free;
  if FBookmarks.Count + FBookmarks.FolderCount = 0 then
  begin
    LNone := TMenuItem.Create(Self);
    LNone.Text := 'No bookmarks yet';
    LNone.Enabled := False;
    LNone.TagString := 'none';
    LNone.Parent := mnuBookmarks;
  end
  else
    AddBookmarkItems(mnuBookmarks, BOOKMARK_ROOT);
  mnuAddBookmark.Enabled := True;
  // The system's own menu bar is made again from the items; on Linux the
  // FMX menu bar shows them as they are
  if mnuMain <> nil then
    mnuMain.RecreateOSMenu;
end;

procedure TfrmMain.AddBookmarkItems(AParent: TMenuItem; AFolder: Integer);
var
  LIndex: Integer;
  LItem, LEmpty: TMenuItem;
  LFolder: TBookmarkFolder;
begin
  // Folders first, as submenus, then the bookmarks, each in its order
  for LIndex in FBookmarks.FoldersIn(AFolder) do
  begin
    LFolder := FBookmarks.Folders[LIndex];
    LItem := TMenuItem.Create(Self);
    // An ampersand would make the next letter a shortcut
    LItem.Text := LFolder.Name.Replace('&', '&&');
    LItem.TagString := 'folder';
    LItem.Parent := AParent;
    AddBookmarkItems(LItem, LFolder.Id);
    if LItem.ItemsCount = 0 then
    begin
      LEmpty := TMenuItem.Create(Self);
      LEmpty.Text := '(empty)';
      LEmpty.Enabled := False;
      LEmpty.TagString := 'none';
      LEmpty.Parent := LItem;
    end;
  end;
  for LIndex in FBookmarks.BookmarksIn(AFolder) do
  begin
    LItem := TMenuItem.Create(Self);
    LItem.Text := FBookmarks[LIndex].Name.Replace('&', '&&');
    LItem.Tag := LIndex;
    LItem.TagString := 'bookmark';
    LItem.OnClick := BookmarkMenuClick;
    LItem.Parent := AParent;
  end;
end;

procedure TfrmMain.BookmarkMenuClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    GoToBookmark(TMenuItem(Sender).Tag);
end;

procedure TfrmMain.GoToBookmark(AIndex: Integer);
var
  LBookmark: TBookmark;
begin
  if (AIndex < 0) or (AIndex >= FBookmarks.Count) then
    Exit;
  LBookmark := FBookmarks[AIndex];
  FNextFlightName := 'Bookmark: ' + LBookmark.Name;

  // The ground round it; then, hidden behind the dialog, drawn as it was
  // and the flight back from its flag along its heading, at its height,
  // looking at the flag; it sets off at its speed once the dialog has
  // closed
  PrepareFlight(TileNameAt(LBookmark.Latitude, LBookmark.Longitude), LBookmark.Latitude,
    LBookmark.Longitude,
    procedure
    var
      I: Integer;
    begin
      // The boxes follow without their handlers, which would take the
      // focus from the dialog
      FTerrainUpdating := True;
      try
        for I := 0 to High(TERRAIN_HEIGHTS) do
          if TERRAIN_HEIGHTS[I] = LBookmark.Heights then
            FTerrainHeightsBox.ItemIndex := I;
        FTerrainRealisticBox.IsChecked := LBookmark.Realistic;
      finally
        FTerrainUpdating := False;
      end;
      FViewOptions.TerrainHeights := ChosenTerrainHeights;
      FViewOptions.TerrainRealistic := FTerrainRealisticBox.IsChecked;
      SaveViewOptions;
      FTerrainView.Exaggeration := ChosenTerrainHeights;
      ApplyTerrainRealistic;
      FTerrainView.StartLookingAlong(LBookmark.Latitude, LBookmark.Longitude,
        LBookmark.Heading, LBookmark.Altitude, LBookmark.AboveGround, LBookmark.Tilt);
    end,
    procedure
    begin
      if (FTerrainView <> nil) and (LBookmark.Speed > 0) then
        FTerrainView.FlightSpeed := LBookmark.Speed;
    end);
  AddLog(Format('3D: bookmark "%s": %s %s, %s, heading %.0f, %s km/h, camera %.0f ' +
    'degrees down, heights x %d%s', [LBookmark.Name, FormatLat(LBookmark.Latitude),
     FormatLon(LBookmark.Longitude), FormatHudHeight(LBookmark.Altitude), LBookmark.Heading,
     FormatFloat('#,##0', LBookmark.Speed * 3.6), LBookmark.Tilt, LBookmark.Heights,
     IfThen(LBookmark.Realistic, ', realistic', '')]));
end;

procedure TfrmMain.TerrainControlsToggle(Sender: TObject);
begin
  if (FTerrainView = nil) or (FViewOptions = nil) then
    Exit;
  FViewOptions.TerrainControlsCollapsed := FTerrainView.ControlsCollapsed;
  SaveViewOptions;
end;

procedure TfrmMain.mnuAddBookmarkClick(Sender: TObject);
begin
  // With a 3D view, its place can be bookmarked; without, typed
  // coordinates only
  if (FTerrainView <> nil) and FTerrainView.HasTerrain then
    tabMain.ActiveTab := tab3D;
  TerrainBookmark(FTerrainView);
end;

procedure TfrmMain.TerrainBookmark(Sender: TObject);
var
  LState: TTerrainFlightState;
  LHaveCurrent, LWasPaused: Boolean;
  LCopy: TBookmarkList;
  LHeights: Integer;
  LRealistic: Boolean;
begin
  // The moment the key was pressed, held still while the dialog is open;
  // with no 3D view, only typed coordinates can be bookmarked
  LHaveCurrent := (FTerrainView <> nil) and FTerrainView.HasTerrain;
  LWasPaused := False;
  if LHaveCurrent then
  begin
    LState := FTerrainView.FlightState;
    LWasPaused := FTerrainView.Paused;
    FTerrainView.Paused := True;
  end
  else
    LState := Default(TTerrainFlightState);
  LHeights := ChosenTerrainHeights;
  LRealistic := FViewOptions.TerrainRealistic;
  // The dialog adds folders to a copy, so Cancel leaves the list as it was
  LCopy := TBookmarkList.Create(FBookmarks.FileName);
  LCopy.Assign(FBookmarks);
  TfrmBookmark.Ask(LCopy, FLastBookmarkFolder, LHaveCurrent, LState.Latitude, LState.Longitude,
    Max(FSettings.FlightStartHeight, 0),
    procedure(const AResult: TBookmarkDialogResult)
    var
      LBookmark: TBookmark;
    begin
      try
        if AResult.Ok then
        begin
          LBookmark := Default(TBookmark);
          LBookmark.Folder := AResult.Folder;
          LBookmark.Name := AResult.Name;
          if AResult.UseCurrent then
          begin
            LBookmark.Latitude := LState.Latitude;
            LBookmark.Longitude := LState.Longitude;
            LBookmark.Altitude := LState.Altitude;
            LBookmark.Heading := LState.Heading;
            LBookmark.Speed := LState.Speed;
            LBookmark.Tilt := LState.Tilt;
          end
          else
          begin
            // Typed: the ground there is not known yet, so the height is
            // kept as above it
            LBookmark.Latitude := AResult.Latitude;
            LBookmark.Longitude := AResult.Longitude;
            LBookmark.Altitude := AResult.AboveGround;
            LBookmark.AboveGround := True;
            LBookmark.Heading := AResult.Heading;
            LBookmark.Speed := AResult.SpeedKmh / 3.6;
            LBookmark.Tilt := AResult.Tilt;
          end;
          LBookmark.Heights := LHeights;
          LBookmark.Realistic := LRealistic;
          LBookmark.Made := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
          try
            LCopy.Add(LBookmark);
            FBookmarks.Assign(LCopy);
            FLastBookmarkFolder := AResult.Folder;
            if SaveBookmarks then
              AddLog(Format('Bookmark "%s" added: %s %s, %s%s, heading %.0f, %s km/h',
                [LBookmark.Name, FormatLat(LBookmark.Latitude), FormatLon(LBookmark.Longitude),
                 FormatHudHeight(LBookmark.Altitude),
                 IfThen(LBookmark.AboveGround, ' above the ground', ''), LBookmark.Heading,
                 FormatFloat('#,##0', LBookmark.Speed * 3.6)]));
            BuildBookmarksMenu;
          except
            on E: Exception do
              ReportError('The bookmark could not be added: ' + E.Message);
          end;
        end;
      finally
        LCopy.Free;
        // Carries on as it was before the key
        if LHaveCurrent and (FTerrainView <> nil) then
        begin
          FTerrainView.Paused := LWasPaused;
          FocusTerrainView;
        end;
      end;
    end);
end;

procedure TfrmMain.LoadMarkers;
begin
  try
    if FMarkers.Load then
      AddLog(Format('Markers: %d, from %s', [FMarkers.Count, FMarkers.FileName]));
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message.TrimRight(['.']) +
        '; starting with no markers, and the file is left as it is until one is added');
  end;
end;

function TfrmMain.SaveMarkers: Boolean;
begin
  Result := False;
  try
    FMarkers.Save;
    Result := True;
  except
    on E: Exception do
      ReportError(E.Message);
  end;
  RebuildSearch;
  FMap.MarkersChanged;
  UpdateTerrainLabels;
end;

procedure TfrmMain.LoadEasterEggs;
var
  LSkipped: TArray<string>;
  LReason: string;
begin
  try
    FEasterEggs := GDEMEasterEggs.LoadEasterEggs(LSkipped);
    for LReason in LSkipped do
      AddLog('WARNING: easter egg left out: ' + LReason);
  except
    on E: Exception do
    begin
      FEasterEggs := nil;
      AddLog('WARNING: ' + E.Message.TrimRight(['.']));
    end;
  end;
end;

procedure TfrmMain.RebuildSearch;
begin
  FSearch.Build(FVectors, FMarkers, FEasterEggs);
  // The indexes of shown matches may have changed
  if (FSearchList <> nil) and FSearchList.Visible then
    RunSearch;
end;

procedure TfrmMain.RunSearch;
var
  LHit: TSearchHit;
begin
  if FSearchEdit.Text.Trim = '' then
  begin
    FSearchHits := nil;
    HideSearchList;
    if FSearchEdit = edtSearch then
      FMap.ClearHighlight;
    Exit;
  end;
  FSearchHits := FSearch.Search(FSearchEdit.Text);
  FSearchList.BeginUpdate;
  try
    FSearchList.Clear;
    for LHit in FSearchHits do
      FSearchList.Items.Add(LHit.Text);
    if Length(FSearchHits) = 0 then
      FSearchList.Items.Add('Nothing found')
    else
      FSearchList.ItemIndex := 0;
  finally
    FSearchList.EndUpdate;
  end;
  ShowSearchList;
end;

procedure TfrmMain.ShowSearchList;
var
  LTopRight: TPointF;
  LRows: Integer;
begin
  // Right edges lined up, just under the box, in the form's coordinates
  LTopRight := FSearchEdit.LocalToAbsolute(PointF(FSearchEdit.Width, FSearchEdit.Height + 2));
  LRows := Max(1, FSearchList.Count);
  FSearchList.SetBounds(Max(0, LTopRight.X - SEARCH_LIST_WIDTH), LTopRight.Y,
    Min(SEARCH_LIST_WIDTH, ClientWidth), LRows * SEARCH_ITEM_HEIGHT + 4);
  FSearchList.Visible := True;
  FSearchList.BringToFront;
end;

procedure TfrmMain.HideSearchList;
begin
  if FSearchList <> nil then
    FSearchList.Visible := False;
end;

procedure TfrmMain.GoToHit(const AHit: TSearchHit);
var
  LExtent: TRectF;
  LPlace: TGeoPlace;
  LPeak: TGeoPeak;
  LMarker: TMapMarker;
  LEgg: TEasterEgg;
  LHalfLat, LHalfLon: Double;
begin
  // Markers > Edit Markers can go to one from any tab
  tabMain.ActiveTab := tabMap;
  HideSearchList;
  // The Map tab's box shows what was chosen
  FSearchEdit := edtSearch;
  case AHit.Kind of
    skCountry:
      begin
        LExtent := FVectors.CountryExtent(AHit.Index);
        // All 0 when the country is not in the data
        if (LExtent.Left = 0) and (LExtent.Right = 0) and (LExtent.Top = 0) and
           (LExtent.Bottom = 0) then
          Exit;
        // Bounds hold south in Top and north in Bottom
        FMap.ZoomToArea(LExtent.Bottom, LExtent.Top, LExtent.Left, LExtent.Right);
        FMap.ClearHighlight;
      end;
    skPlace:
      begin
        LPlace := FVectors.Places[AHit.Index];
        FMap.CentreOn(LPlace.Lat, LPlace.Lon);
        FMap.ShowHighlight(LPlace.Lat, LPlace.Lon);
        // Its tile, ready for Show in 3D, which starts looking at it
        SelectTileAt(LPlace.Lat, LPlace.Lon, LPlace.Name);
        SetFlightTarget(LPlace.Lat, LPlace.Lon);
      end;
    skPeak:
      begin
        // Zoomed in round it, ringed, and its tile selected, ready for the
        // 3D tab
        LPeak := FVectors.Peaks[AHit.Index];
        LHalfLat := PEAK_VIEW_KM / 2 / KM_PER_DEGREE;
        LHalfLon := LHalfLat / Max(Cos(DegToRad(LPeak.Lat)), 0.01);
        FMap.ZoomToArea(LPeak.Lat + LHalfLat, LPeak.Lat - LHalfLat,
          LPeak.Lon - LHalfLon, LPeak.Lon + LHalfLon);
        FMap.ShowHighlight(LPeak.Lat, LPeak.Lon);
        SelectTileAt(LPeak.Lat, LPeak.Lon, LPeak.Name);
        SetFlightTarget(LPeak.Lat, LPeak.Lon);
        lblHover.Text := FVectors.PeakText(AHit.Index);
      end;
    skMarker:
      begin
        LMarker := FMarkers[AHit.Index];
        FMap.CentreOn(LMarker.Lat, LMarker.Lon);
        FMap.ShowHighlight(LMarker.Lat, LMarker.Lon);
        SelectTileAt(LMarker.Lat, LMarker.Lon, LMarker.Name);
        SetFlightTarget(LMarker.Lat, LMarker.Lon);
      end;
    skEgg:
      begin
        LEgg := FEasterEggs[AHit.Index];
        if LEgg.SizeKm > 0 then
        begin
          // Half the size each way: a degree of latitude is about 111 km,
          // and a degree of longitude that times the cosine of the latitude
          LHalfLat := LEgg.SizeKm / 2 / KM_PER_DEGREE;
          LHalfLon := LHalfLat / Max(Cos(DegToRad(LEgg.Lat)), 0.01);
          FMap.ZoomToArea(LEgg.Lat + LHalfLat, LEgg.Lat - LHalfLat,
            LEgg.Lon - LHalfLon, LEgg.Lon + LHalfLon);
        end
        else
          FMap.CentreOn(LEgg.Lat, LEgg.Lon);
        FMap.ShowHighlight(LEgg.Lat, LEgg.Lon);
        SelectTileAt(LEgg.Lat, LEgg.Lon, LEgg.Name);
        SetFlightTarget(LEgg.Lat, LEgg.Lon);
        // Found, so it gets a flag in 3D; the others stay hidden
        FFoundEgg := AHit.Index;
        UpdateTerrainLabels;
        if LEgg.Note <> '' then
        begin
          AddLog(LEgg.Name + ': ' + LEgg.Note);
          lblHover.Text := LEgg.Note;
        end;
      end;
  end;
  // Show what was chosen, without searching for it again
  FSearchUpdating := True;
  try
    edtSearch.Text := AHit.Text;
    FSearchChosen := AHit.Text;
    FChosenHit := AHit;
    edtSearch.SelectAll;
  finally
    FSearchUpdating := False;
  end;
end;

procedure TfrmMain.SearchListItemClick(const Sender: TCustomListBox;
  const Item: TListBoxItem);
begin
  if (Item <> nil) and InRange(Item.Index, 0, High(FSearchHits)) then
    ChooseHit(FSearchHits[Item.Index]);
end;

procedure TfrmMain.ChooseHit(const AHit: TSearchHit);
begin
  if FSearchEdit = FTerrainSearch then
    LaunchHit(AHit)
  else
    GoToHit(AHit);
end;

procedure TfrmMain.LaunchHit(const AHit: TSearchHit);
var
  LExtent: TRectF;
  LLatitude, LLongitude: Double;
  LName: string;
begin
  HideSearchList;
  // As Launch Mode: nothing without a bearer token but Settings
  if FSettings.BearerToken = '' then
  begin
    TThread.ForceQueue(nil,
      procedure
      begin
        AddLog('Flying to a place needs a bearer token: File > Settings');
        ShowSettings(nil);
      end);
    Exit;
  end;
  LName := AHit.Text;
  case AHit.Kind of
    skCountry:
      begin
        LExtent := FVectors.CountryExtent(AHit.Index);
        if (LExtent.Left = 0) and (LExtent.Right = 0) and (LExtent.Top = 0) and
           (LExtent.Bottom = 0) then
          Exit;
        // Its middle; bounds hold south in Top and north in Bottom, and
        // east may be past 180
        LLatitude := (LExtent.Top + LExtent.Bottom) / 2;
        LLongitude := (LExtent.Left + LExtent.Right) / 2;
        if LLongitude >= 180 then
          LLongitude := LLongitude - 360;
      end;
    skPlace:
      begin
        LLatitude := FVectors.Places[AHit.Index].Lat;
        LLongitude := FVectors.Places[AHit.Index].Lon;
      end;
    skPeak:
      begin
        LLatitude := FVectors.Peaks[AHit.Index].Lat;
        LLongitude := FVectors.Peaks[AHit.Index].Lon;
      end;
    skMarker:
      begin
        LLatitude := FMarkers[AHit.Index].Lat;
        LLongitude := FMarkers[AHit.Index].Lon;
      end;
    skEgg:
      begin
        LLatitude := FEasterEggs[AHit.Index].Lat;
        LLongitude := FEasterEggs[AHit.Index].Lon;
        // Found, so it gets a flag
        FFoundEgg := AHit.Index;
        UpdateTerrainLabels;
        if FEasterEggs[AHit.Index].Note <> '' then
          AddLog(FEasterEggs[AHit.Index].Name + ': ' + FEasterEggs[AHit.Index].Note);
      end;
  else
    Exit;
  end;
  // Show what was chosen, without searching for it again
  FSearchUpdating := True;
  try
    FSearchEdit.Text := LName;
    FSearchChosen := LName;
    FChosenHit := AHit;
    FSearchEdit.SelectAll;
  finally
    FSearchUpdating := False;
  end;
  // The map follows, ready for Show in 3D
  SelectTileAt(LLatitude, LLongitude, LName);
  SetFlightTarget(LLatitude, LLongitude);
  AddLog(Format('3D: flying to %s, %s %s', [LName, FormatLat(LLatitude),
    FormatLon(LLongitude)]));
  FNextFlightName := LName;
  PrepareFlight(TileNameAt(LLatitude, LLongitude), LLatitude, LLongitude,
    procedure
    begin
      FTerrainView.StartLookingAt(LLatitude, LLongitude);
    end);
end;

procedure TfrmMain.edtSearchChangeTracking(Sender: TObject);
begin
  if Sender is TEdit then
    FSearchEdit := TEdit(Sender);
  if not FSearchUpdating then
  begin
    FSearchPicked := False;
    RunSearch;
  end;
end;

procedure TfrmMain.BuildSearchGoIcon(AButton: TButton);
var
  LIcon: FMX.Objects.TPath;
begin
  AButton.Text := '';
  LIcon := FMX.Objects.TPath.Create(Self);
  LIcon.Parent := AButton;
  LIcon.Align := TAlignLayout.Center;
  LIcon.Width := 18;
  LIcon.Height := 18;
  // Drawn in its own 24 x 24 box, scaled to fit
  LIcon.WrapMode := TPathWrapMode.Fit;
  LIcon.Data.Data := SEARCH_GO_ICON;
  LIcon.Stroke.Kind := TBrushKind.None;
  // The theme's text colour once the button is styled
  LIcon.Fill.Color := TAlphaColors.Black;
  LIcon.HitTest := False;
  AButton.TagObject := LIcon;
  // In case the button was styled already; a later theme change styles it
  // again, which colours the icon through the same handler
  btnSearchGoApplyStyleLookup(AButton);
end;

procedure TfrmMain.GoToSearchChoice;
var
  LIndex: Integer;
begin
  if not FSearchList.Visible then
    RunSearch;
  LIndex := Max(FSearchList.ItemIndex, 0);
  if InRange(LIndex, 0, High(FSearchHits)) then
    ChooseHit(FSearchHits[LIndex]);
end;

procedure TfrmMain.ClearSearchBox;
begin
  FSearchChosen := '';
  if FSearchEdit.Text <> '' then
    // Taken as typing, so the list closes and the ring goes
    FSearchEdit.Text := '';
end;

procedure TfrmMain.edtSearchEnter(Sender: TObject);
begin
  if Sender is TEdit then
    FSearchEdit := TEdit(Sender);
  ClearSearchBox;
end;

procedure TfrmMain.edtSearchClick(Sender: TObject);
begin
  if Sender is TEdit then
    FSearchEdit := TEdit(Sender);
  if (FSearchChosen <> '') and (FSearchEdit.Text = FSearchChosen) then
    ClearSearchBox;
end;

procedure TfrmMain.btnSearchGoClick(Sender: TObject);
begin
  // The arrow flies there; Enter only goes there on the map
  FSearchEdit := edtSearch;
  LaunchSearchChoice;
end;

function TfrmMain.UniqueSearchHit(out AHit: TSearchHit): Boolean;
var
  LHits: TArray<TSearchHit>;
  LHit: TSearchHit;
  LExact: Integer;
begin
  Result := False;
  if FSearchEdit.Text.Trim = '' then
    Exit;
  // Chosen from the list, and still showing
  if (FSearchChosen <> '') and (FSearchEdit.Text = FSearchChosen) then
  begin
    AHit := FChosenHit;
    Exit(True);
  end;
  // Picked with Up or Down
  if FSearchPicked and FSearchList.Visible and
     InRange(FSearchList.ItemIndex, 0, High(FSearchHits)) then
  begin
    AHit := FSearchHits[FSearchList.ItemIndex];
    Exit(True);
  end;
  LHits := FSearch.Search(FSearchEdit.Text);
  if Length(LHits) = 1 then
  begin
    AHit := LHits[0];
    Exit(True);
  end;
  // Several, but only one by exactly that name
  LExact := 0;
  for LHit in LHits do
    if LHit.Match = smExact then
    begin
      Inc(LExact);
      AHit := LHit;
    end;
  Result := LExact = 1;
end;

procedure TfrmMain.LaunchSearchChoice;
var
  LHit: TSearchHit;
begin
  if UniqueSearchHit(LHit) then
    LaunchHit(LHit)
  else if FSearchEdit.Text.Trim <> '' then
  begin
    // Not one place: the matches, to choose from
    RunSearch;
    lblHover.Text := 'Choose one of the matches to fly there.';
  end;
end;

procedure TfrmMain.btnSearchGoApplyStyleLookup(Sender: TObject);
var
  LButton: TButton;
begin
  if not (Sender is TButton) then
    Exit;
  LButton := TButton(Sender);
  if LButton.TagObject is FMX.Objects.TPath then
    FMX.Objects.TPath(LButton.TagObject).Fill.Color := LButton.ResultingTextSettings.FontColor;
end;

procedure TfrmMain.edtSearchKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  LIndex: Integer;
begin
  if Sender is TEdit then
    FSearchEdit := TEdit(Sender);
  case Key of
    vkDown, vkUp:
      begin
        if not FSearchList.Visible then
          RunSearch
        else if Length(FSearchHits) > 0 then
        begin
          LIndex := FSearchList.ItemIndex;
          if Key = vkDown then
            Inc(LIndex)
          else
            Dec(LIndex);
          FSearchList.ItemIndex := EnsureRange(LIndex, 0, High(FSearchHits));
          FSearchPicked := True;
        end;
        Key := 0;
      end;
    vkReturn:
      begin
        // On the 3D tab Enter flies there, as the arrow does; on the map
        // it goes there
        if FSearchEdit = FTerrainSearch then
          LaunchSearchChoice
        else
          GoToSearchChoice;
        Key := 0;
        KeyChar := #0;
      end;
    vkEscape:
      begin
        if FSearchList.Visible then
          HideSearchList
        else if FSearchEdit = edtSearch then
          FMap.ClearHighlight;
        Key := 0;
      end;
  end;
end;

procedure TfrmMain.LogSystem;
var
  LLine: string;
begin
  for LLine in DescribeSystem do
    AddLog(LLine);
end;

procedure TfrmMain.LogDisplays;
var
  I: Integer;
  LDisplay: TDisplay;
  LText: string;
  LLeft, LTop, LWidth, LHeight, LScale: Single;
begin
  for I := 0 to Screen.DisplayCount - 1 do
  begin
    LDisplay := Screen.Displays[I];
    // Copied to Singles so the format suits whichever type Bounds is
    LLeft := LDisplay.Bounds.Left;
    LTop := LDisplay.Bounds.Top;
    LWidth := LDisplay.Bounds.Width;
    LHeight := LDisplay.Bounds.Height;
    LScale := LDisplay.Scale;
    LText := Format('Display %d: %.0f x %.0f at %.0f, %.0f, scale %.2f',
      [I + 1, LWidth, LHeight, LLeft, LTop, LScale]);
    if LDisplay.Primary then
      LText := LText + ', primary';
    AddLog(LText);
  end;
end;

procedure TfrmMain.MapMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  HideSearchList;
  // A plain left press selects; with Shift it pans, with Ctrl (Cmd) it
  // marks, neither of which selects
  FMapLeftClick := (Button = TMouseButton.mbLeft) and
    ([ssShift, ssCtrl, ssCommand] * Shift = []);
  // Where it was, to start the flight looking at if this click selects
  if FMapLeftClick then
    FPressOnMap := FMap.ScreenToGeo(PointF(X, Y), FPressLatitude, FPressLongitude);
end;

procedure TfrmMain.SetFlightTarget(ALatitude, ALongitude: Double);
begin
  FFlightTargetSet := True;
  FFlightTargetLatitude := ALatitude;
  FFlightTargetLongitude := ALongitude;
end;

procedure TfrmMain.MapMarkerClick(Sender: TObject; ALat, ALon: Double; AShift: TShiftState);
begin
  AddMarkerAt(ALat, ALon);
end;

procedure TfrmMain.AddMarkerAt(ALat, ALon: Double);
var
  LLat, LLon: Double;
begin
  LLat := ALat;
  LLon := ALon;
  TDialogService.InputQuery('Add Marker',
    [Format('Name for the marker at %s %s', [FormatLat(LLat), FormatLon(LLon)])],
    [Format('Marker %d', [FMarkers.Count + 1])],
    procedure(const AResult: TModalResult; const AValues: array of string)
    var
      LIndex: Integer;
    begin
      if (AResult <> mrOk) or (Length(AValues) = 0) then
        Exit;
      if TMarkerList.CleanName(AValues[0]) = '' then
      begin
        AddLog('No marker added: it needs a name');
        Exit;
      end;
      LIndex := FMarkers.Add(AValues[0], LLat, LLon);
      if SaveMarkers then
        AddLog(Format('Marker "%s" added at %s %s', [FMarkers[LIndex].Name,
          FormatLat(FMarkers[LIndex].Lat), FormatLon(FMarkers[LIndex].Lon)]));
    end);
end;

procedure TfrmMain.mnuFindClick(Sender: TObject);
begin
  // The search box is on the Map tab
  tabMain.ActiveTab := tabMap;
  edtSearch.SetFocus;
  edtSearch.SelectAll;
end;

procedure TfrmMain.mnuShowPlacesClick(Sender: TObject);
begin
  FMap.ShowPlaces := mnuShowPlaces.IsChecked;
  SaveViewOptions;
end;

procedure TfrmMain.mnuShowMarkersClick(Sender: TObject);
begin
  FMap.ShowMarkers := mnuShowMarkers.IsChecked;
  SaveViewOptions;
end;

procedure TfrmMain.mnuShowFlightPathClick(Sender: TObject);
begin
  FMap.ShowFlightPath := mnuShowFlightPath.IsChecked;
  SaveViewOptions;
end;

{ Flight paths }

function TfrmMain.CurrentFlightPath: TFlightPath;
begin
  if (FFlights = nil) or (FFlights.Count = 0) then
    Exit(nil);
  Result := FFlights.Last;
end;

procedure TfrmMain.StartFlightPath(const AName: string);
var
  LState: TTerrainFlightState;
  LPath: TFlightPath;
begin
  if (FTerrainView = nil) or not FTerrainView.HasTerrain then
    Exit;
  LState := FTerrainView.FlightState;
  LPath := CurrentFlightPath;
  if (LPath <> nil) and not LPath.Ended then
  begin
    LPath.Finish(FLIGHT_END_ENDED, LState.Latitude, LState.Longitude, LState.Heading);
    FlightLog(Format('3D: flight path %d ended (%s, %.1f km, %d points)', [FFlights.Count,
      LPath.EndReason, LPath.DistanceKm, LPath.PointCount]));
  end;
  LPath := TFlightPath.Create(LState.Latitude, LState.Longitude, LState.Heading, AName);
  FFlights.Add(LPath);
  FlightLog(Format('3D: flight path %d started at %s %s (%s)', [FFlights.Count,
    FormatLat(LState.Latitude), FormatLon(LState.Longitude), AName]));
end;

procedure TfrmMain.TerrainCrash(Sender: TObject);
var
  LState: TTerrainFlightState;
  LPath: TFlightPath;
begin
  LPath := CurrentFlightPath;
  if (LPath = nil) or LPath.Ended or (FTerrainView = nil) then
    Exit;
  LState := FTerrainView.FlightState;
  LPath.Finish(FLIGHT_END_CRASHED, LState.Latitude, LState.Longitude, LState.Heading);
  AddLog(Format('3D: flight path ended: crashed after %.1f km (%d points)',
    [LPath.DistanceKm, LPath.PointCount]));
end;

procedure TfrmMain.TerrainRestart(Sender: TObject);
begin
  StartFlightPath(FTerrainTile + ', started again');
end;

procedure TfrmMain.ShowFlightPathOnMap;
var
  LPath: TFlightPath;
  LTrack: TArray<TPointF>;
  LNorth, LSouth, LWest, LEast, LLon, LShift, LHalf, LMiddle: Double;
  I: Integer;
begin
  LPath := CurrentFlightPath;
  if LPath = nil then
  begin
    FMap.SetFlightPath(nil, False);
    Exit;
  end;
  LTrack := LPath.Track;
  FMap.SetFlightPath(LTrack, LPath.EndReason = FLIGHT_END_CRASHED);
  // Still flying: the map fits the whole path, with longitudes unwrapped
  // as the map draws them, so a crossing of 180 degrees goes the short way
  if LPath.Ended or (Length(LTrack) = 0) or not FMap.ShowFlightPath then
    Exit;
  LNorth := LTrack[0].Y;
  LSouth := LTrack[0].Y;
  LLon := LTrack[0].X;
  LWest := LLon;
  LEast := LLon;
  for I := 1 to High(LTrack) do
  begin
    LShift := LTrack[I].X - LTrack[I - 1].X;
    LShift := LShift - 360 * Round(LShift / 360);
    LLon := LLon + LShift;
    LWest := Min(LWest, LLon);
    LEast := Max(LEast, LLon);
    LNorth := Max(LNorth, LTrack[I].Y);
    LSouth := Min(LSouth, LTrack[I].Y);
  end;
  // Never closer than a small area round it, so a short flight is not
  // shown blown up to the closest zoom
  LHalf := FLIGHT_PATH_VIEW_KM / 2 / KM_PER_DEGREE;
  if LNorth - LSouth < 2 * LHalf then
  begin
    LMiddle := (LNorth + LSouth) / 2;
    LNorth := LMiddle + LHalf;
    LSouth := LMiddle - LHalf;
  end;
  LHalf := LHalf / Max(Cos(DegToRad((LNorth + LSouth) / 2)), 0.01);
  if LEast - LWest < 2 * LHalf then
  begin
    LMiddle := (LEast + LWest) / 2;
    LWest := LMiddle - LHalf;
    LEast := LMiddle + LHalf;
  end;
  FMap.ZoomToArea(Min(LNorth, 90), Max(LSouth, -90), LWest, LEast);
end;

procedure TfrmMain.SaveFlightPathsAs(const AFlights: TArray<TFlightPathRecord>;
  const AWhat: string);
var
  LDialog: TSaveDialog;
  LFolder: string;
begin
  LDialog := TSaveDialog.Create(nil);
  try
    LFolder := System.IOUtils.TPath.Combine(TGDEMSettings.SettingsFolder, 'Flights');
    try
      ForceDirectories(LFolder);
    except
      // Then the dialog starts wherever the system chooses
    end;
    LDialog.InitialDir := LFolder;
    LDialog.Filter := 'Flight paths (*' + FLIGHT_PATH_EXTENSION + ')|*' + FLIGHT_PATH_EXTENSION +
      '|All files (*.*)|*.*';
    LDialog.DefaultExt := FLIGHT_PATH_EXTENSION.Substring(1);
    LDialog.FileName := FormatDateTime('"flight-"yyyymmdd"-"hhnnss', Now) + FLIGHT_PATH_EXTENSION;
    LDialog.Options := LDialog.Options + [TOpenOption.ofOverwritePrompt];
    if not LDialog.Execute then
      Exit;
    try
      SaveFlightPaths(ChangeFileExt(LDialog.FileName, FLIGHT_PATH_EXTENSION), AFlights);
      AddLog(Format('Saved %s to %s', [AWhat, ChangeFileExt(LDialog.FileName,
        FLIGHT_PATH_EXTENSION)]));
    except
      on E: Exception do
        ReportError(E.Message);
    end;
  finally
    LDialog.Free;
  end;
end;

procedure TfrmMain.mnuSaveFlightPathClick(Sender: TObject);
var
  LPath: TFlightPath;
begin
  LPath := CurrentFlightPath;
  if LPath = nil then
  begin
    ShowMessage('There is no flight path yet: fly in the 3D view first.');
    Exit;
  end;
  SaveFlightPathsAs([LPath.ToRecord], Format('the current flight path (%s, %.1f km)',
    [LPath.EndReason, LPath.DistanceKm]));
end;

procedure TfrmMain.mnuSaveAllFlightPathsClick(Sender: TObject);
var
  LRecords: TArray<TFlightPathRecord>;
  LPath: TFlightPath;
begin
  if (FFlights = nil) or (FFlights.Count = 0) then
  begin
    ShowMessage('There are no flight paths yet: fly in the 3D view first.');
    Exit;
  end;
  LRecords := nil;
  for LPath in FFlights do
    LRecords := LRecords + [LPath.ToRecord];
  SaveFlightPathsAs(LRecords, Format('%d flight path(s)', [Length(LRecords)]));
end;

procedure TfrmMain.mnuAddMarkerClick(Sender: TObject);
var
  LLat, LLon: Double;
begin
  if FMap.ScreenToGeo(PointF(FMap.Width / 2, FMap.Height / 2), LLat, LLon) then
    AddMarkerAt(LLat, LLon);
end;

procedure TfrmMain.mnuEditMarkersClick(Sender: TObject);
begin
  HideSearchList;
  TfrmMarkers.Edit(FMarkers,
    procedure(AGoTo: Integer; AChanged: Boolean)
    var
      LHit: TSearchHit;
    begin
      if AChanged then
      begin
        RebuildSearch;
        FMap.MarkersChanged;
        FMap.ClearHighlight;
      end;
      if InRange(AGoTo, 0, FMarkers.Count - 1) then
      begin
        LHit.Kind := skMarker;
        LHit.Index := AGoTo;
        LHit.Text := FMarkers[AGoTo].Name + ' (marker)';
        LHit.Match := smExact;
        LHit.Mistakes := 0;
        GoToHit(LHit);
      end;
    end);
end;

function TfrmMain.SelectedTileCount(AOnlyIn: TTileIndex): Integer;
var
  LRect: TTileRect;
  LMask: TTileIndex;
  LLat, LLon: Integer;
begin
  Result := 0;
  LRect := FMap.Selection;
  LMask := FMap.SelectionMask;
  for LLat := LRect.South to LRect.North - 1 do
    for LLon := LRect.West to LRect.East - 1 do
      if ((LMask = nil) or LMask.Has(LLat, LLon)) and
         ((AOnlyIn = nil) or AOnlyIn.Has(LLat, LLon)) then
        Inc(Result);
end;

function TfrmMain.SelectedTileNames(AOnlyIn: TTileIndex): TArray<string>;
var
  LRect: TTileRect;
  LMask: TTileIndex;
  LLat, LLon, LIndex: Integer;
begin
  SetLength(Result, SelectedTileCount(AOnlyIn));
  LIndex := 0;
  LRect := FMap.Selection;
  LMask := FMap.SelectionMask;
  for LLat := LRect.North - 1 downto LRect.South do
    for LLon := LRect.West to LRect.East - 1 do
      if ((LMask = nil) or LMask.Has(LLat, LLon)) and
         ((AOnlyIn = nil) or AOnlyIn.Has(LLat, LLon)) then
      begin
        Result[LIndex] := TileName(LLat, LLon);
        Inc(LIndex);
      end;
end;

procedure TfrmMain.UpdateSelectionText;
var
  LSelection: TTileRect;
  LText: string;
begin
  LSelection := FMap.Selection;
  if FMap.SelectionMask <> nil then
    LText := Format('%s: %d tile(s)', [FMap.SelectionName, SelectedTileCount(nil)])
  else
    LText := LSelection.Describe;
  if not LSelection.IsEmpty then
  begin
    if not FTileIndex.IsEmpty then
      LText := LText + Format(', %d with data', [SelectedTileCount(FTileIndex)]);
    LText := LText + Format(', %d downloaded', [SelectedTileCount(FDownloaded)]);
  end;
  lblSelection.Text := LText;
end;

procedure TfrmMain.MapSelectionChanging(Sender: TObject);
begin
  UpdateSelectionText;
end;

procedure TfrmMain.MapSelectionChanged(Sender: TObject);
var
  LClicked: Boolean;
begin
  UpdateSelectionText;
  UpdateButtons;
  LClicked := FMapLeftClick;
  FMapLeftClick := False;
  // A click picks the place to start the flight looking at, as a search
  // does
  if LClicked and FPressOnMap then
    SetFlightTarget(FPressLatitude, FPressLongitude);
  // In Launch Mode the user's own click on a tile flies there, as Show in
  // 3D does, after the click's handling (the dialogs are modal); with no
  // bearer token it asks for one first and does nothing else
  if LClicked and swClick3D.IsChecked then
  begin
    if FSettings.BearerToken = '' then
      TThread.ForceQueue(nil,
        procedure
        begin
          AddLog('Launch Mode needs a bearer token: File > Settings');
          ShowSettings(nil);
        end)
    else if btnShow3D.Enabled then
      TThread.ForceQueue(nil,
        procedure
        begin
          btnShow3DClick(btnShow3D);
        end);
  end;
end;

procedure TfrmMain.MapRightClick(Sender: TObject; ALat, ALon: Double; AShift: TShiftState);
var
  LCountry, LLat, LLon, LIndex: Integer;
  LName: string;
  LCountryTiles, LTiles: TTileIndex;
  LNames: TArray<string>;
  LRect: TTileRect;
  LKnown: Boolean;
begin
  LCountry := FVectors.CountryIndexAt(ALat, ALon);
  if LCountry < 0 then
    Exit;
  LName := FVectors.CountryName(LCountry);
  LCountryTiles := TTileIndex.Create;
  LTiles := TTileIndex.Create;
  try
    FVectors.AddCountryTiles(LCountry, LCountryTiles);
    if LCountryTiles.IsEmpty then
    begin
      ShowMessage(LName + ' lies outside ASTER GDEM coverage.');
      Exit;
    end;

    // Shift adds to what is selected: the tiles of a country selection, or
    // every tile of a dragged block
    LNames := nil;
    if (ssShift in AShift) and not FMap.Selection.IsEmpty then
    begin
      if FMap.SelectionMask <> nil then
      begin
        LTiles.Assign(FMap.SelectionMask);
        if (FSelectionLabel <> '') and (FMap.SelectionName = FSelectionLabel) then
          LNames := FSelectedCountries
        else
          LNames := [FMap.SelectionName];
      end
      else
      begin
        LRect := FMap.Selection;
        for LLat := LRect.South to LRect.North - 1 do
          for LLon := LRect.West to LRect.East - 1 do
            LTiles.Add(LLat, LLon);
        LNames := ['Selected area'];
      end;
    end;
    // A union, so tiles the country shares with the selection count once
    LTiles.AddIndex(LCountryTiles);

    LKnown := False;
    for LIndex := 0 to High(LNames) do
      if SameText(LNames[LIndex], LName) then
        LKnown := True;
    if not LKnown then
      LNames := LNames + [LName];
    FSelectedCountries := LNames;
    FSelectionLabel := DescribeCountries(LNames);
    FMap.SelectTiles(LTiles, FSelectionLabel);
  finally
    LTiles.Free;
    LCountryTiles.Free;
  end;
end;

class function TfrmMain.DescribeCountries(const ANames: TArray<string>): string;
begin
  if Length(ANames) <= 3 then
    Result := string.Join(' + ', ANames)
  else
    Result := Format('%s + %s + %d more', [ANames[0], ANames[1], Length(ANames) - 2]);
end;

procedure TfrmMain.MapHover(Sender: TObject; ALat, ALon: Double; AOnMap: Boolean);
var
  LSouth, LWest: Integer;
  LCountry: string;
begin
  if not AOnMap then
  begin
    lblHover.Text := '';
    Exit;
  end;
  LSouth := Floor(ALat);
  LWest := Floor(ALon);
  lblHover.Text := Format('%s  %s   tile %s',
    [FormatLat(ALat), FormatLon(ALon), TileNameAt(ALat, ALon)]);
  if FDownloaded.Has(LSouth, LWest) then
    lblHover.Text := lblHover.Text + ' (downloaded)'
  else if not FTileIndex.IsEmpty then
  begin
    if FTileIndex.Has(LSouth, LWest) then
      lblHover.Text := lblHover.Text + ' (data)'
    else
      lblHover.Text := lblHover.Text + ' (no data)';
  end;
  LCountry := FVectors.CountryAt(ALat, ALon);
  if LCountry <> '' then
    lblHover.Text := lblHover.Text + '   ' + LCountry;
end;

procedure TfrmMain.UpdateButtons;
var
  LBusy, LHaveSelection: Boolean;
begin
  LBusy := FJob <> nil;
  LHaveSelection := not FMap.Selection.IsEmpty;
  btnFetchSelection.Enabled := not LBusy and LHaveSelection;
  btnCancel.Enabled := LBusy;
  btnShow3D.Enabled := Show3DTile <> '';
  mnuZoomSelection.Enabled := LHaveSelection;
  mnuRefreshIndex.Enabled := FIndexBuilder = nil;
  mnuRescan.Enabled := not LBusy;
  mnuImport.Enabled := not LBusy;
  mnuMoveImport.Enabled := not LBusy;
  mnuDeleteSelected.Enabled := not LBusy and LHaveSelection;
end;

procedure TfrmMain.ApplyThemeSetting(AReport: Boolean);
var
  LError: string;
begin
  if ApplyTheme(ThemeFromKey(FSettings.Theme), LError) then
    AddLog('Theme: ' + ThemeCaption(ThemeFromKey(FSettings.Theme)))
  else if AReport then
    ReportError('Could not apply the theme. ' + LError)
  else
    AddLog('WARNING: could not apply the theme. ' + LError);
end;

procedure TfrmMain.mnuSettingsClick(Sender: TObject);
begin
  ShowSettings(nil);
end;

procedure TfrmMain.mnuExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.mnuZoomInClick(Sender: TObject);
begin
  FMap.ZoomBy(2);
end;

procedure TfrmMain.mnuZoomOutClick(Sender: TObject);
begin
  FMap.ZoomBy(0.5);
end;

procedure TfrmMain.mnuZoomFitClick(Sender: TObject);
begin
  FMap.ZoomToFit;
end;

procedure TfrmMain.mnuZoomSelectionClick(Sender: TObject);
begin
  FMap.ZoomToSelection;
end;

procedure TfrmMain.mnuShowTilesClick(Sender: TObject);
begin
  FMap.ShowAvailableTiles := mnuShowTiles.IsChecked;
  SaveViewOptions;
end;

procedure TfrmMain.mnuShowDownloadedClick(Sender: TObject);
begin
  FMap.ShowDownloadedTiles := mnuShowDownloaded.IsChecked;
  SaveViewOptions;
end;

procedure TfrmMain.mnuShowBordersClick(Sender: TObject);
begin
  FMap.ShowBorders := mnuShowBorders.IsChecked;
  SaveViewOptions;
end;

procedure TfrmMain.mnuShowCoastlinesClick(Sender: TObject);
begin
  FMap.ShowCoastlines := mnuShowCoastlines.IsChecked;
  SaveViewOptions;
end;

procedure TfrmMain.mnuShowMapTilesClick(Sender: TObject);
begin
  FMap.ShowMapTiles := mnuShowMapTiles.IsChecked;
  SaveViewOptions;
end;

procedure TfrmMain.mnuCopyLogClick(Sender: TObject);
var
  LClipboard: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, LClipboard) then
    LClipboard.SetClipboard(memLog.Lines.Text)
  else
    ShowMessage('The clipboard is not available on this system.');
end;

procedure TfrmMain.mnuClearLogClick(Sender: TObject);
begin
  memLog.Lines.Clear;
end;

{ Settings }

procedure TfrmMain.ShowSettings(const AOnSaved: TProc);
var
  LOldTheme, LOldDrawing, LOldGpuPreference: string;
begin
  LOldTheme := FSettings.Theme;
  LOldDrawing := FSettings.Drawing;
  LOldGpuPreference := FSettings.GpuPreference;
  TfrmSettings.Edit(FSettings,
    procedure(ASaved: Boolean; const ADataFolder: string)
    begin
      if not ASaved then
        Exit;
      AddLog('Settings saved to ' + TGDEMSettings.SettingsFileName);
      CheckTokenExpiry;
      if not SameText(FSettings.Theme, LOldTheme) then
        ApplyThemeSetting(True);
      SuggestViewForDrawing(LOldDrawing, LOldGpuPreference);
      RefreshStorageStatus;
      if not SameFileName(ADataFolder, FSettings.DataFolder) then
        ChangeDataFolder(ADataFolder);
      // The imagery's layer, cache size or folder may have changed
      CloseImagery;
      ApplyTerrainRealistic;
      if Assigned(AOnSaved) then
        AOnSaved();
    end);
end;

{ Tile index (which tiles have data) }

procedure TfrmMain.mnuRefreshIndexClick(Sender: TObject);
begin
  StartIndexBuild;
end;

procedure TfrmMain.LoadTileIndex;
begin
  try
    if FTileIndex.LoadFromFile(TTileIndex.DefaultFileName) then
    begin
      FMap.TileIndexChanged;
      AddLog(Format('Tile index: %d tiles with data', [FTileIndex.Count]));
      Exit;
    end;
    AddLog('No tile index yet; it will be downloaded from NASA CMR (no login needed).');
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message + ' It will be downloaded again.');
  end;
  FNeedIndexBuild := True;
end;

procedure TfrmMain.StartIndexBuild;
var
  LBuilder: TTileIndexBuilder;
begin
  if (FIndexBuilder <> nil) or (FProgress <> nil) then
    Exit;

  LBuilder := TTileIndexBuilder.Create;
  LBuilder.OnLog :=
    procedure(const Msg: string)
    begin
      AddLog(Msg);
      ProgressStatus(Trim(Msg));
    end;
  LBuilder.OnProgress :=
    procedure(APage, APages, ATiles: Integer)
    begin
      if APages > 0 then
      begin
        AddLog(Format('  page %d of %d: %d tiles so far', [APage, APages, ATiles]));
        ProgressOverall(APage, APages,
          Format('Page %d of %d: %d tiles found', [APage, APages, ATiles]));
      end
      else
      begin
        AddLog(Format('  page %d: %d tiles so far', [APage, ATiles]));
        ProgressOverall(0, 0, Format('Page %d: %d tiles found', [APage, ATiles]));
      end;
    end;
  FIndexBuilder := LBuilder;
  UpdateButtons;
  BeginProgress('Downloading the tile index from NASA CMR',
    procedure
    begin
      LBuilder.Cancel;
      AddLog('Cancelling...');
    end,
    False);

  TTask.Run(
    procedure
    var
      LNew: TTileIndex;
      LHits: Integer;
      LError: string;
      LCancelled: Boolean;
    begin
      LError := '';
      LCancelled := False;
      LNew := TTileIndex.Create;
      try
        LHits := LBuilder.Build(LNew);
        if LNew.IsEmpty then
          raise ETileIndexError.Create('CMR returned no ASTER GDEM tiles.');
        if (LHits > 0) and (LNew.Count <> LHits) then
          AddLog(Format('  note: CMR reported %d granules but %d distinct tiles were found',
            [LHits, LNew.Count]));
        LNew.SaveToFile(TTileIndex.DefaultFileName);
        AddLog('Tile index saved to ' + TTileIndex.DefaultFileName);
      except
        on E: ETileIndexCancelled do
          LCancelled := True;
        on E: Exception do
          LError := E.Message;
      end;
      if LCancelled then
        AddLog('Tile index build cancelled.');

      // Swap in the new index on the main thread, where the map reads it
      TThread.Queue(nil,
        procedure
        begin
          if (LError = '') and not LCancelled then
          begin
            FTileIndex.Assign(LNew);
            FMap.TileIndexChanged;
            MapSelectionChanged(FMap);
          end;
          LNew.Free;
          FIndexBuilder := nil;
          LBuilder.Free;
          EndProgress;
          UpdateButtons;
          CloseIfIdle;
        end);

      // Queued after the clean-up above, so the dialog appears once the
      // buttons are usable again
      if LError <> '' then
        ReportError('Could not build the tile index: ' + LError);
    end);

  ShowProgressModal;
end;

{ Jobs }

function TfrmMain.RunJob(const AName: string; const AWork: TJobWork;
  const AOnDone: TJobDone; const AProgressTitle: string): Boolean;
var
  LToken: TCancelToken;
  LName: string;
  LWork: TJobWork;
  LOnDone: TJobDone;
begin
  Result := FJob = nil;
  if not Result then
  begin
    ReportError('Please wait for the current job to finish, or cancel it, first.');
    Exit;
  end;

  LName := AName;
  LWork := AWork;
  LOnDone := AOnDone;
  LToken := TCancelToken.Create;
  FJob := LToken;
  // Jobs can take hours; do not let the computer sleep part-way
  TKeepAwake.Acquire(AName);
  pbDownload.Value := 0;
  UpdateButtons;
  if AProgressTitle <> '' then
    BeginProgress(AProgressTitle,
      procedure
      begin
        LToken.Cancel;
        AddLog('Cancelling...');
      end,
      True);

  TTask.Run(
    procedure
    var
      LError: string;
      LCancelled: Boolean;
    begin
      LError := '';
      LCancelled := False;
      try
        LWork(LToken);
      except
        on E: EOperationCancelled do
          LCancelled := True;
        on E: Exception do
          LError := E.Message;
      end;
      if LCancelled then
        AddLog(LName + ' cancelled.');

      TThread.Queue(nil,
        procedure
        begin
          FJob := nil;
          TKeepAwake.Release;
          LToken.Free;
          pbDownload.Value := 0;
          EndProgress;
          UpdateButtons;
          if Assigned(LOnDone) then
            LOnDone((LError = '') and not LCancelled);
          RefreshStorageStatus;
          CloseIfIdle;
        end);

      // Queued after the clean-up above, so the dialog appears once the
      // buttons are usable again
      if LError <> '' then
        ReportError(LName + ' failed: ' + LError);
    end);

  if AProgressTitle <> '' then
    ShowProgressModal;
end;

procedure TfrmMain.BeginProgress(const ATitle: string; const AOnCancel: TProc;
  AShowItem: Boolean);
begin
  FProgress := TfrmProgress.CreateWithTitle(Self, ATitle, AShowItem);
  FProgress.OnCancel := AOnCancel;
end;

procedure TfrmMain.ShowProgressModal;
var
  LDialog: TfrmProgress;
begin
  LDialog := FProgress;
  if LDialog = nil then
    Exit;
  {$IFDEF ANDROID}
  // Android cannot block on a modal form; EndProgress closes and frees it
  LDialog.Show;
  {$ELSE}
  // Returns once EndProgress has been called. Updates queued by the
  // background work run inside the modal loop meanwhile.
  try
    LDialog.ShowModal;
  finally
    if FProgress = LDialog then
      FProgress := nil;
    LDialog.Free;
  end;
  {$ENDIF}
end;

procedure TfrmMain.EndProgress;
var
  LDialog: TfrmProgress;
begin
  LDialog := FProgress;
  if LDialog = nil then
    Exit;
  // Later queued updates find no dialog and do nothing
  FProgress := nil;
  LDialog.Finish;
  {$IFDEF ANDROID}
  LDialog.Close;
  TThread.ForceQueue(nil,
    procedure
    begin
      LDialog.Free;
    end);
  {$ENDIF}
end;

procedure TfrmMain.ProgressStatus(const AText: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if FProgress <> nil then
        FProgress.SetStatus(AText);
    end);
end;

procedure TfrmMain.ProgressOverall(ADone, ATotal: Integer; const AText: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if FProgress <> nil then
        FProgress.SetOverall(ADone, ATotal, AText);
    end);
end;

procedure TfrmMain.ProgressItemText(ADone, ATotal: Int64; const AText: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if FProgress <> nil then
        FProgress.SetItemProgress(ADone, ATotal, AText);
    end);
end;

class function TfrmMain.FormatDuration(ASeconds: Double): string;
begin
  Result := GDEMStore.FormatDuration(ASeconds);
end;

procedure TfrmMain.btnCancelClick(Sender: TObject);
begin
  if FJob <> nil then
  begin
    FJob.Cancel;
    AddLog('Cancelling...');
  end;
end;

{ Data folder }

procedure TfrmMain.OpenStore(APromptIfMissing: Boolean);
begin
  FreeAndNil(FStore);
  FStore := TGDEMStore.Create(FSettings.DataFolder);
  // The imagery cache lives in the data folder
  CloseImagery;
  ApplyTerrainRealistic;
  FStore.OnLog := AddLog;
  FStoreOpen := False;
  FStoreWasAvailable := FStore.IsAvailable;
  FDownloaded.Clear;
  FMap.TileIndexChanged;
  MapSelectionChanged(FMap);

  if FStoreWasAvailable then
    LoadDownloaded(nil)
  else if FSettings.DataFolderUsed then
  begin
    AddLog('WARNING: the data folder ' + FStore.Root + ' is not connected.');
    if APromptIfMissing then
      TThread.ForceQueue(nil,
        procedure
        begin
          WithStore(nil);
        end);
  end;
  RefreshStorageStatus;
end;

procedure TfrmMain.LoadDownloaded(const AThen: TProc);
var
  LLoaded: Boolean;
begin
  try
    LLoaded := FStore.LoadDownloadedIndex(FDownloaded);
  except
    on E: Exception do
    begin
      AddLog('WARNING: ' + E.Message + ' Rescanning the data folder.');
      LLoaded := False;
    end;
  end;

  if LLoaded then
  begin
    FStoreOpen := True;
    FMap.TileIndexChanged;
    MapSelectionChanged(FMap);
    AddLog(Format('Data folder %s: %d tile(s) downloaded', [FStore.Root, FDownloaded.Count]));
    if Assigned(AThen) then
      AThen();
  end
  else
    // No bitmap yet (a new folder, or one from before this layout): build
    // it from whatever files are there
    StartRescan(AThen);
end;

procedure TfrmMain.MarkStoreUsed;
begin
  if FSettings.DataFolderUsed then
    Exit;
  FSettings.DataFolderUsed := True;
  try
    FSettings.Save;
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message);
  end;
end;

procedure TfrmMain.WithStore(const AAction: TProc);
var
  LAction: TProc;
begin
  LAction := AAction;

  if FStore.IsAvailable or not FSettings.DataFolderUsed then
  begin
    try
      // Creates a new folder; fails if its drive is not connected
      FStore.EnsureCreated;
      MarkStoreUsed;
      if FStoreOpen then
      begin
        if Assigned(LAction) then
          LAction();
      end
      else
        LoadDownloaded(LAction);
      Exit;
    except
      on E: Exception do
        AddLog('WARNING: ' + E.Message);
    end;
  end;

  TDialogService.MessageDialog(
    Format('The data folder %s is not available.'#13#10#13#10 +
      'If it is on a removable drive or a network share, connect it and ' +
      'press Retry. To use a different folder, press Cancel and choose one ' +
      'in File > Settings.', [FStore.Root]),
    TMsgDlgType.mtWarning, [TMsgDlgBtn.mbRetry, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbRetry, 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrRetry then
        WithStore(LAction);
    end);
end;

procedure TfrmMain.RefreshStorageStatus;
var
  LFree: Int64;
  LText: string;
  LAvailable: Boolean;
begin
  if FStore = nil then
    Exit;

  LAvailable := FStore.IsAvailable;
  if LAvailable then
  begin
    LFree := FStore.FreeSpace;
    LText := Format('Data: %s   %s free   %d tile(s) downloaded',
      [FStore.Root, FormatBytes(LFree), FDownloaded.Count]);
    if (LFree >= 0) and (LFree < ReserveBytes) then
      LText := LText + '   LOW ON SPACE';
    // The drive has just been connected: load what it holds
    if not FStoreWasAvailable and not FStoreOpen and (FJob = nil) then
    begin
      AddLog('The data folder ' + FStore.Root + ' is available again.');
      LoadDownloaded(nil);
    end;
  end
  else
  begin
    if FSettings.DataFolderUsed then
      LText := 'Data folder not connected: ' + FStore.Root
    else
      LText := 'Data: ' + FStore.Root + '   (created on first download)';
    if FStoreOpen then
    begin
      FStoreOpen := False;
      AddLog('WARNING: the data folder ' + FStore.Root + ' is no longer available.');
    end;
  end;
  FStoreWasAvailable := LAvailable;
  lblStorage.Text := LText;
end;

procedure TfrmMain.tmrStorageTimer(Sender: TObject);
begin
  RefreshStorageStatus;
end;

procedure TfrmMain.StartRescan(const AThen: TProc);
var
  LStore: TGDEMStore;
  LNew: TTileIndex;
  LThen: TProc;
begin
  LStore := FStore;
  LThen := AThen;
  LNew := TTileIndex.Create;
  if not RunJob('Rescan',
    procedure(AToken: TCancelToken)
    begin
      LStore.Rescan(LNew, AToken,
        procedure(ADone, ATotal: Integer)
        begin
          ShowProgress(ADone, ATotal);
        end);
    end,
    procedure(ASucceeded: Boolean)
    begin
      if ASucceeded then
      begin
        FDownloaded.Assign(LNew);
        FStoreOpen := True;
        FMap.TileIndexChanged;
        MapSelectionChanged(FMap);
      end;
      LNew.Free;
      if ASucceeded and Assigned(LThen) then
        LThen();
    end) then
    LNew.Free;
end;

procedure TfrmMain.mnuRescanClick(Sender: TObject);
begin
  if FStore.IsAvailable then
    StartRescan(nil)
  else
    // Asks for the drive; loading the folder once it is connected rescans
    // it if it has no bitmap
    WithStore(nil);
end;

procedure TfrmMain.mnuImportClick(Sender: TObject);
var
  LFolder: string;
begin
  LFolder := '';
  if not SelectDirectory('Choose the folder holding existing ASTER GDEM .tif files',
    '', LFolder) then
    Exit;

  TDialogService.MessageDialog(
    Format('Copy the ASTER GDEM tiles found in'#13#10'%s'#13#10'(and any folders ' +
      'inside it) into the data folder'#13#10'%s?'#13#10#13#10 +
      'The original files are only read; nothing in that folder is changed. ' +
      'Tiles already in the data folder are skipped, so an import can be ' +
      'cancelled and run again later.',
      [LFolder, FStore.Root]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbYes, 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
        WithStore(
          procedure
          begin
            StartImport(LFolder);
          end);
    end);
end;

procedure TfrmMain.mnuMoveImportClick(Sender: TObject);
var
  LFolder: string;
begin
  LFolder := '';
  if not SelectDirectory('Choose the folder holding the ASTER GDEM .tif files to move',
    '', LFolder) then
    Exit;

  TDialogService.MessageDialog(
    Format('Move the ASTER GDEM tiles found in'#13#10'%s'#13#10'(and any folders ' +
      'inside it) into the data folder'#13#10'%s?'#13#10#13#10 +
      'Each original file is DELETED once its copy is complete in the data ' +
      'folder, and so is each one the data folder already has. Other files ' +
      'are left alone, and so are any that cannot be copied. A move can be ' +
      'cancelled and run again later.',
      [LFolder, FStore.Root]),
    TMsgDlgType.mtWarning, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbNo, 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
        WithStore(
          procedure
          begin
            StartImport(LFolder, True);
          end);
    end);
end;

procedure TfrmMain.StartImport(const ASourceFolder: string; AMove: Boolean);
var
  LSource, LVerb: string;
  LStore: TGDEMStore;
  LReserve: Int64;
  LWorkers: Integer;
  LMove: Boolean;
begin
  LSource := ASourceFolder;
  LMove := AMove;
  if LMove then
    LVerb := 'Moving'
  else
    LVerb := 'Copying';
  LStore := FStore;
  LReserve := ReserveBytes;
  LWorkers := EnsureRange(FSettings.ImportWorkers, 1, MAX_IMPORT_WORKERS);
  RunJob(IfThen(LMove, 'Move import', 'Import'),
    procedure(AToken: TCancelToken)
    var
      LResult: TImportResult;
      LClock: TStopwatch;
    begin
      ProgressStatus('Looking for ASTER GDEM tiles in ' + LSource + ' ...');
      ProgressOverall(0, 0, 'This can take a while for a large folder');
      LClock := TStopwatch.StartNew;
      LResult := LStore.ImportFrom(LSource, LReserve, LWorkers, AToken,
        procedure(const AProgress: TImportProgress)
        var
          LBytesText: string;
          LSeconds, LRate: Double;
        begin
          ShowProgress(AProgress.FilesDone, AProgress.FilesTotal);

          if AProgress.CurrentFile <> '' then
            ProgressStatus(LVerb + ' ' + AProgress.CurrentFile)
          else if AProgress.FilesDone >= AProgress.FilesTotal then
            ProgressStatus('Finishing...')
          else
            ProgressStatus(Format('Found %d tile file(s); %s...',
              [AProgress.FilesTotal, LVerb.ToLower]));
          ProgressOverall(AProgress.FilesDone, AProgress.FilesTotal,
            Format('File %d of %d', [AProgress.FilesDone, AProgress.FilesTotal]));

          // The bytes bar measures what actually has to be copied, so files
          // already in the data folder do not make it jump ahead
          LBytesText := Format('%s of %s copied',
            [FormatByteSize(AProgress.BytesCopied), FormatByteSize(AProgress.BytesToCopy)]);
          LSeconds := LClock.Elapsed.TotalSeconds;
          if (LSeconds >= 10) and (AProgress.BytesCopied > 0) and
             (AProgress.BytesCopied < AProgress.BytesToCopy) then
          begin
            LRate := AProgress.BytesCopied / LSeconds;
            LBytesText := LBytesText + Format(', %s/s, about %s left',
              [FormatByteSize(Round(LRate)),
               FormatDuration((AProgress.BytesToCopy - AProgress.BytesCopied) / LRate)]);
          end;
          ProgressItemText(AProgress.BytesCopied, AProgress.BytesToCopy, LBytesText);
        end,
        LMove);
      AddLog(Format('%s finished: %d file(s) copied (%s), %d already present, ' +
        '%d replaced, %d ignored, %d failed.',
        [IfThen(LMove, 'Move', 'Import'), LResult.Copied, FormatByteSize(LResult.Bytes),
         LResult.AlreadyPresent, LResult.Replaced, LResult.Ignored, LResult.Failed]));
      if LMove then
      begin
        AddLog(Format('  %d original file(s) deleted from %s', [LResult.SourcesDeleted, LSource]));
        if LResult.SourcesKept > 0 then
          AddLog(Format('WARNING: %d file(s) are safely in the data folder but could not ' +
            'be deleted from %s; the Debug tab lists them.', [LResult.SourcesKept, LSource]));
      end;
      if LResult.Failed > 0 then
        ReportError(Format('The import finished, but %d file(s) could not be copied, ' +
          'even after %d tries each, and were skipped. The Debug tab lists them and ' +
          'why. Run the import again to try them again; files already copied are ' +
          'skipped.', [LResult.Failed, IMPORT_ATTEMPTS]));
    end,
    procedure(ASucceeded: Boolean)
    begin
      // Even a cancelled or failed import may have copied complete tiles,
      // so bring the map up to date either way
      StartRescan(nil);
    end,
    IfThen(LMove, 'Moving tiles', 'Importing tiles'));
end;

procedure TfrmMain.MarkDownloaded(ASouth, AWest: Integer);
begin
  FDownloaded.Add(ASouth, AWest);
  try
    FStore.SaveDownloadedIndex(FDownloaded);
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message);
  end;
  FMap.TileIndexChanged;
  MapSelectionChanged(FMap);
  // Drawn flat in the 3D view until now
  if FTerrainView <> nil then
    FTerrainView.TileDownloaded(ASouth, AWest);
end;

procedure TfrmMain.QueueMarkDownloaded(ASouth, AWest: Integer);
begin
  TThread.Queue(nil,
    procedure
    begin
      MarkDownloaded(ASouth, AWest);
    end);
end;

procedure TfrmMain.mnuDeleteSelectedClick(Sender: TObject);
var
  LTiles: TArray<string>;
begin
  LTiles := SelectedTileNames(FDownloaded);
  if Length(LTiles) = 0 then
  begin
    ShowMessage('None of the selected tiles are downloaded.');
    Exit;
  end;

  TDialogService.MessageDialog(
    Format('Delete %d downloaded tile(s), about %s, from %s?',
      [Length(LTiles), FormatBytes(Length(LTiles) * ESTIMATED_TILE_BYTES), FStore.Root]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbNo, 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult <> mrYes then
        Exit;
      WithStore(
        procedure
        var
          LStore: TGDEMStore;
        begin
          LStore := FStore;
          RunJob('Delete',
            procedure(AToken: TCancelToken)
            begin
              LStore.DeleteTiles(LTiles, AToken,
                procedure(ADone, ATotal: Integer)
                begin
                  ShowProgress(ADone, ATotal);
                end);
            end,
            procedure(ASucceeded: Boolean)
            var
              LTile: string;
              LSouth, LWest: Integer;
            begin
              // Even a cancelled delete may have removed some tiles
              for LTile in LTiles do
                if TryParseTileName(LTile, LSouth, LWest) and
                   not LStore.TileComplete(LSouth, LWest) then
                  FDownloaded.Remove(LSouth, LWest);
              try
                LStore.SaveDownloadedIndex(FDownloaded);
              except
                on E: Exception do
                  AddLog('WARNING: ' + E.Message);
              end;
              FMap.TileIndexChanged;
              MapSelectionChanged(FMap);
              if ASucceeded then
                AddLog(Format('Deleted %d tile(s).', [Length(LTiles)]));
            end);
        end);
    end);
end;

procedure TfrmMain.ChangeDataFolder(const ANewFolder: string);
var
  LNewFolder: string;
begin
  LNewFolder := ANewFolder;
  if FJob <> nil then
  begin
    ReportError('The data folder cannot be changed while a job is running. ' +
      'Wait for it to finish, or cancel it, and try again.');
    Exit;
  end;

  if FStore.IsAvailable and FStoreOpen and not FDownloaded.IsEmpty then
    TDialogService.MessageDialog(
      Format('The current data folder holds %d downloaded tile(s), about %s.'#13#10#13#10 +
        'Move them to %s?'#13#10#13#10 +
        'Yes: move them. This can take a long time; it can be cancelled and ' +
        'resumed later by choosing the folder again.'#13#10 +
        'No: switch without moving; the files stay in %s.'#13#10 +
        'Cancel: keep using the current folder.',
        [FDownloaded.Count, FormatBytes(FDownloaded.Count * ESTIMATED_TILE_BYTES),
         LNewFolder, FStore.Root]),
      TMsgDlgType.mtConfirmation,
      [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
      TMsgDlgBtn.mbCancel, 0,
      procedure(const AResult: TModalResult)
      begin
        case AResult of
          mrYes: StartMove(LNewFolder);
          mrNo: SwitchDataFolder(LNewFolder, False);
        end;
      end)
  else
    SwitchDataFolder(LNewFolder, False);
end;

procedure TfrmMain.SwitchDataFolder(const ANewFolder: string; AForceRescan: Boolean);
var
  LProbe: TGDEMStore;
begin
  FSettings.DataFolder := ANewFolder;
  // A folder that already holds GDEM data counts as used, so it is not
  // silently recreated if its drive is later disconnected
  LProbe := TGDEMStore.Create(ANewFolder);
  try
    FSettings.DataFolderUsed := LProbe.HasMarker;
  finally
    LProbe.Free;
  end;
  try
    FSettings.Save;
  except
    on E: Exception do
      ReportError(E.Message);
  end;
  AddLog('Data folder is now ' + FSettings.DataFolder);

  if AForceRescan and TDirectory.Exists(ANewFolder) then
  begin
    FreeAndNil(FStore);
    FStore := TGDEMStore.Create(FSettings.DataFolder);
    // The imagery cache lives in the data folder
    CloseImagery;
    ApplyTerrainRealistic;
    FStore.OnLog := AddLog;
    FStoreOpen := False;
    FDownloaded.Clear;
    FMap.TileIndexChanged;
    StartRescan(nil);
  end
  else
    OpenStore;
end;

procedure TfrmMain.StartMove(const ANewFolder: string);
var
  LSource: TGDEMStore;
  LTarget: TGDEMStore;
  LNewFolder: string;
  LFree, LNeeded, LReserve: Int64;
  LGo: TProc;
begin
  LNewFolder := ANewFolder;
  LSource := FStore;
  LTarget := TGDEMStore.Create(LNewFolder);
  LTarget.OnLog := AddLog;

  // Starts the move job once any space warning has been accepted. An
  // anonymous method, not a nested procedure, because it captures locals.
  LGo :=
    procedure
    begin
      if not RunJob('Move',
          procedure(AToken: TCancelToken)
          var
            LMoved: Integer;
          begin
            LMoved := LSource.MoveAllTo(LTarget, AToken,
              procedure(ADone, ATotal: Integer)
              begin
                ShowProgress(ADone, ATotal);
              end);
            AddLog(Format('Moved %d file(s) to %s', [LMoved, LTarget.Root]));
          end,
          procedure(ASucceeded: Boolean)
          begin
            LTarget.Free;
            if ASucceeded then
              SwitchDataFolder(LNewFolder, True)
            else
              AddLog('The move did not finish. Files moved so far are in ' + LNewFolder +
                '; the rest are still in ' + LSource.Root + '. Choose ' + LNewFolder +
                ' in File > Settings again to finish moving them.');
          end) then
        LTarget.Free;
    end;

  // The reserve is a share of the destination's own drive
  LFree := TGDEMStore.FreeSpaceAt(LNewFolder);
  LReserve := TGDEMStore.ReserveAt(LNewFolder, FSettings.MinFreePercent);
  LNeeded := FDownloaded.Count * ESTIMATED_TILE_BYTES;
  if (LFree >= 0) and (LFree - LReserve < LNeeded) then
    TDialogService.MessageDialog(
      Format('The destination has %s free, but the data is about %s and %s ' +
        '(%d%% of that drive) must be kept free.'#13#10#13#10 +
        'A move within the same drive needs no extra space. Move anyway?',
        [FormatBytes(LFree), FormatBytes(LNeeded), FormatBytes(LReserve),
         EnsureRange(FSettings.MinFreePercent, MIN_RESERVE_PERCENT, MAX_RESERVE_PERCENT)]),
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
      TMsgDlgBtn.mbNo, 0,
      procedure(const AResult: TModalResult)
      begin
        if AResult = mrYes then
          LGo()
        else
          LTarget.Free;
      end)
  else
    LGo();
end;

{ Downloads }

procedure TfrmMain.btnFetchSelectionClick(Sender: TObject);
var
  LCandidates, LTiles: TArray<string>;
  LTile: string;
  LSouth, LWest, LCount, LAlready: Integer;
  LFree, LNeeded: Int64;
begin
  // Only tiles with data (when that is known) and not yet downloaded. The
  // downloaded ones are counted, so the job's summary can say so: a
  // whole-world fetch once reported "0 were already here" while leaving
  // out one tile that was.
  if FTileIndex.IsEmpty then
    LCandidates := SelectedTileNames(nil)
  else
    LCandidates := SelectedTileNames(FTileIndex);
  SetLength(LTiles, Length(LCandidates));
  LCount := 0;
  LAlready := 0;
  for LTile in LCandidates do
    if TryParseTileName(LTile, LSouth, LWest) then
    begin
      if FDownloaded.Has(LSouth, LWest) then
        Inc(LAlready)
      else
      begin
        LTiles[LCount] := LTile;
        Inc(LCount);
      end;
    end;
  SetLength(LTiles, LCount);

  if LCount = 0 then
  begin
    if Length(LCandidates) = 0 then
      ShowMessage('None of the selected tiles have ASTER GDEM data.')
    else
      ShowMessage('All the selected tiles with data are already downloaded.');
    Exit;
  end;

  // No question asked: the progress dialog has a Cancel button. A drive
  // too full for them all is only mentioned, as downloading stops at the
  // reserve by itself.
  LNeeded := LCount * ESTIMATED_TILE_BYTES;
  LFree := -1;
  if FStore.IsAvailable then
    LFree := FStore.FreeSpace;
  if (LFree >= 0) and (LFree - ReserveBytes < LNeeded) then
    AddLog(Format('WARNING: the %d tile(s) need about %s, but only %s is free on the ' +
      'data drive and %s must be kept free, so downloading will stop after about ' +
      '%d tile(s).', [LCount, FormatBytes(LNeeded), FormatBytes(LFree),
      FormatBytes(ReserveBytes), Max(0, (LFree - ReserveBytes) div ESTIMATED_TILE_BYTES)]));

  FetchTiles(LTiles, LAlready);
end;

procedure TfrmMain.FetchTiles(const ATiles: TArray<string>; AAlready: Integer);
var
  LTiles: TArray<string>;
  LAlready: Integer;
begin
  LTiles := ATiles;
  LAlready := AAlready;
  if FSettings.BearerToken = '' then
    ShowSettings(
      procedure
      begin
        FetchTiles(LTiles, LAlready);
      end)
  else
    WithStore(
      procedure
      begin
        StartFetch(LTiles, LAlready);
      end);
end;

procedure TfrmMain.StartFetch(const ATiles: TArray<string>; AAlready: Integer);
var
  LTiles: TArray<string>;
  LBearer: string;
  LStore: TGDEMStore;
  LReserve: Int64;
  LSpeed: TDownloadSpeed;
  LAlready: Integer;
begin
  if (FSettings.BearerToken = '') or (Length(ATiles) = 0) then
    Exit;
  // NASA would refuse every download; CheckTokenExpiry has said why
  if not CheckTokenExpiry then
    Exit;

  LTiles := ATiles;
  LBearer := FSettings.BearerToken;
  LStore := FStore;
  LReserve := ReserveBytes;
  LSpeed := DownloadSpeedFromKey(FSettings.DownloadSpeed);
  LAlready := AAlready;

  RunJob('Download',
    procedure(AToken: TCancelToken)
    begin
      RunDownloads(AToken, LTiles, LBearer, LStore, LReserve, LSpeed, LAlready);
    end,
    nil,
    'Downloading tiles');
end;

procedure TfrmMain.RunDownloads(AToken: TCancelToken; const ATiles: TArray<string>;
  const ABearer: string; AStore: TGDEMStore; AReserve: Int64; ASpeed: TDownloadSpeed;
  AAlready: Integer);
var
  LBatch: TDownloadBatch;
  LResult: TDownloadBatchResult;
begin
  LBatch := TDownloadBatch.Create(ABearer, AStore, AReserve, ASpeed);
  try
    // Each of these is safe from the batch's threads: they queue their
    // work to the main thread
    LBatch.OnLog := AddLog;
    LBatch.OnStatus := ProgressStatus;
    LBatch.OnOverall := ProgressOverall;
    LBatch.OnItem := ProgressItemText;
    LBatch.OnTileDownloaded := QueueMarkDownloaded;
    LResult := LBatch.Run(AToken, ATiles, AAlready);
  finally
    LBatch.Free;
  end;
  if LResult.Failed > 0 then
    ReportError(Format('%d tile(s) could not be downloaded, even after several tries ' +
      'each, and were skipped. The Debug tab lists them and why. Fetch the same ' +
      'selection again to try them again; tiles already downloaded are skipped.',
      [LResult.Failed]));
end;

end.
