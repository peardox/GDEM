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
  FMX.Controls.Presentation, FMX.Menus, FMX.TabControl,
  GDEMCancel, GDEMSettings, GDEMDownloader, GDEMWorldMap, GDEMTileIndex,
  GDEMStore, GDEMThemes, GDEMReport, GDEMVectors, ProgressForm;

const
  { Name of the RCDATA resource holding the world map image. }
  WORLD_MAP_RESOURCE = 'WORLDMAP';

  { Selections larger than this many tiles ask for confirmation before
    downloading. }
  CONFIRM_TILE_COUNT = 10;

  { How often the data folder and its free space are checked, in
    milliseconds. }
  STORAGE_CHECK_INTERVAL = 60000;

  { Once this many tiles in a row have failed to download, even after
    retries, the batch stops: something is badly wrong. Failures with good
    tiles between them only skip those tiles, however many there are. }
  MAX_DOWNLOAD_FAILURES = 10;

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
    { Separator above @link(mnuExit). Hidden on macOS. }
    mnuFileSep: TMenuItem;
    { File > Exit. Hidden on macOS, where Quit is in the application menu. }
    mnuExit: TMenuItem;
    { The Data menu. }
    mnuData: TMenuItem;
    { Data > Import Existing Tiles: copies tiles from another folder into
      the data folder. }
    mnuImport: TMenuItem;
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
    { Separator above the log commands. }
    mnuLogSep: TMenuItem;
    { View > Copy Log: puts the whole log on the clipboard. }
    mnuCopyLog: TMenuItem;
    { View > Clear Log: empties the log. }
    mnuClearLog: TMenuItem;
    { Toolbar above the tabs. }
    layTop: TLayout;
    { Caption for @link(edtTile). }
    lblTile: TLabel;
    { Tile to fetch by name, such as @code(N50W002). Filled in when a single
      tile is selected on the map. }
    edtTile: TEdit;
    { Fetches the tile named in @link(edtTile). }
    btnFetch: TButton;
    { Fetches every tile in the map selection that has data and is not
      downloaded yet. }
    btnFetchSelection: TButton;
    { Stops the running job. Enabled only while one is running. }
    btnCancel: TButton;
    { Describes the map selection. }
    lblSelection: TLabel;
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

    { Fetches the tile named in @link(edtTile).
      @param(Sender The button.) }
    procedure btnFetchClick(Sender: TObject);

    { Fetches the tiles in the map selection that still need downloading,
      confirming large or space-hungry batches.
      @param(Sender The button.) }
    procedure btnFetchSelectionClick(Sender: TObject);

    { Asks the running job to stop.
      @param(Sender The button.) }
    procedure btnCancelClick(Sender: TObject);

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

    { Puts the whole log on the clipboard, ready to paste.
      @param(Sender The menu item.) }
    procedure mnuCopyLogClick(Sender: TObject);

    { Empties the log, so the next job's messages are easy to copy.
      @param(Sender The menu item.) }
    procedure mnuClearLogClick(Sender: TObject);

    { Periodic check of the data folder and its free space.
      @param(Sender The timer.) }
    procedure tmrStorageTimer(Sender: TObject);
  private
    { The user's saved settings, loaded at start-up. }
    FSettings: TGDEMSettings;

    { The world map, created in @link(FormCreate). }
    FMap: TWorldMapView;

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
      @param(ASourceFolder The folder to import from.) }
    procedure StartImport(const ASourceFolder: string);

    { The free-space reserve from the settings.
      @returns(Bytes that must be left free.) }
    function ReserveBytes: Int64;

    { Loads the world map image from the @link(WORLD_MAP_RESOURCE)
      resource into @link(FMap), reporting any failure, then the borders and
      coastlines. The map works without the borders, so failing to load them
      is only logged as a warning. }
    procedure LoadWorldMap;

    { Updates the selection label and buttons after the map selection or a
      tile bitmap changes, and copies a single selected tile into
      @link(edtTile).
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
      or delete. Does nothing over the sea.
      @param(Sender The map view.)
      @param(ALat Latitude clicked.)
      @param(ALon Longitude clicked.) }
    procedure MapRightClick(Sender: TObject; ALat, ALon: Double);

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
      @link(StartFetch). Skips tiles already in the data folder, asks CMR
      where the rest are, many tiles per request, then downloads them
      several tiles at a time, sharing a @link(TDownloadThrottle) that
      starts at the speed's starting number, climbs towards its most while
      all goes well, and cuts back if NASA objects. A tile that keeps failing is logged
      and skipped; the job stops early only if the bearer token is rejected,
      free space runs low, the data folder disappears, or
      @link(MAX_DOWNLOAD_FAILURES) tiles in a row fail. Every request,
      redirect and saved file is written to a @link(TDownloadReport); the
      Debug tab gets only the start, problems and the summary.
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
  end;

var
  { The application's main form instance. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  System.Math, System.Diagnostics, System.SyncObjs, System.Generics.Collections,
  System.Rtti, FMX.DialogService, FMX.Platform, GDEMAwake,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  GDEMTiles, GDEMDrawing, SettingsForm;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  {$IF defined(MACOS) and not defined(IOS)}
  mnuFileSep.Visible := False;
  mnuExit.Visible := False;
  {$ENDIF}

  edtTile.Text := 'N50W002';

  FMap := TWorldMapView.Create(Self);
  FMap.Parent := layMap;
  FMap.Align := TAlignLayout.Client;
  FMap.OnSelectionChanged := MapSelectionChanged;
  FMap.OnSelectionChanging := MapSelectionChanging;
  FMap.OnHover := MapHover;
  FMap.OnRightClick := MapRightClick;
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
  FMap.Vectors := nil;
  FVectors.Free;
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
  Result := Int64(FSettings.MinFreeSpaceMB) * 1024 * 1024;
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
  LSelection: TTileRect;
begin
  LSelection := FMap.Selection;
  UpdateSelectionText;
  if LSelection.Count = 1 then
    edtTile.Text := TileName(LSelection.South, LSelection.West);
  UpdateButtons;
end;

procedure TfrmMain.MapRightClick(Sender: TObject; ALat, ALon: Double);
var
  LCountry: Integer;
  LName: string;
  LTiles: TTileIndex;
begin
  LCountry := FVectors.CountryIndexAt(ALat, ALon);
  if LCountry < 0 then
    Exit;
  LName := FVectors.CountryName(LCountry);
  LTiles := TTileIndex.Create;
  try
    FVectors.AddCountryTiles(LCountry, LTiles);
    if LTiles.IsEmpty then
      ShowMessage(LName + ' lies outside ASTER GDEM coverage.')
    else
      FMap.SelectTiles(LTiles, LName);
  finally
    LTiles.Free;
  end;
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
  btnFetch.Enabled := not LBusy;
  btnFetchSelection.Enabled := not LBusy and LHaveSelection;
  btnCancel.Enabled := LBusy;
  mnuZoomSelection.Enabled := LHaveSelection;
  mnuRefreshIndex.Enabled := FIndexBuilder = nil;
  mnuRescan.Enabled := not LBusy;
  mnuImport.Enabled := not LBusy;
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
end;

procedure TfrmMain.mnuShowDownloadedClick(Sender: TObject);
begin
  FMap.ShowDownloadedTiles := mnuShowDownloaded.IsChecked;
end;

procedure TfrmMain.mnuShowBordersClick(Sender: TObject);
begin
  FMap.ShowBorders := mnuShowBorders.IsChecked;
end;

procedure TfrmMain.mnuShowCoastlinesClick(Sender: TObject);
begin
  FMap.ShowCoastlines := mnuShowCoastlines.IsChecked;
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
  LOldTheme: string;
begin
  LOldTheme := FSettings.Theme;
  TfrmSettings.Edit(FSettings,
    procedure(ASaved: Boolean; const ADataFolder: string)
    begin
      if not ASaved then
        Exit;
      AddLog('Settings saved to ' + TGDEMSettings.SettingsFileName);
      CheckTokenExpiry;
      if not SameText(FSettings.Theme, LOldTheme) then
        ApplyThemeSetting(True);
      RefreshStorageStatus;
      if not SameFileName(ADataFolder, FSettings.DataFolder) then
        ChangeDataFolder(ADataFolder);
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
var
  LSeconds, LMinutes, LHours: Int64;
begin
  LSeconds := Round(ASeconds);
  LHours := LSeconds div 3600;
  LMinutes := (LSeconds mod 3600) div 60;
  if LHours > 0 then
    Result := Format('%d h %d min', [LHours, LMinutes])
  else if LMinutes > 0 then
    Result := Format('%d min %d s', [LMinutes, LSeconds mod 60])
  else
    Result := Format('%d s', [LSeconds]);
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

procedure TfrmMain.StartImport(const ASourceFolder: string);
var
  LSource: string;
  LStore: TGDEMStore;
  LReserve: Int64;
  LWorkers: Integer;
begin
  LSource := ASourceFolder;
  LStore := FStore;
  LReserve := ReserveBytes;
  LWorkers := EnsureRange(FSettings.ImportWorkers, 1, MAX_IMPORT_WORKERS);
  RunJob('Import',
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
            ProgressStatus('Copying ' + AProgress.CurrentFile)
          else if AProgress.FilesDone >= AProgress.FilesTotal then
            ProgressStatus('Finishing...')
          else
            ProgressStatus(Format('Found %d tile file(s); copying...',
              [AProgress.FilesTotal]));
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
        end);
      AddLog(Format('Import finished: %d file(s) copied (%s), %d already present, ' +
        '%d replaced, %d ignored, %d failed.',
        [LResult.Copied, FormatByteSize(LResult.Bytes), LResult.AlreadyPresent,
         LResult.Replaced, LResult.Ignored, LResult.Failed]));
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
    'Importing tiles');
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
  LFree, LNeeded: Int64;
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

  LFree := TGDEMStore.FreeSpaceAt(LNewFolder);
  LNeeded := FDownloaded.Count * ESTIMATED_TILE_BYTES;
  if (LFree >= 0) and (LFree - ReserveBytes < LNeeded) then
    TDialogService.MessageDialog(
      Format('The destination has %s free, but the data is about %s and %s ' +
        'must be kept free.'#13#10#13#10 +
        'A move within the same drive needs no extra space. Move anyway?',
        [FormatBytes(LFree), FormatBytes(LNeeded), FormatBytes(ReserveBytes)]),
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

procedure TfrmMain.btnFetchClick(Sender: TObject);
begin
  FetchTiles([Trim(edtTile.Text)]);
end;

procedure TfrmMain.btnFetchSelectionClick(Sender: TObject);
var
  LCandidates, LTiles: TArray<string>;
  LTile, LQuestion, LSpace: string;
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

  LNeeded := LCount * ESTIMATED_TILE_BYTES;
  LFree := -1;
  if FStore.IsAvailable then
    LFree := FStore.FreeSpace;
  LSpace := '';
  if (LFree >= 0) and (LFree - ReserveBytes < LNeeded) then
    LSpace := Format(#13#10#13#10'Only %s is free on the data drive and %s must be ' +
      'kept free, so downloading will stop after about %d tile(s).',
      [FormatBytes(LFree), FormatBytes(ReserveBytes),
       Max(0, (LFree - ReserveBytes) div ESTIMATED_TILE_BYTES)]);

  if FTileIndex.IsEmpty then
    LQuestion := Format('Download up to %d tile(s), about %s? Tiles with no data ' +
      'are skipped.', [LCount, FormatBytes(LNeeded)])
  else
    LQuestion := Format('Download %d tile(s), about %s?', [LCount, FormatBytes(LNeeded)]);

  if (LCount <= CONFIRM_TILE_COUNT) and (LSpace = '') then
    FetchTiles(LTiles, LAlready)
  else
    TDialogService.MessageDialog(LQuestion + LSpace,
      TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
      TMsgDlgBtn.mbNo, 0,
      procedure(const AResult: TModalResult)
      begin
        if AResult = mrYes then
          FetchTiles(LTiles, LAlready);
      end);
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
  LTodo, LQueueList, LFolders: TList<string>;
  LTile, LFolder: string;
  LSouth, LWest, LAlready, LNoData, LIndex, LMost: Integer;
  LLookup: TGDEMDownloader;
  LURLs: TDictionary<string, TArray<string>>;
  LQueue: TArray<string>;
  LLock: TObject;
  LWorker: TProc;
  LThreads: TArray<TThread>;
  LClock: TStopwatch;
  // Shared by the workers; counters change only through TInterlocked
  LNext, LDone, LDownloaded, LFailed, LFailRun: Integer;
  LBytes, LSaved, LLastUi: Int64;
  LError, LCutBack: string;
  LStop: Boolean;
  LSeconds: Double;
  LThrottle: TDownloadThrottle;
  LReport: TDownloadReport;
  // Detail goes only to the report; summary lines go to both
  LDetail, LBoth: TGDEMLogEvent;
begin
  LThrottle := nil;
  LReport := nil;
  LTodo := TList<string>.Create;
  LQueueList := TList<string>.Create;
  LFolders := TList<string>.Create;
  LLock := TObject.Create;
  LURLs := nil;
  try
  try
    // 1. Tiles already in the data folder need nothing from NASA. Those
    // the caller left out are counted too.
    LAlready := AAlready;
    for LTile in ATiles do
    begin
      AToken.Check;
      // Validates the name, raising a clear error if it is wrong
      TGDEMDownloader.TileGranuleName(LTile);
      TryParseTileName(LTile, LSouth, LWest);
      if AStore.TileComplete(LSouth, LWest) then
      begin
        Inc(LAlready);
        QueueMarkDownloaded(LSouth, LWest);
      end
      else if not LTodo.Contains(TileName(LSouth, LWest)) then
        LTodo.Add(TileName(LSouth, LWest));
    end;
    if LAlready > 0 then
      AddLog(Format('%d tile(s) already downloaded', [LAlready]));
    if LTodo.Count = 0 then
    begin
      AddLog('Nothing to download.');
      Exit;
    end;

    // The report file; if it cannot be made, the detail goes to the Debug
    // tab as before
    try
      LReport := TDownloadReport.Create('download');
      LDetail := LReport.Add;
      LBoth :=
        procedure(const Msg: string)
        begin
          AddLog(Msg);
          LReport.Add(Msg);
        end;
      AddLog('Download report: ' + LReport.FileName);
      if LAlready > 0 then
        LReport.Add(Format('%d tile(s) already downloaded', [LAlready]));
    except
      on E: Exception do
      begin
        AddLog('WARNING: could not start a download report (' +
          E.Message.TrimRight(['.']) + '); details follow here instead');
        LDetail := AddLog;
        LBoth := AddLog;
      end;
    end;

    // 2. Ask CMR where they all are, many tiles per request
    ProgressStatus('Asking NASA CMR where the tiles are ...');
    LClock := TStopwatch.StartNew;
    LLookup := TGDEMDownloader.Create(ABearer);
    try
      LLookup.CancelToken := AToken;
      LLookup.OnLog := LDetail;
      LURLs := LLookup.LookUpTiles(LTodo.ToArray,
        procedure(ABatch, ABatches: Integer)
        begin
          ProgressOverall(ABatch - 1, ABatches,
            Format('Looking up tiles: request %d of %d', [ABatch, ABatches]));
        end);
    finally
      LLookup.Free;
    end;

    LNoData := 0;
    for LTile in LTodo do
      if LURLs.ContainsKey(LTile) then
        LQueueList.Add(LTile)
      else
      begin
        Inc(LNoData);
        LDetail('  no data for ' + LTile + ' (ocean or outside coverage)');
      end;
    LQueue := LQueueList.ToArray;
    LBoth(Format('Looked up %d tile(s) in NASA CMR in %s: %d have data',
      [LTodo.Count, FormatDuration(LClock.Elapsed.TotalSeconds), Length(LQueue)]));

    // 3. Download them, several tiles at a time. From here on LURLs is
    // only read, which is safe from several threads at once.
    LNext := -1;
    LDone := 0;
    LDownloaded := 0;
    LFailed := 0;
    LFailRun := 0;
    LBytes := 0;
    LSaved := 0;
    LLastUi := -1000;
    // Shared by every worker: limits files at once, climbing towards the
    // most while all goes well and backing off if NASA starts cutting off
    // or refusing downloads
    LMost := DOWNLOAD_SPEED_MAX[ASpeed];
    LThrottle := TDownloadThrottle.Create(DOWNLOAD_SPEED_START[ASpeed], LMost);
    LThrottle.OnLog := LBoth;
    LError := '';
    LStop := False;
    LBoth(Format('Downloading %d tile(s) at %s speed: %d at a time to start with, ' +
      'at most %d', [Length(LQueue), DOWNLOAD_SPEED_KEYS[ASpeed].ToLower,
      LThrottle.Allowed, LMost]));
    ProgressOverall(0, Length(LQueue), Format('Tile 0 of %d', [Length(LQueue)]));
    LClock := TStopwatch.StartNew;

    LWorker :=
      procedure
      var
        LIdx, LCount, LFailures, LS, LW: Integer;
        LName, LTileFolder, LMessage: string;
        LDownloader: TGDEMDownloader;
        LSpace, LPrev: Int64;
        LFatal: Boolean;
      begin
        LPrev := 0;
        LDownloader := TGDEMDownloader.Create(ABearer);
        try
          LDownloader.CancelToken := AToken;
          LDownloader.Throttle := LThrottle;
          LDownloader.OnLog := LDetail;
          LDownloader.OnProgress :=
            procedure(const FileName: string; Received, Total: Int64)
            var
              LNow, LLast: Int64;
              LSeconds: Double;
              LText: string;
              LAllowed: Integer;
            begin
              // Received starts again from 0 for each file and each retry
              if Received < LPrev then
                LPrev := 0;
              TInterlocked.Add(LBytes, Received - LPrev);
              LPrev := Received;

              // At most four screen updates a second, whichever worker
              LNow := LClock.ElapsedMilliseconds;
              LLast := TInterlocked.Read(LLastUi);
              if (LNow - LLast < 250) or
                 (TInterlocked.CompareExchange(LLastUi, LNow, LLast) <> LLast) then
                Exit;
              LText := FormatByteSize(TInterlocked.Read(LBytes)) + ' downloaded';
              LSeconds := LNow / 1000;
              if LSeconds >= 2 then
                LText := LText + Format(', %s/s',
                  [FormatByteSize(Round(TInterlocked.Read(LBytes) / LSeconds))]);
              LAllowed := LThrottle.Allowed;
              if LAllowed = 1 then
                ProgressItemText(Received, Total, FileName + ': ' + LText)
              else
                ProgressItemText(0, 0, Format('%d at a time: %s', [LAllowed, LText]));
            end;

          while not LStop and not AToken.Cancelled do
          begin
            LIdx := TInterlocked.Increment(LNext);
            if LIdx >= Length(LQueue) then
              Exit;
            LName := LQueue[LIdx];
            TryParseTileName(LName, LS, LW);
            LTileFolder := AStore.TileFolder(LS, LW);
            LMessage := '';
            LFatal := False;
            ProgressStatus('Downloading ' + LName);

            if not TDirectory.Exists(AStore.Root) then
            begin
              LFatal := True;
              LMessage := Format('Downloading stopped: the data folder %s is no longer ' +
                'available. If it is on a removable drive, check that it is still ' +
                'connected, then fetch again.', [AStore.Root]);
            end
            else
            begin
              // Every worker may be about to write a tile of about this size
              LSpace := AStore.FreeSpace;
              if (LSpace >= 0) and (LSpace - ESTIMATED_TILE_BYTES * LMost < AReserve) then
              begin
                LFatal := True;
                LMessage := Format('Downloading stopped: only %s is free on the data ' +
                  'drive, and %s must be kept free. Free some space or change the ' +
                  'reserve in File > Settings.',
                  [FormatByteSize(LSpace), FormatByteSize(AReserve)]);
              end
              else
                try
                  // Several workers may need the same new block folder at
                  // once, and ForceDirectories is not safe for that
                  TMonitor.Enter(LLock);
                  try
                    if not TDirectory.Exists(LTileFolder) then
                      ForceDirectories(LTileFolder);
                  finally
                    TMonitor.Exit(LLock);
                  end;
                  if not TDirectory.Exists(LTileFolder) then
                    raise EGDEMError.Create('the folder ' + LTileFolder + ' could not be created');

                  TInterlocked.Add(LSaved, LDownloader.DownloadFiles(LURLs[LName], LTileFolder));
                  if AStore.TileComplete(LS, LW) then
                  begin
                    TInterlocked.Increment(LDownloaded);
                    QueueMarkDownloaded(LS, LW);
                  end;
                  // A good tile ends any run of failures
                  TInterlocked.Exchange(LFailRun, 0);
                except
                  on E: EOperationCancelled do
                    Exit;
                  on E: EGDEMAuthError do
                  begin
                    // Every other tile would fail the same way
                    LFatal := True;
                    LMessage := E.Message;
                  end;
                  on E: Exception do
                  begin
                    // Already tried several times; skip the tile and carry on
                    TInterlocked.Increment(LFailed);
                    LFailures := TInterlocked.Increment(LFailRun);
                    LBoth(Format('  FAILED %s: %s', [LName, E.Message.TrimRight(['.'])]));
                    TMonitor.Enter(LLock);
                    try
                      if not LFolders.Contains(LTileFolder) then
                        LFolders.Add(LTileFolder);
                    finally
                      TMonitor.Exit(LLock);
                    end;
                    if LFailures >= MAX_DOWNLOAD_FAILURES then
                    begin
                      LFatal := True;
                      LMessage := Format('Downloading stopped after %d tiles in a row ' +
                        'failed; the last with: %s. The Debug tab lists them.',
                        [LFailures, E.Message.TrimRight(['.'])]);
                    end;
                  end;
                end;
            end;

            if LFatal then
            begin
              TMonitor.Enter(LLock);
              try
                // The first fatal problem is the one reported
                if LError = '' then
                  LError := LMessage;
                LStop := True;
                if not LFolders.Contains(LTileFolder) then
                  LFolders.Add(LTileFolder);
              finally
                TMonitor.Exit(LLock);
              end;
              Exit;
            end;

            LCount := TInterlocked.Increment(LDone);
            ProgressOverall(LCount, Length(LQueue),
              Format('Tile %d of %d', [LCount, Length(LQueue)]));
          end;
        finally
          LDownloader.Free;
        end;
      end;

    // Plain threads rather than the task pool, as this already runs on a
    // pool thread and must wait for the workers. There is one for the most
    // files allowed at once; the throttle holds back any not yet allowed.
    SetLength(LThreads, Min(LMost, Max(1, Length(LQueue))));
    for LIndex := 0 to High(LThreads) do
    begin
      LThreads[LIndex] := TThread.CreateAnonymousThread(LWorker);
      LThreads[LIndex].FreeOnTerminate := False;
    end;
    try
      for LIndex := 0 to High(LThreads) do
        LThreads[LIndex].Start;
      for LIndex := 0 to High(LThreads) do
        LThreads[LIndex].WaitFor;
    finally
      for LIndex := 0 to High(LThreads) do
        LThreads[LIndex].Free;
    end;

    // Only now that no worker is writing can empty folders be removed
    for LFolder in LFolders do
      AStore.PruneEmptyFolders(LFolder);

    // LClock was restarted when the downloads began, so the lookup is not
    // counted in the speed
    LSeconds := LClock.Elapsed.TotalSeconds;
    // The speed counts everything that arrived, including retries; the
    // size is what was saved
    LCutBack := '';
    if LThrottle.Lowest < LThrottle.Peak then
      LCutBack := Format(' (cut back to %d at worst, %d at the end)',
        [LThrottle.Lowest, LThrottle.Allowed]);
    LBoth(Format('Downloaded %d tile(s), %s, in %s at %s/s, up to %d at a time%s; %d were ' +
      'already here, %d have no data, %d failed.',
      [LDownloaded, FormatByteSize(LSaved), FormatDuration(LSeconds),
       FormatByteSize(Round(LBytes / Max(LSeconds, 0.001))), LThrottle.Peak, LCutBack,
       LAlready, LNoData, LFailed]));
    if LError <> '' then
      raise EGDEMError.Create(LError);
    AToken.Check;
    ProgressOverall(Length(LQueue), Length(LQueue), 'Finished');
    if LFailed > 0 then
      ReportError(Format('%d tile(s) could not be downloaded, even after several tries ' +
        'each, and were skipped. The Debug tab lists them and why. Fetch the same ' +
        'selection again to try them again; tiles already downloaded are skipped.',
        [LFailed]));
  except
    // Record why the batch stopped, then let the job report it as usual
    on E: Exception do
    begin
      if LReport <> nil then
        LReport.Add('Stopped: ' + E.Message);
      raise;
    end;
  end;
  finally
    LReport.Free;
    LThrottle.Free;
    LURLs.Free;
    LLock.Free;
    LFolders.Free;
    LQueueList.Free;
    LTodo.Free;
  end;
end;

end.
