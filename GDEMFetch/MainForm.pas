{ @abstract(Main window of GDEMFetch.)

  Shows a world map (@link(TWorldMapView)) on which the user selects ASTER
  GDEM V3 tiles by dragging a box, then downloads them with
  @link(TGDEMDownloader). A single tile can also be typed in by name.

  The window has three tabs: @bold(Map) holds the world map, @bold(3D) is
  reserved for a 3D view to come, and @bold(Debug) holds the log. The
  toolbar, progress bar and status bar stay visible on every tab.

  Serious problems, such as a failed download, a failed tile index build,
  unreadable settings or a missing world map, are written to the log and
  also shown in a modal error dialog (see @link(TfrmMain.ReportError)), so
  they are noticed even when the Debug tab is not open. Cancelling is not
  treated as an error.

  The world map image is linked into the program as the @code(WORLDMAP)
  RCDATA resource, so nothing has to be deployed alongside the program on
  any platform.

  Which tiles have data is held in a @link(TTileIndex), loaded from the
  settings folder at start-up. If there is no index yet, one is built from
  NASA CMR in the background; @bold(File > Refresh Tile Index) rebuilds it.
  With an index, the map tints tiles that have data and
  @bold(Fetch selection) skips the rest without asking CMR about each one.

  The Earthdata Login bearer token comes from @link(TGDEMSettings) and is
  edited through @bold(File > Settings), which opens
  @link(TfrmSettings). If no settings file exists when the program starts,
  the settings dialog is shown automatically.

  Downloads run on a background task so the window stays responsive; all
  updates to controls are queued back to the main thread. }
unit MainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  System.Threading, FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Edit, FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Layouts,
  FMX.Controls.Presentation, FMX.Menus, FMX.TabControl,
  GDEMSettings, GDEMDownloader, GDEMWorldMap, GDEMTileIndex;

const
  { Name of the RCDATA resource holding the world map image. }
  WORLD_MAP_RESOURCE = 'WORLDMAP';

  { Selections larger than this many tiles ask for confirmation before
    downloading. }
  CONFIRM_TILE_COUNT = 10;

type
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
    { Separator above @link(mnuShowTiles). }
    mnuViewSep: TMenuItem;
    { View > Show Available Tiles: toggles the tint on tiles with data. }
    mnuShowTiles: TMenuItem;
    { Toolbar above the map. }
    layTop: TLayout;
    { Caption for @link(edtTile). }
    lblTile: TLabel;
    { Tile to fetch by name, such as @code(N50W002). Filled in when a single
      tile is selected on the map. }
    edtTile: TEdit;
    { Fetches the tile named in @link(edtTile). }
    btnFetch: TButton;
    { Fetches every tile in the map selection. }
    btnFetchSelection: TButton;
    { Stops the current download. Enabled only while one is running. }
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
    { Progress of the current file, from 0 to 100. }
    pbDownload: TProgressBar;
    { Status bar under the log. }
    layStatus: TLayout;
    { Shows the position and tile under the mouse pointer. }
    lblHover: TLabel;
    { Shows the folder files are saved to. }
    lblFolder: TLabel;

    { Creates the map, loads the settings, and queues the settings dialog
      if there are none.
      @param(Sender The form.) }
    procedure FormCreate(Sender: TObject);

    { Frees the settings.
      @param(Sender The form.) }
    procedure FormDestroy(Sender: TObject);

    { Lets the window close only when no download is running. If one is,
      it is cancelled and the window closes once it has stopped, so no
      queued update can reach a freed form.
      @param(Sender The form.)
      @param(CanClose Set to @false while a download is still stopping.) }
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);

    { Fetches the tile named in @link(edtTile).
      @param(Sender The button.) }
    procedure btnFetchClick(Sender: TObject);

    { Fetches every tile in the map selection, confirming large ones.
      @param(Sender The button.) }
    procedure btnFetchSelectionClick(Sender: TObject);

    { Asks the running download to stop.
      @param(Sender The button.) }
    procedure btnCancelClick(Sender: TObject);

    { Opens the settings dialog.
      @param(Sender The menu item.) }
    procedure mnuSettingsClick(Sender: TObject);

    { Closes the application.
      @param(Sender The menu item.) }
    procedure mnuExitClick(Sender: TObject);

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
  private
    { The user's saved settings, loaded at start-up. }
    FSettings: TGDEMSettings;

    { The world map, created in @link(FormCreate). }
    FMap: TWorldMapView;

    { The downloader for the batch in progress, or @nil when idle. Created
      and freed on the main thread, so @link(btnCancelClick) can safely
      reach it. }
    FDownloader: TGDEMDownloader;

    { Which tiles have data. Owned by the form and shown on @link(FMap).
      Empty until loaded or built. Only touched on the main thread. }
    FTileIndex: TTileIndex;

    { The tile index build in progress, or @nil when idle. Created and freed
      on the main thread. }
    FIndexBuilder: TTileIndexBuilder;

    { Folder downloaded tiles are saved to: an @code(ASTGTM) folder inside
      the user's documents folder on every platform. }
    FDestFolder: string;

    { Set when the user tries to close the window during a download, so it
      closes once the download has stopped. }
    FCloseWhenIdle: Boolean;

    { Adds a line to @link(memLog). Safe to call from any thread.
      @param(Msg The line to add.) }
    procedure AddLog(const Msg: string);

    { Reports a serious problem: logs it and shows it in a modal error
      dialog. Safe to call from any thread. The dialog is queued, so it
      appears once the main thread is free (after the window has been shown,
      when called during start-up). Nothing is shown while the window is
      closing.
      @param(AMessage Description of the problem.) }
    procedure ReportError(const AMessage: string);

    { Loads the world map image from the @link(WORLD_MAP_RESOURCE)
      resource into @link(FMap), logging any failure. }
    procedure LoadWorldMap;

    { Updates the selection label and buttons after the map selection
      changes, and copies a single selected tile into @link(edtTile).
      @param(Sender The map view.) }
    procedure MapSelectionChanged(Sender: TObject);

    { Shows the position and tile under the pointer in the status bar.
      @param(Sender The map view.)
      @param(ALat Latitude under the pointer.)
      @param(ALon Longitude under the pointer.)
      @param(AOnMap @false when the pointer is off the map.) }
    procedure MapHover(Sender: TObject; ALat, ALon: Double; AOnMap: Boolean);

    { Enables and disables controls to match whether a download is
      running. }
    procedure UpdateButtons;

    { Opens the settings dialog.
      @param(AOnSaved Called after the dialog closes, only if new settings
        were saved. May be @nil.) }
    procedure ShowSettings(const AOnSaved: TProc);

    { Loads the tile index from its default file, or starts building one if
      there is none or it cannot be read. }
    procedure LoadTileIndex;

    { Builds a new tile index from CMR on a background task. On success it
      replaces the current index, is saved, and the map is updated. Does
      nothing if a build is already running. }
    procedure StartIndexBuild;

    { Closes the window if a close was deferred and nothing is running any
      more. }
    procedure CloseIfIdle;

    { Downloads tiles, asking for a bearer token first if none is saved.
      @param(ATiles Tile names such as @code(N50W002).) }
    procedure FetchTiles(const ATiles: TArray<string>);

    { Downloads tiles one after another on a background task, using the
      saved bearer token. Tiles with no data are logged and skipped. The
      batch stops at the first error or when cancelled.
      @param(ATiles Tile names such as @code(N50W002).) }
    procedure StartFetch(const ATiles: TArray<string>);
  end;

var
  { The application's main form instance. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  System.Math, FMX.DialogService,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  GDEMTiles, SettingsForm;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  LHaveSettings: Boolean;
begin
  {$IF defined(MACOS) and not defined(IOS)}
  mnuFileSep.Visible := False;
  mnuExit.Visible := False;
  {$ENDIF}

  FDestFolder := TPath.Combine(TPath.GetDocumentsPath, 'ASTGTM');
  lblFolder.Text := 'Save to: ' + FDestFolder;
  edtTile.Text := 'N50W002';

  FMap := TWorldMapView.Create(Self);
  FMap.Parent := layMap;
  FMap.Align := TAlignLayout.Client;
  FMap.OnSelectionChanged := MapSelectionChanged;
  FMap.OnHover := MapHover;
  LoadWorldMap;

  FTileIndex := TTileIndex.Create;
  FMap.TileIndex := FTileIndex;
  LoadTileIndex;
  MapSelectionChanged(FMap);

  FSettings := TGDEMSettings.Create;
  try
    LHaveSettings := FSettings.Load;
  except
    on E: Exception do
    begin
      ReportError(E.Message);
      LHaveSettings := False;
    end;
  end;

  // The form is not visible yet, so show the dialog once it is
  if not LHaveSettings then
    TThread.ForceQueue(nil,
      procedure
      begin
        ShowSettings(nil);
      end);
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FSettings.Free;
  FTileIndex.Free;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := (FDownloader = nil) and (FIndexBuilder = nil);
  if not CanClose then
  begin
    FCloseWhenIdle := True;
    if FDownloader <> nil then
      FDownloader.Cancel;
    if FIndexBuilder <> nil then
      FIndexBuilder.Cancel;
    AddLog('Stopping before closing...');
  end;
end;

procedure TfrmMain.CloseIfIdle;
begin
  if FCloseWhenIdle and (FDownloader = nil) and (FIndexBuilder = nil) then
    Close;
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
    AddLog('No tile index yet; building one from NASA CMR (no login needed).');
  except
    on E: Exception do
      AddLog('WARNING: ' + E.Message + ' Rebuilding it.');
  end;
  TThread.ForceQueue(nil, StartIndexBuild);
end;

procedure TfrmMain.StartIndexBuild;
var
  LBuilder: TTileIndexBuilder;
begin
  if FIndexBuilder <> nil then
    Exit;

  LBuilder := TTileIndexBuilder.Create;
  LBuilder.OnLog := AddLog;
  LBuilder.OnProgress :=
    procedure(APage, APages, ATiles: Integer)
    begin
      if APages > 0 then
        AddLog(Format('  page %d of %d: %d tiles so far', [APage, APages, ATiles]))
      else
        AddLog(Format('  page %d: %d tiles so far', [APage, ATiles]));
    end;
  FIndexBuilder := LBuilder;
  UpdateButtons;

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
          UpdateButtons;
          CloseIfIdle;
        end);

      // Queued after the clean-up above, so the dialog appears once the
      // buttons are usable again
      if LError <> '' then
        ReportError('Could not build the tile index: ' + LError);
    end);
end;

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
end;

procedure TfrmMain.MapSelectionChanged(Sender: TObject);
var
  LSelection: TTileRect;
begin
  LSelection := FMap.Selection;
  lblSelection.Text := LSelection.Describe;
  if not LSelection.IsEmpty and not FTileIndex.IsEmpty then
    lblSelection.Text := lblSelection.Text +
      Format(', %d with data', [FTileIndex.CountIn(LSelection)]);
  if LSelection.Count = 1 then
    edtTile.Text := TileName(LSelection.South, LSelection.West);
  UpdateButtons;
end;

procedure TfrmMain.MapHover(Sender: TObject; ALat, ALon: Double; AOnMap: Boolean);
const
  DATA_TEXT: array[Boolean] of string = (' (no data)', ' (data)');
begin
  if not AOnMap then
  begin
    lblHover.Text := '';
    Exit;
  end;
  lblHover.Text := Format('%s  %s   tile %s',
    [FormatLat(ALat), FormatLon(ALon), TileNameAt(ALat, ALon)]);
  if not FTileIndex.IsEmpty then
    lblHover.Text := lblHover.Text +
      DATA_TEXT[FTileIndex.Has(Floor(ALat), Floor(ALon))];
end;

procedure TfrmMain.UpdateButtons;
var
  LBusy: Boolean;
begin
  LBusy := FDownloader <> nil;
  btnFetch.Enabled := not LBusy;
  btnFetchSelection.Enabled := not LBusy and not FMap.Selection.IsEmpty;
  btnCancel.Enabled := LBusy;
  mnuZoomSelection.Enabled := not FMap.Selection.IsEmpty;
  mnuRefreshIndex.Enabled := FIndexBuilder = nil;
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

procedure TfrmMain.mnuRefreshIndexClick(Sender: TObject);
begin
  StartIndexBuild;
end;

procedure TfrmMain.mnuShowTilesClick(Sender: TObject);
begin
  FMap.ShowAvailableTiles := mnuShowTiles.IsChecked;
end;

procedure TfrmMain.ShowSettings(const AOnSaved: TProc);
begin
  TfrmSettings.Edit(FSettings,
    procedure(ASaved: Boolean)
    begin
      if ASaved then
      begin
        AddLog('Settings saved to ' + TGDEMSettings.SettingsFileName);
        if Assigned(AOnSaved) then
          AOnSaved();
      end;
    end);
end;

procedure TfrmMain.AddLog(const Msg: string);
var
  LMsg: string;
begin
  LMsg := Msg;
  TThread.Queue(nil,
    procedure
    begin
      memLog.Lines.Add(LMsg);
      memLog.GoToTextEnd;
    end);
end;

procedure TfrmMain.ReportError(const AMessage: string);
var
  LMsg: string;
begin
  LMsg := AMessage;
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

procedure TfrmMain.btnFetchClick(Sender: TObject);
begin
  FetchTiles([Trim(edtTile.Text)]);
end;

procedure TfrmMain.btnFetchSelectionClick(Sender: TObject);
var
  LTiles: TArray<string>;
  LQuestion: string;
begin
  if FTileIndex.IsEmpty then
  begin
    // No index yet: try every tile and let CMR say which have data
    LTiles := FMap.Selection.TileNames;
    LQuestion := Format('The selection covers %d tiles. Tiles with no data are ' +
      'skipped, but each land tile is about 25 MB or more. Download them?',
      [Length(LTiles)]);
  end
  else
  begin
    LTiles := FTileIndex.TileNamesIn(FMap.Selection);
    if Length(LTiles) = 0 then
    begin
      ShowMessage('None of the selected tiles have ASTER GDEM data.');
      Exit;
    end;
    LQuestion := Format('%d of the selected tiles have data, about 25 MB or more ' +
      'each. Download them?', [Length(LTiles)]);
  end;

  if Length(LTiles) <= CONFIRM_TILE_COUNT then
    FetchTiles(LTiles)
  else
    TDialogService.MessageDialog(LQuestion,
      TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
      TMsgDlgBtn.mbNo, 0,
      procedure(const AResult: TModalResult)
      begin
        if AResult = mrYes then
          FetchTiles(LTiles);
      end);
end;

procedure TfrmMain.btnCancelClick(Sender: TObject);
begin
  if FDownloader <> nil then
  begin
    FDownloader.Cancel;
    AddLog('Cancelling...');
  end;
end;

procedure TfrmMain.FetchTiles(const ATiles: TArray<string>);
var
  LTiles: TArray<string>;
begin
  LTiles := ATiles;
  if FSettings.BearerToken = '' then
    ShowSettings(
      procedure
      begin
        StartFetch(LTiles);
      end)
  else
    StartFetch(LTiles);
end;

procedure TfrmMain.StartFetch(const ATiles: TArray<string>);
var
  LTiles: TArray<string>;
  LFolder: string;
  LDownloader: TGDEMDownloader;
begin
  if (FDownloader <> nil) or (FSettings.BearerToken = '') or (Length(ATiles) = 0) then
    Exit;

  LTiles := ATiles;
  LFolder := FDestFolder;
  LDownloader := TGDEMDownloader.Create(FSettings.BearerToken);
  LDownloader.OnLog := AddLog;
  LDownloader.OnProgress :=
    procedure(const FileName: string; Received, Total: Int64)
    begin
      TThread.Queue(nil,
        procedure
        begin
          if Total > 0 then
            pbDownload.Value := Received * 100 / Total;
        end);
    end;
  FDownloader := LDownloader;
  pbDownload.Value := 0;
  UpdateButtons;

  TTask.Run(
    procedure
    var
      LIndex, LFound, LEmpty: Integer;
      LError: string;
      LCancelled: Boolean;
    begin
      LCancelled := False;
      LFound := 0;
      LEmpty := 0;
      LError := '';
      try
        for LIndex := 0 to High(LTiles) do
        begin
          if Length(LTiles) > 1 then
            AddLog(Format('[%d/%d] %s', [LIndex + 1, Length(LTiles), LTiles[LIndex]]));
          if LDownloader.DownloadTileIfExists(LTiles[LIndex], LFolder) then
            Inc(LFound)
          else
          begin
            Inc(LEmpty);
            AddLog('  no data for ' + LTiles[LIndex] + ' (ocean or outside coverage)');
          end;
        end;
      except
        on E: EGDEMCancelled do
          LCancelled := True;
        on E: Exception do
          LError := E.Message;
      end;

      if LCancelled then
        AddLog(Format('Cancelled after %d tile(s) with data, %d without.',
          [LFound, LEmpty]))
      else if LError = '' then
        AddLog(Format('Done: %d tile(s) with data, %d without.', [LFound, LEmpty]));

      // Free the downloader on the main thread, where FDownloader lives
      TThread.Queue(nil,
        procedure
        begin
          FDownloader := nil;
          LDownloader.Free;
          UpdateButtons;
          CloseIfIdle;
        end);

      // Queued after the clean-up above, so the dialog appears once the
      // buttons are usable again
      if LError <> '' then
        ReportError('Download failed: ' + LError);
    end);
end;

end.
