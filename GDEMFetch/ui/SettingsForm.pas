{ @abstract(Modal dialog for editing the application settings.)

  Shows:
  @unorderedList(
    @item(the Earthdata Login bearer token, in a multi-line box since tokens
      are long, with a clickable link to the page where tokens are
      generated;)
    @item(the data folder that downloaded tiles are kept in, with a Browse
      button;)
    @item(how much free space downloads must leave on that drive;)
    @item(how many files an import copies at once, and how fast tiles are
      downloaded: Slow, Medium or Fast, see @link(TDownloadSpeed);)
    @item(the theme, the program's look; see @link(GDEMThemes);)
    @item(whether the program draws on the GPU or the CPU, see
      @link(GDEMDrawing), which takes effect at the next start. Not shown
      where Skia has no GPU drawing (Linux);)
    @item(on Windows, which graphics processor Windows starts the program
      on: let Windows decide, power saving or high performance, see
      @link(GDEMGpuPreference). It is written to Windows' own setting as
      soon as OK is pressed, if it changed, and takes effect at the next
      start.)
  )

  The token, free-space setting and theme are saved by the dialog itself;
  the caller applies a changed theme. A new
  data folder is only handed back to the caller (see
  @link(TSettingsClosedProc)), because switching folders may mean moving a
  large amount of data, which the caller arranges.

  Use @link(TfrmSettings.Edit) rather than creating the form directly. On
  desktop platforms it shows the dialog with a blocking @code(ShowModal);
  on Android, where blocking modal calls are not supported, it uses the
  callback form instead. Either way the caller is told the outcome through
  a @link(TSettingsClosedProc), after the dialog has been freed. }
unit SettingsForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Layouts,
  FMX.Controls.Presentation, FMX.Edit, FMX.EditBox, FMX.NumberBox, FMX.ListBox,
  GDEMSettings;

const
  { The choices offered for how many files an import copies at once. }
  IMPORT_WORKER_CHOICES: array[0..7] of Integer = (1, 2, 4, 6, 8, 10, 12, 16);

  { Height of the Drawing row under the theme, in pixels, removed where
    there is no choice to offer (see @link(GPU_DRAWING_AVAILABLE)). }
  DRAWING_ROW_HEIGHT = 24;

  { Page where an Earthdata Login user generates a bearer token. }
  EARTHDATA_TOKEN_URL = 'https://urs.earthdata.nasa.gov';

  { Smallest free-space reserve the dialog allows, in megabytes. }
  MIN_FREE_SPACE_LOWER_MB = 100;

  { Largest free-space reserve the dialog allows, in megabytes (1 TB). }
  MIN_FREE_SPACE_UPPER_MB = 1024 * 1024;

type
  { Called when the settings dialog closes.
    @param(ASaved @true if the user pressed OK and the settings were
      saved successfully.)
    @param(ADataFolder The data folder chosen in the dialog. It has not
      been stored in the settings; compare it with
      @link(TGDEMSettings.DataFolder) to see whether the user wants to
      change folder. Meaningful only when ASaved is @true.) }
  TSettingsClosedProc = reference to procedure(ASaved: Boolean; const ADataFolder: string);

  { @abstract(The settings dialog.) }
  TfrmSettings = class(TForm)
    { Caption above the token box. }
    lblToken: TLabel;
    { Explains where to get a token; sits beside @link(lblLink). }
    lblHelp: TLabel;
    { Clickable link to @link(EARTHDATA_TOKEN_URL). }
    lblLink: TLabel;
    { Holds the explanatory text and link above the token box. }
    layHelp: TLayout;
    { When the token entered expires; see @code(DescribeTokenExpiry). }
    lblTokenExpiry: TLabel;
    { Multi-line box for the bearer token. }
    memToken: TMemo;
    { Holds the data folder and free-space controls. }
    layData: TLayout;
    { Caption above the data folder box. }
    lblDataFolder: TLabel;
    { The data folder. }
    edtDataFolder: TEdit;
    { Opens a folder picker for @link(edtDataFolder). }
    btnBrowse: TButton;
    { Caption for @link(nbMinFree). }
    lblMinFree: TLabel;
    { Free space to keep, in megabytes. }
    nbMinFree: TNumberBox;
    { Unit shown after @link(nbMinFree). }
    lblMinFreeUnit: TLabel;
    { Caption for @link(cbImportWorkers). }
    lblImportWorkers: TLabel;
    { How many files an import copies at once, one of
      @link(IMPORT_WORKER_CHOICES). }
    cbImportWorkers: TComboBox;
    { Advice shown after @link(cbImportWorkers). }
    lblImportWorkersHint: TLabel;
    { Caption for @link(cbDownloadSpeed). }
    lblDownloadSpeed: TLabel;
    { How fast tiles are downloaded, in the order of
      @link(TDownloadSpeed). }
    cbDownloadSpeed: TComboBox;
    { Advice shown after @link(cbDownloadSpeed). }
    lblDownloadSpeedHint: TLabel;
    { Holds the theme controls. }
    layTheme: TLayout;
    { Caption for @link(cbTheme). }
    lblTheme: TLabel;
    { The theme, in the order of @code(TGDEMTheme). }
    cbTheme: TComboBox;
    { Caption for @link(cbDrawing). }
    lblDrawing: TLabel;
    { Where the program draws, in the order of @link(TDrawingMode). }
    cbDrawing: TComboBox;
    { Says that @link(cbDrawing) takes effect at the next start. }
    lblDrawingHint: TLabel;
    { Caption for @link(cbGpu). }
    lblGpu: TLabel;
    { Which graphics processor Windows starts the program on, in the order
      of @link(TGpuPreference). }
    cbGpu: TComboBox;
    { Says what @link(cbGpu) does and when it takes effect. }
    lblGpuHint: TLabel;
    { Shows where the settings file is stored. }
    lblLocation: TLabel;
    { Holds the OK and Cancel buttons. }
    layButtons: TLayout;
    { Saves the settings and closes the dialog. Enabled only when a token
      and a data folder have been entered. }
    btnOK: TButton;
    { Closes the dialog without saving. }
    btnCancel: TButton;

    { Styles the labels, fills in the link text and settings location, and
      lists the themes.
      @param(Sender The form.) }
    procedure FormCreate(Sender: TObject);

    { Opens @link(EARTHDATA_TOKEN_URL) in the default browser.
      @param(Sender The link label.) }
    procedure lblLinkClick(Sender: TObject);

    { Re-checks whether OK can be pressed as the user types.
      @param(Sender The control that changed.) }
    procedure InputChangeTracking(Sender: TObject);

    { Lets the user pick the data folder.
      @param(Sender The button.) }
    procedure btnBrowseClick(Sender: TObject);
  private
    { The token as entered, with whitespace removed.
      @returns(The cleaned token; see @link(TGDEMSettings.CleanToken).) }
    function GetToken: string;

    { The data folder as entered.
      @returns(The folder, tidied by @link(NormalizeFolder).) }
    function GetDataFolder: string;

    { Enables @link(btnOK) only when a token and a data folder have been
      entered, and shows when the token expires. }
    procedure UpdateOK;

    { Selects the choice in @link(cbImportWorkers) for a number of files.
      A number that is not one of the choices, perhaps edited into the
      settings file by hand, selects the largest choice not above it.
      @param(AWorkers The number of files.) }
    procedure SetImportWorkers(AWorkers: Integer);

    { The number of files chosen in @link(cbImportWorkers).
      @returns(One of @link(IMPORT_WORKER_CHOICES).) }
    function GetImportWorkers: Integer;

    { Selects an entry in a drop-down of numbers: the largest choice not
      above AValue, or the first if none is.
      @param(ACombo The drop-down, listing AChoices in order.)
      @param(AChoices The numbers it lists.)
      @param(AValue The number to select.) }
    class procedure SelectChoice(ACombo: TComboBox; const AChoices: array of Integer;
      AValue: Integer); static;

    { The number chosen in a drop-down of numbers.
      @param(ACombo The drop-down, listing AChoices in order.)
      @param(AChoices The numbers it lists.)
      @param(ADefault The number to return if nothing is chosen.)
      @returns(The chosen number.) }
    class function ChosenValue(ACombo: TComboBox; const AChoices: array of Integer;
      ADefault: Integer): Integer; static;
  public
    { Shows the settings dialog modally for ASettings.

      If the user presses OK, the token, free-space, import, download speed
      and theme settings are stored in ASettings and saved to disk, and the chosen data folder is passed to
      AOnClosed. If saving fails, the error is shown and AOnClosed is told
      nothing was saved. The form is freed before AOnClosed is called, so
      AOnClosed may safely open other dialogs.

      @param(ASettings Settings to show and update. Must stay alive until
        AOnClosed has been called.)
      @param(AOnClosed Called once the dialog has closed. May be @nil.) }
    class procedure Edit(ASettings: TGDEMSettings; const AOnClosed: TSettingsClosedProc);

    { The token as entered, ready to store. }
    property Token: string read GetToken;

    { The data folder as entered. }
    property DataFolder: string read GetDataFolder;
  end;

implementation

{$R *.fmx}

uses
  System.IOUtils, System.Math, GDEMBrowser, GDEMThemes, GDEMDrawing, GDEMGpuPreference;

{ TfrmSettings }

procedure TfrmSettings.FormCreate(Sender: TObject);
var
  LTheme: TGDEMTheme;
  LWorkers: Integer;
  LSpeed: TDownloadSpeed;
  LMode: TDrawingMode;
  LPreference: TGpuPreference;
begin
  lblToken.TextSettings.Font.Style := [TFontStyle.fsBold];
  lblDataFolder.TextSettings.Font.Style := [TFontStyle.fsBold];
  lblTheme.TextSettings.Font.Style := [TFontStyle.fsBold];
  lblDrawing.TextSettings.Font.Style := [TFontStyle.fsBold];
  cbDrawing.Items.Clear;
  for LMode := Low(TDrawingMode) to High(TDrawingMode) do
    cbDrawing.Items.Add(DRAWING_MODE_CAPTIONS[LMode]);
  if not GPU_DRAWING_AVAILABLE then
  begin
    // Nothing to choose: Skia only draws on the CPU here
    lblDrawing.Visible := False;
    cbDrawing.Visible := False;
    lblDrawingHint.Visible := False;
    layTheme.Height := layTheme.Height - DRAWING_ROW_HEIGHT;
    ClientHeight := ClientHeight - DRAWING_ROW_HEIGHT;
    // The graphics row moves up into its place
    lblGpu.Position.Y := lblGpu.Position.Y - DRAWING_ROW_HEIGHT;
    cbGpu.Position.Y := cbGpu.Position.Y - DRAWING_ROW_HEIGHT;
    lblGpuHint.Position.Y := lblGpuHint.Position.Y - DRAWING_ROW_HEIGHT;
  end;
  lblGpu.TextSettings.Font.Style := [TFontStyle.fsBold];
  cbGpu.Items.Clear;
  for LPreference := Low(TGpuPreference) to High(TGpuPreference) do
    cbGpu.Items.Add(GPU_PREFERENCE_CAPTIONS[LPreference]);
  if not GPU_PREFERENCE_AVAILABLE then
  begin
    // Only Windows chooses between graphics processors for a program
    lblGpu.Visible := False;
    cbGpu.Visible := False;
    lblGpuHint.Visible := False;
    layTheme.Height := layTheme.Height - DRAWING_ROW_HEIGHT;
    ClientHeight := ClientHeight - DRAWING_ROW_HEIGHT;
  end;
  cbTheme.Items.Clear;
  for LTheme := Low(TGDEMTheme) to High(TGDEMTheme) do
    cbTheme.Items.Add(ThemeCaption(LTheme));
  lblLink.TextSettings.Font.Style := [TFontStyle.fsUnderline];
  lblLink.Text := EARTHDATA_TOKEN_URL;
  lblLocation.Text := 'Settings are saved to: ' + TGDEMSettings.SettingsFileName;
  nbMinFree.Min := MIN_FREE_SPACE_LOWER_MB;
  nbMinFree.Max := MIN_FREE_SPACE_UPPER_MB;
  // Whole megabytes only
  nbMinFree.DecimalDigits := 0;
  cbImportWorkers.Items.Clear;
  for LWorkers in IMPORT_WORKER_CHOICES do
    cbImportWorkers.Items.Add(IntToStr(LWorkers));
  cbDownloadSpeed.Items.Clear;
  for LSpeed := Low(TDownloadSpeed) to High(TDownloadSpeed) do
    cbDownloadSpeed.Items.Add(DOWNLOAD_SPEED_KEYS[LSpeed]);
end;

function TfrmSettings.GetToken: string;
begin
  Result := TGDEMSettings.CleanToken(memToken.Text);
end;

function TfrmSettings.GetDataFolder: string;
begin
  Result := NormalizeFolder(edtDataFolder.Text);
end;

procedure TfrmSettings.UpdateOK;
begin
  lblTokenExpiry.Text := DescribeTokenExpiry(Token);
  btnOK.Enabled := (Token <> '') and (DataFolder <> '') and
    TPath.IsPathRooted(DataFolder);
end;

class procedure TfrmSettings.SelectChoice(ACombo: TComboBox;
  const AChoices: array of Integer; AValue: Integer);
var
  LIndex: Integer;
begin
  ACombo.ItemIndex := 0;
  for LIndex := 0 to High(AChoices) do
    if AChoices[LIndex] <= AValue then
      ACombo.ItemIndex := LIndex;
end;

class function TfrmSettings.ChosenValue(ACombo: TComboBox;
  const AChoices: array of Integer; ADefault: Integer): Integer;
begin
  if InRange(ACombo.ItemIndex, 0, High(AChoices)) then
    Result := AChoices[ACombo.ItemIndex]
  else
    Result := ADefault;
end;

procedure TfrmSettings.SetImportWorkers(AWorkers: Integer);
begin
  SelectChoice(cbImportWorkers, IMPORT_WORKER_CHOICES, AWorkers);
end;

function TfrmSettings.GetImportWorkers: Integer;
begin
  Result := ChosenValue(cbImportWorkers, IMPORT_WORKER_CHOICES, DEFAULT_IMPORT_WORKERS);
end;

procedure TfrmSettings.InputChangeTracking(Sender: TObject);
begin
  UpdateOK;
end;

procedure TfrmSettings.lblLinkClick(Sender: TObject);
begin
  if not OpenURL(EARTHDATA_TOKEN_URL) then
    ShowMessage('Could not open a browser. Please visit ' + EARTHDATA_TOKEN_URL);
end;

procedure TfrmSettings.btnBrowseClick(Sender: TObject);
var
  LFolder: string;
begin
  LFolder := DataFolder;
  if SelectDirectory('Choose the folder for downloaded tiles', '', LFolder) then
  begin
    edtDataFolder.Text := LFolder;
    UpdateOK;
  end;
end;

class procedure TfrmSettings.Edit(ASettings: TGDEMSettings;
  const AOnClosed: TSettingsClosedProc);
var
  LForm: TfrmSettings;
  LSaved: Boolean;
  LFolder: string;
  LOnClosed: TSettingsClosedProc;
  LApply: TProc<TModalResult>;
  {$IFDEF ANDROID}
  LDone: TProc<TModalResult>;
  {$ENDIF}
begin
  LOnClosed := AOnClosed;
  LSaved := False;
  LFolder := '';

  LForm := TfrmSettings.Create(Application);
  LForm.memToken.Text := ASettings.BearerToken;
  LForm.edtDataFolder.Text := ASettings.DataFolder;
  LForm.nbMinFree.Value := ASettings.MinFreeSpaceMB;
  LForm.SetImportWorkers(ASettings.ImportWorkers);
  LForm.cbDownloadSpeed.ItemIndex := Ord(DownloadSpeedFromKey(ASettings.DownloadSpeed));
  LForm.cbTheme.ItemIndex := Ord(ThemeFromKey(ASettings.Theme));
  LForm.cbDrawing.ItemIndex := Ord(DrawingModeFromKey(ASettings.Drawing));
  LForm.cbGpu.ItemIndex := Ord(GpuPreferenceFromKey(ASettings.GpuPreference));
  LForm.UpdateOK;

  // Reads the dialog and saves the settings. It does not free the form or
  // call back, so that both can happen after the dialog is gone.
  LApply :=
    procedure(AResult: TModalResult)
    begin
      LFolder := LForm.DataFolder;
      if AResult = mrOk then
      begin
        ASettings.BearerToken := LForm.Token;
        ASettings.MinFreeSpaceMB := Round(LForm.nbMinFree.Value);
        ASettings.ImportWorkers := LForm.GetImportWorkers;
        if LForm.cbDownloadSpeed.ItemIndex >= 0 then
          ASettings.DownloadSpeed :=
            DOWNLOAD_SPEED_KEYS[TDownloadSpeed(LForm.cbDownloadSpeed.ItemIndex)];
        if LForm.cbTheme.ItemIndex >= 0 then
          ASettings.Theme := ThemeKey(TGDEMTheme(LForm.cbTheme.ItemIndex));
        if GPU_DRAWING_AVAILABLE and (LForm.cbDrawing.ItemIndex >= 0) then
          ASettings.Drawing := DRAWING_MODE_KEYS[TDrawingMode(LForm.cbDrawing.ItemIndex)];
        // Windows' own setting is only touched when the choice changes, so
        // one made in Windows' Settings stands until it is changed here
        if GPU_PREFERENCE_AVAILABLE and (LForm.cbGpu.ItemIndex >= 0) and
           (TGpuPreference(LForm.cbGpu.ItemIndex) <> GpuPreferenceFromKey(ASettings.GpuPreference)) then
        begin
          ASettings.GpuPreference := GPU_PREFERENCE_KEYS[TGpuPreference(LForm.cbGpu.ItemIndex)];
          if not WriteGpuPreference(TGpuPreference(LForm.cbGpu.ItemIndex)) then
            ShowMessage('Could not change Windows'' graphics setting for GDEMFetch. ' +
              'It can be set in Windows Settings > System > Display > Graphics.');
        end;
        try
          ASettings.Save;
          LSaved := True;
        except
          on E: Exception do
            ShowMessage(E.Message);
        end;
      end;
    end;

  {$IFDEF ANDROID}
  // Android cannot block on a modal form, so it reports back through a
  // callback, after which the form is freed once the callback has returned
  LDone :=
    procedure(AResult: TModalResult)
    begin
      LApply(AResult);
      TThread.ForceQueue(nil,
        procedure
        begin
          LForm.Free;
        end);
      if Assigned(LOnClosed) then
        LOnClosed(LSaved, LFolder);
    end;
  LForm.ShowModal(LDone);
  {$ELSE}
  // Desktop platforms block until the dialog closes
  try
    LApply(LForm.ShowModal);
  finally
    LForm.Free;
  end;
  if Assigned(LOnClosed) then
    LOnClosed(LSaved, LFolder);
  {$ENDIF}
end;

end.
