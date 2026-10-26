{ @abstract(Modal dialog for editing the application settings.)

  Shows:
  @unorderedList(
    @item(the Earthdata Login bearer token, in a multi-line box since tokens
      are long, with a clickable link to the page where tokens are
      generated;)
    @item(the data folder that downloaded tiles are kept in, with a Browse
      button;)
    @item(how much free space downloads must leave on that drive.)
  )

  The token and free-space setting are saved by the dialog itself. A new
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
  FMX.Controls.Presentation, FMX.Edit, FMX.EditBox, FMX.NumberBox,
  GDEMSettings;

const
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
    { Shows where the settings file is stored. }
    lblLocation: TLabel;
    { Holds the OK and Cancel buttons. }
    layButtons: TLayout;
    { Saves the settings and closes the dialog. Enabled only when a token
      and a data folder have been entered. }
    btnOK: TButton;
    { Closes the dialog without saving. }
    btnCancel: TButton;

    { Styles the labels and fills in the link text and settings location.
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
      @returns(The folder, trimmed and without a trailing separator.) }
    function GetDataFolder: string;

    { Enables @link(btnOK) only when a token and a data folder have been
      entered. }
    procedure UpdateOK;
  public
    { Shows the settings dialog modally for ASettings.

      If the user presses OK, the token and free-space setting are stored in
      ASettings and saved to disk, and the chosen data folder is passed to
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
  System.IOUtils, GDEMBrowser;

{ TfrmSettings }

procedure TfrmSettings.FormCreate(Sender: TObject);
begin
  lblToken.TextSettings.Font.Style := [TFontStyle.fsBold];
  lblDataFolder.TextSettings.Font.Style := [TFontStyle.fsBold];
  lblLink.TextSettings.Font.Style := [TFontStyle.fsUnderline];
  lblLink.Text := EARTHDATA_TOKEN_URL;
  lblLocation.Text := 'Settings are saved to: ' + TGDEMSettings.SettingsFileName;
  nbMinFree.Min := MIN_FREE_SPACE_LOWER_MB;
  nbMinFree.Max := MIN_FREE_SPACE_UPPER_MB;
  // Whole megabytes only
  nbMinFree.DecimalDigits := 0;
end;

function TfrmSettings.GetToken: string;
begin
  Result := TGDEMSettings.CleanToken(memToken.Text);
end;

function TfrmSettings.GetDataFolder: string;
begin
  Result := ExcludeTrailingPathDelimiter(Trim(edtDataFolder.Text));
end;

procedure TfrmSettings.UpdateOK;
begin
  btnOK.Enabled := (Token <> '') and (DataFolder <> '') and
    TPath.IsPathRooted(DataFolder);
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
