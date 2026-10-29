{ @abstract(GDEMFetch: downloads ASTER GDEM V3 elevation tiles.)

  A small cross-platform FMX application that fetches the @code(_dem.tif)
  and @code(_num.tif) GeoTIFF files of an ASTER Global Digital Elevation
  Model V3 tile from NASA Earthdata Cloud, using an Earthdata Login bearer
  token. It is the first step of the GDEM project.

  @unorderedList(
    @item(@link(MainForm) holds the main window.)
    @item(@link(SettingsForm) is the modal settings dialog.)
    @item(@link(ProgressForm) is the modal progress dialog for downloads.)
    @item(@link(GDEMSettings) stores settings as JSON in a per-user folder.)
    @item(@link(GDEMBrowser) opens web pages in the default browser.)
    @item(@link(GDEMWorldMap) is the zoomable map used to select tiles.)
    @item(@link(GDEMTiles) names and selects tiles on the 1 degree grid.)
    @item(@link(GDEMTileIndex) records which tiles exist, built from CMR.)
    @item(@link(GDEMDownloader) finds and downloads tiles, and
      @link(GDEMDownloadBatch) runs a whole batch of downloads.)
    @item(@link(GDEMStore) keeps downloaded tiles in the data folder.)
    @item(@link(GDEMCancel) lets the user cancel background work.)
    @item(@link(GDEMThemes), @link(GDEMStyles) and @link(GDEMTitleBar) give
      the program its chosen look.)
    @item(@link(GDEMCMR) models and parses NASA CMR search results with the
      Neon JSON library.)
    @item(@link(GDEMReport) writes the full record of each batch of
      downloads to a report file.)
    @item(@link(GDEMAwake) keeps the computer from sleeping while a job
      runs.)
    @item(@link(GDEMVectors) holds the country borders, coastlines,
      country names and towns and cities drawn on the map.)
    @item(@link(GDEMSearch) finds countries, places and markers by name,
      forgiving spelling mistakes; @link(GDEMMarkers) keeps the user's
      markers, which @link(MarkersForm) lists for renaming and deleting.)
    @item(@link(GDEMViewOptions) remembers what the View menu shows.)
    @item(@link(GDEMEasterEggs) reads a few hidden places for the search
      to find.)
    @item(@link(GDEMDrawing) tells Skia whether to draw on the GPU or the
      CPU, before the program starts up.)
    @item(@link(GDEMGpuPreference) reads and sets Windows' choice of
      graphics processor for the program.)
    @item(@link(GDEMMapTiles) opens the tile set built into the program
      as the high-resolution map; @link(GDEMTileSet) (shared with
      TileMaker) and @link(GDEMTileCache), in the repository's
      @code(common) folder, read it.)
    @item(@link(GDEMGeoTiff), in @code(common), reads the downloaded
      GeoTIFF tiles; @link(GDEMTerrain) makes patches of the surface from
      them, @link(GDEMTerrainLod) decides which to draw and has them made
      on worker threads, and @link(GDEMTerrainView) shows them on the 3D
      tab with Gorilla3D, drawn with @link(GDEMImagery)'s satellite
      imagery when Realistic is on, flown over as @link(GDEMFlight) moves, with
      @link(GDEMTerrainHud)'s instruments over it and no faster than the
      display refreshes (@link(GDEMDisplays)).)
    @item(@link(GDEMSystemInfo), in @code(common), reads the computer's
      memory and graphics processors, and this program's use of them, for
      the log.)
    @item(On Windows, FastMM5 (a submodule in @code(FastMM5)) is the
      memory manager; with @code(REPORT_LEAKS) defined, leaks are reported
      at shut-down.)
  ) }
program GDEMFetch;

// Define to report memory leaks at shut-down (see below); leave it off for
// a release build
// {$DEFINE REPORT_LEAKS}

uses
  // On Windows FastMM5 is the memory manager, so it must come first; with
  // REPORT_LEAKS defined it writes the full leak report to a file
  {$IFDEF MSWINDOWS}
  FastMM5,
  {$ENDIF}
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  MainForm in 'ui\MainForm.pas' {frmMain},
  GDEMDownloader in 'lib\GDEMDownloader.pas',
  GDEMDownloadBatch in 'lib\GDEMDownloadBatch.pas',
  GDEMCMR in 'lib\GDEMCMR.pas',
  GDEMSettings in 'lib\GDEMSettings.pas',
  GDEMBrowser in 'lib\GDEMBrowser.pas',
  SettingsForm in 'ui\SettingsForm.pas' {frmSettings},
  GDEMTiles in 'lib\GDEMTiles.pas',
  GDEMWorldMap in 'ui\GDEMWorldMap.pas',
  GDEMTileIndex in 'lib\GDEMTileIndex.pas',
  GDEMCancel in 'lib\GDEMCancel.pas',
  GDEMStore in 'lib\GDEMStore.pas',
  ProgressForm in 'ui\ProgressForm.pas' {frmProgress},
  GDEMStyles in 'ui\GDEMStyles.pas',
  GDEMTitleBar in 'ui\GDEMTitleBar.pas',
  GDEMThemes in 'ui\GDEMThemes.pas',
  GDEMReport in 'lib\GDEMReport.pas',
  GDEMAwake in 'lib\GDEMAwake.pas',
  GDEMVectors in 'lib\GDEMVectors.pas',
  GDEMDrawing in 'ui\GDEMDrawing.pas',
  GDEMGpuPreference in 'lib\GDEMGpuPreference.pas',
  GDEMMapTiles in 'lib\GDEMMapTiles.pas',
  GDEMTileSet in '..\common\GDEMTileSet.pas',
  GDEMTileCache in '..\common\GDEMTileCache.pas',
  GDEMGeoTiff in '..\common\GDEMGeoTiff.pas',
  GDEMSystemInfo in '..\common\GDEMSystemInfo.pas',
  GDEMMarkers in 'lib\GDEMMarkers.pas',
  GDEMSearch in 'lib\GDEMSearch.pas',
  MarkersForm in 'ui\MarkersForm.pas' {frmMarkers},
  GDEMViewOptions in 'lib\GDEMViewOptions.pas',
  GDEMEasterEggs in 'lib\GDEMEasterEggs.pas',
  GDEMTerrain in 'lib\GDEMTerrain.pas',
  GDEMTerrainLod in 'lib\GDEMTerrainLod.pas',
  GDEMFlight in 'lib\GDEMFlight.pas',
  GDEMImagery in 'lib\GDEMImagery.pas',
  GDEMBookmarks in 'lib\GDEMBookmarks.pas',
  GDEMFlightPath in 'lib\GDEMFlightPath.pas',
  BookmarkForm in 'ui\BookmarkForm.pas',
  FlightPathForm in 'ui\FlightPathForm.pas',
  GDEMDisplays in 'ui\GDEMDisplays.pas',
  GDEMTerrainHud in 'ui\GDEMTerrainHud.pas',
  GDEMTerrainView in 'ui\GDEMTerrainView.pas';

{$R *.res}
{ The world map image and its borders and coastlines, built from the
  RcItems in the project file. }
{$R *.dres}
{ The themes' FMX styles, inside the program on every platform. The .res is
  built by styles\buildstyles.cmd in the pre-build event; see
  styles\GDEMThemes.rc. }
{$R '..\styles\GDEMThemes.res'}

begin
  {$IF DEFINED(REPORT_LEAKS)}
  // Leaks still allocated at shut-down are listed in a message box. On
  // Windows FastMM5 also writes every leak, in full, to
  // GDEMFetch_MemoryManager_EventLog.txt beside the executable, its default
  // place. It adds to that file each run, so the last run's is deleted
  // first and the file holds only this run's leaks; no file, no leaks.
  ReportMemoryLeaksOnShutdown := True;
  {$IF DEFINED(MSWINDOWS)}
  FastMM_DeleteEventLogFile;
  FastMM_LogToFileEvents := FastMM_LogToFileEvents +
    [mmetUnexpectedMemoryLeakSummary, mmetUnexpectedMemoryLeakDetail];
  // Gorilla3D 1.5.3 makes a lock (a plain TObject) in
  // Gorilla.Context.Vulkan's initialization and keeps it on purpose at
  // shut-down, since units finalized after it may still need it. Its
  // variable is not visible outside the unit, so one TObject is registered
  // as expected; a report of a plain TObject means one more has leaked
  FastMM_RegisterExpectedMemoryLeak(TObject, 1);
  {$ENDIF}
  {$ENDIF}
  {$IF DEFINED(MSWINDOWS)}
  // FastMM5's count of the bytes allocated, for the memory lines in the
  // log (GDEMSystemInfo)
  ProgramHeapReader :=
    function: Int64
    begin
      Result := Int64(FastMM_GetUsageSummary(50).AllocatedBytes);
    end;
  {$ENDIF}
  // Skia, on the GPU or the CPU as File > Settings says; it must be set
  // before Application.Initialize
  ConfigureDrawing;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
