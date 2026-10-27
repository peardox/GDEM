{ @abstract(A bitmap of which ASTER GDEM V3 tiles exist.)

  The world is 360 by 180 one-degree tiles, but only about 23,000 of the
  64,800 contain ASTER GDEM data. @link(TTileIndex) records which ones with
  one bit per tile: 8,100 bytes for the whole world.

  @link(TTileIndexBuilder) fills an index by listing every granule in the
  ASTGTM collection from NASA CMR. CMR is public, so no bearer token is
  needed. It takes about a dozen requests of up to 2,000 granules each.

  The collection's final version was released in 2019 and is not expected
  to change, so an index is built once and saved with
  @link(TTileIndex.SaveToFile). The default location is
  @code(tileindex.bin) in the settings folder; see
  @link(TTileIndex.DefaultFileName).

  @bold(File format.) All numbers are little-endian.
  @table(
    @rowHead(@cell(Offset) @cell(Size) @cell(Contents))
    @row(@cell(0) @cell(4) @cell(The ASCII characters @code(GDTI).))
    @row(@cell(4) @cell(2) @cell(Format version, currently 1.))
    @row(@cell(6) @cell(2) @cell(Width in tiles, 360.))
    @row(@cell(8) @cell(2) @cell(Height in tiles, 180.))
    @row(@cell(10) @cell(4) @cell(Number of tiles that exist.))
    @row(@cell(14) @cell(8100) @cell(The bits.))
  )
  Tile (south, west) is bit number @code((south + 90) * 360 + (west + 180)),
  counting from the least significant bit of the first byte. So the first
  bit is the tile at 90 south, 180 west, and each row of 360 bits runs west
  to east. }
unit GDEMTileIndex;

interface

uses
  System.SysUtils, System.Classes, System.Net.HttpClient, System.Net.URLClient,
  GDEMTiles;

const
  { Tiles across the world. }
  TILE_INDEX_WIDTH = 360;
  { Tiles from pole to pole. }
  TILE_INDEX_HEIGHT = 180;
  { Bytes needed for one bit per tile. }
  TILE_INDEX_BYTES = TILE_INDEX_WIDTH * TILE_INDEX_HEIGHT div 8;
  { Current version of the file format. }
  TILE_INDEX_VERSION = 1;
  { Name of the index file inside the settings folder. }
  TILE_INDEX_FILE_NAME = 'tileindex.bin';

type
  { @abstract(Raised when an index file cannot be read or written, or an
    index cannot be built.) }
  ETileIndexError = class(Exception);

  { @abstract(Raised when @link(TTileIndexBuilder.Cancel) stops a build.) }
  ETileIndexCancelled = class(ETileIndexError);

  { @abstract(One bit for each of the world's 64,800 one-degree tiles.)

    A set bit means ASTER GDEM has data for that tile. An index is not
    thread-safe: fill it on one thread, then only read it. }
  TTileIndex = class
  private
    { The bits; see the unit description for the layout. }
    FBits: array[0..TILE_INDEX_BYTES - 1] of Byte;
    { Number of set bits, kept up to date as bits are set. }
    FCount: Integer;

    { Position of a tile's bit.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge. Values outside
        -180 to 179 are wrapped round, so blocks that cross the 180 degree
        meridian can be looked up directly.)
      @param(AIndex Receives the bit number.)
      @returns(@false if the tile is outside the world.) }
    class function BitIndex(ASouth, AWest: Integer; out AIndex: Integer): Boolean; static;

    { Counts the set bits from scratch.
      @returns(The number of tiles that exist.) }
    function CountBits: Integer;
  public
    { Default location of the index file: @code(tileindex.bin) in the
      settings folder used by @link(TGDEMSettings).
      @returns(Full path of the file.) }
    class function DefaultFileName: string; static;

    { Marks every tile as having no data. }
    procedure Clear;

    { Copies another index into this one.
      @param(ASource The index to copy.) }
    procedure Assign(ASource: TTileIndex);

    { Marks every tile that has data in another index as having data in
      this one too, keeping those it already has: the union of the two.
      @param(ASource The index to add.) }
    procedure AddIndex(ASource: TTileIndex);

    { Marks a tile as having data. Tiles outside the world are ignored.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.) }
    procedure Add(ASouth, AWest: Integer);

    { Marks a tile as having no data. Tiles outside the world are ignored.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.) }
    procedure Remove(ASouth, AWest: Integer);

    { Checks whether a tile has data.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.)
      @returns(@true if the tile has data; @false if it has none or is
        outside the world.) }
    function Has(ASouth, AWest: Integer): Boolean;

    { Counts the tiles with data in a block.
      @param(ARect The block of tiles.)
      @returns(The number of tiles with data.) }
    function CountIn(const ARect: TTileRect): Integer;

    { Names the tiles with data in a block, north-west first, row by row.
      @param(ARect The block of tiles.)
      @returns(Tile names such as @code(N50W002).) }
    function TileNamesIn(const ARect: TTileRect): TArray<string>;

    { The smallest block of tiles holding every tile in the index. Across
      longitudes it takes the shorter way round the world, so tiles on both
      sides of the 180 degree meridian (Russia, Fiji) give a block that
      crosses it rather than one spanning the whole world.
      @returns(The block, or @code(TTileRect.Empty) if the index is empty.) }
    function BoundingRect: TTileRect;

    { Checks whether the index holds no tiles at all, which means it has
      not been loaded or built.
      @returns(@true if no tile has data.) }
    function IsEmpty: Boolean;

    { Writes the index in the format described for this unit.
      @param(AStream Stream to write to.) }
    procedure SaveToStream(AStream: TStream);

    { Reads an index written by @link(SaveToStream).
      @param(AStream Stream positioned at the start of the index.)
      @raises(ETileIndexError if the data is not a valid index.) }
    procedure LoadFromStream(AStream: TStream);

    { Writes the index to a file, creating its folder if needed. The file
      is written under a temporary name first and then renamed.
      @param(AFileName Path of the file.)
      @raises(ETileIndexError if the file cannot be written.) }
    procedure SaveToFile(const AFileName: string);

    { Reads an index file.
      @param(AFileName Path of the file.)
      @returns(@true if the file existed and was read; @false if it does
        not exist, in which case the index is unchanged.)
      @raises(ETileIndexError if the file exists but is not a valid
        index.) }
    function LoadFromFile(const AFileName: string): Boolean;

    { Number of tiles with data. }
    property Count: Integer read FCount;
  end;

  { Reports progress while an index is built.
    @param(APage Number of pages received so far.)
    @param(APages Expected total number of pages, or 0 if not yet known.)
    @param(ATiles Number of tiles found so far.) }
  TTileIndexProgressEvent = reference to procedure(APage, APages, ATiles: Integer);

  { Called with a line of progress text for the user.
    @param(Msg The text to show.) }
  TTileIndexLogEvent = reference to procedure(const Msg: string);

  { @abstract(Builds a @link(TTileIndex) from NASA CMR.)

    Create one, optionally set @link(OnLog) and @link(OnProgress), then
    call @link(Build), usually on a background thread. Events are called on
    that thread. @link(Cancel) can be called from any thread. }
  TTileIndexBuilder = class
  private
    { HTTP client used for every request. }
    FClient: THTTPClient;
    { Set by @link(Cancel). }
    FCancelled: Boolean;
    { Backing field for @link(OnLog). }
    FOnLog: TTileIndexLogEvent;
    { Backing field for @link(OnProgress). }
    FOnProgress: TTileIndexProgressEvent;

    { Passes a message to @link(OnLog) if it is assigned.
      @param(Msg The text to pass on.) }
    procedure Log(const Msg: string);

    { Raises @link(ETileIndexCancelled) if @link(Cancel) has been called. }
    procedure CheckCancelled;

    { Requests one page of results, retrying if CMR asks the client to slow
      down.
      @param(AURL The search URL.)
      @param(ASearchAfter Value of @link(CMR_SEARCH_AFTER_HEADER) from the
        previous page; empty for the first page.)
      @param(ABody Receives the response body.)
      @returns(The response.)
      @raises(ETileIndexError if CMR returns an error or a timed-out
        result.) }
    function GetPage(const AURL, ASearchAfter: string; ABody: TStream): IHTTPResponse;
  public
    { Creates a builder. }
    constructor Create;

    { Frees the HTTP client. }
    destructor Destroy; override;

    { Lists every ASTER GDEM V3 granule and marks its tile in AIndex.
      AIndex is cleared first.
      @param(AIndex Index to fill.)
      @returns(The number of granules CMR reported, from
        @link(CMR_HITS_HEADER), for comparison with @code(AIndex.Count).)
      @raises(ETileIndexError if a request fails.)
      @raises(ETileIndexCancelled if @link(Cancel) was called.) }
    function Build(AIndex: TTileIndex): Integer;

    { Asks a build in progress to stop after the current request. Safe to
      call from any thread. }
    procedure Cancel;

    { Receives progress text. Called on the building thread. }
    property OnLog: TTileIndexLogEvent read FOnLog write FOnLog;

    { Receives progress after each page. Called on the building thread. }
    property OnProgress: TTileIndexProgressEvent read FOnProgress write FOnProgress;
  end;

implementation

uses
  System.IOUtils, System.Math,
  GDEMCMR, GDEMSettings;

const
  { Identifies an index file. }
  TILE_INDEX_MAGIC: array[0..3] of AnsiChar = ('G', 'D', 'T', 'I');
  { Most times to retry a page when CMR answers HTTP 429. }
  MAX_RETRIES = 5;
  { Wait before retrying when CMR gives no Retry-After value, in seconds. }
  DEFAULT_RETRY_SECONDS = 5;

{ TTileIndex }

class function TTileIndex.DefaultFileName: string;
begin
  Result := TPath.Combine(TGDEMSettings.SettingsFolder, TILE_INDEX_FILE_NAME);
end;

class function TTileIndex.BitIndex(ASouth, AWest: Integer; out AIndex: Integer): Boolean;
begin
  AWest := NormalizeLon(AWest);
  Result := InRange(ASouth, -90, 89);
  if Result then
    AIndex := (ASouth + 90) * TILE_INDEX_WIDTH + (AWest + 180)
  else
    AIndex := -1;
end;

procedure TTileIndex.Clear;
begin
  FillChar(FBits, SizeOf(FBits), 0);
  FCount := 0;
end;

procedure TTileIndex.Assign(ASource: TTileIndex);
begin
  Move(ASource.FBits, FBits, SizeOf(FBits));
  FCount := ASource.FCount;
end;

procedure TTileIndex.AddIndex(ASource: TTileIndex);
var
  LIndex: Integer;
begin
  for LIndex := 0 to High(FBits) do
    FBits[LIndex] := FBits[LIndex] or ASource.FBits[LIndex];
  FCount := CountBits;
end;

procedure TTileIndex.Add(ASouth, AWest: Integer);
var
  LIndex: Integer;
  LMask: Byte;
begin
  if not BitIndex(ASouth, AWest, LIndex) then
    Exit;
  LMask := 1 shl (LIndex and 7);
  if FBits[LIndex shr 3] and LMask = 0 then
  begin
    FBits[LIndex shr 3] := FBits[LIndex shr 3] or LMask;
    Inc(FCount);
  end;
end;

procedure TTileIndex.Remove(ASouth, AWest: Integer);
var
  LIndex: Integer;
  LMask: Byte;
begin
  if not BitIndex(ASouth, AWest, LIndex) then
    Exit;
  LMask := 1 shl (LIndex and 7);
  if FBits[LIndex shr 3] and LMask <> 0 then
  begin
    FBits[LIndex shr 3] := FBits[LIndex shr 3] and not LMask;
    Dec(FCount);
  end;
end;

function TTileIndex.Has(ASouth, AWest: Integer): Boolean;
var
  LIndex: Integer;
begin
  Result := BitIndex(ASouth, AWest, LIndex) and
    (FBits[LIndex shr 3] and (1 shl (LIndex and 7)) <> 0);
end;

function TTileIndex.CountBits: Integer;
var
  LByte: Byte;
  LValue: Byte;
begin
  Result := 0;
  for LByte in FBits do
  begin
    LValue := LByte;
    while LValue <> 0 do
    begin
      Inc(Result, LValue and 1);
      LValue := LValue shr 1;
    end;
  end;
end;

function TTileIndex.CountIn(const ARect: TTileRect): Integer;
var
  LLat, LLon: Integer;
begin
  Result := 0;
  for LLat := ARect.South to ARect.North - 1 do
    for LLon := ARect.West to ARect.East - 1 do
      if Has(LLat, LLon) then
        Inc(Result);
end;

function TTileIndex.TileNamesIn(const ARect: TTileRect): TArray<string>;
var
  LLat, LLon, LIndex: Integer;
begin
  SetLength(Result, CountIn(ARect));
  LIndex := 0;
  for LLat := ARect.North - 1 downto ARect.South do
    for LLon := ARect.West to ARect.East - 1 do
      if Has(LLat, LLon) then
      begin
        Result[LIndex] := TileName(LLat, LLon);
        Inc(LIndex);
      end;
end;

function TTileIndex.BoundingRect: TTileRect;
var
  LUsed: array[0..TILE_INDEX_WIDTH - 1] of Boolean;
  LRow, LCol, LSouth, LNorth, LGap, LBestGap, LBestEnd, LStep: Integer;
begin
  if FCount = 0 then
    Exit(TTileRect.Empty);

  // Which rows and columns hold any tile
  LSouth := MaxInt;
  LNorth := -MaxInt;
  FillChar(LUsed, SizeOf(LUsed), 0);
  for LRow := -90 to 89 do
    for LCol := 0 to TILE_INDEX_WIDTH - 1 do
      if Has(LRow, LCol - 180) then
      begin
        LUsed[LCol] := True;
        LSouth := Min(LSouth, LRow);
        LNorth := Max(LNorth, LRow + 1);
      end;

  // The longest run of empty columns, going round the world twice so a run
  // through the 180 degree meridian is measured whole
  LGap := 0;
  LBestGap := 0;
  LBestEnd := 0;
  for LStep := 0 to 2 * TILE_INDEX_WIDTH - 1 do
    if LUsed[LStep mod TILE_INDEX_WIDTH] then
      LGap := 0
    else
    begin
      Inc(LGap);
      if (LGap > LBestGap) and (LGap <= TILE_INDEX_WIDTH) then
      begin
        LBestGap := LGap;
        LBestEnd := LStep mod TILE_INDEX_WIDTH;
      end;
    end;

  Result.South := LSouth;
  Result.North := LNorth;
  if LBestGap = 0 then
  begin
    // Every column is used
    Result.West := -180;
    Result.East := 180;
  end
  else
  begin
    // The block starts just after the gap and covers everything else
    Result.West := NormalizeLon((LBestEnd + 1) mod TILE_INDEX_WIDTH - 180);
    Result.East := Result.West + TILE_INDEX_WIDTH - LBestGap;
  end;
end;

function TTileIndex.IsEmpty: Boolean;
begin
  Result := FCount = 0;
end;

procedure TTileIndex.SaveToStream(AStream: TStream);
var
  LWord: Word;
  LCount: Cardinal;
begin
  AStream.WriteBuffer(TILE_INDEX_MAGIC, SizeOf(TILE_INDEX_MAGIC));
  LWord := TILE_INDEX_VERSION;
  AStream.WriteBuffer(LWord, SizeOf(LWord));
  LWord := TILE_INDEX_WIDTH;
  AStream.WriteBuffer(LWord, SizeOf(LWord));
  LWord := TILE_INDEX_HEIGHT;
  AStream.WriteBuffer(LWord, SizeOf(LWord));
  LCount := FCount;
  AStream.WriteBuffer(LCount, SizeOf(LCount));
  AStream.WriteBuffer(FBits, SizeOf(FBits));
end;

procedure TTileIndex.LoadFromStream(AStream: TStream);
var
  LMagic: array[0..3] of AnsiChar;
  LVersion, LWidth, LHeight: Word;
  LCount: Cardinal;
  LBits: array[0..TILE_INDEX_BYTES - 1] of Byte;
begin
  try
    AStream.ReadBuffer(LMagic, SizeOf(LMagic));
    AStream.ReadBuffer(LVersion, SizeOf(LVersion));
    AStream.ReadBuffer(LWidth, SizeOf(LWidth));
    AStream.ReadBuffer(LHeight, SizeOf(LHeight));
    AStream.ReadBuffer(LCount, SizeOf(LCount));
  except
    raise ETileIndexError.Create('The tile index is truncated.');
  end;

  if not CompareMem(@LMagic, @TILE_INDEX_MAGIC, SizeOf(LMagic)) then
    raise ETileIndexError.Create('This is not a tile index file.');
  if LVersion <> TILE_INDEX_VERSION then
    raise ETileIndexError.CreateFmt('Unsupported tile index version %d.', [LVersion]);
  if (LWidth <> TILE_INDEX_WIDTH) or (LHeight <> TILE_INDEX_HEIGHT) then
    raise ETileIndexError.CreateFmt('Unexpected tile index size %d x %d.', [LWidth, LHeight]);

  try
    AStream.ReadBuffer(LBits, SizeOf(LBits));
  except
    raise ETileIndexError.Create('The tile index is truncated.');
  end;

  Move(LBits, FBits, SizeOf(FBits));
  FCount := CountBits;
  if Cardinal(FCount) <> LCount then
    raise ETileIndexError.CreateFmt(
      'The tile index is damaged: it says %d tiles but holds %d.', [LCount, FCount]);
end;

procedure TTileIndex.SaveToFile(const AFileName: string);
var
  LTempName: string;
  LStream: TFileStream;
begin
  LTempName := AFileName + '.tmp';
  try
    ForceDirectories(TPath.GetDirectoryName(AFileName));
    LStream := TFileStream.Create(LTempName, fmCreate);
    try
      SaveToStream(LStream);
    finally
      LStream.Free;
    end;
    if TFile.Exists(AFileName) then
      TFile.Delete(AFileName);
    TFile.Move(LTempName, AFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise ETileIndexError.CreateFmt('Could not save the tile index to %s: %s',
        [AFileName, E.Message]);
    end;
  end;
end;

function TTileIndex.LoadFromFile(const AFileName: string): Boolean;
var
  LStream: TFileStream;
  LLoaded: TTileIndex;
begin
  if not TFile.Exists(AFileName) then
    Exit(False);
  // Read into a separate index so a damaged file leaves this one unchanged
  LLoaded := TTileIndex.Create;
  try
    LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      LLoaded.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assign(LLoaded);
  finally
    LLoaded.Free;
  end;
  Result := True;
end;

{ TTileIndexBuilder }

constructor TTileIndexBuilder.Create;
begin
  inherited Create;
  FClient := THTTPClient.Create;
  FClient.UserAgent := 'GDEMFetch/0.1 (Delphi FMX)';
  FClient.ConnectionTimeout := 30000;
  // CMR can take a while to assemble 2,000 results
  FClient.ResponseTimeout := 180000;
end;

destructor TTileIndexBuilder.Destroy;
begin
  FClient.Free;
  inherited;
end;

procedure TTileIndexBuilder.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

procedure TTileIndexBuilder.Cancel;
begin
  FCancelled := True;
end;

procedure TTileIndexBuilder.CheckCancelled;
begin
  if FCancelled then
    raise ETileIndexCancelled.Create('Tile index build cancelled.');
end;

function TTileIndexBuilder.GetPage(const AURL, ASearchAfter: string;
  ABody: TStream): IHTTPResponse;
var
  LHeaders: TNetHeaders;
  LAttempt, LWait, LSecond: Integer;
begin
  if ASearchAfter <> '' then
    LHeaders := [TNetHeader.Create(CMR_SEARCH_AFTER_HEADER, ASearchAfter)]
  else
    LHeaders := nil;

  for LAttempt := 0 to MAX_RETRIES do
  begin
    CheckCancelled;
    ABody.Size := 0;
    Result := FClient.Get(AURL, ABody, LHeaders);

    if Result.StatusCode = 429 then
    begin
      LWait := StrToIntDef(Result.HeaderValue['Retry-After'], DEFAULT_RETRY_SECONDS);
      Log(Format('  CMR asked us to wait %d s', [LWait]));
      // Wait a second at a time so a cancel is not held up
      for LSecond := 1 to Max(1, LWait) do
      begin
        CheckCancelled;
        Sleep(1000);
      end;
      Continue;
    end;

    if Result.StatusCode <> 200 then
      raise ETileIndexError.CreateFmt('CMR request failed: HTTP %d %s',
        [Result.StatusCode, Result.StatusText]);
    if SameText(Result.HeaderValue[CMR_TIMEOUT_HEADER], 'true') then
      raise ETileIndexError.Create('CMR timed out and returned partial results. Try again later.');
    Exit;
  end;
  raise ETileIndexError.Create('CMR is busy; too many retries. Try again later.');
end;

function TTileIndexBuilder.Build(AIndex: TTileIndex): Integer;
var
  LURL, LSearchAfter: string;
  LBody: TStringStream;
  LResp: IHTTPResponse;
  LSearch: TCMRGranuleSearch;
  LGranule: TCMRGranule;
  LPage, LPages, LSouth, LWest, LSkipped: Integer;
begin
  AIndex.Clear;
  LURL := TCMRGranuleSearch.CollectionURL(CMR_MAX_PAGE_SIZE);
  LSearchAfter := '';
  LPage := 0;
  LPages := 0;
  LSkipped := 0;
  Result := 0;

  Log('Building tile index from NASA CMR ...');
  LBody := TStringStream.Create('', TEncoding.UTF8);
  try
    repeat
      LResp := GetPage(LURL, LSearchAfter, LBody);
      Inc(LPage);

      if LPage = 1 then
      begin
        Result := StrToIntDef(LResp.HeaderValue[CMR_HITS_HEADER], 0);
        if Result > 0 then
          LPages := (Result + CMR_MAX_PAGE_SIZE - 1) div CMR_MAX_PAGE_SIZE;
        Log(Format('  CMR lists %d granules', [Result]));
      end;

      LSearch := TCMRGranuleSearch.FromJSON(LBody.DataString);
      for LGranule in LSearch.Feed.Entry do
        if TryParseTileName(LGranule.Title, LSouth, LWest) or
           TryParseTileName(LGranule.ProducerGranuleId, LSouth, LWest) then
          AIndex.Add(LSouth, LWest)
        else
          Inc(LSkipped);

      if Assigned(FOnProgress) then
        FOnProgress(LPage, LPages, AIndex.Count);

      // The last page is empty and carries no search-after value
      LSearchAfter := LResp.HeaderValue[CMR_SEARCH_AFTER_HEADER];
    until (Length(LSearch.Feed.Entry) = 0) or (LSearchAfter = '');
  finally
    LBody.Free;
  end;

  if LSkipped > 0 then
    Log(Format('  %d granule names could not be read and were skipped', [LSkipped]));
  Log(Format('  index holds %d tiles', [AIndex.Count]));
end;

end.
