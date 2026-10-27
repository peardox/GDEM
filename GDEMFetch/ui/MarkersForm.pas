{ @abstract(Modal dialog listing the user's markers, to go to, rename or
  delete them.)

  Changes are saved to the markers file (see @code(TMarkerList)) as soon
  as they are made, so closing the dialog never loses them. Use
  @link(TfrmMarkers.Edit) rather than creating the form directly. }
unit MarkersForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.ListBox, FMX.Controls.Presentation,
  GDEMMarkers;

type
  { Called once the dialog has closed.
    @param(AGoTo The marker chosen with Go To (or a double click), to show
      on the map; -1 if none.)
    @param(AChanged @true if any marker was renamed or deleted.) }
  TMarkersClosedProc = reference to procedure(AGoTo: Integer; AChanged: Boolean);

  { @abstract(The markers dialog.) }
  TfrmMarkers = class(TForm)
    { How to add markers. }
    lblHint: TLabel;
    { The markers, in the order they were added. }
    lstMarkers: TListBox;
    { Holds the buttons. }
    layButtons: TLayout;
    { Closes the dialog and shows the chosen marker on the map. }
    btnGoTo: TButton;
    { Renames the chosen marker. }
    btnRename: TButton;
    { Deletes the chosen marker, after asking. }
    btnDelete: TButton;
    { Closes the dialog. }
    btnClose: TButton;

    { Enables the buttons for the chosen marker.
      @param(Sender The list.) }
    procedure lstMarkersChange(Sender: TObject);

    { Goes to the marker double-clicked.
      @param(Sender The list.) }
    procedure lstMarkersDblClick(Sender: TObject);

    { Closes the dialog to show the chosen marker on the map.
      @param(Sender The button.) }
    procedure btnGoToClick(Sender: TObject);

    { Asks for a new name for the chosen marker.
      @param(Sender The button.) }
    procedure btnRenameClick(Sender: TObject);

    { Asks whether to delete the chosen marker, then does.
      @param(Sender The button.) }
    procedure btnDeleteClick(Sender: TObject);
  private
    { The markers being edited. Not owned. }
    FMarkers: TMarkerList;
    { @true once a marker has been renamed or deleted. }
    FChanged: Boolean;
    { The marker to go to once closed; -1 for none. }
    FGoTo: Integer;

    { Fills the list from @link(FMarkers).
      @param(ASelect The marker to select; kept within the list.) }
    procedure FillList(ASelect: Integer);

    { Enables the buttons that need a marker chosen. }
    procedure UpdateButtons;

    { Saves the markers after a change, reporting any failure. }
    procedure SaveChange;
  public
    { Shows the dialog.
      @param(AMarkers The markers; changed and saved in place.)
      @param(AOnClosed Called once it has closed; may be @nil.) }
    class procedure Edit(AMarkers: TMarkerList; const AOnClosed: TMarkersClosedProc);
  end;

implementation

{$R *.fmx}

uses
  System.Math, FMX.DialogService, GDEMTiles;

{ TfrmMarkers }

procedure TfrmMarkers.FillList(ASelect: Integer);
var
  LIndex: Integer;
begin
  lstMarkers.BeginUpdate;
  try
    lstMarkers.Clear;
    for LIndex := 0 to FMarkers.Count - 1 do
      lstMarkers.Items.Add(Format('%s     %s %s', [FMarkers[LIndex].Name,
        FormatLat(FMarkers[LIndex].Lat), FormatLon(FMarkers[LIndex].Lon)]));
    if FMarkers.Count > 0 then
      lstMarkers.ItemIndex := EnsureRange(ASelect, 0, FMarkers.Count - 1);
  finally
    lstMarkers.EndUpdate;
  end;
  UpdateButtons;
end;

procedure TfrmMarkers.UpdateButtons;
var
  LChosen: Boolean;
begin
  LChosen := InRange(lstMarkers.ItemIndex, 0, FMarkers.Count - 1);
  btnGoTo.Enabled := LChosen;
  btnRename.Enabled := LChosen;
  btnDelete.Enabled := LChosen;
end;

procedure TfrmMarkers.SaveChange;
begin
  FChanged := True;
  try
    FMarkers.Save;
  except
    on E: Exception do
      ShowMessage(E.Message);
  end;
end;

procedure TfrmMarkers.lstMarkersChange(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TfrmMarkers.lstMarkersDblClick(Sender: TObject);
begin
  if InRange(lstMarkers.ItemIndex, 0, FMarkers.Count - 1) then
    btnGoToClick(Sender);
end;

procedure TfrmMarkers.btnGoToClick(Sender: TObject);
begin
  if not InRange(lstMarkers.ItemIndex, 0, FMarkers.Count - 1) then
    Exit;
  FGoTo := lstMarkers.ItemIndex;
  ModalResult := mrOk;
end;

procedure TfrmMarkers.btnRenameClick(Sender: TObject);
var
  LIndex: Integer;
begin
  LIndex := lstMarkers.ItemIndex;
  if not InRange(LIndex, 0, FMarkers.Count - 1) then
    Exit;
  TDialogService.InputQuery('Rename Marker', ['New name'], [FMarkers[LIndex].Name],
    procedure(const AResult: TModalResult; const AValues: array of string)
    begin
      if (AResult <> mrOk) or (Length(AValues) = 0) or
         (TMarkerList.CleanName(AValues[0]) = '') or
         (TMarkerList.CleanName(AValues[0]) = FMarkers[LIndex].Name) then
        Exit;
      FMarkers.Rename(LIndex, AValues[0]);
      SaveChange;
      FillList(LIndex);
    end);
end;

procedure TfrmMarkers.btnDeleteClick(Sender: TObject);
var
  LIndex: Integer;
begin
  LIndex := lstMarkers.ItemIndex;
  if not InRange(LIndex, 0, FMarkers.Count - 1) then
    Exit;
  TDialogService.MessageDialog(Format('Delete the marker "%s"?', [FMarkers[LIndex].Name]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult <> mrYes then
        Exit;
      FMarkers.Delete(LIndex);
      SaveChange;
      FillList(LIndex);
    end);
end;

class procedure TfrmMarkers.Edit(AMarkers: TMarkerList; const AOnClosed: TMarkersClosedProc);
var
  LForm: TfrmMarkers;
  LOnClosed: TMarkersClosedProc;
  {$IFDEF ANDROID}
  LDone: TProc<TModalResult>;
  {$ENDIF}
begin
  LOnClosed := AOnClosed;
  LForm := TfrmMarkers.Create(Application);
  LForm.FMarkers := AMarkers;
  LForm.FGoTo := -1;
  LForm.FillList(0);

  {$IFDEF ANDROID}
  // Android cannot block on a modal form, so it reports back through a
  // callback, after which the form is freed once the callback has returned
  LDone :=
    procedure(AResult: TModalResult)
    var
      LGoTo: Integer;
      LChanged: Boolean;
    begin
      LGoTo := LForm.FGoTo;
      LChanged := LForm.FChanged;
      TThread.ForceQueue(nil,
        procedure
        begin
          LForm.Free;
        end);
      if Assigned(LOnClosed) then
        LOnClosed(LGoTo, LChanged);
    end;
  LForm.ShowModal(LDone);
  {$ELSE}
  // Desktop platforms block until the dialog closes
  try
    LForm.ShowModal;
    if Assigned(LOnClosed) then
      LOnClosed(LForm.FGoTo, LForm.FChanged);
  finally
    LForm.Free;
  end;
  {$ENDIF}
end;

end.
