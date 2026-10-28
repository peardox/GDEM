{ @abstract(The dialog for adding a bookmark: its name, where it is (the
  3D view's current place, or typed latitude and longitude), and the
  folder it goes in, chosen from a tree whose top is the Bookmarks menu.)

  With typed coordinates, the height above the ground, the heading, the
  speed and the camera's tilt may be typed too; a box left blank takes
  the default its grey prompt shows. Latitude and longitude are decimal
  degrees, negative to the south and west, or with N, S, E or W after
  them (a comma works as the decimal point too).

  New folders can be made in the folder chosen, to any depth. The dialog
  works on a copy of the bookmarks (@link(TfrmBookmark.Ask)), so folders
  made and then cancelled leave the real list untouched. The form is
  built in code, so it has no @code(.fmx); it has no style book of its
  own, so the theme reaches it. }
unit BookmarkForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.TreeView,
  GDEMBookmarks;

type
  { @abstract(What the dialog was told.) }
  TBookmarkDialogResult = record
    { @true for OK, @false for Cancel. }
    Ok: Boolean;
    { The name typed, tidied. }
    Name: string;
    { The folder chosen; @code(BOOKMARK_ROOT) for the top level. }
    Folder: Integer;
    { @true for the 3D view's current place; @false for the coordinates
      below. }
    UseCurrent: Boolean;
    { Typed latitude, degrees. }
    Latitude: Double;
    { Typed longitude, degrees. }
    Longitude: Double;
    { Typed height above the ground, metres. }
    AboveGround: Double;
    { Typed heading, degrees clockwise from north. }
    Heading: Double;
    { Typed speed, kilometres an hour. }
    SpeedKmh: Double;
    { Typed camera tilt, degrees below the level. }
    Tilt: Double;
  end;

  { @abstract(Reports how the dialog was closed.)
    @param(AResult What was chosen.) }
  TBookmarkDialogDoneProc = reference to procedure(const AResult: TBookmarkDialogResult);

  { @abstract(Asks for a bookmark's name, place and folder.) }
  TfrmBookmark = class(TForm)
  private
    { The bookmarks' copy the dialog adds folders to. Not owned. }
    FList: TBookmarkList;
    { The height used when its box is left blank, metres. }
    FDefaultHeight: Double;
    { The name box. }
    FNameEdit: TEdit;
    { Chooses the 3D view's current place. }
    FCurrentRadio: TRadioButton;
    { Chooses typed coordinates. }
    FTypedRadio: TRadioButton;
    { Latitude. }
    FLatitudeEdit: TEdit;
    { Longitude. }
    FLongitudeEdit: TEdit;
    { Height above the ground, metres. }
    FHeightEdit: TEdit;
    { Heading, degrees. }
    FHeadingEdit: TEdit;
    { Speed, kilometres an hour. }
    FSpeedEdit: TEdit;
    { Camera tilt, degrees down. }
    FTiltEdit: TEdit;
    { Says what is wrong with what is typed, or how to type it. }
    FHintLabel: TLabel;
    { The folders, under the top level, which is the Bookmarks menu. }
    FTree: TTreeView;
    { Adds the bookmark. }
    FOkButton: TButton;

    { Builds the controls.
      @param(AHaveCurrent @true if there is a current place to offer.) }
    procedure BuildControls(AHaveCurrent: Boolean);

    { Adds a label and a box for a number, in the coordinates' grid.
      @param(ACaption The label.)
      @param(APrompt The grey prompt: the default, or how to type it.)
      @param(ALeft The label's left edge, pixels.)
      @param(ATop The row's top, pixels.)
      @returns(The box.) }
    function AddNumberBox(const ACaption, APrompt: string; ALeft, ATop: Single): TEdit;

    { Fills the tree from @link(FList), and chooses a folder.
      @param(ASelect The folder to choose.) }
    procedure FillTree(ASelect: Integer);

    { Adds a folder's item, and its folders' items, to the tree.
      @param(AParent The tree or item it goes in.)
      @param(AFolder The folder.)
      @param(ASelect The folder to choose, if it is among them.) }
    procedure AddFolderItems(AParent: TFmxObject; AFolder: Integer; ASelect: Integer);

    { The folder chosen in the tree.
      @returns(Its number; @code(BOOKMARK_ROOT) if none is chosen.) }
    function ChosenFolder: Integer;

    { Reads everything typed into a result, saying what is wrong if
      anything is.
      @param(AResult What was chosen.)
      @param(AProblem What is wrong; empty if nothing is.) }
    procedure ReadResult(out AResult: TBookmarkDialogResult; out AProblem: string);

    { Allows OK only when the name and, for typed coordinates, every box
      make sense, and says what does not.
      @param(Sender The control that changed.) }
    procedure Changed(Sender: TObject);

    { Asks for a folder's name and makes it in the folder chosen.
      @param(Sender The button.) }
    procedure NewFolderClick(Sender: TObject);

    { Puts the cursor in the name box.
      @param(Sender The form.) }
    procedure FormShowing(Sender: TObject);
  public
    { Asks for a bookmark's name, place and folder.
      @param(AList A copy of the bookmarks, which folders made in the
        dialog are added to; on OK the caller takes them from it.)
      @param(AFolder The folder to choose first.)
      @param(AHaveCurrent @true if the 3D view has a place to offer;
        otherwise only typed coordinates can be chosen.)
      @param(ALatitude A latitude to start the box with, when
        @code(AHaveCurrent).)
      @param(ALongitude A longitude to start the box with, when
        @code(AHaveCurrent).)
      @param(ADefaultHeight The height above the ground a blank box means,
        metres.)
      @param(ADone Told how the dialog was closed; on desktop platforms
        before this returns.) }
    class procedure Ask(AList: TBookmarkList; AFolder: Integer; AHaveCurrent: Boolean;
      ALatitude, ALongitude, ADefaultHeight: Double; const ADone: TBookmarkDialogDoneProc);
  end;

{ Reads a latitude or longitude as typed: decimal degrees, negative to the
  south and west, or with N, S, E or W before or after; a comma may be the
  decimal point, and a degree sign is allowed.
  @param(AText The text.)
  @param(AIsLatitude @true for a latitude (-90 to 90, N or S), @false for
    a longitude (-180 to 180, E or W).)
  @param(AValue The degrees.)
  @returns(@false if it is not a valid latitude or longitude.) }
function ParseCoordinate(const AText: string; AIsLatitude: Boolean; out AValue: Double): Boolean;

implementation

uses
  System.Math, FMX.DialogService, GDEMFlight;

const
  { The dialog's width, pixels. }
  DIALOG_WIDTH = 480;
  { The dialog's height, pixels. }
  DIALOG_HEIGHT = 600;
  { The space round the controls, pixels. }
  DIALOG_MARGIN = 16;
  { The caption of the tree's top level. }
  ROOT_CAPTION = 'Bookmarks';
  { The degree sign; source files are ASCII only. Typed, so it is a string
    wherever it is used. }
  DEGREE_SIGN: string = #$00B0;

function ParseCoordinate(const AText: string; AIsLatitude: Boolean; out AValue: Double): Boolean;
var
  LText: string;
  LSign: Integer;
  LFormat: TFormatSettings;
  LLast, LFirst: Char;
begin
  AValue := 0;
  LText := AText.Trim.ToUpper.Replace(DEGREE_SIGN, '').Replace(',', '.').Replace(' ', '');
  LSign := 1;
  if LText = '' then
    Exit(False);
  // A compass letter before or after the number
  LLast := LText[High(LText)];
  LFirst := LText[Low(LText)];
  if CharInSet(LLast, ['N', 'S', 'E', 'W']) then
  begin
    if AIsLatitude <> CharInSet(LLast, ['N', 'S']) then
      Exit(False);
    if CharInSet(LLast, ['S', 'W']) then
      LSign := -1;
    LText := LText.Substring(0, Length(LText) - 1);
  end
  else if CharInSet(LFirst, ['N', 'S', 'E', 'W']) then
  begin
    if AIsLatitude <> CharInSet(LFirst, ['N', 'S']) then
      Exit(False);
    if CharInSet(LFirst, ['S', 'W']) then
      LSign := -1;
    LText := LText.Substring(1);
  end;
  LFormat := TFormatSettings.Invariant;
  if not TryStrToFloat(LText, AValue, LFormat) or IsNan(AValue) or IsInfinite(AValue) then
    Exit(False);
  AValue := AValue * LSign;
  if AIsLatitude then
    Result := InRange(AValue, -90, 90)
  else
    Result := InRange(AValue, -180, 180);
end;

{ Reads a number as typed, or a default when the box is blank.
  @param(AText The text.)
  @param(ADefault The number a blank box means.)
  @param(AValue The number.)
  @returns(@false if the text is not a number.) }
function ParseNumber(const AText: string; ADefault: Double; out AValue: Double): Boolean;
var
  LText: string;
begin
  LText := AText.Trim.Replace(DEGREE_SIGN, '').Replace(',', '.');
  if LText = '' then
  begin
    AValue := ADefault;
    Exit(True);
  end;
  Result := TryStrToFloat(LText, AValue, TFormatSettings.Invariant) and not IsNan(AValue) and
    not IsInfinite(AValue);
end;

{ TfrmBookmark }

class procedure TfrmBookmark.Ask(AList: TBookmarkList; AFolder: Integer; AHaveCurrent: Boolean;
  ALatitude, ALongitude, ADefaultHeight: Double; const ADone: TBookmarkDialogDoneProc);
var
  LForm: TfrmBookmark;
  LDone: TBookmarkDialogDoneProc;
  LResult: TBookmarkDialogResult;
  LProblem: string;
  {$IFDEF ANDROID}
  LClosed: TProc<TModalResult>;
  {$ENDIF}
begin
  LDone := ADone;
  LForm := TfrmBookmark.CreateNew(Application);
  LForm.FList := AList;
  LForm.FDefaultHeight := ADefaultHeight;
  LForm.BuildControls(AHaveCurrent);
  if AHaveCurrent then
  begin
    // The current place to start from, should the user type near it
    LForm.FLatitudeEdit.Text := FormatFloat('0.0000', ALatitude, TFormatSettings.Invariant);
    LForm.FLongitudeEdit.Text := FormatFloat('0.0000', ALongitude, TFormatSettings.Invariant);
  end;
  LForm.FillTree(AFolder);
  LForm.Changed(nil);

  {$IFDEF ANDROID}
  // Android cannot block on a modal form, so it reports back through a
  // callback, after which the form is freed once the callback has returned
  LClosed :=
    procedure(AModal: TModalResult)
    var
      LAnswer: TBookmarkDialogResult;
      LWhy: string;
    begin
      LForm.ReadResult(LAnswer, LWhy);
      LAnswer.Ok := (AModal = mrOk) and (LWhy = '');
      TThread.ForceQueue(nil,
        procedure
        begin
          LForm.Free;
        end);
      if Assigned(LDone) then
        LDone(LAnswer);
    end;
  LForm.ShowModal(LClosed);
  {$ELSE}
  // Desktop platforms block until the dialog closes
  try
    LResult := Default(TBookmarkDialogResult);
    LResult.Ok := LForm.ShowModal = mrOk;
    if Assigned(LDone) then
    begin
      if LResult.Ok then
      begin
        LForm.ReadResult(LResult, LProblem);
        LResult.Ok := LProblem = '';
      end;
      LDone(LResult);
    end;
  finally
    LForm.Free;
  end;
  {$ENDIF}
end;

function TfrmBookmark.AddNumberBox(const ACaption, APrompt: string; ALeft, ATop: Single): TEdit;
var
  LLabel: TLabel;
begin
  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(ALeft, ATop, 110, 24);
  LLabel.Text := ACaption;
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(ALeft + 112, ATop, 92, 24);
  Result.TextPrompt := APrompt;
  Result.OnChangeTracking := Changed;
end;

procedure TfrmBookmark.BuildControls(AHaveCurrent: Boolean);
var
  LTop, LMid: Single;
  LLabel: TLabel;
  LButton: TButton;
begin
  Caption := 'Add Bookmark';
  BorderStyle := TFmxFormBorderStyle.Single;
  BorderIcons := [TBorderIcon.biSystemMenu];
  Position := TFormPosition.MainFormCenter;
  ClientWidth := DIALOG_WIDTH;
  ClientHeight := DIALOG_HEIGHT;
  OnShow := FormShowing;
  LMid := DIALOG_WIDTH / 2 + 4;
  LTop := DIALOG_MARGIN;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN, 20);
  LLabel.Text := 'Name';
  LTop := LTop + 22;
  FNameEdit := TEdit.Create(Self);
  FNameEdit.Parent := Self;
  FNameEdit.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN, 26);
  FNameEdit.MaxLength := MAX_BOOKMARK_NAME_LENGTH;
  FNameEdit.OnChangeTracking := Changed;
  LTop := LTop + 38;

  // Where: the current place, or typed coordinates
  FCurrentRadio := TRadioButton.Create(Self);
  FCurrentRadio.Parent := Self;
  FCurrentRadio.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN, 22);
  FCurrentRadio.GroupName := 'BookmarkPlace';
  FCurrentRadio.Text := 'Current location in the 3D view';
  FCurrentRadio.Enabled := AHaveCurrent;
  FCurrentRadio.OnChange := Changed;
  LTop := LTop + 26;
  FTypedRadio := TRadioButton.Create(Self);
  FTypedRadio.Parent := Self;
  FTypedRadio.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN, 22);
  FTypedRadio.GroupName := 'BookmarkPlace';
  FTypedRadio.Text := 'Latitude and longitude:';
  FTypedRadio.OnChange := Changed;
  if AHaveCurrent then
    FCurrentRadio.IsChecked := True
  else
    FTypedRadio.IsChecked := True;
  LTop := LTop + 30;

  FLatitudeEdit := AddNumberBox('Latitude', 'e.g. 54.45N', DIALOG_MARGIN + 20, LTop);
  FLongitudeEdit := AddNumberBox('Longitude', 'e.g. 3.21W', LMid, LTop);
  LTop := LTop + 30;
  FHeightEdit := AddNumberBox('Above ground, m', FormatFloat('0', FDefaultHeight),
    DIALOG_MARGIN + 20, LTop);
  FHeadingEdit := AddNumberBox('Heading, ' + DEGREE_SIGN, '0', LMid, LTop);
  LTop := LTop + 30;
  FSpeedEdit := AddNumberBox('Speed, km/h', '0', DIALOG_MARGIN + 20, LTop);
  FTiltEdit := AddNumberBox('Camera down, ' + DEGREE_SIGN, FormatFloat('0', DEFAULT_FLIGHT_TILT),
    LMid, LTop);
  LTop := LTop + 30;
  FHintLabel := TLabel.Create(Self);
  FHintLabel.Parent := Self;
  FHintLabel.SetBounds(DIALOG_MARGIN + 20, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN - 20, 36);
  FHintLabel.WordWrap := True;
  LTop := LTop + 44;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := Self;
  LLabel.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN, 20);
  LLabel.Text := 'Put it in (the top is the Bookmarks menu itself)';
  LTop := LTop + 22;
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.SetBounds(DIALOG_MARGIN, LTop, DIALOG_WIDTH - 2 * DIALOG_MARGIN,
    DIALOG_HEIGHT - LTop - DIALOG_MARGIN - 44);

  LButton := TButton.Create(Self);
  LButton.Parent := Self;
  LButton.SetBounds(DIALOG_MARGIN, DIALOG_HEIGHT - DIALOG_MARGIN - 30, 120, 30);
  LButton.Text := 'New Folder...';
  LButton.OnClick := NewFolderClick;

  FOkButton := TButton.Create(Self);
  FOkButton.Parent := Self;
  FOkButton.SetBounds(DIALOG_WIDTH - DIALOG_MARGIN - 2 * 88 - 8,
    DIALOG_HEIGHT - DIALOG_MARGIN - 30, 88, 30);
  FOkButton.Text := 'OK';
  FOkButton.Default := True;
  FOkButton.ModalResult := mrOk;

  LButton := TButton.Create(Self);
  LButton.Parent := Self;
  LButton.SetBounds(DIALOG_WIDTH - DIALOG_MARGIN - 88, DIALOG_HEIGHT - DIALOG_MARGIN - 30, 88, 30);
  LButton.Text := 'Cancel';
  LButton.Cancel := True;
  LButton.ModalResult := mrCancel;
end;

procedure TfrmBookmark.FillTree(ASelect: Integer);
var
  LRoot: TTreeViewItem;
begin
  FTree.BeginUpdate;
  try
    FTree.Clear;
    LRoot := TTreeViewItem.Create(Self);
    LRoot.Text := ROOT_CAPTION;
    LRoot.Tag := BOOKMARK_ROOT;
    LRoot.Parent := FTree;
    AddFolderItems(LRoot, BOOKMARK_ROOT, ASelect);
    LRoot.IsExpanded := True;
    if FTree.Selected = nil then
      FTree.Selected := LRoot;
  finally
    FTree.EndUpdate;
  end;
end;

procedure TfrmBookmark.AddFolderItems(AParent: TFmxObject; AFolder: Integer; ASelect: Integer);
var
  LIndex: Integer;
  LItem: TTreeViewItem;
  LFolder: TBookmarkFolder;
begin
  for LIndex in FList.FoldersIn(AFolder) do
  begin
    LFolder := FList.Folders[LIndex];
    LItem := TTreeViewItem.Create(Self);
    LItem.Text := LFolder.Name;
    LItem.Tag := LFolder.Id;
    LItem.Parent := AParent;
    AddFolderItems(LItem, LFolder.Id, ASelect);
    LItem.IsExpanded := True;
    if LFolder.Id = ASelect then
      FTree.Selected := LItem;
  end;
end;

function TfrmBookmark.ChosenFolder: Integer;
begin
  if FTree.Selected <> nil then
    Result := FTree.Selected.Tag
  else
    Result := BOOKMARK_ROOT;
end;

procedure TfrmBookmark.ReadResult(out AResult: TBookmarkDialogResult; out AProblem: string);
begin
  AResult := Default(TBookmarkDialogResult);
  AProblem := '';
  AResult.Name := TBookmarkList.CleanName(FNameEdit.Text);
  AResult.Folder := ChosenFolder;
  AResult.UseCurrent := FCurrentRadio.IsChecked and FCurrentRadio.Enabled;
  if AResult.Name = '' then
    AProblem := 'Type a name for the bookmark.';
  if AResult.UseCurrent then
    Exit;
  // Typed coordinates: every box must make sense; blank ones take their
  // defaults
  if not ParseCoordinate(FLatitudeEdit.Text, True, AResult.Latitude) then
    AProblem := 'Type a latitude: degrees, -90 to 90, or with N or S.'
  else if not ParseCoordinate(FLongitudeEdit.Text, False, AResult.Longitude) then
    AProblem := 'Type a longitude: degrees, -180 to 180, or with E or W.'
  else if not ParseNumber(FHeightEdit.Text, FDefaultHeight, AResult.AboveGround) or
     (AResult.AboveGround < 0) then
    AProblem := 'The height above the ground is metres, 0 or more.'
  else if not ParseNumber(FHeadingEdit.Text, 0, AResult.Heading) then
    AProblem := 'The heading is degrees from north, such as 90 for east.'
  else if not ParseNumber(FSpeedEdit.Text, 0, AResult.SpeedKmh) or
     not InRange(AResult.SpeedKmh, 0, MAX_FLIGHT_SPEED * 3.6) then
    AProblem := Format('The speed is km/h, 0 to %s.', [FormatFloat('#,##0',
      MAX_FLIGHT_SPEED * 3.6)])
  else if not ParseNumber(FTiltEdit.Text, DEFAULT_FLIGHT_TILT, AResult.Tilt) or
     not InRange(AResult.Tilt, MIN_FLIGHT_TILT, MAX_FLIGHT_TILT) then
    AProblem := Format('The camera looks down %d to %d degrees (negative looks up).',
      [MIN_FLIGHT_TILT, MAX_FLIGHT_TILT]);
end;

procedure TfrmBookmark.Changed(Sender: TObject);
var
  LResult: TBookmarkDialogResult;
  LProblem: string;
  LTyped: Boolean;
begin
  if FOkButton = nil then
    Exit;
  LTyped := FTypedRadio.IsChecked;
  FLatitudeEdit.Enabled := LTyped;
  FLongitudeEdit.Enabled := LTyped;
  FHeightEdit.Enabled := LTyped;
  FHeadingEdit.Enabled := LTyped;
  FSpeedEdit.Enabled := LTyped;
  FTiltEdit.Enabled := LTyped;
  ReadResult(LResult, LProblem);
  FOkButton.Enabled := LProblem = '';
  if LProblem <> '' then
    FHintLabel.Text := LProblem
  else if LTyped then
    FHintLabel.Text := 'Blank boxes take the grey defaults. The height is above the ground ' +
      'there, found when you fly to it.'
  else
    FHintLabel.Text := '';
end;

procedure TfrmBookmark.NewFolderClick(Sender: TObject);
var
  LParent: Integer;
  LParentName: string;
begin
  LParent := ChosenFolder;
  if FTree.Selected <> nil then
    LParentName := FTree.Selected.Text
  else
    LParentName := ROOT_CAPTION;
  TDialogService.InputQuery('New Folder', [Format('Name for the new folder in "%s"',
    [LParentName])], [''],
    procedure(const AResult: TModalResult; const AValues: array of string)
    var
      LId: Integer;
    begin
      if (AResult <> mrOk) or (Length(AValues) = 0) or
         (TBookmarkList.CleanName(AValues[0]) = '') then
        Exit;
      LId := FList.AddFolder(LParent, AValues[0]);
      // The tree again, with the new folder chosen for the bookmark
      FillTree(LId);
    end);
end;

procedure TfrmBookmark.FormShowing(Sender: TObject);
begin
  FNameEdit.SetFocus;
end;

end.
