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
  { Space kept free when a drive's size cannot be found out, as the old
    fixed reserve was: 2 GB. }
  FALLBACK_RESERVE_BYTES = Int64(2) * 1024 * 1024 * 1024;
  { Most files @link(TGDEMStore.ImportFrom) copies at once. The default,
    1, is @code(DEFAULT_IMPORT_WORKERS) in @code(GDEMSettings). }
  MAX_IMPORT_WORKERS = 16;
  { How many times @link(TGDEMStore.ImportFrom) tries each file before
    skipping it. }
  IMPORT_ATTEMPTS = 3;
  { Pause after a failed try, in milliseconds, multiplied by the number of
    tries so far. }
  IMPORT_RETRY_DELAY_MS = 1000;
  { Once this many files have been skipped, the import stops: something is
    badly wrong. }
  MAX_IMPORT_FAILURES = 20;

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
    { Files skipped because they could not be copied, even after
      @link(IMPORT_ATTEMPTS) tries. Each is listed in the log; running the
      import again tries them again. }
    Failed: Integer;
    { When moving: source files deleted, because they were copied or the
      store already had them at the same size. Always 0 when copying. }
    SourcesDeleted: Integer;
    { When moving: source files that were safely in the store but could
      not be deleted from the source (read-only, say). Each is listed in
      the log. Always 0 when copying. }
    SourcesKept: Integer;
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

  { @abstract(Where an import has got to.) }
  TImportProgress = record
    { Files dealt with so far, copied or skipped. }
    FilesDone: Integer;
    { Tile files found in the source. }
    FilesTotal: Integer;
    { Bytes copied so far. }
    BytesCopied: Int64;
    { Bytes that need copying in all, leaving out files the store already
      has. }
    BytesToCopy: Int64;
    { Name, without its folder, of the file about to be copied or just
      dealt with; empty once the import is finished. }
    CurrentFile: string;
  end;

  { Reports progress through an import. Called before each file is copied
    and after each file is dealt with.
    @param(AProgress Where the import has got to.) }
  TImportProgressEvent = reference to procedure(const AProgress: TImportProgress);

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

    { Size of the drive holding a path, used and free together. The path
      need not exist; its nearest existing parent is checked.
      @param(APath Any path.)
      @returns(Bytes, or -1 if it cannot be found out.) }
    class function DriveSizeAt(const APath: string): Int64; static;

    { How much space must be left free on the drive holding a path: a
      percentage of the drive's size, so the reserve suits the drive. SSDs
      in particular slow down and wear faster when nearly full.
      @param(APath Any path on the drive.)
      @param(APercent The percentage of the drive to keep free; kept to
        @link(MIN_RESERVE_PERCENT) to @link(MAX_RESERVE_PERCENT).)
      @returns(Bytes to leave free; @link(FALLBACK_RESERVE_BYTES) if the
        drive's size cannot be found out.) }
    class function ReserveAt(const APath: string; APercent: Integer): Int64; static;

    { How much space must be left free on the drive holding the root; see
      @link(ReserveAt).
      @param(APercent The percentage of the drive to keep free.)
      @returns(Bytes to leave free.) }
    function Reserve(APercent: Integer): Int64;

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
      folders inside it, into this store's block layout. Unless AMoveSource
      is set, the source is opened for reading only and nothing in it is
      changed, moved or deleted.

      With AMoveSource set, the files are moved instead: each source file
      is deleted once its copy is in the store, complete and under its
      real name, and so is each source file the store already has at the
      same size. Files that are not tile files, and files that fail, are
      left where they are. Folders inside the source left empty are
      removed; the source folder itself is kept. When the source is on the
      same drive as the store, moving needs no extra space overall, so the
      check of the total space needed is skipped; the check before each
      file still applies.

      Files the store already has, at the same size, are skipped, so an
      interrupted import can simply be run again. Each file is copied under
      a temporary name, its size checked, and only then renamed, so a
      cancelled or failed import never leaves a partial tile behind.

      Several files are copied at once, by AWorkers threads taking files
      from a shared list. Copying one file at a time leaves fast drives
      idle while each file is opened, flushed, checked and renamed (and, on
      Windows, often scanned for viruses); overlapping files hides that.
      Use 1 for a spinning hard disk, where several files at once make the
      heads jump between them.

      A file that cannot be copied is tried @link(IMPORT_ATTEMPTS) times,
      which rides out brief problems such as a virus scanner holding the new
      file or a drive resetting for a moment. If it still fails it is
      logged, counted in @link(TImportResult.Failed) and skipped, and the
      import carries on. Only these stop the whole import: free space
      falling below AReserve, the data folder disappearing (a removable
      drive unplugged), or @link(MAX_IMPORT_FAILURES) files failing.

      Before copying, the space needed is worked out; the import does not
      start if it would leave less than AReserve free, and it stops if free
      space falls below AReserve along the way.

      @param(ASourceFolder The folder to import from. It must not be inside
        the store, nor contain it.)
      @param(AReserve Bytes that must be left free on the store's drive.)
      @param(AWorkers How many files to copy at once, from 1 to
        @link(MAX_IMPORT_WORKERS).)
      @param(AToken Checked between files.)
      @param(AOnProgress Called before each file is copied and after each
        file is dealt with, from the worker threads, possibly from several
        at once. May be @nil.)
      @param(AMoveSource @true to delete each source file once it is safely
        in the store: a move rather than a copy.)
      @returns(What was copied, skipped and, when moving, deleted.)
      @raises(EStoreError if the folders overlap, space is short, the data
        folder disappears, or too many files cannot be copied.)
      @raises(EOperationCancelled if AToken is cancelled.) }
    function ImportFrom(const ASourceFolder: string; AReserve: Int64;
      AWorkers: Integer; AToken: TCancelToken;
      const AOnProgress: TImportProgressEvent; AMoveSource: Boolean = False): TImportResult;

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

{ Formats a time for display, such as @code(1 h 46 min), @code(3 min 5 s)
  or @code(38 s).
  @param(ASeconds The time, in seconds.)
  @returns(The formatted time, rounded to the second.) }
function FormatDuration(ASeconds: Double): string;

implementation

uses
  System.IOUtils, System.Types, System.Math, System.StrUtils,
  System.Generics.Collections, System.RegularExpressions, System.SyncObjs,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  {$IFDEF POSIX}
  Posix.SysStatvfs, Posix.SysStat,
  {$ENDIF}
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON,
  GDEMSettings;

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

function FormatDuration(ASeconds: Double): string;
var
  LSeconds, LMinutes, LHours: Int64;
begin
  LSeconds := Round(ASeconds);
  LHours := LSeconds div 3600;
  LMinutes := (LSeconds mod 3600) div 60;
  if LHours > 0 then
    Result := Format('%d h %d min', [LHours, LMinutes])
  else if LMinutes > 0 then
    Result := Format('%d min %d s', [LMinutes, LSeconds mod 60])
  else
    Result := Format('%d s', [LSeconds]);
end;

{ Checks whether two paths are on the same drive (volume), so a move
  between them needs no extra space. Both paths must exist.
  @param(APath1 A path.)
  @param(APath2 Another path.)
  @returns(@true if they are on the same drive; @false if they are not, or
    it cannot be found out.) }
function SameDrive(const APath1, APath2: string): Boolean;
{$IFDEF MSWINDOWS}
var
  LVolume1, LVolume2: array[0..MAX_PATH] of Char;
begin
  Result := False;
  if not GetVolumePathName(PChar(APath1), LVolume1, Length(LVolume1)) then
    Exit;
  if not GetVolumePathName(PChar(APath2), LVolume2, Length(LVolume2)) then
    Exit;
  Result := SameText(string(PChar(@LVolume1[0])), string(PChar(@LVolume2[0])));
end;
{$ELSE}
var
  LStat1, LStat2: _stat;
begin
  Result := (stat(PAnsiChar(UTF8String(APath1)), LStat1) = 0) and
    (stat(PAnsiChar(UTF8String(APath2)), LStat2) = 0) and
    (LStat1.st_dev = LStat2.st_dev);
end;
{$ENDIF}

{ Removes a folder if it is empty, then each parent that becomes empty, up
  to but not including a top folder. Errors are ignored: a folder that
  cannot be removed is simply left.
  @param(AFolder The folder to start from.)
  @param(ATop The folder to stop at, which is never removed.) }
procedure RemoveEmptyFoldersUpTo(const AFolder, ATop: string);
var
  LFolder, LTop: string;
begin
  LFolder := NormalizeFolder(AFolder);
  LTop := NormalizeFolder(ATop);
  while (LFolder <> '') and not SameText(LFolder, LTop) and
        StartsText(IncludeTrailingPathDelimiter(LTop), LFolder) do
  begin
    try
      if not TDirectory.IsEmpty(LFolder) then
        Exit;
      TDirectory.Delete(LFolder);
    except
      Exit;
    end;
    LFolder := NormalizeFolder(TPath.GetDirectoryName(LFolder));
  end;
end;

type
  { One file for @link(TGDEMStore.ImportFrom) to copy. }
  TImportItem = record
    { Where the file is now. }
    Source: string;
    { Where it goes in the store. }
    Dest: string;
    { Its size in bytes. }
    Size: Int64;
  end;

  { Passes import progress on; see @link(TGDEMStore.ImportFrom).
    @param(AFilesDone Files dealt with so far.)
    @param(ACurrentFile The file about to be copied or just dealt with.) }
  TImportReportProc = reference to procedure(AFilesDone: Integer;
    const ACurrentFile: string);

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
  // Keeps a drive root as F:\ rather than F:, which means something else
  FRoot := NormalizeFolder(ARoot);
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

{ Measures the drive holding a path. The path need not exist; its nearest
  existing parent is measured.
  @param(APath Any path.)
  @param(AFree Receives the bytes free for the current user.)
  @param(ASize Receives the size of the drive, in bytes.)
  @returns(@false if the drive could not be measured, in which case AFree
    and ASize are -1.) }
function MeasureDrive(const APath: string; out AFree, ASize: Int64): Boolean;
var
  LPath: string;
  {$IFDEF MSWINDOWS}
  LFree, LTotal: Int64;
  {$ENDIF}
  {$IFDEF POSIX}
  LStat: _statvfs;
  {$ENDIF}
begin
  Result := False;
  AFree := -1;
  ASize := -1;
  // Walk up to the nearest folder that exists
  LPath := NormalizeFolder(APath);
  while (LPath <> '') and not TDirectory.Exists(LPath) do
  begin
    if NormalizeFolder(TPath.GetDirectoryName(LPath)) = LPath then
      Exit;
    LPath := NormalizeFolder(TPath.GetDirectoryName(LPath));
  end;
  if LPath = '' then
    Exit;

  {$IFDEF MSWINDOWS}
  if GetDiskFreeSpaceEx(PChar(IncludeTrailingPathDelimiter(LPath)), LFree, LTotal, nil) then
  begin
    AFree := LFree;
    ASize := LTotal;
    Result := True;
  end;
  {$ENDIF}
  {$IFDEF POSIX}
  if statvfs(PAnsiChar(UTF8String(LPath)), LStat) = 0 then
  begin
    AFree := Int64(LStat.f_bavail) * Int64(LStat.f_frsize);
    ASize := Int64(LStat.f_blocks) * Int64(LStat.f_frsize);
    Result := True;
  end;
  {$ENDIF}
end;

class function TGDEMStore.FreeSpaceAt(const APath: string): Int64;
var
  LSize: Int64;
begin
  MeasureDrive(APath, Result, LSize);
end;

class function TGDEMStore.DriveSizeAt(const APath: string): Int64;
var
  LFree: Int64;
begin
  MeasureDrive(APath, LFree, Result);
end;

class function TGDEMStore.ReserveAt(const APath: string; APercent: Integer): Int64;
var
  LSize: Int64;
begin
  LSize := DriveSizeAt(APath);
  if LSize <= 0 then
    Exit(FALLBACK_RESERVE_BYTES);
  Result := LSize div 100 * EnsureRange(APercent, MIN_RESERVE_PERCENT, MAX_RESERVE_PERCENT);
end;

function TGDEMStore.Reserve(APercent: Integer): Int64;
begin
  Result := ReserveAt(FRoot, APercent);
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
  AWorkers: Integer; AToken: TCancelToken;
  const AOnProgress: TImportProgressEvent; AMoveSource: Boolean): TImportResult;
var
  LSource, LSourceDir, LRootDir: string;
  LFiles: TArray<string>;
  LPresentSources: TList<string>;
  LMove, LSameDrive: Boolean;
  LDeleted, LKept: Integer;
  LSourceFolders: TList<string>;
  LTodo: TList<TImportItem>;
  LItem: TImportItem;
  LIndex, LSouth, LWest, LTotal, LPresent, LIgnored, LWorkerCount: Integer;
  LNeeded, LFree, LReserve: Int64;
  LToken: TCancelToken;
  LOnProgress: TImportProgressEvent;
  // Shared by the workers; counters change only through TInterlocked
  LNext, LDone, LCopied, LReplaced, LIgnoredCopy, LFailedCount: Integer;
  LCopiedBytes: Int64;
  LError: string;
  LStop: Boolean;
  LLock: TObject;
  LFailedFolders: TList<string>;
  LReport: TImportReportProc;
  LWorker: TProc;
  LThreads: TArray<TThread>;
  LFolder: string;
begin
  Result := Default(TImportResult);
  // Parameters are copied so the workers' anonymous methods can use them
  LToken := AToken;
  LOnProgress := AOnProgress;
  LReserve := AReserve;
  LWorkerCount := EnsureRange(AWorkers, 1, MAX_IMPORT_WORKERS);
  LMove := AMoveSource;

  LSource := NormalizeFolder(TPath.GetFullPath(NormalizeFolder(ASourceFolder)));
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

  LTodo := TList<TImportItem>.Create;
  LFailedFolders := TList<string>.Create;
  LSourceFolders := TList<string>.Create;
  LPresentSources := TList<string>.Create;
  LLock := TObject.Create;
  try
    // Work out what needs copying and how much space it takes. Files the
    // store already has are counted now, so the workers only see real work.
    LTotal := 0;
    LPresent := 0;
    LIgnored := 0;
    LNeeded := 0;
    for LIndex := 0 to High(LFiles) do
    begin
      LToken.Check;
      if not TryParseFileName(LFiles[LIndex], LSouth, LWest) then
      begin
        Inc(LIgnored);
        Continue;
      end;
      Inc(LTotal);
      LItem.Source := LFiles[LIndex];
      LItem.Dest := PathForFile(LFiles[LIndex]);
      LItem.Size := TFile.GetSize(LItem.Source);
      if TFile.Exists(LItem.Dest) and (TFile.GetSize(LItem.Dest) = LItem.Size) then
      begin
        Inc(LPresent);
        LPresentSources.Add(LItem.Source);
      end
      else
      begin
        LTodo.Add(LItem);
        Inc(LNeeded, LItem.Size);
      end;
    end;
    Log(Format('  found %d tile file(s): %d already in the data folder, %d to copy (%s), ' +
      '%d at a time', [LTotal, LPresent, LTodo.Count, FormatByteSize(LNeeded), LWorkerCount]));

    // Moving within one drive frees each file's space as the next is used,
    // so only the check before each file matters
    LSameDrive := LMove and SameDrive(LSource, FRoot);
    if LSameDrive then
      Log('  moving within the same drive: no extra space is needed overall');
    LFree := FreeSpace;
    if not LSameDrive and (LFree >= 0) and (LFree - LNeeded < LReserve) then
      raise EStoreError.CreateFmt('Importing needs about %s, but the data drive has %s ' +
        'free and %s must be kept free. Free some space, choose a larger drive, or ' +
        'lower the reserve in File > Settings.',
        [FormatByteSize(LNeeded), FormatByteSize(LFree), FormatByteSize(LReserve)]);

    // Moving: the store already has these, the same size, so their source
    // files can go
    LDeleted := 0;
    LKept := 0;
    if LMove then
      for LIndex := 0 to LPresentSources.Count - 1 do
      begin
        LToken.Check;
        try
          TFile.Delete(LPresentSources[LIndex]);
          Inc(LDeleted);
          if not LSourceFolders.Contains(TPath.GetDirectoryName(LPresentSources[LIndex])) then
            LSourceFolders.Add(TPath.GetDirectoryName(LPresentSources[LIndex]));
        except
          on E: Exception do
          begin
            Inc(LKept);
            Log(Format('  WARNING: %s is already in the data folder but could not be ' +
              'deleted: %s', [LPresentSources[LIndex], E.Message.TrimRight(['.'])]));
          end;
        end;
      end;
    if LMove and (LDeleted > 0) then
      Log(Format('  deleted %d source file(s) the data folder already had', [LDeleted]));

    LNext := -1;
    LDone := LPresent;
    LCopied := 0;
    LReplaced := 0;
    LIgnoredCopy := 0;
    LFailedCount := 0;
    LCopiedBytes := 0;
    LError := '';
    LStop := False;

    LReport :=
      procedure(AFilesDone: Integer; const ACurrentFile: string)
      var
        LProgress: TImportProgress;
      begin
        if not Assigned(LOnProgress) then
          Exit;
        LProgress.FilesDone := AFilesDone;
        LProgress.FilesTotal := LTotal;
        LProgress.BytesCopied := TInterlocked.Read(LCopiedBytes);
        LProgress.BytesToCopy := LNeeded;
        LProgress.CurrentFile := ACurrentFile;
        LOnProgress(LProgress);
      end;
    LReport(LDone, '');

    // Each worker takes the next file from the list until none are left,
    // the import is cancelled, or another worker has failed
    LWorker :=
      procedure
      var
        LIdx, LCount, LAttempt, LFailures: Integer;
        LJob: TImportItem;
        LTempName, LDestDir, LMessage: string;
        LSpace: Int64;
        LWasThere, LCopiedOk, LFatal: Boolean;
      begin
        while not LStop and not LToken.Cancelled do
        begin
          LIdx := TInterlocked.Increment(LNext);
          if LIdx >= LTodo.Count then
            Exit;
          LJob := LTodo[LIdx];
          LTempName := LJob.Dest + '.tmp';
          LDestDir := TPath.GetDirectoryName(LJob.Dest);
          LMessage := '';
          LFatal := False;

          if (LJob.Size = 0) or not StartsLikeTIFF(LJob.Source) then
          begin
            TInterlocked.Increment(LIgnoredCopy);
            Log('  skipped ' + LJob.Source + ': not a TIFF file');
          end
          else if not TDirectory.Exists(FRoot) then
          begin
            LFatal := True;
            LMessage := Format('Import stopped: the data folder %s is no longer ' +
              'available. If it is on a removable drive, check that it is still ' +
              'connected, then run the import again.', [FRoot]);
          end
          else
          begin
            // Every worker may be about to write a file of about this size
            LSpace := FreeSpace;
            if (LSpace >= 0) and (LSpace - LJob.Size * LWorkerCount < LReserve) then
            begin
              LFatal := True;
              LMessage := Format('Import stopped: only %s is free on the data drive, ' +
                'and %s must be kept free.', [FormatByteSize(LSpace), FormatByteSize(LReserve)]);
            end
            else
            begin
              LReport(LDone, ExtractFileName(LJob.Source));
              // A brief failure, such as a virus scanner still holding the
              // new file, or a drive resetting for a moment, is tried again
              LCopiedOk := False;
              for LAttempt := 1 to IMPORT_ATTEMPTS do
              begin
                if LToken.Cancelled then
                  Break;
                try
                  // A tile's two files sit next to each other in the list,
                  // so two workers often need a new block folder at the same
                  // moment. ForceDirectories is not safe for that: when
                  // another thread wins the race for the parent it gives up
                  // without making the child. Folders are therefore made
                  // one worker at a time.
                  TMonitor.Enter(LLock);
                  try
                    if not TDirectory.Exists(LDestDir) then
                      ForceDirectories(LDestDir);
                  finally
                    TMonitor.Exit(LLock);
                  end;
                  if not TDirectory.Exists(LDestDir) then
                    raise Exception.Create('the folder ' + LDestDir + ' could not be created');
                  TFile.Copy(LJob.Source, LTempName, True);
                  if TFile.GetSize(LTempName) <> LJob.Size then
                    raise Exception.Create('the copy is incomplete');
                  LWasThere := TFile.Exists(LJob.Dest);
                  if LWasThere then
                    TFile.Delete(LJob.Dest);
                  TFile.Move(LTempName, LJob.Dest);
                  if LWasThere then
                    TInterlocked.Increment(LReplaced);
                  TInterlocked.Increment(LCopied);
                  TInterlocked.Add(LCopiedBytes, LJob.Size);
                  LCopiedOk := True;
                  Break;
                except
                  on E: Exception do
                  begin
                    LMessage := E.Message;
                    try
                      if TFile.Exists(LTempName) then
                        TFile.Delete(LTempName);
                    except
                      // A rescan removes it later
                    end;
                    if LAttempt < IMPORT_ATTEMPTS then
                      Sleep(IMPORT_RETRY_DELAY_MS * LAttempt);
                  end;
                end;
              end;

              // Moving: the copy is complete and under its real name, so
              // the source can go. Failing to delete it loses nothing.
              if LCopiedOk and LMove then
              begin
                try
                  TFile.Delete(LJob.Source);
                  TInterlocked.Increment(LDeleted);
                  TMonitor.Enter(LLock);
                  try
                    if not LSourceFolders.Contains(TPath.GetDirectoryName(LJob.Source)) then
                      LSourceFolders.Add(TPath.GetDirectoryName(LJob.Source));
                  finally
                    TMonitor.Exit(LLock);
                  end;
                except
                  on E: Exception do
                  begin
                    TInterlocked.Increment(LKept);
                    Log(Format('  WARNING: copied %s but could not delete it: %s',
                      [LJob.Source, E.Message.TrimRight(['.'])]));
                  end;
                end;
              end;

              if not LCopiedOk and not LToken.Cancelled then
              begin
                if not TDirectory.Exists(FRoot) then
                begin
                  // The drive went while this file was being tried
                  LFatal := True;
                  LMessage := Format('Import stopped: the data folder %s is no ' +
                    'longer available. If it is on a removable drive, check that it ' +
                    'is still connected, then run the import again.', [FRoot]);
                end
                else
                begin
                  // Skip it and carry on; running the import again retries it
                  LFailures := TInterlocked.Increment(LFailedCount);
                  Log(Format('  FAILED to copy %s after %d tries: %s',
                    [LJob.Source, IMPORT_ATTEMPTS, LMessage]));
                  TMonitor.Enter(LLock);
                  try
                    if not LFailedFolders.Contains(LDestDir) then
                      LFailedFolders.Add(LDestDir);
                  finally
                    TMonitor.Exit(LLock);
                  end;
                  if LFailures >= MAX_IMPORT_FAILURES then
                  begin
                    LFatal := True;
                    LMessage := Format('Import stopped after %d files could not be ' +
                      'copied; the last failed with: %s. The Debug tab lists them.',
                      [LFailures, LMessage.TrimRight(['.'])]);
                  end;
                end;
              end;
            end;
          end;

          if LFatal then
          begin
            TMonitor.Enter(LLock);
            try
              // The first fatal problem is the one reported
              if LError = '' then
                LError := LMessage;
              LStop := True;
              if not LFailedFolders.Contains(LDestDir) then
                LFailedFolders.Add(LDestDir);
            finally
              TMonitor.Exit(LLock);
            end;
            Exit;
          end;
          if LToken.Cancelled then
            Exit;

          LCount := TInterlocked.Increment(LDone);
          if LCount mod 250 = 0 then
            Log(Format('  %d of %d file(s) done, %s copied',
              [LCount, LTotal, FormatByteSize(TInterlocked.Read(LCopiedBytes))]));
          LReport(LCount, ExtractFileName(LJob.Source));
        end;
      end;

    // Plain threads rather than the task pool, as this already runs on a
    // pool thread and must wait for the workers
    SetLength(LThreads, Min(LWorkerCount, Max(1, LTodo.Count)));
    for LIndex := 0 to High(LThreads) do
    begin
      LThreads[LIndex] := TThread.CreateAnonymousThread(LWorker);
      LThreads[LIndex].FreeOnTerminate := False;
    end;
    try
      for LIndex := 0 to High(LThreads) do
        LThreads[LIndex].Start;
      for LIndex := 0 to High(LThreads) do
        LThreads[LIndex].WaitFor;
    finally
      for LIndex := 0 to High(LThreads) do
        LThreads[LIndex].Free;
    end;

    // Only now that no worker is writing can empty folders be removed
    for LFolder in LFailedFolders do
      PruneEmptyFolders(LFolder);
    // Moving: folders inside the source that are now empty go too, but
    // never the source folder itself
    for LFolder in LSourceFolders do
      RemoveEmptyFoldersUpTo(LFolder, LSource);

    Result.Copied := LCopied;
    Result.AlreadyPresent := LPresent;
    Result.Replaced := LReplaced;
    Result.Ignored := LIgnored + LIgnoredCopy;
    Result.Bytes := LCopiedBytes;
    Result.Failed := LFailedCount;
    Result.SourcesDeleted := LDeleted;
    Result.SourcesKept := LKept;

    if LError <> '' then
      raise EStoreError.Create(LError);
    LToken.Check;
    LReport(LTotal, '');
  finally
    LLock.Free;
    LPresentSources.Free;
    LSourceFolders.Free;
    LFailedFolders.Free;
    LTodo.Free;
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
