{ @abstract(Modal dialog for editing the application settings.)

  Shows the Earthdata Login bearer token in a multi-line box, since tokens
  are long, with a clickable link to the page where tokens are generated.

  Use @link(TfrmSettings.Edit) rather than creating the form directly. It
  uses the callback form of @code(ShowModal), which is modal on desktop
  platforms and also works on Android, where blocking modal calls are not
  supported. }
unit SettingsForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Layouts,
  FMX.Controls.Presentation,
  GDEMSettings;

const
  { Page where an Earthdata Login user generates a bearer token. }
  EARTHDATA_TOKEN_URL = 'https://urs.earthdata.nasa.gov';

type
  { Called when the settings dialog closes.
    @param(ASaved @true if the user pressed OK and the settings were
      saved successfully.) }
  TSettingsClosedProc = reference to procedure(ASaved: Boolean);

  { @abstract(The settings dialog.) }
  TfrmSettings = class(TForm)
    { Caption above the token box. }
    lblToken: TLabel;
    { Explains where to get a token; sits beside @link(lblLink). }
    lblHelp: TLabel;
    { Clickable link to @link(EARTHDATA_TOKEN_URL). }
    lblLink: TLabel;
    { Multi-line box for the bearer token. }
    memToken: TMemo;
    { Shows where the settings file is stored. }
    lblLocation: TLabel;
    { Holds the OK and Cancel buttons. }
    layButtons: TLayout;
    { Saves the settings and closes the dialog. Enabled only when a token
      has been entered. }
    btnOK: TButton;
    { Closes the dialog without saving. }
    btnCancel: TButton;
    { Holds the explanatory text and link above the token box. }
    layHelp: TLayout;

    { Styles the labels and fills in the link text and settings location.
      @param(Sender The form.) }
    procedure FormCreate(Sender: TObject);

    { Opens @link(EARTHDATA_TOKEN_URL) in the default browser.
      @param(Sender The link label.) }
    procedure lblLinkClick(Sender: TObject);

    { Enables @link(btnOK) only while the token box holds something.
      @param(Sender The token box.) }
    procedure memTokenChangeTracking(Sender: TObject);
  private
    { The token as entered, with whitespace removed.
      @returns(The cleaned token; see @link(TGDEMSettings.CleanToken).) }
    function GetToken: string;
  public
    { Shows the settings dialog modally for ASettings.

      If the user presses OK, the new token is stored in ASettings and
      saved to disk. If saving fails, the error is shown and AOnClosed is
      told nothing was saved. The form frees itself afterwards.

      @param(ASettings Settings to show and update. Must stay alive until
        AOnClosed has been called.)
      @param(AOnClosed Called once the dialog has closed. May be @nil.) }
    class procedure Edit(ASettings: TGDEMSettings; const AOnClosed: TSettingsClosedProc);

    { The token as entered, ready to store. }
    property Token: string read GetToken;
  end;

implementation

{$R *.fmx}

uses
  GDEMBrowser;

{ TfrmSettings }

procedure TfrmSettings.FormCreate(Sender: TObject);
begin
  lblToken.TextSettings.Font.Style := [TFontStyle.fsBold];
  lblLink.TextSettings.Font.Style := [TFontStyle.fsUnderline];
  lblLink.Text := EARTHDATA_TOKEN_URL;
  lblLocation.Text := 'Saved to: ' + TGDEMSettings.SettingsFileName;
end;

function TfrmSettings.GetToken: string;
begin
  Result := TGDEMSettings.CleanToken(memToken.Text);
end;

procedure TfrmSettings.lblLinkClick(Sender: TObject);
begin
  if not OpenURL(EARTHDATA_TOKEN_URL) then
    ShowMessage('Could not open a browser. Please visit ' + EARTHDATA_TOKEN_URL);
end;

procedure TfrmSettings.memTokenChangeTracking(Sender: TObject);
begin
  btnOK.Enabled := Token <> '';
end;

class procedure TfrmSettings.Edit(ASettings: TGDEMSettings;
  const AOnClosed: TSettingsClosedProc);
var
  LForm: TfrmSettings;
begin
  LForm := TfrmSettings.Create(Application);
  LForm.memToken.Text := ASettings.BearerToken;
  LForm.btnOK.Enabled := ASettings.BearerToken <> '';

  LForm.ShowModal(
    procedure(AResult: TModalResult)
    var
      LSaved: Boolean;
    begin
      LSaved := False;
      if AResult = mrOk then
      begin
        ASettings.BearerToken := LForm.Token;
        try
          ASettings.Save;
          LSaved := True;
        except
          on E: Exception do
            ShowMessage(E.Message);
        end;
      end;
      // Release defers freeing until this callback has returned
      LForm.Release;
      if Assigned(AOnClosed) then
        AOnClosed(LSaved);
    end);
end;

end.
