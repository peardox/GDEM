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
    @item(@link(GDEMDownloader) finds and downloads tiles.)
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
  ) }
program GDEMFetch;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  MainForm in 'MainForm.pas' {frmMain},
  GDEMDownloader in 'GDEMDownloader.pas',
  GDEMCMR in 'GDEMCMR.pas',
  GDEMSettings in 'GDEMSettings.pas',
  GDEMBrowser in 'GDEMBrowser.pas',
  SettingsForm in 'SettingsForm.pas' {frmSettings},
  GDEMTiles in 'GDEMTiles.pas',
  GDEMWorldMap in 'GDEMWorldMap.pas',
  GDEMTileIndex in 'GDEMTileIndex.pas',
  GDEMCancel in 'GDEMCancel.pas',
  GDEMStore in 'GDEMStore.pas',
  ProgressForm in 'ProgressForm.pas' {frmProgress},
  GDEMStyles in 'GDEMStyles.pas',
  GDEMTitleBar in 'GDEMTitleBar.pas',
  GDEMThemes in 'GDEMThemes.pas',
  GDEMReport in 'GDEMReport.pas',
  GDEMAwake in 'GDEMAwake.pas',
  GDEMVectors in 'GDEMVectors.pas';

{$R *.res}
{ The world map image and its borders and coastlines, built from the
  RcItems in the project file. }
{$R *.dres}
{ The themes' FMX styles, inside the program on every platform. The .res is
  built by styles\buildstyles.cmd in the pre-build event; see
  styles\GDEMThemes.rc. }
{$R '..\styles\GDEMThemes.res'}

begin
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
