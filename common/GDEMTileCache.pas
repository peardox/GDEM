{ @abstract(Reads a tile set's tiles as they are needed and keeps the
  recent ones in memory.)

  A @link(TTileCache) opens a tile set (see @code(GDEMTileSet)) and
  decodes its tiles with Skia only when asked, keeping at most a set
  number. When it is full, the tile used longest ago goes. The tile set can
  be a folder, as TileMaker writes it, or packed into one zip file (by
  @code(tools/pack_tiles.py)) read from a stream, such as a resource linked
  into the program. A level can be
  pinned (@link(TTileCache.PreloadLevel)) so it is never dropped: the
  smallest level is a handful of tiles and makes a good stand-in while
  sharper ones load. A tile whose file is missing or cannot be decoded is
  remembered as such, so it is not tried again.

  Tiles are decoded into raster images straight away, so drawing one never
  stalls on decoding. A cache is not thread-safe: use it from one thread,
  normally the one that draws.

  No FMX: only Skia's own units, so any program can use it. }
unit GDEMTileCache;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Zip,
  System.Skia,
  GDEMTileSet;

const
  { Tiles kept unless asked otherwise. A 225-pixel tile takes about
    200 KB decoded, so this is about 80 MB. }
  DEFAULT_TILE_CACHE_CAPACITY = 400;

type
  { @abstract(One tile in a @link(TTileCache).) }
  TTileCacheEntry = record
    { The decoded tile; @nil if its file is missing or unreadable. }
    Image: ISkImage;
    { When it was last used, as a count of uses of the cache. }
    LastUsed: Int64;
    { @true if it must never be dropped. }
    Pinned: Boolean;
  end;

  { @abstract(The tiles of one tile set, decoded as needed and cached.) }
  TTileCache = class
  private
    { Backing field for @link(TileSet). }
    FTileSet: TTileSet;
    { Backing field for @link(Folder). }
    FFolder: string;
    { Backing field for @link(Origin). }
    FOrigin: string;
    { The packed tile set's stream, owned; @nil for a folder. }
    FPackStream: TStream;
    { The packed tile set, read from @link(FPackStream); @nil for a
      folder. }
    FPack: TZipFile;
    { Each entry of @link(FPack) by name, to its position in the zip. }
    FPackIndex: TDictionary<string, Integer>;
    { The tiles tried so far, by @link(Key). }
    FEntries: TDictionary<Int64, TTileCacheEntry>;
    { Most tiles kept, pinned ones not counted. }
    FCapacity: Integer;
    { Counts uses, to tell which tile was used longest ago. }
    FClock: Int64;
    { Tiles kept that are not pinned. }
    FUnpinned: Integer;
    { Backing field for @link(Failures). }
    FFailures: Integer;

    { The dictionary key of a tile.
      @param(ALevel The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(A number unique to the tile.) }
    class function Key(ALevel, ARow, AColumn: Integer): Int64; static;

    { Drops the tile used longest ago that is not pinned. }
    procedure DropOldest;

    { A tile's encoded file, from the folder or the pack.
      @param(ALevel The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(The file's bytes, or @nil if it is missing.) }
    function ReadTile(ALevel, ARow, AColumn: Integer): TBytes;

    { Decodes a tile's file and keeps it.
      @param(ALevel The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @param(APinned @true to keep it for good.)
      @returns(The tile, or @nil if its file is missing or unreadable.) }
    function Decode(ALevel, ARow, AColumn: Integer; APinned: Boolean): ISkImage;
  public
    { Opens a tile set's folder.
      @param(AFolder The folder holding @code(tileset.json).)
      @param(ACapacity Most tiles to keep, besides pinned ones.)
      @raises(ETileSetError if the folder is not a finished, valid tile
        set.) }
    constructor Create(const AFolder: string;
      ACapacity: Integer = DEFAULT_TILE_CACHE_CAPACITY);

    { Opens a packed tile set: a zip holding @code(tileset.json) and the
      tiles under the names @code(TTileSet.TileEntryName) gives.
      @param(AStream The zip; the cache owns it from here on and frees it,
        even if this raises.)
      @param(AOrigin Where the pack came from, for @link(Origin) and error
        messages, such as @code(built into the program).)
      @param(ACapacity Most tiles to keep, besides pinned ones.)
      @raises(ETileSetError if the stream is not a zip holding a valid
        tile set.) }
    constructor CreateFromPack(AStream: TStream; const AOrigin: string;
      ACapacity: Integer = DEFAULT_TILE_CACHE_CAPACITY);

    { Frees the cached tiles. }
    destructor Destroy; override;

    { Whether a tile is a real one: its level, row and column are inside
      the tile set.
      @param(ALevel The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(@true if it exists in the tile set.) }
    function Contains(ALevel, ARow, AColumn: Integer): Boolean;

    { A tile, if it is in memory already; nothing is read.
      @param(ALevel The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(The tile, or @nil if it has not been read or could not
        be.) }
    function Find(ALevel, ARow, AColumn: Integer): ISkImage;

    { Whether a tile has been tried, read or not, so @link(Load) would not
      read its file again.
      @param(ALevel The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(@true if it has been tried.) }
    function Tried(ALevel, ARow, AColumn: Integer): Boolean;

    { A tile, read from its file now if it is not in memory.
      @param(ALevel The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(The tile, or @nil if it is outside the tile set, or its file
        is missing or unreadable.) }
    function Load(ALevel, ARow, AColumn: Integer): ISkImage;

    { Reads every tile of a level and keeps them for good, so there is
      always something to draw. Meant for the smallest level.
      @param(ALevel The level.) }
    procedure PreloadLevel(ALevel: Integer);

    { The tile set's description. }
    property TileSet: TTileSet read FTileSet;

    { The tile set's folder; empty for a packed tile set. }
    property Folder: string read FFolder;

    { Where the tile set came from: its folder, or the description given
      to @link(CreateFromPack). }
    property Origin: string read FOrigin;

    { Tiles whose files were missing or could not be decoded. }
    property Failures: Integer read FFailures;
  end;

implementation

uses
  System.IOUtils, System.Math;

{ TTileCache }

constructor TTileCache.Create(const AFolder: string; ACapacity: Integer);
begin
  inherited Create;
  FTileSet := TTileSet.Load(AFolder);
  FFolder := AFolder;
  FOrigin := AFolder;
  FCapacity := Max(ACapacity, 16);
  FEntries := TDictionary<Int64, TTileCacheEntry>.Create;
end;

constructor TTileCache.CreateFromPack(AStream: TStream; const AOrigin: string;
  ACapacity: Integer);
var
  I, LIndex: Integer;
  LBytes: TBytes;
begin
  inherited Create;
  // Kept first, so the destructor frees it if anything below raises
  FPackStream := AStream;
  FOrigin := AOrigin;
  FCapacity := Max(ACapacity, 16);
  FEntries := TDictionary<Int64, TTileCacheEntry>.Create;
  FPackIndex := TDictionary<string, Integer>.Create;
  FPack := TZipFile.Create;
  try
    FPack.Open(FPackStream, zmRead);
  except
    on E: Exception do
      raise ETileSetError.CreateFmt('The tile set %s is not a readable zip: %s',
        [AOrigin, E.Message]);
  end;
  // TZipFile looks names up one by one; a dictionary is quicker for 1500
  for I := 0 to FPack.FileCount - 1 do
    FPackIndex.AddOrSetValue(FPack.FileName[I], I);
  if not FPackIndex.TryGetValue(TILESET_FILE_NAME, LIndex) then
    raise ETileSetError.CreateFmt('The tile set %s has no %s.', [AOrigin, TILESET_FILE_NAME]);
  FPack.Read(LIndex, LBytes);
  FTileSet := TTileSet.FromJSON(TEncoding.UTF8.GetString(LBytes),
    TILESET_FILE_NAME + ' in ' + AOrigin);
end;

destructor TTileCache.Destroy;
begin
  FEntries.Free;
  FPackIndex.Free;
  FPack.Free;
  FPackStream.Free;
  inherited;
end;

class function TTileCache.Key(ALevel, ARow, AColumn: Integer): Int64;
begin
  // Rows and columns stay well under a million in any sensible tile set
  Result := (Int64(ALevel) shl 40) or (Int64(ARow) shl 20) or Int64(AColumn);
end;

function TTileCache.Contains(ALevel, ARow, AColumn: Integer): Boolean;
begin
  Result := InRange(ALevel, 0, High(FTileSet.Levels)) and
    InRange(ARow, 0, FTileSet.Levels[ALevel].Rows - 1) and
    InRange(AColumn, 0, FTileSet.Levels[ALevel].Columns - 1);
end;

function TTileCache.Find(ALevel, ARow, AColumn: Integer): ISkImage;
var
  LKey: Int64;
  LEntry: TTileCacheEntry;
begin
  Result := nil;
  LKey := Key(ALevel, ARow, AColumn);
  if not FEntries.TryGetValue(LKey, LEntry) then
    Exit;
  Inc(FClock);
  LEntry.LastUsed := FClock;
  FEntries[LKey] := LEntry;
  Result := LEntry.Image;
end;

function TTileCache.Tried(ALevel, ARow, AColumn: Integer): Boolean;
begin
  Result := FEntries.ContainsKey(Key(ALevel, ARow, AColumn));
end;

procedure TTileCache.DropOldest;
var
  LPair: TPair<Int64, TTileCacheEntry>;
  LOldestKey, LOldest: Int64;
begin
  LOldest := High(Int64);
  LOldestKey := -1;
  // A few hundred entries, so a scan is quick enough
  for LPair in FEntries do
    if not LPair.Value.Pinned and (LPair.Value.LastUsed < LOldest) then
    begin
      LOldest := LPair.Value.LastUsed;
      LOldestKey := LPair.Key;
    end;
  if LOldestKey >= 0 then
  begin
    FEntries.Remove(LOldestKey);
    Dec(FUnpinned);
  end;
end;

function TTileCache.ReadTile(ALevel, ARow, AColumn: Integer): TBytes;
var
  LFileName: string;
  LIndex: Integer;
begin
  Result := nil;
  if FPack <> nil then
  begin
    if FPackIndex.TryGetValue(FTileSet.TileEntryName(ALevel, ARow, AColumn), LIndex) then
      FPack.Read(LIndex, Result);
  end
  else
  begin
    LFileName := TPath.Combine(FFolder, FTileSet.TileFileName(ALevel, ARow, AColumn));
    if TFile.Exists(LFileName) then
      Result := TFile.ReadAllBytes(LFileName);
  end;
end;

function TTileCache.Decode(ALevel, ARow, AColumn: Integer; APinned: Boolean): ISkImage;
var
  LEntry: TTileCacheEntry;
  LBytes: TBytes;
  LEncoded: ISkImage;
begin
  Result := nil;
  try
    LBytes := ReadTile(ALevel, ARow, AColumn);
    if Length(LBytes) > 0 then
    begin
      LEncoded := TSkImage.MakeFromEncoded(LBytes);
      // Decoded now, so drawing it never has to
      if LEncoded <> nil then
        Result := LEncoded.MakeRasterImage;
    end;
  except
    Result := nil;
  end;
  if Result = nil then
    Inc(FFailures);

  if not APinned then
  begin
    while FUnpinned >= FCapacity do
      DropOldest;
    Inc(FUnpinned);
  end;
  Inc(FClock);
  LEntry.Image := Result;
  LEntry.LastUsed := FClock;
  LEntry.Pinned := APinned;
  FEntries.AddOrSetValue(Key(ALevel, ARow, AColumn), LEntry);
end;

function TTileCache.Load(ALevel, ARow, AColumn: Integer): ISkImage;
begin
  if not Contains(ALevel, ARow, AColumn) then
    Exit(nil);
  if Tried(ALevel, ARow, AColumn) then
    Exit(Find(ALevel, ARow, AColumn));
  Result := Decode(ALevel, ARow, AColumn, False);
end;

procedure TTileCache.PreloadLevel(ALevel: Integer);
var
  LRow, LColumn: Integer;
begin
  if not InRange(ALevel, 0, High(FTileSet.Levels)) then
    Exit;
  for LRow := 0 to FTileSet.Levels[ALevel].Rows - 1 do
    for LColumn := 0 to FTileSet.Levels[ALevel].Columns - 1 do
      if not Tried(ALevel, LRow, LColumn) then
        Decode(ALevel, LRow, LColumn, True);
end;

end.
