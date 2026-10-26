{ @abstract(The folder where downloaded ASTER GDEM tiles are kept.)

  The whole world is about 23,000 tiles, 46,000 files and roughly 400 GB,
  so files are not kept in one folder. Each tile goes in a folder chosen
  from its position, grouping tiles into 10 by 10 degree blocks:

  @code(<root>/N50/W010/ASTGTMV003_N50W002_dem.tif)

  The first level is the block's southern edge, the second its western
  edge, named the same way as tiles. A block holds at most 100 tiles (200
  files), and the world needs at most about 600 block folders. This is a
  deterministic, geographic hash: neighbouring tiles share a folder, so a
  map selection touches only a few folders, and the layout can be browsed
  by hand. Folders are created when a file is first written to them and
  removed once they are empty; see @link(TGDEMStore.PruneEmptyFolders).

  The store describes itself, so it can be moved freely, including to a
  removable drive:
  @unorderedList(
    @item(@code(gdem-store.json), written with Neon, marks the folder as a
      GDEM data folder and records the layout version.)
    @item(@code(downloaded.bin) is a @link(TTileIndex) recording which
      tiles are fully downloaded (both files present). It can always be
      rebuilt from the files with @link(TGDEMStore.Rescan).)
  )

  @link(TGDEMStore.Rescan) also moves any tile files that are in the wrong
  place, such as downloads from before this layout existed, into their
  block folders.

  @link(TGDEMStore.ImportFrom) copies tiles from any other folder, such as
  the single flat folder other download tools produce, into the store. The
  source is only read, never changed.

  Methods that take a @link(TCancelToken) are meant for background
  threads. The others are cheap and can be called from any thread. }
unit GDEMStore;

interface

uses
  System.SysUtils, System.Classes,
  Neon.Core.Attributes,
  GDEMCancel, GDEMTiles, GDEMTileIndex;

const
  { Name of the file that marks a folder as a GDEM data folder. }
  STORE_MARKER_FILE = 'gdem-store.json';
  { Name of the downloaded-tiles index inside the data folder. }
  STORE_DOWNLOADED_FILE = 'downloaded.bin';
  { Current layout version, written to the marker file. }
  STORE_FORMAT = 1;
  { Size of the blocks tiles are grouped into, in degrees. }
  STORE_BLOCK_DEGREES = 10;
  { Average size of one tile's two files, used for estimates. The whole
    world is about 400 GB over about 23,000 tiles. }
  ESTIMATED_TILE_BYTES = Int64(18) * 1024 * 1024;

type
  { @abstract(Raised when the data folder cannot be used.) }
  EStoreError = class(Exception);

  { @abstract(What an import did.) }
  TImportResult = record
    { Files copied into the store. }
    Copied: Integer;
    { Files skipped because the store already had them, the same size. }
    AlreadyPresent: Integer;
    { Files copied over a different-sized copy already in the store, which
      is taken to be incomplete. Also counted in @link(Copied). }
    Replaced: Integer;
    { Files skipped because they are not ASTER GDEM V3 tile files, or do
      not start like a TIFF. }
    Ignored: Integer;
    { Bytes copied. }
    Bytes: Int64;
  end;

  { @abstract(Contents of @link(STORE_MARKER_FILE).) }
  TStoreMarker = class
  private
    { Backing field for @link(Format). }
    FFormat: Integer;
    { Backing field for @link(Layout). }
    FLayout: string;
  public
    { Layout version; see @link(STORE_FORMAT). }
    [NeonProperty('format')]
    property Format: Integer read FFormat write FFormat;
    { Human-readable description of the layout. }
    [NeonProperty('layout')]
    property Layout: string read FLayout write FLayout;
  end;

  { Reports progress through a long store operation.
    @param(ADone Items processed so far.)
    @param(ATotal Total items, or 0 if not known.) }
  TStoreProgressEvent = reference to procedure(ADone, ATotal: Integer);

  { Called with a line of progress text for the user.
    @param(Msg The text to show.) }
  TStoreLogEvent = reference to procedure(const Msg: string);

  { @abstract(A data folder holding downloaded tiles.)

    Creating one does not touch the disk. Check @link(IsAvailable) before
    use, since the folder may be on a drive that is not connected, and call
    @link(EnsureCreated) before writing. }
  TGDEMStore = class
  private
    { Backing field for @link(Root). }
    FRoot: string;
    { Backing field for @link(OnLog). }
    FOnLog: TStoreLogEvent;

    { Passes a message to @link(OnLog) if it is assigned.
      @param(Msg The text to pass on.) }
    procedure Log(const Msg: string);

    { Moves one file, falling back to copy, check and delete when a rename
      is not possible (for example between drives).
      @param(ASource File to move.)
      @param(ADest Where it should end up. Must not exist.) }
    class procedure MoveFileSafely(const ASource, ADest: string); static;

    { Lists every tile file under the root, in any folder.
      @returns(Full paths of every @code(.tif) file.) }
    function AllTileFiles: TArray<string>;
  public
    { Creates a store object for a folder. Nothing is read or written.
      @param(ARoot The data folder.) }
    constructor Create(const ARoot: string);

    { Name of the block folder, relative to the root, for a tile.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.)
      @returns(For example @code(N50/W010), using the platform's path
        separator.) }
    class function BlockFolderName(ASouth, AWest: Integer): string; static;

    { Reads the tile and kind from a file name of the form
      @code(ASTGTMV003_N50W002_dem.tif) or @code(..._num.tif).
      @param(AFileName File name, with or without a folder.)
      @param(ASouth Receives the latitude of the tile's southern edge.)
      @param(AWest Receives the longitude of the tile's western edge.)
      @returns(@true for an ASTER GDEM tile file.) }
    class function TryParseFileName(const AFileName: string;
      out ASouth, AWest: Integer): Boolean; static;

    { Full path of a tile's block folder.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.)
      @returns(The folder path.) }
    function TileFolder(ASouth, AWest: Integer): string; overload;

    { Full path of a tile's block folder, from its name.
      @param(ATile Tile name such as @code(N50W002).)
      @returns(The folder path.)
      @raises(EStoreError if ATile is not a tile name.) }
    function TileFolder(const ATile: string): string; overload;

    { Full path where a tile file belongs.
      @param(AFileName File name such as
        @code(ASTGTMV003_N50W002_dem.tif).)
      @returns(The full path, or an empty string if the name is not a tile
        file name.) }
    function PathForFile(const AFileName: string): string;

    { Full paths of a tile's two files.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.)
      @param(ADem Receives the path of the @code(_dem.tif) file.)
      @param(ANum Receives the path of the @code(_num.tif) file.) }
    procedure TileFiles(ASouth, AWest: Integer; out ADem, ANum: string);

    { Checks whether both of a tile's files are present and not empty.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.)
      @returns(@true if the tile is fully downloaded.) }
    function TileComplete(ASouth, AWest: Integer): Boolean;

    { Checks whether the folder can be reached now.
      @returns(@true if the root folder exists.) }
    function IsAvailable: Boolean;

    { Checks whether the folder has been set up as a data folder.
      @returns(@true if @link(STORE_MARKER_FILE) is present.) }
    function HasMarker: Boolean;

    { Creates the root folder and the marker file if they are missing.
      @raises(EStoreError if the folder cannot be created, for example
        because its drive is not connected.) }
    procedure EnsureCreated;

    { Removes AFolder if it is empty, then each parent that becomes empty,
      stopping at the root, which is never removed.
      @param(AFolder A folder inside the root.) }
    procedure PruneEmptyFolders(const AFolder: string);

    { Space free for the current user on the drive holding the root.
      @returns(Bytes free, or -1 if it cannot be found out.) }
    function FreeSpace: Int64;

    { Space free for the current user on the drive holding a path. The
      path need not exist; its nearest existing parent is checked.
      @param(APath Any path.)
      @returns(Bytes free, or -1 if it cannot be found out.) }
    class function FreeSpaceAt(const APath: string): Int64; static;

    { Full path of the downloaded-tiles index file.
      @returns(@code(downloaded.bin) in the root.) }
    function DownloadedIndexFileName: string;

    { Reads the downloaded-tiles index.
      @param(AIndex Index to fill.)
      @returns(@true if the file existed and was read.)
      @raises(ETileIndexError if the file is damaged.) }
    function LoadDownloadedIndex(AIndex: TTileIndex): Boolean;

    { Writes the downloaded-tiles index.
      @param(AIndex Index to save.)
      @raises(ETileIndexError if it cannot be written.) }
    procedure SaveDownloadedIndex(AIndex: TTileIndex);

    { Checks every file in the data folder and rebuilds the
      downloaded-tiles index from what is there:
      @unorderedList(
        @item(tile files in the wrong folder are moved to their block
          folder;)
        @item(leftover partial downloads (@code(.part) and @code(.tmp)
          files) are deleted;)
        @item(empty folders are removed;)
        @item(a tile counts as downloaded only when both files are present.)
      )
      The index is saved when done.
      @param(AIndex Receives the rebuilt index.)
      @param(AToken Checked between files.)
      @param(AOnProgress Called as files are checked. May be @nil.)
      @raises(EOperationCancelled if AToken is cancelled.) }
    procedure Rescan(AIndex: TTileIndex; AToken: TCancelToken;
      const AOnProgress: TStoreProgressEvent);

    { Moves every tile file into another data folder, keeping the layout.
      Files already at the destination with the same size are not copied
      again, so an interrupted move can simply be run again. Empty folders
      are removed from this store afterwards.
      @param(ATarget The destination store. It is created if needed.)
      @param(AToken Checked between files.)
      @param(AOnProgress Called after each file. May be @nil.)
      @returns(Number of files moved.)
      @raises(EStoreError if a file cannot be moved.)
      @raises(EOperationCancelled if AToken is cancelled.) }
    function MoveAllTo(ATarget: TGDEMStore; AToken: TCancelToken;
      const AOnProgress: TStoreProgressEvent): Integer;

    { Deletes the files of the given tiles and removes folders left empty.
      @param(ATiles Tile names such as @code(N50W002).)
      @param(AToken Checked between tiles.)
      @param(AOnProgress Called after each tile. May be @nil.)
      @returns(The names of the tiles whose files were deleted.)
      @raises(EOperationCancelled if AToken is cancelled.) }
    function DeleteTiles(const ATiles: TArray<string>; AToken: TCancelToken;
      const AOnProgress: TStoreProgressEvent): TArray<string>;

    { Copies every ASTER GDEM V3 tile file found in a folder, and in any
      folders inside it, into this store's block layout. The source is
      opened for reading only and nothing in it is changed, moved or
      deleted.

      Files the store already has, at the same size, are skipped, so an
      interrupted import can simply be run again. Each file is copied under
      a temporary name, its size checked, and only then renamed, so a
      cancelled or failed import never leaves a partial tile behind.

      Before copying, the space needed is worked out; the import does not
      start if it would leave less than AReserve free, and it stops if free
      space falls below AReserve along the way.

      @param(ASourceFolder The folder to import from. It must not be inside
        the store, nor contain it.)
      @param(AReserve Bytes that must be left free on the store's drive.)
      @param(AToken Checked between files.)
      @param(AOnProgress Called after each file. May be @nil.)
      @returns(What was copied and skipped.)
      @raises(EStoreError if the folders overlap, space is short, or a file
        cannot be copied.)
      @raises(EOperationCancelled if AToken is cancelled.) }
    function ImportFrom(const ASourceFolder: string; AReserve: Int64;
      AToken: TCancelToken; const AOnProgress: TStoreProgressEvent): TImportResult;

    { Total size of all tile files.
      @param(AToken Checked between files. May be @nil.)
      @returns(Size in bytes.) }
    function DataSize(AToken: TCancelToken): Int64;

    { The data folder. }
    property Root: string read FRoot;

    { Receives progress text. Called on whichever thread runs the
      operation. }
    property OnLog: TStoreLogEvent read FOnLog write FOnLog;
  end;

{ Formats a number of bytes for display, such as @code(12.3 GB).
  @param(ABytes The size; negative means unknown.)
  @returns(The formatted size.) }
function FormatByteSize(ABytes: Int64): string;

implementation

uses
  System.IOUtils, System.Types, System.Math, System.StrUtils,
  System.Generics.Collections, System.RegularExpressions,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  {$IFDEF POSIX}
  Posix.SysStatvfs,
  {$ENDIF}
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON;

function FormatByteSize(ABytes: Int64): string;
const
  MB = Int64(1024) * 1024;
  GB = MB * 1024;
  TB = GB * 1024;
begin
  if ABytes < 0 then
    Result := 'unknown'
  else if ABytes >= TB then
    Result := FormatFloat('0.00', ABytes / TB) + ' TB'
  else if ABytes >= GB then
    Result := FormatFloat('0.0', ABytes / GB) + ' GB'
  else
    Result := FormatFloat('0', ABytes / MB) + ' MB';
end;

{ Checks whether a file starts like a TIFF: @code(II) (little-endian) or
  @code(MM) (big-endian).
  @param(AFileName File to check.)
  @returns(@true if it looks like a TIFF.) }
function StartsLikeTIFF(const AFileName: string): Boolean;
var
  LStream: TFileStream;
  LHead: array[0..1] of Byte;
begin
  Result := False;
  try
    LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if LStream.Read(LHead, 2) = 2 then
        Result := ((LHead[0] = Ord('I')) and (LHead[1] = Ord('I'))) or
                  ((LHead[0] = Ord('M')) and (LHead[1] = Ord('M')));
    finally
      LStream.Free;
    end;
  except
    Result := False;
  end;
end;

{ TGDEMStore }

constructor TGDEMStore.Create(const ARoot: string);
begin
  inherited Create;
  FRoot := ExcludeTrailingPathDelimiter(ARoot);
end;

procedure TGDEMStore.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

class function TGDEMStore.BlockFolderName(ASouth, AWest: Integer): string;
const
  NS: array[Boolean] of Char = ('S', 'N');
  EW: array[Boolean] of Char = ('W', 'E');
var
  LBlockSouth, LBlockWest: Integer;
begin
  // Floor division, so -1 falls in the block starting at -10
  LBlockSouth := Floor(ASouth / STORE_BLOCK_DEGREES) * STORE_BLOCK_DEGREES;
  LBlockWest := Floor(AWest / STORE_BLOCK_DEGREES) * STORE_BLOCK_DEGREES;
  Result := TPath.Combine(
    Format('%s%.2d', [NS[LBlockSouth >= 0], Abs(LBlockSouth)]),
    Format('%s%.3d', [EW[LBlockWest >= 0], Abs(LBlockWest)]));
end;

class function TGDEMStore.TryParseFileName(const AFileName: string;
  out ASouth, AWest: Integer): Boolean;
begin
  Result := TRegEx.IsMatch(TPath.GetFileName(AFileName),
    '^ASTGTMV003_[NS]\d{2}[EW]\d{3}_(dem|num)\.tif$', [roIgnoreCase]) and
    TryParseTileName(TPath.GetFileName(AFileName), ASouth, AWest);
end;

function TGDEMStore.TileFolder(ASouth, AWest: Integer): string;
begin
  Result := TPath.Combine(FRoot, BlockFolderName(ASouth, AWest));
end;

function TGDEMStore.TileFolder(const ATile: string): string;
var
  LSouth, LWest: Integer;
begin
  if not TryParseTileName(ATile, LSouth, LWest) then
    raise EStoreError.CreateFmt('"%s" is not a tile name.', [ATile]);
  Result := TileFolder(LSouth, LWest);
end;

function TGDEMStore.PathForFile(const AFileName: string): string;
var
  LSouth, LWest: Integer;
begin
  if TryParseFileName(AFileName, LSouth, LWest) then
    Result := TPath.Combine(TileFolder(LSouth, LWest), TPath.GetFileName(AFileName))
  else
    Result := '';
end;

procedure TGDEMStore.TileFiles(ASouth, AWest: Integer; out ADem, ANum: string);
var
  LBase: string;
begin
  LBase := TPath.Combine(TileFolder(ASouth, AWest),
    'ASTGTMV003_' + TileName(ASouth, AWest));
  ADem := LBase + '_dem.tif';
  ANum := LBase + '_num.tif';
end;

function TGDEMStore.TileComplete(ASouth, AWest: Integer): Boolean;
var
  LDem, LNum: string;
begin
  TileFiles(ASouth, AWest, LDem, LNum);
  Result := TFile.Exists(LDem) and (TFile.GetSize(LDem) > 0) and
            TFile.Exists(LNum) and (TFile.GetSize(LNum) > 0);
end;

function TGDEMStore.IsAvailable: Boolean;
begin
  Result := TDirectory.Exists(FRoot);
end;

function TGDEMStore.HasMarker: Boolean;
begin
  Result := TFile.Exists(TPath.Combine(FRoot, STORE_MARKER_FILE));
end;

procedure TGDEMStore.EnsureCreated;
var
  LMarker: TStoreMarker;
  LConfig: INeonConfiguration;
begin
  try
    ForceDirectories(FRoot);
    if not TDirectory.Exists(FRoot) then
      raise EStoreError.Create('the folder could not be created');
    if not HasMarker then
    begin
      LMarker := TStoreMarker.Create;
      try
        LMarker.Format := STORE_FORMAT;
        LMarker.Layout := 'ASTER GDEM V3 tiles in 10x10 degree block folders';
        LConfig := TNeonConfiguration.Create
          .SetMemberCase(TNeonCase.Unchanged)
          .SetPrettyPrint(True);
        TFile.WriteAllBytes(TPath.Combine(FRoot, STORE_MARKER_FILE),
          TEncoding.UTF8.GetBytes(TNeon.ObjectToJSONString(LMarker, LConfig)));
      finally
        LMarker.Free;
      end;
    end;
  except
    on E: Exception do
      raise EStoreError.CreateFmt('Cannot use the data folder %s: %s', [FRoot, E.Message]);
  end;
end;

procedure TGDEMStore.PruneEmptyFolders(const AFolder: string);
var
  LFolder: string;
begin
  LFolder := ExcludeTrailingPathDelimiter(AFolder);
  // Only folders strictly inside the root are ever removed
  while (Length(LFolder) > Length(FRoot)) and
        StartsText(IncludeTrailingPathDelimiter(FRoot), LFolder) do
  begin
    if not TDirectory.Exists(LFolder) or not TDirectory.IsEmpty(LFolder) then
      Break;
    try
      TDirectory.Delete(LFolder);
    except
      Break;
    end;
    LFolder := ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(LFolder));
  end;
end;

class function TGDEMStore.FreeSpaceAt(const APath: string): Int64;
var
  LPath: string;
  {$IFDEF MSWINDOWS}
  LFree, LTotal: Int64;
  {$ENDIF}
  {$IFDEF POSIX}
  LStat: _statvfs;
  {$ENDIF}
begin
  Result := -1;
  // Walk up to the nearest folder that exists
  LPath := ExcludeTrailingPathDelimiter(APath);
  while (LPath <> '') and not TDirectory.Exists(LPath) do
  begin
    if TPath.GetDirectoryName(LPath) = LPath then
      Exit;
    LPath := ExcludeTrailingPathDelimiter(TPath.GetDirectoryName(LPath));
  end;
  if LPath = '' then
    Exit;

  {$IFDEF MSWINDOWS}
  if GetDiskFreeSpaceEx(PChar(IncludeTrailingPathDelimiter(LPath)), LFree, LTotal, nil) then
    Result := LFree;
  {$ENDIF}
  {$IFDEF POSIX}
  if statvfs(PAnsiChar(UTF8String(LPath)), LStat) = 0 then
    Result := Int64(LStat.f_bavail) * Int64(LStat.f_frsize);
  {$ENDIF}
end;

function TGDEMStore.FreeSpace: Int64;
begin
  Result := FreeSpaceAt(FRoot);
end;

function TGDEMStore.DownloadedIndexFileName: string;
begin
  Result := TPath.Combine(FRoot, STORE_DOWNLOADED_FILE);
end;

function TGDEMStore.LoadDownloadedIndex(AIndex: TTileIndex): Boolean;
begin
  Result := AIndex.LoadFromFile(DownloadedIndexFileName);
end;

procedure TGDEMStore.SaveDownloadedIndex(AIndex: TTileIndex);
begin
  AIndex.SaveToFile(DownloadedIndexFileName);
end;

function TGDEMStore.AllTileFiles: TArray<string>;
begin
  if TDirectory.Exists(FRoot) then
    Result := TDirectory.GetFiles(FRoot, '*.tif', TSearchOption.soAllDirectories)
  else
    Result := nil;
end;

class procedure TGDEMStore.MoveFileSafely(const ASource, ADest: string);
var
  LTemp: string;
begin
  ForceDirectories(TPath.GetDirectoryName(ADest));
  try
    // A rename is instant when both are on the same drive
    TFile.Move(ASource, ADest);
    Exit;
  except
    // Fall through to copying, which also works between drives
  end;
  LTemp := ADest + '.tmp';
  try
    TFile.Copy(ASource, LTemp, True);
    if TFile.GetSize(LTemp) <> TFile.GetSize(ASource) then
      raise EStoreError.CreateFmt('Copy of %s is incomplete.', [ASource]);
    TFile.Move(LTemp, ADest);
  except
    if TFile.Exists(LTemp) then
      TFile.Delete(LTemp);
    raise;
  end;
  TFile.Delete(ASource);
end;

procedure TGDEMStore.Rescan(AIndex: TTileIndex; AToken: TCancelToken;
  const AOnProgress: TStoreProgressEvent);
var
  LFiles: TArray<string>;
  LFile, LTarget, LFolder: string;
  LIndex, LSouth, LWest, LMoved: Integer;
  LFolders: TList<string>;
  LDem, LNum: TDictionary<Integer, Boolean>;
  LKey: Integer;
begin
  Log('Checking the data folder ' + FRoot + ' ...');
  AIndex.Clear;
  LMoved := 0;
  LFolders := TList<string>.Create;
  LDem := TDictionary<Integer, Boolean>.Create;
  LNum := TDictionary<Integer, Boolean>.Create;
  try
    // Remove leftovers of interrupted downloads and moves
    if TDirectory.Exists(FRoot) then
      for LFile in TDirectory.GetFiles(FRoot, '*.*', TSearchOption.soAllDirectories) do
        if EndsText('.tif.part', LFile) or EndsText('.tif.tmp', LFile) then
        begin
          AToken.Check;
          TFile.Delete(LFile);
          if not LFolders.Contains(TPath.GetDirectoryName(LFile)) then
            LFolders.Add(TPath.GetDirectoryName(LFile));
        end;

    LFiles := AllTileFiles;
    for LIndex := 0 to High(LFiles) do
    begin
      AToken.Check;
      LFile := LFiles[LIndex];
      if not TryParseFileName(LFile, LSouth, LWest) or (TFile.GetSize(LFile) = 0) then
        Continue;

      LTarget := PathForFile(LFile);
      if not SameFileName(LTarget, LFile) then
      begin
        if TFile.Exists(LTarget) then
          Log('  ' + LFile + ' is a duplicate of ' + LTarget + '; left where it is')
        else
        begin
          LFolder := TPath.GetDirectoryName(LFile);
          MoveFileSafely(LFile, LTarget);
          Inc(LMoved);
          if not LFolders.Contains(LFolder) then
            LFolders.Add(LFolder);
        end;
      end;

      LKey := (LSouth + 90) * 360 + (LWest + 180);
      if EndsText('_dem.tif', LFile) then
        LDem.AddOrSetValue(LKey, True)
      else
        LNum.AddOrSetValue(LKey, True);

      if Assigned(AOnProgress) and ((LIndex mod 200 = 0) or (LIndex = High(LFiles))) then
        AOnProgress(LIndex + 1, Length(LFiles));
    end;

    // A tile is downloaded only when both of its files are present
    for LKey in LDem.Keys do
      if LNum.ContainsKey(LKey) then
        AIndex.Add(LKey div 360 - 90, LKey mod 360 - 180);

    for LFolder in LFolders do
      PruneEmptyFolders(LFolder);
  finally
    LNum.Free;
    LDem.Free;
    LFolders.Free;
  end;

  if LMoved > 0 then
    Log(Format('  moved %d file(s) into their block folders', [LMoved]));
  Log(Format('  %d tile(s) fully downloaded', [AIndex.Count]));
  EnsureCreated;
  SaveDownloadedIndex(AIndex);
end;

function TGDEMStore.MoveAllTo(ATarget: TGDEMStore; AToken: TCancelToken;
  const AOnProgress: TStoreProgressEvent): Integer;
var
  LFiles: TArray<string>;
  LFile, LDest: string;
  LIndex: Integer;
  LFolders: TList<string>;
begin
  Result := 0;
  ATarget.EnsureCreated;
  LFiles := AllTileFiles;
  Log(Format('Moving %d file(s) from %s to %s ...', [Length(LFiles), FRoot, ATarget.Root]));
  LFolders := TList<string>.Create;
  try
    for LIndex := 0 to High(LFiles) do
    begin
      AToken.Check;
      LFile := LFiles[LIndex];
      LDest := ATarget.PathForFile(LFile);
      if LDest = '' then
        Continue;
      try
        if TFile.Exists(LDest) and (TFile.GetSize(LDest) = TFile.GetSize(LFile)) then
          // Already moved by an earlier, interrupted run
          TFile.Delete(LFile)
        else
        begin
          if TFile.Exists(LDest) then
            TFile.Delete(LDest);
          MoveFileSafely(LFile, LDest);
          Inc(Result);
        end;
      except
        on E: Exception do
          raise EStoreError.CreateFmt('Could not move %s: %s', [LFile, E.Message]);
      end;
      if not LFolders.Contains(TPath.GetDirectoryName(LFile)) then
        LFolders.Add(TPath.GetDirectoryName(LFile));
      if Assigned(AOnProgress) then
        AOnProgress(LIndex + 1, Length(LFiles));
    end;

    for LFile in LFolders do
      PruneEmptyFolders(LFile);
  finally
    LFolders.Free;
  end;

  // The index belongs to the data; the destination rebuilds its own
  if TFile.Exists(DownloadedIndexFileName) then
    TFile.Delete(DownloadedIndexFileName);
  // Once no tiles are left this is no longer a data folder. The root
  // itself is kept, since the user may have chosen a folder with other
  // contents.
  if Length(AllTileFiles) = 0 then
  begin
    if HasMarker then
      TFile.Delete(TPath.Combine(FRoot, STORE_MARKER_FILE));
  end;
end;

function TGDEMStore.DeleteTiles(const ATiles: TArray<string>; AToken: TCancelToken;
  const AOnProgress: TStoreProgressEvent): TArray<string>;
var
  LDeleted: TList<string>;
  LIndex, LSouth, LWest: Integer;
  LDem, LNum: string;
  LAny: Boolean;
begin
  LDeleted := TList<string>.Create;
  try
    for LIndex := 0 to High(ATiles) do
    begin
      AToken.Check;
      if not TryParseTileName(ATiles[LIndex], LSouth, LWest) then
        Continue;
      TileFiles(LSouth, LWest, LDem, LNum);
      LAny := False;
      if TFile.Exists(LDem) then
      begin
        TFile.Delete(LDem);
        LAny := True;
      end;
      if TFile.Exists(LNum) then
      begin
        TFile.Delete(LNum);
        LAny := True;
      end;
      if LAny then
      begin
        LDeleted.Add(ATiles[LIndex]);
        PruneEmptyFolders(TileFolder(LSouth, LWest));
      end;
      if Assigned(AOnProgress) then
        AOnProgress(LIndex + 1, Length(ATiles));
    end;
    Result := LDeleted.ToArray;
  finally
    LDeleted.Free;
  end;
end;

function TGDEMStore.ImportFrom(const ASourceFolder: string; AReserve: Int64;
  AToken: TCancelToken; const AOnProgress: TStoreProgressEvent): TImportResult;
type
  { One file to import. }
  TImportItem = record
    Source, Dest: string;
    Size: Int64;
  end;
var
  LSource, LSourceDir, LRootDir, LTemp: string;
  LFiles: TArray<string>;
  LItems: TList<TImportItem>;
  LItem: TImportItem;
  LIndex, LSouth, LWest: Integer;
  LNeeded, LFree: Int64;
begin
  Result := Default(TImportResult);
  LSource := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ASourceFolder));
  if not TDirectory.Exists(LSource) then
    raise EStoreError.CreateFmt('The folder %s does not exist.', [LSource]);

  // Copying a folder into itself would never end
  LSourceDir := IncludeTrailingPathDelimiter(LSource);
  LRootDir := IncludeTrailingPathDelimiter(TPath.GetFullPath(FRoot));
  if StartsText(LSourceDir, LRootDir) or StartsText(LRootDir, LSourceDir) then
    raise EStoreError.CreateFmt('The folder to import from (%s) and the data folder ' +
      '(%s) overlap. Choose a folder outside the data folder.', [LSource, FRoot]);

  EnsureCreated;
  Log('Looking for ASTER GDEM tiles in ' + LSource + ' ...');
  LFiles := TDirectory.GetFiles(LSource, '*.tif', TSearchOption.soAllDirectories);

  LItems := TList<TImportItem>.Create;
  try
    // Work out what needs copying and how much space it takes
    LNeeded := 0;
    for LIndex := 0 to High(LFiles) do
    begin
      AToken.Check;
      if not TryParseFileName(LFiles[LIndex], LSouth, LWest) then
      begin
        Inc(Result.Ignored);
        Continue;
      end;
      LItem.Source := LFiles[LIndex];
      LItem.Dest := PathForFile(LFiles[LIndex]);
      LItem.Size := TFile.GetSize(LItem.Source);
      LItems.Add(LItem);
      if not (TFile.Exists(LItem.Dest) and (TFile.GetSize(LItem.Dest) = LItem.Size)) then
        Inc(LNeeded, LItem.Size);
    end;
    Log(Format('  found %d tile file(s); %s to copy', [LItems.Count, FormatByteSize(LNeeded)]));

    LFree := FreeSpace;
    if (LFree >= 0) and (LFree - LNeeded < AReserve) then
      raise EStoreError.CreateFmt('Importing needs about %s, but the data drive has %s ' +
        'free and %s must be kept free. Free some space, choose a larger drive, or ' +
        'lower the reserve in File > Settings.',
        [FormatByteSize(LNeeded), FormatByteSize(LFree), FormatByteSize(AReserve)]);

    for LIndex := 0 to LItems.Count - 1 do
    begin
      AToken.Check;
      LItem := LItems[LIndex];

      if TFile.Exists(LItem.Dest) and (TFile.GetSize(LItem.Dest) = LItem.Size) then
        Inc(Result.AlreadyPresent)
      else if (LItem.Size = 0) or not StartsLikeTIFF(LItem.Source) then
      begin
        Inc(Result.Ignored);
        Log('  skipped ' + LItem.Source + ': not a TIFF file');
      end
      else
      begin
        LFree := FreeSpace;
        if (LFree >= 0) and (LFree - LItem.Size < AReserve) then
          raise EStoreError.CreateFmt('Import stopped: only %s is free on the data drive, ' +
            'and %s must be kept free.', [FormatByteSize(LFree), FormatByteSize(AReserve)]);

        LTemp := LItem.Dest + '.tmp';
        try
          ForceDirectories(TPath.GetDirectoryName(LItem.Dest));
          TFile.Copy(LItem.Source, LTemp, True);
          if TFile.GetSize(LTemp) <> LItem.Size then
            raise EStoreError.Create('the copy is incomplete');
          if TFile.Exists(LItem.Dest) then
          begin
            TFile.Delete(LItem.Dest);
            Inc(Result.Replaced);
          end;
          TFile.Move(LTemp, LItem.Dest);
        except
          on E: Exception do
          begin
            if TFile.Exists(LTemp) then
              TFile.Delete(LTemp);
            PruneEmptyFolders(TPath.GetDirectoryName(LItem.Dest));
            raise EStoreError.CreateFmt('Could not copy %s: %s', [LItem.Source, E.Message]);
          end;
        end;
        Inc(Result.Copied);
        Inc(Result.Bytes, LItem.Size);
      end;

      if (LIndex + 1) mod 250 = 0 then
        Log(Format('  %d of %d file(s) checked, %s copied',
          [LIndex + 1, LItems.Count, FormatByteSize(Result.Bytes)]));
      if Assigned(AOnProgress) then
        AOnProgress(LIndex + 1, LItems.Count);
    end;
  finally
    LItems.Free;
  end;
end;

function TGDEMStore.DataSize(AToken: TCancelToken): Int64;
var
  LFile: string;
begin
  Result := 0;
  for LFile in AllTileFiles do
  begin
    if AToken <> nil then
      AToken.Check;
    Inc(Result, TFile.GetSize(LFile));
  end;
end;

end.
