{ @abstract(The user's bookmarks of 3D views, in folders, kept in
  @code(bookmarks.json) in the settings folder.)

  A bookmark holds everything needed to go back to a moment of flight:
  where the flight was (latitude, longitude, true altitude), which way it
  went and how fast, how far the camera looked down, and how the view was
  drawn (heights stretched, imagery on or off). A bookmark made from typed
  coordinates holds a height above the ground instead, as the ground there
  was not known (@link(TBookmark.AboveGround)).

  Folders hold bookmarks and other folders, to any depth. The file keeps
  them as two flat lists, folders and bookmarks, each naming the folder it
  is in by number (0 is the top level), which reads and writes plainly
  with Neon and stays readable by hand. The order of each list is the order
  things are shown in. No FMX. }
unit GDEMBookmarks;

interface

uses
  System.SysUtils, Neon.Core.Attributes;

const
  { Name of the bookmarks file, in the settings folder. }
  BOOKMARKS_FILE_NAME = 'bookmarks.json';

  { Version of the bookmarks file this unit writes and reads. }
  BOOKMARKS_FORMAT = 1;

  { Longest name kept, in characters; longer names are cut short. }
  MAX_BOOKMARK_NAME_LENGTH = 80;

  { The folder number of the top level. }
  BOOKMARK_ROOT = 0;

type
  { @abstract(Raised when the bookmarks file cannot be read or written, or
    a name is empty.) }
  EBookmarkError = class(Exception);

  { @abstract(A folder of bookmarks.) }
  TBookmarkFolder = record
    { Its number, unique and more than 0. }
    [NeonProperty('id')]
    Id: Integer;
    { The folder it is in; @link(BOOKMARK_ROOT) for the top level. }
    [NeonProperty('parent')]
    Parent: Integer;
    { Its name. }
    [NeonProperty('name')]
    Name: string;
  end;

  { @abstract(One bookmark: a moment of flight to go back to.) }
  TBookmark = record
    { The folder it is in; @link(BOOKMARK_ROOT) for the top level. }
    [NeonProperty('folder')]
    Folder: Integer;
    { Its name. }
    [NeonProperty('name')]
    Name: string;
    { Latitude, degrees. }
    [NeonProperty('lat')]
    Latitude: Double;
    { Longitude, degrees, -180 to 180. }
    [NeonProperty('lon')]
    Longitude: Double;
    { True height above sea level, metres; or above the ground, if
      @link(TBookmark.AboveGround). }
    [NeonProperty('altitude')]
    Altitude: Double;
    { @true if @link(TBookmark.Altitude) is a height above the ground there,
      as for a bookmark made from typed coordinates, where the ground was
      not known. @false (above the sea) in files without it. }
    [NeonProperty('aboveGround')]
    AboveGround: Boolean;
    { The way the flight went, degrees clockwise from true north. }
    [NeonProperty('heading')]
    Heading: Double;
    { Speed over the ground, metres a second. }
    [NeonProperty('speed')]
    Speed: Double;
    { The camera's tilt below the level, degrees. }
    [NeonProperty('tilt')]
    Tilt: Double;
    { Times heights were stretched. }
    [NeonProperty('heights')]
    Heights: Integer;
    { @true if the satellite imagery was on. }
    [NeonProperty('realistic')]
    Realistic: Boolean;
    { When it was made, ISO 8601 in UTC, for the record. }
    [NeonProperty('made')]
    Made: string;
  end;

  { @abstract(The bookmarks file's contents.) }
  TBookmarkFile = record
    { Version of the file; see @link(BOOKMARKS_FORMAT). }
    [NeonProperty('format')]
    Format: Integer;
    { The folders, in the order they are shown. }
    [NeonProperty('folders')]
    Folders: TArray<TBookmarkFolder>;
    { The bookmarks, in the order they are shown. }
    [NeonProperty('bookmarks')]
    Bookmarks: TArray<TBookmark>;
  end;

  { @abstract(The user's bookmarks and their folders, kept in a file.) }
  TBookmarkList = class
  private
    { The folders. }
    FFolders: TArray<TBookmarkFolder>;
    { The bookmarks. }
    FBookmarks: TArray<TBookmark>;
    { Backing field for @link(FileName). }
    FFileName: string;

    { Reader for @link(FolderCount). @returns(How many folders there
      are.) }
    function GetFolderCount: Integer;

    { Reader for @link(Folders).
      @param(AIndex Which folder, from 0.)
      @returns(The folder.) }
    function GetFolder(AIndex: Integer): TBookmarkFolder;

    { Reader for @link(Count). @returns(How many bookmarks there are.) }
    function GetCount: Integer;

    { Reader for @link(Items).
      @param(AIndex Which bookmark, from 0.)
      @returns(The bookmark.) }
    function GetItem(AIndex: Integer): TBookmark;
  public
    { Makes an empty list, kept in a file.
      @param(AFileName The file; empty for @link(BOOKMARKS_FILE_NAME) in
        the settings folder.) }
    constructor Create(const AFileName: string = '');

    { Tidies a name as typed: spaces trimmed, line breaks and other control
      characters made spaces, and cut to @link(MAX_BOOKMARK_NAME_LENGTH).
      @param(AName The name.)
      @returns(The tidied name; may be empty.) }
    class function CleanName(const AName: string): string; static;

    { Reads the file, replacing what is held. A missing file is not an
      error: the list is just empty. Folders whose parent is missing, and
      bookmarks whose folder is missing, are moved to the top level.
      @returns(@true if the file was there and read.)
      @raises(EBookmarkError if the file is there but cannot be read.) }
    function Load: Boolean;

    { Writes the file, through a temporary file renamed into place.
      @raises(EBookmarkError if it cannot be written.) }
    procedure Save;

    { Copies another list's folders and bookmarks (not its file name).
      @param(ASource The list to copy.) }
    procedure Assign(ASource: TBookmarkList);

    { Adds a folder. Does not save.
      @param(AParent The folder it goes in; @link(BOOKMARK_ROOT) for the
        top level.)
      @param(AName Its name, tidied by @link(CleanName); must not be empty
        after tidying.)
      @returns(Its number.)
      @raises(EBookmarkError if the name is empty or the parent is not a
        folder.) }
    function AddFolder(AParent: Integer; const AName: string): Integer;

    { Adds a bookmark. Does not save.
      @param(ABookmark The bookmark; its name is tidied by
        @link(CleanName) and must not be empty after tidying, and its folder
        must exist.)
      @returns(Its index.)
      @raises(EBookmarkError if the name is empty or the folder is not a
        folder.) }
    function Add(const ABookmark: TBookmark): Integer;

    { Where a folder is in @link(Folders).
      @param(AId The folder's number.)
      @returns(Its index, or -1 if there is no such folder.) }
    function FolderIndex(AId: Integer): Integer;

    { The folders in a folder, in order.
      @param(AParent The folder; @link(BOOKMARK_ROOT) for the top level.)
      @returns(Their indexes in @link(Folders).) }
    function FoldersIn(AParent: Integer): TArray<Integer>;

    { The bookmarks in a folder, in order.
      @param(AFolder The folder; @link(BOOKMARK_ROOT) for the top level.)
      @returns(Their indexes in @link(Items).) }
    function BookmarksIn(AFolder: Integer): TArray<Integer>;

    { The file the bookmarks are kept in. }
    property FileName: string read FFileName;

    { How many folders there are. }
    property FolderCount: Integer read GetFolderCount;

    { The folders. }
    property Folders[AIndex: Integer]: TBookmarkFolder read GetFolder;

    { How many bookmarks there are. }
    property Count: Integer read GetCount;

    { The bookmarks. }
    property Items[AIndex: Integer]: TBookmark read GetItem; default;
  end;

implementation

uses
  System.IOUtils, System.Math, System.Rtti,
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON,
  GDEMSettings;

{ The Neon configuration for the bookmarks file: names exactly as in the
  [NeonProperty] attributes, laid out readably, and exceptions raised so a
  bad file is reported.
  @returns(The configuration.) }
function BookmarksNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Create
    .SetMemberCase(TNeonCase.Unchanged)
    .SetPrettyPrint(True)
    .SetRaiseExceptions(True);
end;

{ Wraps a longitude into -180 to 180.
  @param(ALon The longitude, in degrees.)
  @returns(The same meridian, from -180 up to but not including 180.) }
function WrapLon(ALon: Double): Double;
begin
  Result := ALon - Floor((ALon + 180) / 360) * 360;
end;

{ @true if a number is an ordinary one, neither NaN nor infinite.
  @param(AValue The number.)
  @returns(@true if ordinary.) }
function IsOrdinary(AValue: Double): Boolean;
begin
  Result := not IsNan(AValue) and not IsInfinite(AValue);
end;

{ TBookmarkList }

constructor TBookmarkList.Create(const AFileName: string);
begin
  inherited Create;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := TPath.Combine(TGDEMSettings.SettingsFolder, BOOKMARKS_FILE_NAME);
end;

class function TBookmarkList.CleanName(const AName: string): string;
var
  LChar: Char;
begin
  Result := '';
  for LChar in AName do
    if LChar >= ' ' then
      Result := Result + LChar
    else
      Result := Result + ' ';
  Result := Result.Trim;
  if Length(Result) > MAX_BOOKMARK_NAME_LENGTH then
    Result := Result.Substring(0, MAX_BOOKMARK_NAME_LENGTH).TrimRight;
end;

function TBookmarkList.GetFolderCount: Integer;
begin
  Result := Length(FFolders);
end;

function TBookmarkList.GetFolder(AIndex: Integer): TBookmarkFolder;
begin
  Result := FFolders[AIndex];
end;

function TBookmarkList.GetCount: Integer;
begin
  Result := Length(FBookmarks);
end;

function TBookmarkList.GetItem(AIndex: Integer): TBookmark;
begin
  Result := FBookmarks[AIndex];
end;

function TBookmarkList.FolderIndex(AId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FFolders) do
    if FFolders[I].Id = AId then
      Exit(I);
  Result := -1;
end;

function TBookmarkList.FoldersIn(AParent: Integer): TArray<Integer>;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FFolders) do
    if FFolders[I].Parent = AParent then
      Result := Result + [I];
end;

function TBookmarkList.BookmarksIn(AFolder: Integer): TArray<Integer>;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FBookmarks) do
    if FBookmarks[I].Folder = AFolder then
      Result := Result + [I];
end;

function TBookmarkList.Load: Boolean;
var
  LFile: TBookmarkFile;
  LFolder: TBookmarkFolder;
  LBookmark: TBookmark;
  I, J, LSteps: Integer;
  LSeen: Boolean;
begin
  if not TFile.Exists(FFileName) then
  begin
    FFolders := nil;
    FBookmarks := nil;
    Exit(False);
  end;
  try
    LFile := TNeon.JSONToValue<TBookmarkFile>(
      TEncoding.UTF8.GetString(TFile.ReadAllBytes(FFileName)), BookmarksNeonConfig);
  except
    on E: Exception do
      raise EBookmarkError.CreateFmt('Could not read %s: %s', [FFileName, E.Message]);
  end;
  if LFile.Format > BOOKMARKS_FORMAT then
    raise EBookmarkError.CreateFmt('%s is format %d; this program reads format %d.',
      [FFileName, LFile.Format, BOOKMARKS_FORMAT]);

  // Folders with a name and a number of their own; a hand-edited file
  // cannot repeat a number
  FFolders := nil;
  for LFolder in LFile.Folders do
    if (LFolder.Id > 0) and (CleanName(LFolder.Name) <> '') and (FolderIndex(LFolder.Id) < 0) then
    begin
      FFolders := FFolders + [LFolder];
      FFolders[High(FFolders)].Name := CleanName(LFolder.Name);
    end;
  // A folder whose parent is missing, or that would be inside itself,
  // goes to the top level
  for I := 0 to High(FFolders) do
  begin
    J := FFolders[I].Parent;
    LSeen := False;
    LSteps := 0;
    // Up the parents to the top; a chain longer than there are folders
    // goes round in a loop somewhere above
    while (J <> BOOKMARK_ROOT) and not LSeen do
    begin
      Inc(LSteps);
      if (J = FFolders[I].Id) or (FolderIndex(J) < 0) or (LSteps > Length(FFolders)) then
        LSeen := True
      else
        J := FFolders[FolderIndex(J)].Parent;
    end;
    if LSeen then
      FFolders[I].Parent := BOOKMARK_ROOT;
  end;

  // Bookmarks that make sense, so a hand-edited file cannot put one off
  // the globe
  FBookmarks := nil;
  for LBookmark in LFile.Bookmarks do
    if (CleanName(LBookmark.Name) <> '') and InRange(LBookmark.Latitude, -90, 90) and
       IsOrdinary(LBookmark.Longitude) and IsOrdinary(LBookmark.Altitude) and
       IsOrdinary(LBookmark.Heading) and IsOrdinary(LBookmark.Speed) and
       IsOrdinary(LBookmark.Tilt) then
    begin
      FBookmarks := FBookmarks + [LBookmark];
      I := High(FBookmarks);
      FBookmarks[I].Name := CleanName(LBookmark.Name);
      FBookmarks[I].Longitude := WrapLon(LBookmark.Longitude);
      FBookmarks[I].Speed := Max(LBookmark.Speed, 0);
      if (LBookmark.Folder <> BOOKMARK_ROOT) and (FolderIndex(LBookmark.Folder) < 0) then
        FBookmarks[I].Folder := BOOKMARK_ROOT;
    end;
  Result := True;
end;

procedure TBookmarkList.Save;
var
  LFile: TBookmarkFile;
  LTempName, LJSON: string;
begin
  LFile.Format := BOOKMARKS_FORMAT;
  LFile.Folders := FFolders;
  LFile.Bookmarks := FBookmarks;
  LTempName := FFileName + '.tmp';
  try
    ForceDirectories(ExtractFileDir(FFileName));
    LJSON := TNeon.ValueToJSONString(TValue.From<TBookmarkFile>(LFile), BookmarksNeonConfig);
    TFile.WriteAllBytes(LTempName, TEncoding.UTF8.GetBytes(LJSON));
    if TFile.Exists(FFileName) then
      TFile.Delete(FFileName);
    TFile.Move(LTempName, FFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise EBookmarkError.CreateFmt('Could not write %s: %s', [FFileName, E.Message]);
    end;
  end;
end;

procedure TBookmarkList.Assign(ASource: TBookmarkList);
begin
  FFolders := Copy(ASource.FFolders);
  FBookmarks := Copy(ASource.FBookmarks);
end;

function TBookmarkList.AddFolder(AParent: Integer; const AName: string): Integer;
var
  LFolder: TBookmarkFolder;
  I: Integer;
begin
  LFolder.Name := CleanName(AName);
  if LFolder.Name = '' then
    raise EBookmarkError.Create('A folder needs a name.');
  if (AParent <> BOOKMARK_ROOT) and (FolderIndex(AParent) < 0) then
    raise EBookmarkError.Create('There is no such folder to put it in.');
  LFolder.Parent := AParent;
  // One more than the highest number in use
  LFolder.Id := 1;
  for I := 0 to High(FFolders) do
    LFolder.Id := Max(LFolder.Id, FFolders[I].Id + 1);
  FFolders := FFolders + [LFolder];
  Result := LFolder.Id;
end;

function TBookmarkList.Add(const ABookmark: TBookmark): Integer;
var
  LBookmark: TBookmark;
begin
  LBookmark := ABookmark;
  LBookmark.Name := CleanName(ABookmark.Name);
  if LBookmark.Name = '' then
    raise EBookmarkError.Create('A bookmark needs a name.');
  if (LBookmark.Folder <> BOOKMARK_ROOT) and (FolderIndex(LBookmark.Folder) < 0) then
    raise EBookmarkError.Create('There is no such folder to put it in.');
  LBookmark.Longitude := WrapLon(ABookmark.Longitude);
  LBookmark.Speed := Max(ABookmark.Speed, 0);
  FBookmarks := FBookmarks + [LBookmark];
  Result := High(FBookmarks);
end;

end.
