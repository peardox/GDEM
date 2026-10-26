{ @abstract(Modal progress dialog shown while data is downloaded.)

  Shown whenever the program fetches external data (downloading tiles, and
  building the tile index from NASA CMR) and while importing existing
  tiles. It has:
  @unorderedList(
    @item(a status line, showing the step in progress;)
    @item(an overall progress bar, for tiles or pages;)
    @item(a second progress bar, normally for the bytes of the current file
      (@link(TfrmProgress.SetItem)) but usable for any measure
      (@link(TfrmProgress.SetItemProgress)), which can be hidden when there
      is nothing to follow;)
    @item(a Cancel button.)
  )

  The dialog does no work itself. The caller starts the work on a
  background task, shows the dialog with @link(TfrmProgress.ShowModal),
  sends updates through the @code(Set...) methods (on the main thread), and
  calls @link(TfrmProgress.Finish) when the work has stopped. Cancel, the
  Escape key and the window's close button all call
  @link(TfrmProgress.OnCancel) and then wait: the dialog stays open until
  the work has actually stopped and @link(TfrmProgress.Finish) is called,
  so nothing is left running behind it. }
unit ProgressForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls,
  FMX.Layouts, FMX.Controls.Presentation;

type
  { @abstract(The progress dialog.) }
  TfrmProgress = class(TForm)
    { The step in progress. }
    lblStatus: TLabel;
    { Describes the overall progress, such as @code(Tile 3 of 12). }
    lblOverall: TLabel;
    { Overall progress, from 0 to 100. }
    pbOverall: TProgressBar;
    { Describes the current file's progress, such as
      @code(12.3 of 25.0 MB). }
    lblItem: TLabel;
    { Progress through the current file, from 0 to 100. }
    pbItem: TProgressBar;
    { Holds the Cancel button. }
    layButtons: TLayout;
    { Asks the work to stop. }
    btnCancel: TButton;

    { Asks the work to stop.
      @param(Sender The button.) }
    procedure btnCancelClick(Sender: TObject);

    { Keeps the dialog open until @link(Finish) has been called; a close
      request before that is treated as Cancel.
      @param(Sender The form.)
      @param(CanClose Set to @false until the work has stopped.) }
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    { Backing field for @link(OnCancel). }
    FOnCancel: TProc;
    { Set by @link(Finish), after which the dialog may close. }
    FFinished: Boolean;
    { Set once the user has asked to cancel. }
    FCancelling: Boolean;

    { Calls @link(OnCancel) once, and shows that cancelling has started. }
    procedure RequestCancel;
  public
    { Creates the dialog with a title.
      @param(AOwner Owner of the form.)
      @param(ATitle Window title, such as @code(Downloading tiles).)
      @param(AShowItem @true to show the per-file progress bar.) }
    constructor CreateWithTitle(AOwner: TComponent; const ATitle: string; AShowItem: Boolean);

    { Shows the step in progress.
      @param(AText The text to show.) }
    procedure SetStatus(const AText: string);

    { Shows overall progress.
      @param(ADone Items finished, or the number of the current item.)
      @param(ATotal Total items; when 0 or less the bar is left empty.)
      @param(AText Description shown above the bar.) }
    procedure SetOverall(ADone, ATotal: Integer; const AText: string);

    { Shows progress through the current file.
      @param(AReceived Bytes received so far.)
      @param(ATotal Expected size in bytes; when 0 or less only the bytes
        received are shown.) }
    procedure SetItem(AReceived, ATotal: Int64);

    { Shows any progress on the second bar, with a description of your
      own.
      @param(ADone How far through.)
      @param(ATotal The end; when 0 or less the bar is left empty.)
      @param(AText Description shown above the bar.) }
    procedure SetItemProgress(ADone, ATotal: Int64; const AText: string);

    { Empties the per-file bar, between files. }
    procedure ClearItem;

    { Called when the work has stopped, for whatever reason. Lets the
      dialog close, ending @code(ShowModal). }
    procedure Finish;

    { Called on the main thread when the user asks to cancel, at most once.
      It should only ask the work to stop; @link(Finish) is called once it
      has. }
    property OnCancel: TProc read FOnCancel write FOnCancel;
  end;

implementation

{$R *.fmx}

{ Formats a byte count as megabytes with one decimal place.
  @param(ABytes The size.)
  @returns(For example @code(12.3 MB).) }
function FormatMB(ABytes: Int64): string;
begin
  Result := FormatFloat('0.0', ABytes / (1024 * 1024)) + ' MB';
end;

{ TfrmProgress }

constructor TfrmProgress.CreateWithTitle(AOwner: TComponent; const ATitle: string;
  AShowItem: Boolean);
begin
  inherited Create(AOwner);
  Caption := ATitle;
  lblStatus.Text := 'Starting...';
  lblOverall.Text := '';
  lblItem.Text := '';
  pbOverall.Value := 0;
  pbItem.Value := 0;
  lblItem.Visible := AShowItem;
  pbItem.Visible := AShowItem;
end;

procedure TfrmProgress.SetStatus(const AText: string);
begin
  if not FCancelling then
    lblStatus.Text := AText;
end;

procedure TfrmProgress.SetOverall(ADone, ATotal: Integer; const AText: string);
begin
  lblOverall.Text := AText;
  if ATotal > 0 then
    pbOverall.Value := ADone * 100 / ATotal
  else
    pbOverall.Value := 0;
end;

procedure TfrmProgress.SetItem(AReceived, ATotal: Int64);
begin
  if ATotal > 0 then
  begin
    pbItem.Value := AReceived * 100 / ATotal;
    lblItem.Text := FormatMB(AReceived) + ' of ' + FormatMB(ATotal);
  end
  else
  begin
    pbItem.Value := 0;
    lblItem.Text := FormatMB(AReceived);
  end;
end;

procedure TfrmProgress.SetItemProgress(ADone, ATotal: Int64; const AText: string);
begin
  lblItem.Text := AText;
  if ATotal > 0 then
    pbItem.Value := ADone * 100 / ATotal
  else
    pbItem.Value := 0;
end;

procedure TfrmProgress.ClearItem;
begin
  pbItem.Value := 0;
  lblItem.Text := '';
end;

procedure TfrmProgress.RequestCancel;
begin
  if FCancelling or FFinished then
    Exit;
  FCancelling := True;
  btnCancel.Enabled := False;
  lblStatus.Text := 'Cancelling...';
  if Assigned(FOnCancel) then
    FOnCancel();
end;

procedure TfrmProgress.btnCancelClick(Sender: TObject);
begin
  RequestCancel;
end;

procedure TfrmProgress.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FFinished;
  if not CanClose then
    RequestCancel;
end;

procedure TfrmProgress.Finish;
begin
  FFinished := True;
  ModalResult := mrOk;
end;

end.
