{ @abstract(TileMaker's main window: open an image, see how it divides,
  choose how to tile it, and save the tile set.)

  File > Open... reads an image (with Skia, so JPEG, PNG, WebP and the
  like). The right-hand panel shows its size, the prime factors of its
  width and height, and the levels of detail they allow, with the tiles
  each would need; the preview shows the tile grid of a chosen level over
  the image. The tile size, the smallest level's width, the tile format
  and quality, and whether the image is a whole-world map can be changed,
  and the plan follows.

  File > Save As... asks for a name and makes a folder of that name
  holding the tile set (see @code(GDEMTileSet)): a folder per level and a
  @code(tileset.json). The work runs in the background with a progress
  bar and a Cancel button.

  The form only shows things and starts work; the tiling itself is in
  @code(GDEMTiler), the resampling in @code(GDEMResample) and the
  arithmetic in @code(GDEMFactors). }
unit TileMakerForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Controls.Presentation,
  FMX.Menus, FMX.ListBox, FMX.Edit, FMX.EditBox, FMX.NumberBox,
  System.Skia, FMX.Skia,
  GDEMResample, GDEMTileSet, GDEMTiler;

const
  { Smallest tile size offered. Smaller tiles mean thousands of files for
    little gain. }
  MIN_OFFERED_TILE_SIZE = 16;

  { Largest tile size offered. Larger tiles take long to decode when only a
    corner is on screen. }
  MAX_OFFERED_TILE_SIZE = 2048;

type
  { @abstract(TileMaker's main window.) }
  TfrmTileMaker = class(TForm)
    { The menu bar. On macOS it is the system menu bar; on Linux it is
      replaced by an FMX one (see @link(UseFmxMenuBar)). }
    mnuMain: TMainMenu;
    { The File menu. }
    mnuFile: TMenuItem;
    { File > Open...: chooses an image to tile. }
    mnuOpen: TMenuItem;
    { File > Save As...: writes the tile set to a new folder. }
    mnuSaveAs: TMenuItem;
    { Separator above @link(mnuExit). Hidden on macOS. }
    mnuFileSep: TMenuItem;
    { File > Exit. Hidden on macOS, where Quit is in the application
      menu. }
    mnuExit: TMenuItem;
    { Holds the progress bar, its text and the Cancel button. }
    layProgress: TLayout;
    { What the background work is doing. }
    lblProgress: TLabel;
    { How far the background work has got through its current stage. }
    pbProgress: TProgressBar;
    { Stops the background work. }
    btnCancel: TButton;
    { Progress messages and results. }
    memLog: TMemo;
    { The right-hand panel. }
    layRight: TLayout;
    { The image's name and size. }
    lblSource: TLabel;
    { Holds the options. }
    layOptions: TLayout;
    { Caption for @link(cbTileSize). }
    lblTileSize: TLabel;
    { The tile sizes that cut every level exactly. }
    cbTileSize: TComboBox;
    { Caption for @link(nbCoarsest). }
    lblCoarsest: TLabel;
    { Halving stops once a level is no wider than this. }
    nbCoarsest: TNumberBox;
    { Caption for @link(cbFormat). }
    lblFormat: TLabel;
    { The tiles' file type, in the order of @code(TTileImageFormat). }
    cbFormat: TComboBox;
    { Caption for @link(nbQuality). }
    lblQuality: TLabel;
    { Encoding quality, 1 to 100. }
    nbQuality: TNumberBox;
    { Whether the image is a map of the whole world: bounds of 180 west to
      180 east, 90 north to 90 south, and resampling that wraps east to
      west. }
    chkWorld: TCheckBox;
    { Caption for @link(cbGridLevel). }
    lblGridLevel: TLabel;
    { Which level's tile grid the preview shows. }
    cbGridLevel: TComboBox;
    { The factors, levels and tile counts. }
    memPlan: TMemo;
    { The image, with a level's tile grid over it. }
    pbPreview: TSkPaintBox;

    { Sets up the lists and, on macOS and Linux, the menus.
      @param(Sender The form.) }
    procedure FormCreate(Sender: TObject);

    { Lets the window close only when no work is running; otherwise
      cancels it and closes once it has stopped.
      @param(Sender The form.)
      @param(CanClose Set to @false while work is stopping.) }
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);

    { Asks for an image and reads it in the background.
      @param(Sender The menu item.) }
    procedure mnuOpenClick(Sender: TObject);

    { Asks for a name and writes the tile set into a folder of that name.
      @param(Sender The menu item.) }
    procedure mnuSaveAsClick(Sender: TObject);

    { Closes the window.
      @param(Sender The menu item.) }
    procedure mnuExitClick(Sender: TObject);

    { Asks the background work to stop.
      @param(Sender The button.) }
    procedure btnCancelClick(Sender: TObject);

    { Works the plan out again after an option changes.
      @param(Sender The control that changed.) }
    procedure OptionChange(Sender: TObject);

    { Offers new tile sizes after the smallest level's width changes,
      since the levels, and so the sizes that fit, may have changed.
      @param(Sender The number box.) }
    procedure nbCoarsestChange(Sender: TObject);

    { Shows another level's tile grid.
      @param(Sender The combo box.) }
    procedure cbGridLevelChange(Sender: TObject);

    { Draws the preview: the image fitted to the box, and the tile grid of
      the level chosen in @link(cbGridLevel).
      @param(ASender The paint box.)
      @param(ACanvas Skia's canvas.)
      @param(ADest The area to draw in.)
      @param(AOpacity The opacity to draw at.) }
    procedure pbPreviewDraw(ASender: TObject; const ACanvas: ISkCanvas;
      const ADest: TRectF; const AOpacity: Single);
  private
    { The image, as read; empty until one is opened. }
    FSource: TRGBA8Image;
    { The image's file. }
    FSourceFile: string;
    { A small copy of the image for the preview; @nil until one is
      opened. }
    FPreview: ISkImage;
    { The plan for the current options; valid when @link(FPlanOk). }
    FPlan: TTileSet;
    { @true when @link(FPlan) is a valid plan. }
    FPlanOk: Boolean;
    { @true while an image is being read or a tile set written. }
    FBusy: Boolean;
    { Set by Cancel; the background work stops at its next step. }
    FCancel: Boolean;
    { Set when the window was asked to close during work; it closes once
      the work stops. }
    FCloseWhenIdle: Boolean;
    { @true while the lists are being filled, so their change events do
      nothing. }
    FUpdating: Boolean;
    { Linux only: the menu bar FMX draws itself; see
      @link(UseFmxMenuBar). }
    FFmxMenuBar: TMenuBar;

    { Adds a line to @link(memLog). Safe from any thread.
      @param(Msg The line.) }
    procedure AddLog(const Msg: string);

    { Shows background progress. Safe from any thread.
      @param(AStage What is being done.)
      @param(ADone Steps done.)
      @param(ATotal Steps in all.) }
    procedure ShowProgress(const AStage: string; ADone, ATotal: Integer);

    { Enables and disables the controls for whether work is running and an
      image is open. }
    procedure UpdateControls;

    { The options as currently set.
      @returns(The options; the tile size is 0 if none is chosen.) }
    function CurrentOptions: TTileOptions;

    { Fills @link(cbTileSize) with the sizes that cut every level of the
      image exactly, keeping the current choice if it still fits and
      otherwise choosing the one nearest 256. }
    procedure FillTileSizes;

    { Works out @link(FPlan) from the options, shows it in
      @link(memPlan), fills @link(cbGridLevel) and redraws the preview. }
    procedure UpdatePlan;

    { Reads an image in the background, then shows it.
      @param(AFileName The image.) }
    procedure StartOpen(const AFileName: string);

    { Writes the tile set in the background.
      @param(AFolder The folder to make it in.) }
    procedure StartSave(const AFolder: string);

    { Checks for Cancel; called between steps of the background work.
      @raises(EAbort if Cancel was pressed.) }
    procedure CheckCancel;

    {$IF defined(LINUX) and not defined(ANDROID)}
    { Replaces @link(mnuMain) with @link(FFmxMenuBar), which FMX draws
      itself: on Linux FMX shows a @code(TMainMenu) as a GTK menu bar that
      shows only the first letter of each item. The items are copied, the
      originals freed one at a time so FMX rebuilds the GTK bar empty, then
      @link(mnuMain) is freed and each copy given its original's name,
      which points the form's field at it. The same as GDEMFetch's
      @code(TfrmMain.UseFmxMenuBar). }
    procedure UseFmxMenuBar;
    {$ENDIF}
  end;

var
  { The application's main form. }
  frmTileMaker: TfrmTileMaker;

implementation

{$R *.fmx}

uses
  System.IOUtils, System.Math, System.StrUtils, System.Threading, FMX.DialogService,
  GDEMFactors;

{ TfrmTileMaker }

{$IF defined(LINUX) and not defined(ANDROID)}
procedure TfrmTileMaker.UseFmxMenuBar;
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
  FFmxMenuBar.Position.Y := -1;
  FFmxMenuBar.Align := TAlignLayout.Top;
  for LIndex := 0 to mnuMain.ItemsCount - 1 do
    if mnuMain.Items[LIndex] is TMenuItem then
      CopyItem(TMenuItem(mnuMain.Items[LIndex]), FFmxMenuBar);
  while mnuMain.ItemsCount > 0 do
    mnuMain.Items[0].Free;
  mnuMain.RecreateOSMenu;
  FreeAndNil(mnuMain);
  for LIndex := 0 to High(LCopies) do
    if LNames[LIndex] <> '' then
      LCopies[LIndex].Name := LNames[LIndex];
end;
{$ENDIF}

procedure TfrmTileMaker.FormCreate(Sender: TObject);
var
  LFormat: TTileImageFormat;
begin
  {$IF defined(LINUX) and not defined(ANDROID)}
  UseFmxMenuBar;
  {$ENDIF}
  {$IF defined(MACOS) and not defined(IOS)}
  mnuFileSep.Visible := False;
  mnuExit.Visible := False;
  {$ENDIF}
  lblSource.TextSettings.Font.Style := [TFontStyle.fsBold];
  FUpdating := True;
  try
    cbFormat.Items.Clear;
    for LFormat := Low(TTileImageFormat) to High(TTileImageFormat) do
      cbFormat.Items.Add(TILE_FORMAT_CAPTIONS[LFormat]);
    cbFormat.ItemIndex := Ord(TTileImageFormat.Jpeg);
    nbQuality.Min := 1;
    nbQuality.Max := 100;
    nbQuality.DecimalDigits := 0;
    nbQuality.Value := DEFAULT_TILE_QUALITY;
    nbCoarsest.Min := 64;
    nbCoarsest.Max := 65536;
    nbCoarsest.DecimalDigits := 0;
    nbCoarsest.Value := DEFAULT_COARSEST_WIDTH;
    chkWorld.IsChecked := True;
  finally
    FUpdating := False;
  end;
  memPlan.Lines.Text := 'Open an image with File > Open...';
  UpdateControls;
end;

procedure TfrmTileMaker.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FBusy;
  if FBusy then
  begin
    FCancel := True;
    FCloseWhenIdle := True;
    AddLog('Stopping before closing...');
  end;
end;

procedure TfrmTileMaker.AddLog(const Msg: string);
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

procedure TfrmTileMaker.ShowProgress(const AStage: string; ADone, ATotal: Integer);
var
  LStage: string;
begin
  LStage := AStage;
  TThread.Queue(nil,
    procedure
    begin
      lblProgress.Text := LStage;
      pbProgress.Max := Max(ATotal, 1);
      pbProgress.Value := ADone;
    end);
end;

procedure TfrmTileMaker.CheckCancel;
begin
  if FCancel then
    Abort;
end;

procedure TfrmTileMaker.UpdateControls;
var
  LOpen: Boolean;
begin
  LOpen := FSource.Width > 0;
  mnuOpen.Enabled := not FBusy;
  mnuSaveAs.Enabled := not FBusy and LOpen and FPlanOk;
  btnCancel.Enabled := FBusy;
  layOptions.Enabled := not FBusy and LOpen;
end;

function TfrmTileMaker.CurrentOptions: TTileOptions;
begin
  Result := TTileOptions.Defaults;
  if cbTileSize.ItemIndex >= 0 then
    Result.TileSize := StrToIntDef(cbTileSize.Items[cbTileSize.ItemIndex], 0);
  Result.CoarsestWidth := Round(nbCoarsest.Value);
  if cbFormat.ItemIndex >= 0 then
    Result.ImageFormat := TTileImageFormat(cbFormat.ItemIndex);
  Result.Quality := EnsureRange(Round(nbQuality.Value), 1, 100);
  if chkWorld.IsChecked then
  begin
    Result.Bounds := TTileSetBounds.World;
    Result.Projection := PROJECTION_EQUIRECTANGULAR;
    Result.WrapEastWest := True;
  end
  else
  begin
    // Not a map: the bounds are simply the image's own pixels
    Result.Bounds.West := 0;
    Result.Bounds.North := 0;
    Result.Bounds.East := FSource.Width;
    Result.Bounds.South := FSource.Height;
    Result.Projection := '';
    Result.WrapEastWest := False;
  end;
end;

procedure TfrmTileMaker.FillTileSizes;
var
  LLevels: TArray<TSize>;
  LSizes, LOffered: TArray<Integer>;
  LSize, LKeep, LIndex: Integer;
  LKept: Boolean;
begin
  LKeep := 0;
  if cbTileSize.ItemIndex >= 0 then
    LKeep := StrToIntDef(cbTileSize.Items[cbTileSize.ItemIndex], 0);
  LLevels := LevelSizes(FSource.Width, FSource.Height, Round(nbCoarsest.Value));
  LSizes := TileSizesFor(LLevels);
  LOffered := nil;
  for LSize in LSizes do
    if InRange(LSize, MIN_OFFERED_TILE_SIZE, MAX_OFFERED_TILE_SIZE) then
      LOffered := LOffered + [LSize];
  LKept := False;
  for LSize in LOffered do
    if LSize = LKeep then
      LKept := True;
  if not LKept then
    LKeep := SuggestTileSize(LOffered);

  FUpdating := True;
  try
    cbTileSize.Items.Clear;
    for LIndex := 0 to High(LOffered) do
    begin
      cbTileSize.Items.Add(IntToStr(LOffered[LIndex]));
      if LOffered[LIndex] = LKeep then
        cbTileSize.ItemIndex := LIndex;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TfrmTileMaker.UpdatePlan;
var
  LOptions: TTileOptions;
  LLines: TStringList;
  LLevel, LTotal, LKeepGrid: Integer;
  LGcd: Integer;
  LUnit: string;
begin
  FPlanOk := False;
  if FSource.Width = 0 then
  begin
    UpdateControls;
    Exit;
  end;
  LOptions := CurrentOptions;
  LGcd := GreatestCommonDivisor(FSource.Width, FSource.Height);
  LLines := TStringList.Create;
  try
    LLines.Add(Format('%d x %d', [FSource.Width, FSource.Height]));
    LLines.Add(Format('  %d = %s', [FSource.Width, FactorsText(PrimeFactors(FSource.Width))]));
    LLines.Add(Format('  %d = %s', [FSource.Height, FactorsText(PrimeFactors(FSource.Height))]));
    LLines.Add(Format('  shared: %d = %s', [LGcd, FactorsText(PrimeFactors(LGcd))]));
    LLines.Add('');
    if cbTileSize.Items.Count = 0 then
    begin
      LLines.Add(Format('No tile size from %d to %d pixels cuts every level exactly. ' +
        'Try another smallest width, or crop or resize the image so its sides ' +
        'share more factors.', [MIN_OFFERED_TILE_SIZE, MAX_OFFERED_TILE_SIZE]));
    end
    else
      try
        FPlan := PlanTileSet(FSourceFile, FSource.Width, FSource.Height, LOptions);
        FPlanOk := True;
        if LOptions.Projection = PROJECTION_EQUIRECTANGULAR then
          LUnit := 'px/degree'
        else
          LUnit := 'of full size';
        LLines.Add(Format('%d level(s), tiles of %d x %d:', [Length(FPlan.Levels),
          FPlan.TileSize, FPlan.TileSize]));
        LTotal := 0;
        for LLevel := 0 to High(FPlan.Levels) do
        begin
          if LOptions.Projection = PROJECTION_EQUIRECTANGULAR then
            LLines.Add(Format('  L%d  %d x %d  %d x %d = %d tiles  %s %s', [LLevel,
              FPlan.Levels[LLevel].Width, FPlan.Levels[LLevel].Height,
              FPlan.Levels[LLevel].Columns, FPlan.Levels[LLevel].Rows,
              FPlan.Levels[LLevel].Columns * FPlan.Levels[LLevel].Rows,
              FormatFloat('0.###', FPlan.PixelsPerUnit(LLevel)), LUnit]))
          else
            LLines.Add(Format('  L%d  %d x %d  %d x %d = %d tiles  1/%d %s', [LLevel,
              FPlan.Levels[LLevel].Width, FPlan.Levels[LLevel].Height,
              FPlan.Levels[LLevel].Columns, FPlan.Levels[LLevel].Rows,
              FPlan.Levels[LLevel].Columns * FPlan.Levels[LLevel].Rows,
              1 shl LLevel, LUnit]));
          Inc(LTotal, FPlan.Levels[LLevel].Columns * FPlan.Levels[LLevel].Rows);
        end;
        LLines.Add(Format('  %d tiles in all, as %s', [LTotal,
          TILE_FORMAT_CAPTIONS[LOptions.ImageFormat]]));
        LLines.Add('');
        LLines.Add('Smaller levels: ' + RESAMPLING_DESCRIPTION +
          IfThen(LOptions.WrapEastWest, ', wrapping east to west', ''));
      except
        on E: ETilerError do
          LLines.Add(E.Message);
      end;
    memPlan.Lines.Assign(LLines);
  finally
    LLines.Free;
  end;

  // The grid choice, keeping the level shown if it still exists
  LKeepGrid := cbGridLevel.ItemIndex;
  FUpdating := True;
  try
    cbGridLevel.Items.Clear;
    cbGridLevel.Items.Add('None');
    if FPlanOk then
      for LLevel := 0 to High(FPlan.Levels) do
        cbGridLevel.Items.Add(Format('L%d (%d x %d tiles)', [LLevel,
          FPlan.Levels[LLevel].Columns, FPlan.Levels[LLevel].Rows]));
    if InRange(LKeepGrid, 0, cbGridLevel.Items.Count - 1) then
      cbGridLevel.ItemIndex := LKeepGrid
    else
      cbGridLevel.ItemIndex := cbGridLevel.Items.Count - 1;
  finally
    FUpdating := False;
  end;
  pbPreview.Redraw;
  UpdateControls;
end;

procedure TfrmTileMaker.OptionChange(Sender: TObject);
begin
  if not FUpdating then
    UpdatePlan;
end;

procedure TfrmTileMaker.nbCoarsestChange(Sender: TObject);
begin
  if FUpdating or (FSource.Width = 0) then
    Exit;
  FillTileSizes;
  UpdatePlan;
end;

procedure TfrmTileMaker.cbGridLevelChange(Sender: TObject);
begin
  if not FUpdating then
    pbPreview.Redraw;
end;

procedure TfrmTileMaker.pbPreviewDraw(ASender: TObject; const ACanvas: ISkCanvas;
  const ADest: TRectF; const AOpacity: Single);
var
  LScale: Single;
  LImage: TRectF;
  LPaint: ISkPaint;
  LLevel, LIndex: Integer;
  LX, LY: Single;
begin
  if FPreview = nil then
    Exit;
  // Fitted, keeping its shape, and centred
  LScale := Min(ADest.Width / FPreview.Width, ADest.Height / FPreview.Height);
  LImage := TRectF.Create(0, 0, FPreview.Width * LScale, FPreview.Height * LScale);
  LImage.Offset(ADest.Left + (ADest.Width - LImage.Width) / 2,
    ADest.Top + (ADest.Height - LImage.Height) / 2);
  ACanvas.DrawImageRect(FPreview, LImage,
    TSkSamplingOptions.Create(TSkFilterMode.Linear, TSkMipmapMode.Linear));

  // The chosen level's tile grid
  LLevel := cbGridLevel.ItemIndex - 1;
  if not FPlanOk or not InRange(LLevel, 0, High(FPlan.Levels)) then
    Exit;
  LPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  LPaint.AntiAlias := True;
  LPaint.Color := TAlphaColors.White;
  LPaint.AlphaF := 0.6 * AOpacity;
  LPaint.StrokeWidth := 1;
  for LIndex := 0 to FPlan.Levels[LLevel].Columns do
  begin
    LX := LImage.Left + LImage.Width * LIndex / FPlan.Levels[LLevel].Columns;
    ACanvas.DrawLine(LX, LImage.Top, LX, LImage.Bottom, LPaint);
  end;
  for LIndex := 0 to FPlan.Levels[LLevel].Rows do
  begin
    LY := LImage.Top + LImage.Height * LIndex / FPlan.Levels[LLevel].Rows;
    ACanvas.DrawLine(LImage.Left, LY, LImage.Right, LY, LPaint);
  end;
end;

procedure TfrmTileMaker.mnuOpenClick(Sender: TObject);
var
  LDialog: TOpenDialog;
begin
  LDialog := TOpenDialog.Create(nil);
  try
    LDialog.Title := 'Open an image to tile';
    LDialog.Filter := 'Images|*.jpg;*.jpeg;*.png;*.webp;*.bmp;*.gif|All files|*';
    if LDialog.Execute then
      StartOpen(LDialog.FileName);
  finally
    LDialog.Free;
  end;
end;

procedure TfrmTileMaker.StartOpen(const AFileName: string);
var
  LFileName: string;
  LWrap: Boolean;
  LCoarsest: Integer;
begin
  LFileName := AFileName;
  LWrap := chkWorld.IsChecked;
  LCoarsest := Round(nbCoarsest.Value);
  FBusy := True;
  FCancel := False;
  UpdateControls;
  AddLog('Reading ' + LFileName + ' ...');
  ShowProgress('Reading the image', 0, 1);
  TTask.Run(
    procedure
    var
      LSource: TRGBA8Image;
      LSmall: TRGBA8Image;
      LLevels: TArray<TSize>;
      LFactor: Integer;
      LPreview: ISkImage;
      LError: string;
    begin
      LError := '';
      try
        LSource := LoadSourceImage(LFileName);
        // The preview is the smallest level, made the same way the tiles
        // will be, so it shows the quality too
        LLevels := LevelSizes(LSource.Width, LSource.Height, LCoarsest);
        LFactor := LSource.Width div LLevels[High(LLevels)].cx;
        LSmall := ReduceImage(LSource, LFactor, LWrap,
          procedure(ADone, ATotal: Integer)
          begin
            CheckCancel;
            ShowProgress('Making the preview', ADone, ATotal);
          end);
        LPreview := TSkImage.MakeRasterCopy(TSkImageInfo.Create(LSmall.Width, LSmall.Height,
          TSkColorType.RGBA8888, TSkAlphaType.Unpremul), @LSmall.Pixels[0], LSmall.RowBytes);
      except
        on E: EAbort do
          LError := 'Cancelled.';
        on E: Exception do
          LError := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          FBusy := False;
          ShowProgress('', 0, 1);
          if LError = '' then
          begin
            FSource := LSource;
            FSourceFile := LFileName;
            FPreview := LPreview;
            lblSource.Text := Format('%s  (%d x %d)', [TPath.GetFileName(LFileName),
              LSource.Width, LSource.Height]);
            AddLog(Format('Read %s: %d x %d', [LFileName, LSource.Width, LSource.Height]));
            FillTileSizes;
            UpdatePlan;
          end
          else
          begin
            AddLog('Could not open ' + LFileName + ': ' + LError);
            if not FCloseWhenIdle then
              ShowMessage('Could not open ' + LFileName + ':' + sLineBreak + LError);
          end;
          UpdateControls;
          if FCloseWhenIdle then
            Close;
        end);
    end);
end;

procedure TfrmTileMaker.mnuSaveAsClick(Sender: TObject);
var
  LDialog: TSaveDialog;
  LFolder: string;
begin
  if not FPlanOk then
    Exit;
  LDialog := TSaveDialog.Create(nil);
  try
    LDialog.Title := 'Save the tile set as (a folder of this name is made)';
    LDialog.FileName := FPlan.Name + '_' + IntToStr(FPlan.TileSize);
    LDialog.Filter := 'Tile set folder|*';
    if not LDialog.Execute then
      Exit;
    // The name chosen is the folder; any extension typed is dropped
    LFolder := TPath.Combine(TPath.GetDirectoryName(LDialog.FileName),
      TPath.GetFileNameWithoutExtension(LDialog.FileName));
  finally
    LDialog.Free;
  end;

  if TDirectory.Exists(LFolder) and not TDirectory.IsEmpty(LFolder) then
  begin
    // Only an old tile set is replaced; anything else is left alone
    if not TFile.Exists(TPath.Combine(LFolder, TILESET_FILE_NAME)) then
    begin
      ShowMessage(LFolder + ' already holds other files. Choose a new name, or an ' +
        'empty folder.');
      Exit;
    end;
    TDialogService.MessageDialog(LFolder + ' already holds a tile set. Replace it? ' +
      'Everything in that folder is deleted first.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0,
      procedure(const AResult: TModalResult)
      begin
        if AResult <> mrYes then
          Exit;
        try
          TDirectory.Delete(LFolder, True);
        except
          on E: Exception do
          begin
            ShowMessage('Could not clear ' + LFolder + ': ' + E.Message);
            Exit;
          end;
        end;
        StartSave(LFolder);
      end);
  end
  else
    StartSave(LFolder);
end;

procedure TfrmTileMaker.StartSave(const AFolder: string);
var
  LFolder: string;
  LPlan: TTileSet;
  LOptions: TTileOptions;
  LSource: TRGBA8Image;
begin
  LFolder := AFolder;
  LPlan := FPlan;
  LOptions := CurrentOptions;
  LSource := FSource;
  FBusy := True;
  FCancel := False;
  UpdateControls;
  AddLog('Writing the tile set to ' + LFolder + ' ...');
  TTask.Run(
    procedure
    var
      LError: string;
    begin
      LError := '';
      try
        WriteTileSet(LSource, LPlan, LFolder, LOptions,
          procedure(const AStage: string; ADone, ATotal: Integer)
          begin
            CheckCancel;
            ShowProgress(AStage, ADone, ATotal);
          end,
          AddLog);
      except
        on E: EAbort do
          LError := 'Cancelled; the folder has no tileset.json, so it is not a ' +
            'finished tile set.';
        on E: Exception do
          LError := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          FBusy := False;
          ShowProgress('', 0, 1);
          if LError <> '' then
          begin
            AddLog(LError);
            if not FCloseWhenIdle and not FCancel then
              ShowMessage('Could not write the tile set:' + sLineBreak + LError);
          end;
          UpdateControls;
          if FCloseWhenIdle then
            Close;
        end);
    end);
end;

procedure TfrmTileMaker.mnuExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmTileMaker.btnCancelClick(Sender: TObject);
begin
  if FBusy then
  begin
    FCancel := True;
    AddLog('Cancelling...');
  end;
end;

end.
