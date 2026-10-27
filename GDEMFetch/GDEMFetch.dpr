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
    @item(@link(GDEMVectors) holds the country borders, coastlines and
      country names drawn on the map.)
    @item(@link(GDEMDrawing) tells Skia whether to draw on the GPU or the
      CPU, before the program starts up.)
    @item(@link(GDEMGpuPreference) reads and sets Windows' choice of
      graphics processor for the program.)
  ) }
program GDEMFetch;

uses
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
  GDEMGpuPreference in 'lib\GDEMGpuPreference.pas';

{$R *.res}
{ The world map image and its borders and coastlines, built from the
  RcItems in the project file. }
{$R *.dres}
{ The themes' FMX styles, inside the program on every platform. The .res is
  built by styles\buildstyles.cmd in the pre-build event; see
  styles\GDEMThemes.rc. }
{$R '..\styles\GDEMThemes.res'}

begin
  // Skia, on the GPU or the CPU as File > Settings says; it must be set
  // before Application.Initialize
  ConfigureDrawing;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
