unit MainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  System.Threading, FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Edit, FMX.Memo, FMX.Memo.Types, FMX.ScrollBox, FMX.Layouts,
  FMX.Controls.Presentation;

type
  TfrmMain = class(TForm)
    layTop: TLayout;
    lblToken: TLabel;
    edtToken: TEdit;
    lblTile: TLabel;
    edtTile: TEdit;
    btnFetch: TButton;
    lblFolder: TLabel;
    pbDownload: TProgressBar;
    memLog: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure btnFetchClick(Sender: TObject);
  private
    FDestFolder: string;
    procedure AddLog(const Msg: string);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  GDEMDownloader;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FDestFolder := TPath.Combine(TPath.GetDocumentsPath, 'ASTGTM');
  lblFolder.Text := 'Save to: ' + FDestFolder;
  edtTile.Text := 'N50W002';
  // Keep the token out of source code: paste it in, or set EARTHDATA_TOKEN
  edtToken.Text := GetEnvironmentVariable('EARTHDATA_TOKEN');
end;

procedure TfrmMain.AddLog(const Msg: string);
var
  S: string;
begin
  S := Msg;
  TThread.Queue(nil,
    procedure
    begin
      memLog.Lines.Add(S);
      memLog.GoToTextEnd;
    end);
end;

procedure TfrmMain.btnFetchClick(Sender: TObject);
var
  Token, Tile, Folder: string;
begin
  Token := Trim(edtToken.Text);
  Tile := Trim(edtTile.Text);
  Folder := FDestFolder;

  if Token = '' then
  begin
    ShowMessage('Paste your Earthdata Login bearer token first ' +
      '(urs.earthdata.nasa.gov > Generate Token).');
    Exit;
  end;

  btnFetch.Enabled := False;
  pbDownload.Value := 0;

  TTask.Run(
    procedure
    var
      D: TGDEMDownloader;
      ErrMsg: string;
    begin
      ErrMsg := '';
      D := TGDEMDownloader.Create(Token);
      try
        D.OnLog := AddLog;
        D.OnProgress :=
          procedure(const FileName: string; Received, Total: Int64)
          begin
            TThread.Queue(nil,
              procedure
              begin
                if Total > 0 then
                  pbDownload.Value := Received * 100 / Total;
              end);
          end;
        try
          D.DownloadTile(Tile, Folder);
          AddLog('Done.');
        except
          on E: Exception do
            ErrMsg := E.Message;
        end;
      finally
        D.Free;
      end;

      if ErrMsg <> '' then
        AddLog('ERROR: ' + ErrMsg);

      TThread.Queue(nil,
        procedure
        begin
          btnFetch.Enabled := True;
        end);
    end);
end;

end.
