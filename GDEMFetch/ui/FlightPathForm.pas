{ @abstract(The dialog for choosing which of the flight paths in a file to
  play.)

  Each path is a line in a list: its name, length, when it was flown and
  how it ended; under the list, more about the one chosen (where it
  starts, its points, how long its replay takes). A double click plays
  it too. The form is built in code, so it has no @code(.fmx); it has no
  style book of its own, so the theme reaches it. }
unit FlightPathForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.ListBox, FMX.Layouts,
  GDEMFlightPath;

type
  { @abstract(Reports which path was chosen.)
    @param(AIndex The chosen path's index in the list given; -1 for
      Cancel.) }
  TFlightPathChosenProc = reference to procedure(AIndex: Integer);

  { @abstract(Asks which flight path to play.) }
  TfrmFlightPath = class(TForm)
  private
    { The paths offered. }
    FFlights: TArray<TFlightPathRecord>;
    { One line for each path. }
    FList: TListBox;
    { More about the path chosen. }
    FDetailLabel: TLabel;
    { Plays the path chosen. }
    FPlayButton: TButton;

    { Builds the controls.
      @param(AFileName The file the paths came from, for the heading.) }
    procedure BuildControls(const AFileName: string);

    { Puts a line for each path in the list, and chooses the first. }
    procedure FillList;

    { The path chosen.
      @returns(Its index; -1 if none is chosen.) }
    function ChosenIndex: Integer;

    { Says more about the path chosen, and allows Play once one is.
      @param(Sender The list.) }
    procedure Changed(Sender: TObject);

    { Plays the path double-clicked.
      @param(Sender The list.) }
    procedure ListDblClick(Sender: TObject);

    { Gives the list the keyboard.
      @param(Sender The form.) }
    procedure FormShowing(Sender: TObject);
  public
    { Asks which of a file's flight paths to play.
      @param(AFileName The file they came from, for the heading.)
      @param(AFlights The paths.)
      @param(ADone Told which was chosen; on desktop platforms before this
        returns, with the dialog already closed.) }
    class procedure Choose(const AFileName: string; const AFlights: TArray<TFlightPathRecord>;
      const ADone: TFlightPathChosenProc);
  end;

{ A flight path's line in the list: its name, length, when it was flown
  and how it ended.
  @param(AFlight The path.)
  @returns(The line.) }
function DescribeFlightPath(const AFlight: TFlightPathRecord): string;

implementation

uses
  System.Math, System.DateUtils, GDEMTiles;

const
  { The dialog's width, pixels. }
  DIALOG_WIDTH = 600;
  { The dialog's height, pixels. }
  DIALOG_HEIGHT = 440;
  { The space round the controls, pixels. }
  DIALOG_MARGIN = 16;

{ When a path was flown, in local time, for showing.
  @param(AText The time as saved.)
  @returns(Such as @code(28 Oct 2026 18:30); empty if it cannot be
    read.) }
function LocalTimeText(const AText: string): string;
var
  LTime: TDateTime;
begin
  if TryReadFlightTime(AText, LTime) then
    Result := FormatDateTime('d mmm yyyy hh:nn', TTimeZone.Local.ToLocalTime(LTime))
  else
    Result := '';
end;

function DescribeFlightPath(const AFlight: TFlightPathRecord): string;
var
  LName, LWhen: string;
begin
  LName := AFlight.Name.Trim;
  if LName = '' then
    LName := '(no name)';
  Result := Format('%s  -  %s km', [LName, FormatFloat('#,##0.0', AFlight.DistanceKm)]);
  LWhen := LocalTimeText(AFlight.Started);
  if LWhen <> '' then
    Result := Result + ', ' + LWhen;
  if AFlight.EndReason <> '' then
    Result := Result + ', ' + AFlight.EndReason.ToLower;
end;

{ A replay's time, such as @code(4 min 05 s).
  @param(ASeconds Seconds.)
  @returns(The time, to the second.) }
function ReplayTimeText(ASeconds: Double): string;
var
  LSeconds: Int64;
begin
  LSeconds := Round(Max(ASeconds, 0));
  if LSeconds >= 3600 then
    Result := Format('%d h %.2d min', [LSeconds div 3600, (LSeconds mod 3600) div 60])
  else if LSeconds >= 60 then
    Result := Format('%d min %.2d s', [LSeconds div 60, LSeconds mod 60])
  else
    Result := Format('%d s', [LSeconds]);
end;

{ TfrmFlightPath }

class procedure TfrmFlightPath.Choose(const AFileName: string;
  const AFlights: TArray<TFlightPathRecord>; const ADone: TFlightPathChosenProc);
var
  LForm: TfrmFlightPath;
  LDone: TFlightPathChosenProc;
  {$IFDEF ANDROID}
  LClosed: TProc<TModalResult>;
  {$ELSE}
  LIndex: Integer;
  {$ENDIF}
begin
  LDone := ADone;
  LForm := TfrmFlightPath.CreateNew(Application);
  LForm.FFlights := AFlights;
  LForm.BuildControls(AFileName);
  LForm.FillList;

  {$IFDEF ANDROID}
  // Android cannot block on a modal form, so it reports back through a
  // callback, after which the form is freed once the callback has returned
  LClosed :=
    procedure(AModal: TModalResult)
    var
      LChosen: Integer;
    begin
      if AModal = mrOk then
        LChosen := LForm.ChosenIndex
      else
        LChosen := -1;
      TThread.ForceQueue(nil,
        procedure
        begin
          LForm.Free;
        end);
      if Assigned(LDone) then
        LDone(LChosen);
    end;
  LForm.ShowModal(LClosed);
  {$ELSE}
  // Desktop platforms block until the dialog closes
  try
    if LForm.ShowModal = mrOk then
      LIndex := LForm.ChosenIndex
    else
      LIndex := -1;
  finally
    LForm.Free;
  end;
  if Assigned(LDone) then
    LDone(LIndex);
  {$ENDIF}
end;

procedure TfrmFlightPath.BuildControls(const AFileName: string);
var
  LTop: Single;
  LLabel: TLabel;
  LButton: TButton;
begin
  Caption := 'Play Flight Path';
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  Position := TFormPosition.MainFormCenter;
  ClientWidth := DIALOG_WIDTH;
  ClientHeight := DIALOG_HEIGHT;
  OnShow := FormShowing;
  LTop := DIALOG_MARGIN;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN, 40);
  LLabel.WordWrap := True;
  LLabel.Text := Format('%s holds %d flight paths. Choose the one to play:',
    [ExtractFileName(AFileName), Length(FFlights)]);
  LTop := LTop + 44;

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN,
    DIALOG_HEIGHT - LTop - DIALOG_MARGIN - 30 - 12 - 48);
  FList.OnChange := Changed;
  FList.OnDblClick := ListDblClick;
  LTop := FList.Position.Y + FList.Height + 8;

  FDetailLabel := TLabel.Create(Self);
  FDetailLabel.Parent := Self;
  FDetailLabel.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN, 40);
  FDetailLabel.WordWrap := True;

  FPlayButton := TButton.Create(Self);
  FPlayButton.Parent := Self;
  FPlayButton.SetBounds(DIALOG_WIDTH - DIALOG_MARGIN - 2 * 88 - 8,
    DIALOG_HEIGHT - DIALOG_MARGIN - 30, 88, 30);
  FPlayButton.Text := 'Play';
  FPlayButton.Default := True;
  FPlayButton.ModalResult := mrOk;

  LButton := TButton.Create(Self);
  LButton.Parent := Self;
  LButton.SetBounds(DIALOG_WIDTH - DIALOG_MARGIN - 88, DIALOG_HEIGHT - DIALOG_MARGIN - 30, 88, 30);
  LButton.Text := 'Cancel';
  LButton.Cancel := True;
  LButton.ModalResult := mrCancel;
end;

procedure TfrmFlightPath.FillList;
var
  LItem: TListBoxItem;
  I: Integer;
begin
  FList.BeginUpdate;
  try
    FList.Clear;
    for I := 0 to High(FFlights) do
    begin
      LItem := TListBoxItem.Create(Self);
      // An ampersand would make the next letter a shortcut
      LItem.Text := DescribeFlightPath(FFlights[I]).Replace('&', '&&');
      LItem.Tag := I;
      LItem.Parent := FList;
    end;
  finally
    FList.EndUpdate;
  end;
  if FList.Count > 0 then
    FList.ItemIndex := 0;
  Changed(nil);
end;

function TfrmFlightPath.ChosenIndex: Integer;
begin
  if FList.Selected <> nil then
    Result := FList.Selected.Tag
  else
    Result := -1;
end;

procedure TfrmFlightPath.Changed(Sender: TObject);
var
  LIndex: Integer;
  LReplay: TFlightReplay;
begin
  if FPlayButton = nil then
    Exit;
  LIndex := ChosenIndex;
  FPlayButton.Enabled := LIndex >= 0;
  if LIndex < 0 then
  begin
    FDetailLabel.Text := '';
    Exit;
  end;
  LReplay := TFlightReplay.Create(FFlights[LIndex]);
  try
    FDetailLabel.Text := Format('Starts at %s %s heading %.0f' + #$00B0 + '; %d points; ' +
      'the replay takes %s.', [FormatLat(LReplay.StartLatitude),
       FormatLon(LReplay.StartLongitude), LReplay.StartHeading, LReplay.PointCount,
       ReplayTimeText(LReplay.Duration)]);
  finally
    LReplay.Free;
  end;
end;

procedure TfrmFlightPath.ListDblClick(Sender: TObject);
begin
  if ChosenIndex >= 0 then
    ModalResult := mrOk;
end;

procedure TfrmFlightPath.FormShowing(Sender: TObject);
begin
  FList.SetFocus;
end;

end.
