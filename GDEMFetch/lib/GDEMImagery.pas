{ @abstract(Satellite imagery for the 3D view: EOX's Sentinel-2 cloudless
  mosaics, fetched in the background, kept in a cache on disk, and made
  into one texture for each patch of ground.)

  The imagery comes from EOX's public tile service
  (@link(IMAGERY_URL_FORMAT)), in its WGS84 grid: level z covers the world
  in 2^(z+1) x 2^z tiles of 256 x 256 pixels, 180 / 2^z degrees a tile,
  so latitude and longitude map straight to pixels, as they do for the
  elevation tiles. Level 13, the finest used (@link(IMAGERY_MAX_ZOOM)),
  is about 9.5 m a pixel at the equator, about Sentinel-2's own 10 m.

  A patch's texture is @link(IMAGERY_PIXELS) square. Its first and last
  pixels' centres lie on the patch's edges (@link(ImageryPatchTexCoords)),
  so two neighbouring patches show the same imagery along the edge they
  share and no seam can show. Each texture is made from the coarsest level
  that has at least as many pixels across the patch, so a distant patch
  costs a few small tiles.

  @link(TImageryService) takes requests on the main thread, makes the
  textures on worker threads (@link(IMAGERY_WORKERS) at once), and hands
  them back through @link(TImageryService.Take), matched by the caller's
  id. A request cancelled before it is done is dropped.

  EOX's public service limits how fast it is asked, answering with errors
  or a redirect to a "heavy load" page when asked too fast, and publishes
  no figures. So downloads are paced: they start at
  @link(IMAGERY_START_RATE) tiles a second, go a little faster with each
  tile downloaded, and on a refusal halve the pace and pause, the pause
  doubling while refusals go on (as GDEMFetch's NASA downloads back off).
  A refused tile is tried again, up to @link(IMAGERY_TRIES) times. Tiles are read
  from the disk cache when there, otherwise downloaded and written to it;
  the cache keeps under its size limit by deleting the tiles used least
  recently (each file's time is set when it is used, so the order lasts
  from one run to the next). No FMX.

  The recent years are licensed for non-commercial use only; see
  @link(ImageryLicence) and @code(CREDITS.md). }
unit GDEMImagery;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.SyncObjs,
  System.Generics.Collections, System.Diagnostics;

const
  { Pixels across a patch's texture. }
  IMAGERY_PIXELS = 256;

  { Pixels across one of EOX's tiles. }
  IMAGERY_TILE_PIXELS = 256;

  { The finest level used: about 9.5 m a pixel at the equator. EOX serves
    finer levels, but they only enlarge Sentinel-2's 10 m. }
  IMAGERY_MAX_ZOOM = 13;

  { Textures made at once, each on its own worker thread. }
  IMAGERY_WORKERS = 6;

  { Tiles downloaded a second at the start; see
    @link(TImageryService.Rate). }
  IMAGERY_START_RATE = 8;

  { The fewest tiles downloaded a second, however often EOX refuses. }
  IMAGERY_MIN_RATE = 1;

  { The most tiles downloaded a second. }
  IMAGERY_MAX_RATE = 32;

  { Tiles a second added to the pace for each tile downloaded. }
  IMAGERY_RATE_STEP = 0.25;

  { Times a refused tile is asked for before its texture is given up. }
  IMAGERY_TRIES = 6;

  { The first pause after a refusal, milliseconds; it doubles with each
    refusal in a row, up to @link(IMAGERY_MAX_PAUSE_MS). }
  IMAGERY_FIRST_PAUSE_MS = 1000;

  { The longest pause after refusals, milliseconds. }
  IMAGERY_MAX_PAUSE_MS = 60000;

  { Where a tile is: layer, level, row, column. }
  IMAGERY_URL_FORMAT = 'https://tiles.maps.eox.at/wmts/1.0.0/%s/default/WGS84/%d/%d/%d.jpg';

  { The layer used unless the settings say otherwise: the newest year EOX
    serves (CC BY-NC-SA 4.0). }
  DEFAULT_IMAGERY_LAYER = 's2cloudless-2025';

  { The disk cache's size limit unless the settings say otherwise,
    megabytes. }
  DEFAULT_IMAGERY_CACHE_MB = 2048;

  { The name of the cache's folder in the data folder. }
  IMAGERY_FOLDER_NAME = 'Imagery';

type
  { @abstract(A texture made for a request, or why it could not be.) }
  TImageryResult = record
    { The id the request was made with. }
    Id: Int64;
    { @link(IMAGERY_PIXELS) x @link(IMAGERY_PIXELS) colours, row by row
      from the north-west; empty if it could not be made. }
    Pixels: TArray<TAlphaColor>;
    { Why it could not be made; empty if it was. }
    Error: string;
    { The level its tiles came from. }
    Zoom: Integer;
    { Tiles downloaded for it; the rest came from memory or the disk. }
    Downloaded: Integer;
    { How long it took, milliseconds. }
    Milliseconds: Double;
  end;

  { @abstract(The patch a request is for.) }
  TImageryArea = record
    { Its north edge, degrees. }
    North: Double;
    { Its west edge, degrees. }
    West: Double;
    { Its size, degrees, north to south and west to east. }
    Size: Double;
  end;

  { @abstract(A tile decoded, kept in memory for the next texture that
    needs it.) }
  TImageryTilePixels = TArray<TAlphaColor>;

  { @abstract(One file in the disk cache.) }
  TImageryCacheEntry = record
    { Its size, bytes. }
    Size: Int64;
    { When it was last used. }
    Used: TDateTime;
  end;

  { @abstract(Makes patch textures from EOX's tiles in the background.) }
  TImageryService = class
  private
    { Backing field for @link(Layer). }
    FLayer: string;
    { The cache's folder for this layer; empty for no disk cache. }
    FCacheFolder: string;
    { The cache's size limit, bytes. }
    FCacheLimit: Int64;
    { Guards everything below that is shared with the workers. }
    FLock: TCriticalSection;
    { Requests waiting for a worker, oldest first. }
    FQueue: TQueue<Int64>;
    { The patch each request is for, by id. A request cancelled is
      removed. }
    FWanted: TDictionary<Int64, TImageryArea>;
    { Textures made, oldest first, for @link(Take). }
    FResults: TQueue<TImageryResult>;
    { Lines for the log, oldest first, for @link(TakeMessage). }
    FMessages: TQueue<string>;
    { Decoded tiles in memory, by key. }
    FTiles: TDictionary<string, TImageryTilePixels>;
    { The keys of @link(FTiles), least recently used first. }
    FTileOrder: TList<string>;
    { Keys of tiles being downloaded or read now, so two workers do not
      fetch the same one. }
    FFetching: TDictionary<string, Boolean>;
    { The disk cache's files, by path. }
    FCacheFiles: TDictionary<string, TImageryCacheEntry>;
    { The disk cache's total size, bytes. }
    FCacheBytes: Int64;
    { @true once the disk cache has been measured. }
    FCacheScanned: Boolean;
    { Workers running. }
    FInFlight: Integer;
    { @true while the service is being freed: no more work starts. }
    FClosing: Boolean;
    { Problems so far, to keep the log short. }
    FErrorCount: Integer;
    { Times the pacing, from the start. }
    FClock: TStopwatch;
    { Backing field for @link(Rate). }
    FRate: Double;
    { When, on @link(FClock), the next download may start. }
    FNextSlotMs: Double;
    { Until when, on @link(FClock), downloads pause after a refusal. }
    FPausedUntilMs: Double;
    { The next pause after a refusal, milliseconds. }
    FPauseMs: Double;
    { Backing field for @link(Refusals). }
    FRefusals: Integer;

    { Starts workers for waiting requests, up to @link(IMAGERY_WORKERS);
      called with @link(FLock) held. }
    procedure Pump;

    { Makes one texture; on a worker thread.
      @param(AId The request's id.) }
    procedure Work(AId: Int64);

    { A worker's method for a request, with the id copied in, so each
      task has its own.
      @param(AId The request's id.)
      @returns(The method to run.) }
    function MakeWork(AId: Int64): TProc;

    { The pixels of one tile, from memory, the disk or the web.
      @param(AId The request that needs it.)
      @param(AZoom The level.)
      @param(ARow The row, from the north.)
      @param(AColumn The column, from 180 west.)
      @param(ADownloaded Counts one up if the tile was downloaded.)
      @returns(The tile's colours.)
      @raises(Exception if it cannot be had.) }
    function TilePixels(AId: Int64; AZoom, ARow, AColumn: Integer;
      var ADownloaded: Integer): TImageryTilePixels;

    { Downloads a tile at the pace allowed, trying again after refusals.
      @param(AId The request that needs it, to stop if it is cancelled.)
      @param(AZoom The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(The JPEG.)
      @raises(Exception if it cannot be downloaded, or the request is no
        longer wanted.) }
    function Download(AId: Int64; AZoom, ARow, AColumn: Integer): TBytes;

    { Asks EOX for a tile once.
      @param(AZoom The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @param(AStatus The HTTP status; 0 if no answer came.)
      @param(AWhy What went wrong, when it did.)
      @returns(The JPEG, or empty if it was not given.) }
    function DownloadOnce(AZoom, ARow, AColumn: Integer; out AStatus: Integer;
      out AWhy: string): TBytes;

    { Waits until a download may start, at the pace allowed.
      @param(AId The request waiting.)
      @returns(@false if the request was cancelled meanwhile.) }
    function WaitForSlot(AId: Int64): Boolean;

    { @true while a request is still wanted.
      @param(AId The request.)
      @returns(@true if wanted.) }
    function StillWanted(AId: Int64): Boolean;

    { Speeds the pace up a little after a tile is downloaded. }
    procedure Downloaded;

    { Halves the pace and pauses after a refusal, and says so in the log
      the first time and every fiftieth.
      @param(AWhy What EOX answered.) }
    procedure Refused(const AWhy: string);

    { Reader for @link(Rate). @returns(Tiles a second.) }
    function GetRate: Double;

    { Reader for @link(Refusals). @returns(Refusals so far.) }
    function GetRefusals: Integer;

    { Decodes a tile.
      @param(ABytes The JPEG.)
      @returns(Its colours, @link(IMAGERY_TILE_PIXELS) square.)
      @raises(Exception if it cannot be decoded.) }
    function Decode(const ABytes: TBytes): TImageryTilePixels;

    { A tile's file in the disk cache.
      @param(AZoom The level.)
      @param(ARow The row.)
      @param(AColumn The column.)
      @returns(The path; empty with no disk cache.) }
    function CacheFile(AZoom, ARow, AColumn: Integer): string;

    { Reads a tile from the disk cache, marking it used.
      @param(AFile Its path.)
      @returns(The JPEG, or empty if it is not there.) }
    function CacheRead(const AFile: string): TBytes;

    { Writes a tile to the disk cache, then deletes the least recently used
      tiles if the cache has grown past its limit.
      @param(AFile Its path.)
      @param(ABytes The JPEG.) }
    procedure CacheWrite(const AFile: string; const ABytes: TBytes);

    { Deletes the least recently used tiles until the cache is under 90%
      of its limit; called with @link(FLock) held. }
    procedure TrimCache;

    { Measures the disk cache; on a worker thread, at the start. }
    procedure ScanCache;

    { Keeps a decoded tile in memory, dropping the least recently used
      beyond the first few dozen.
      @param(AKey The tile's key.)
      @param(APixels Its colours.) }
    procedure KeepTile(const AKey: string; const APixels: TImageryTilePixels);

    { Adds a line for the log; any thread.
      @param(AText The line.) }
    procedure AddMessage(const AText: string);
  public
    { Starts the service; the disk cache is measured in the background.
      @param(ALayer EOX's layer, such as @code(s2cloudless-2025).)
      @param(ACacheRoot The folder the cache goes in (a folder for the
        layer is made inside it); empty for no disk cache.)
      @param(ACacheMB The cache's size limit, megabytes.) }
    constructor Create(const ALayer, ACacheRoot: string; ACacheMB: Integer);

    { Stops taking work, waits for the workers (at most half a minute),
      and frees everything. }
    destructor Destroy; override;

    { Asks for a patch's texture.
      @param(AId The caller's id for it, returned with the result.)
      @param(ANorth The patch's north edge, degrees.)
      @param(AWest Its west edge, degrees.)
      @param(ASize Its size, degrees, north to south and west to east.) }
    procedure Request(AId: Int64; ANorth, AWest, ASize: Double);

    { Forgets a request: not started, it never will be; started, its result
      is dropped.
      @param(AId The id.) }
    procedure Cancel(AId: Int64);

    { Forgets every request. }
    procedure CancelAll;

    { Takes the oldest texture made.
      @param(AResult The texture.)
      @returns(@false if there is none.) }
    function Take(out AResult: TImageryResult): Boolean;

    { Takes the oldest line for the log.
      @param(AText The line.)
      @returns(@false if there is none.) }
    function TakeMessage(out AText: string): Boolean;

    { Requests waiting or being made. }
    function Pending: Integer;

    { EOX's layer. }
    property Layer: string read FLayer;

    { The pace downloads are allowed now, tiles a second. }
    property Rate: Double read GetRate;

    { Times EOX has refused a tile so far. }
    property Refusals: Integer read GetRefusals;
  end;

{ The year a layer shows.
  @param(ALayer Such as @code(s2cloudless-2025); plain
    @code(s2cloudless) is 2016.)
  @returns(The year, or 0 if the name has none.) }
function ImageryLayerYear(const ALayer: string): Integer;

{ The licence a layer is under.
  @param(ALayer The layer.)
  @returns(@code(CC BY 4.0) for 2016 and 2017, @code(CC BY-NC-SA 4.0)
    for later years.) }
function ImageryLicence(const ALayer: string): string;

{ The credit EOX asks to be shown with a layer.
  @param(ALayer The layer.)
  @returns(The credit.) }
function ImageryCredit(const ALayer: string): string;

{ The level to make a patch's texture from: the coarsest with at least
  @link(IMAGERY_PIXELS) pixels across it, at most
  @link(IMAGERY_MAX_ZOOM).
  @param(ASize The patch's size, degrees.)
  @returns(The level.) }
function ImageryZoomFor(ASize: Double): Integer;

{ The texture coordinates of a patch's vertices, the same for every patch:
  in the order @code(BuildTerrainPatch) lays its vertices out (the
  surface row by row from the north-west, then the skirt along the north,
  south, west and east edges, each skirt vertex as the edge vertex above
  it).
  @returns(@code(PATCH_VERTICES) points, 0 to 1 across and down.) }
function ImageryPatchTexCoords: TArray<TPointF>;

implementation

uses
  System.IOUtils, System.Math, System.DateUtils, System.Threading,
  System.Generics.Defaults,
  System.Net.HttpClient, System.Net.URLClient, System.Skia,
  GDEMTerrain;

const
  { Decoded tiles kept in memory: 256 KB each. }
  TILES_KEPT = 96;
  { The cache is trimmed down to this share of its limit. }
  TRIM_TO = 0.9;
  { Problems logged in full before only every hundredth is. }
  ERRORS_LOGGED = 5;
  { Milliseconds a worker waits for another to finish fetching a tile it
    also needs, between looks. }
  FETCH_WAIT_MS = 20;
  { The most milliseconds a worker waits for another's fetch. }
  FETCH_WAIT_LIMIT_MS = 30000;
  { Milliseconds to connect to EOX, and to wait for a reply. }
  CONNECT_TIMEOUT_MS = 10000;
  { See @link(CONNECT_TIMEOUT_MS). }
  RESPONSE_TIMEOUT_MS = 20000;
  { How GDEMFetch names itself to EOX. }
  IMAGERY_USER_AGENT = 'GDEMFetch/0.1 (Delphi FMX)';

function ImageryLayerYear(const ALayer: string): Integer;
var
  LDash: Integer;
begin
  if SameText(ALayer, 's2cloudless') then
    Exit(2016);
  LDash := ALayer.LastIndexOf('-');
  if (LDash < 0) or not TryStrToInt(ALayer.Substring(LDash + 1), Result) then
    Result := 0;
end;

function ImageryLicence(const ALayer: string): string;
var
  LYear: Integer;
begin
  LYear := ImageryLayerYear(ALayer);
  if (LYear > 0) and (LYear <= 2017) then
    Result := 'CC BY 4.0'
  else
    Result := 'CC BY-NC-SA 4.0';
end;

function ImageryCredit(const ALayer: string): string;
var
  LYear: Integer;
begin
  LYear := ImageryLayerYear(ALayer);
  Result := 'Sentinel-2 cloudless - https://s2maps.eu by EOX IT Services GmbH ' +
    '(Contains modified Copernicus Sentinel data';
  if LYear > 0 then
    Result := Result + ' ' + IntToStr(LYear);
  Result := Result + '), ' + ImageryLicence(ALayer);
end;

function ImageryZoomFor(ASize: Double): Integer;
var
  LNeeded: Double;
begin
  // Level z has 256 x 2^z / 180 pixels a degree; the texture needs
  // IMAGERY_PIXELS - 1 gaps across the patch
  if ASize <= 0 then
    Exit(IMAGERY_MAX_ZOOM);
  LNeeded := 180 * (IMAGERY_PIXELS - 1) / (IMAGERY_TILE_PIXELS * ASize);
  if LNeeded <= 1 then
    Exit(0);
  Result := EnsureRange(Ceil(Log2(LNeeded) - 1E-9), 0, IMAGERY_MAX_ZOOM);
end;

function ImageryPatchTexCoords: TArray<TPointF>;
var
  LRow, LColumn, LEdge, LStep, K: Integer;

  { The coordinate of a sample along a side, so the first and last pixels'
    centres fall on the patch's edges.
    @param(AStep 0 to @code(PATCH_CELLS).)
    @returns(0 to 1.) }
  function Along(AStep: Integer): Single;
  begin
    Result := (0.5 + AStep * (IMAGERY_PIXELS - 1) / PATCH_CELLS) / IMAGERY_PIXELS;
  end;

begin
  SetLength(Result, PATCH_VERTICES);
  K := 0;
  for LRow := 0 to PATCH_CELLS do
    for LColumn := 0 to PATCH_CELLS do
    begin
      Result[K] := PointF(Along(LColumn), Along(LRow));
      Inc(K);
    end;
  // The skirt, as BuildTerrainPatch makes it: north, south, west, east
  for LEdge := 0 to 3 do
    for LStep := 0 to PATCH_CELLS do
    begin
      case LEdge of
        0: Result[K] := PointF(Along(LStep), Along(0));
        1: Result[K] := PointF(Along(LStep), Along(PATCH_CELLS));
        2: Result[K] := PointF(Along(0), Along(LStep));
      else
        Result[K] := PointF(Along(PATCH_CELLS), Along(LStep));
      end;
      Inc(K);
    end;
end;

{ A tile's key, for the dictionaries.
  @param(AZoom The level.)
  @param(ARow The row.)
  @param(AColumn The column.)
  @returns(The key.) }
function TileKey(AZoom, ARow, AColumn: Integer): string;
begin
  Result := Format('%d/%d/%d', [AZoom, ARow, AColumn]);
end;

{ TImageryService }

constructor TImageryService.Create(const ALayer, ACacheRoot: string; ACacheMB: Integer);
begin
  inherited Create;
  FLayer := ALayer;
  if ACacheRoot <> '' then
    FCacheFolder := TPath.Combine(ACacheRoot, ALayer);
  FCacheLimit := Int64(Max(ACacheMB, 16)) * 1024 * 1024;
  FLock := TCriticalSection.Create;
  FQueue := TQueue<Int64>.Create;
  FWanted := TDictionary<Int64, TImageryArea>.Create;
  FResults := TQueue<TImageryResult>.Create;
  FMessages := TQueue<string>.Create;
  FTiles := TDictionary<string, TImageryTilePixels>.Create;
  FTileOrder := TList<string>.Create;
  FFetching := TDictionary<string, Boolean>.Create;
  FCacheFiles := TDictionary<string, TImageryCacheEntry>.Create;
  FClock := TStopwatch.StartNew;
  FRate := IMAGERY_START_RATE;
  FPauseMs := IMAGERY_FIRST_PAUSE_MS;
  if FCacheFolder <> '' then
  begin
    FLock.Enter;
    try
      Inc(FInFlight);
    finally
      FLock.Leave;
    end;
    TTask.Run(
      procedure
      begin
        try
          ScanCache;
        finally
          FLock.Enter;
          try
            Dec(FInFlight);
          finally
            FLock.Leave;
          end;
        end;
      end);
  end
  else
    FCacheScanned := True;
end;

destructor TImageryService.Destroy;
var
  LWatch: TStopwatch;
  LBusy: Boolean;
begin
  FLock.Enter;
  try
    FClosing := True;
    FQueue.Clear;
    FWanted.Clear;
  finally
    FLock.Leave;
  end;
  // Workers finish their download or give up at its time-out
  LWatch := TStopwatch.StartNew;
  repeat
    FLock.Enter;
    try
      LBusy := FInFlight > 0;
    finally
      FLock.Leave;
    end;
    if LBusy then
      Sleep(10);
  until not LBusy or (LWatch.ElapsedMilliseconds > 30000);
  FCacheFiles.Free;
  FFetching.Free;
  FTileOrder.Free;
  FTiles.Free;
  FMessages.Free;
  FResults.Free;
  FWanted.Free;
  FQueue.Free;
  FLock.Free;
  inherited;
end;

procedure TImageryService.AddMessage(const AText: string);
begin
  FLock.Enter;
  try
    if not FClosing then
      FMessages.Enqueue(AText);
  finally
    FLock.Leave;
  end;
end;

procedure TImageryService.Request(AId: Int64; ANorth, AWest, ASize: Double);
var
  LArea: TImageryArea;
begin
  LArea.North := ANorth;
  LArea.West := AWest;
  LArea.Size := ASize;
  FLock.Enter;
  try
    if FClosing then
      Exit;
    if not FWanted.ContainsKey(AId) then
      FQueue.Enqueue(AId);
    FWanted.AddOrSetValue(AId, LArea);
    Pump;
  finally
    FLock.Leave;
  end;
end;

procedure TImageryService.Cancel(AId: Int64);
begin
  FLock.Enter;
  try
    FWanted.Remove(AId);
  finally
    FLock.Leave;
  end;
end;

procedure TImageryService.CancelAll;
begin
  FLock.Enter;
  try
    FQueue.Clear;
    FWanted.Clear;
  finally
    FLock.Leave;
  end;
end;

function TImageryService.Take(out AResult: TImageryResult): Boolean;
begin
  FLock.Enter;
  try
    Result := FResults.Count > 0;
    if Result then
      AResult := FResults.Dequeue;
  finally
    FLock.Leave;
  end;
end;

function TImageryService.TakeMessage(out AText: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FMessages.Count > 0;
    if Result then
      AText := FMessages.Dequeue;
  finally
    FLock.Leave;
  end;
end;

function TImageryService.Pending: Integer;
begin
  FLock.Enter;
  try
    Result := FWanted.Count;
  finally
    FLock.Leave;
  end;
end;

function TImageryService.MakeWork(AId: Int64): TProc;
begin
  Result :=
    procedure
    begin
      Work(AId);
    end;
end;

procedure TImageryService.Pump;
var
  LId: Int64;
begin
  while not FClosing and (FInFlight < IMAGERY_WORKERS) and (FQueue.Count > 0) do
  begin
    LId := FQueue.Dequeue;
    // Cancelled while waiting
    if not FWanted.ContainsKey(LId) then
      Continue;
    Inc(FInFlight);
    TTask.Run(MakeWork(LId));
  end;
end;

procedure TImageryService.Work(AId: Int64);
var
  LResult: TImageryResult;
  LArea: TImageryArea;
  LSize, LNorth, LWest, LStep, LPerDegree, LGX, LGY, LFX, LFY: Double;
  LWanted: Boolean;
  LWatch: TStopwatch;
  LZoom, LWidth, LHeight, I, J, LX0, LY0, LX1, LY1, LMinRow, LMaxRow, LMinCol, LMaxCol,
    LRow, LCol: Integer;
  LTiles: TDictionary<Int64, TImageryTilePixels>;
  C00, C10, C01, C11: TAlphaColor;

  { Divides, rounding down, also for negative numbers (Delphi's
    @code(div) rounds towards 0).
    @param(A The number.)
    @param(B What it is divided by, more than 0.)
    @returns(The quotient, rounded down.) }
  function FloorDiv(A, B: Integer): Integer;
  begin
    Result := A div B;
    if (A mod B <> 0) and (A < 0) then
      Dec(Result);
  end;

  { The colour of one pixel of the level, from the tiles fetched.
    @param(AX Column, wrapped east to west.)
    @param(AY Row, kept within the poles.)
    @returns(The colour.) }
  function PixelAt(AX, AY: Integer): TAlphaColor;
  var
    LTile: TImageryTilePixels;
  begin
    AX := ((AX mod LWidth) + LWidth) mod LWidth;
    AY := EnsureRange(AY, 0, LHeight - 1);
    LTile := LTiles[Int64(AY div IMAGERY_TILE_PIXELS) shl 32 or (AX div IMAGERY_TILE_PIXELS)];
    Result := LTile[(AY mod IMAGERY_TILE_PIXELS) * IMAGERY_TILE_PIXELS +
      (AX mod IMAGERY_TILE_PIXELS)];
  end;

  { Blends four colours, channel by channel.
    @returns(The colour at the fractions LFX across and LFY down.) }
  function Blend: TAlphaColor;
  var
    LShift: Integer;
    LValue: Double;
  begin
    Result := $FF000000;
    LShift := 0;
    while LShift <= 16 do
    begin
      LValue := ((C00 shr LShift) and $FF) * (1 - LFX) * (1 - LFY) +
        ((C10 shr LShift) and $FF) * LFX * (1 - LFY) +
        ((C01 shr LShift) and $FF) * (1 - LFX) * LFY +
        ((C11 shr LShift) and $FF) * LFX * LFY;
      Result := Result or (Cardinal(EnsureRange(Round(LValue), 0, 255)) shl LShift);
      Inc(LShift, 8);
    end;
  end;

begin
  LWatch := TStopwatch.StartNew;
  LResult := Default(TImageryResult);
  LResult.Id := AId;
  LTiles := TDictionary<Int64, TImageryTilePixels>.Create;
  try
    try
      FLock.Enter;
      try
        LWanted := not FClosing and FWanted.TryGetValue(AId, LArea);
      finally
        FLock.Leave;
      end;
      if not LWanted then
        Exit;
      LNorth := LArea.North;
      LWest := LArea.West;
      LSize := LArea.Size;
      LZoom := ImageryZoomFor(LSize);
      LResult.Zoom := LZoom;
      // The level's pixels, and where each texture pixel's centre falls
      // among their centres
      LWidth := IMAGERY_TILE_PIXELS shl (LZoom + 1);
      LHeight := IMAGERY_TILE_PIXELS shl LZoom;
      LPerDegree := LHeight / 180;
      LStep := LSize / (IMAGERY_PIXELS - 1);

      // The tiles the texture needs (columns unwrapped, then wrapped)
      LMinCol := FloorDiv(Floor((LWest + 180) * LPerDegree - 0.5), IMAGERY_TILE_PIXELS);
      LMaxCol := FloorDiv(Floor((LWest + LSize + 180) * LPerDegree - 0.5) + 1,
        IMAGERY_TILE_PIXELS);
      LMinRow := Max(Floor(((90 - LNorth) * LPerDegree - 0.5)), 0) div IMAGERY_TILE_PIXELS;
      LMaxRow := Min(Floor(((90 - (LNorth - LSize)) * LPerDegree - 0.5)) + 1, LHeight - 1) div
        IMAGERY_TILE_PIXELS;
      for LRow := LMinRow to LMaxRow do
        for LCol := LMinCol to LMaxCol do
        begin
          I := ((LCol mod (LWidth div IMAGERY_TILE_PIXELS)) + (LWidth div IMAGERY_TILE_PIXELS)) mod
            (LWidth div IMAGERY_TILE_PIXELS);
          if not LTiles.ContainsKey(Int64(LRow) shl 32 or I) then
            LTiles.Add(Int64(LRow) shl 32 or I, TilePixels(AId, LZoom, LRow, I, LResult.Downloaded));
          // Given up on the way: no texture is wanted any more
          FLock.Enter;
          try
            LWanted := not FClosing and FWanted.ContainsKey(AId);
          finally
            FLock.Leave;
          end;
          if not LWanted then
            Exit;
        end;

      // Each texture pixel from the four level pixels round it
      SetLength(LResult.Pixels, IMAGERY_PIXELS * IMAGERY_PIXELS);
      for J := 0 to IMAGERY_PIXELS - 1 do
      begin
        LGY := (90 - (LNorth - J * LStep)) * LPerDegree - 0.5;
        LY0 := Floor(LGY);
        LFY := LGY - LY0;
        LY1 := LY0 + 1;
        for I := 0 to IMAGERY_PIXELS - 1 do
        begin
          LGX := (LWest + I * LStep + 180) * LPerDegree - 0.5;
          LX0 := Floor(LGX);
          LFX := LGX - LX0;
          LX1 := LX0 + 1;
          C00 := PixelAt(LX0, LY0);
          C10 := PixelAt(LX1, LY0);
          C01 := PixelAt(LX0, LY1);
          C11 := PixelAt(LX1, LY1);
          LResult.Pixels[J * IMAGERY_PIXELS + I] := Blend;
        end;
      end;
    except
      on E: Exception do
      begin
        LResult.Pixels := nil;
        LResult.Error := E.Message;
      end;
    end;
    LResult.Milliseconds := LWatch.Elapsed.TotalMilliseconds;
    FLock.Enter;
    try
      if not FClosing and FWanted.ContainsKey(AId) then
      begin
        FResults.Enqueue(LResult);
        FWanted.Remove(AId);
      end;
    finally
      FLock.Leave;
    end;
  finally
    LTiles.Free;
    FLock.Enter;
    try
      Dec(FInFlight);
      Pump;
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TImageryService.KeepTile(const AKey: string; const APixels: TImageryTilePixels);
begin
  FLock.Enter;
  try
    if FTiles.ContainsKey(AKey) then
      FTileOrder.Remove(AKey);
    FTiles.AddOrSetValue(AKey, APixels);
    FTileOrder.Add(AKey);
    while FTileOrder.Count > TILES_KEPT do
    begin
      FTiles.Remove(FTileOrder[0]);
      FTileOrder.Delete(0);
    end;
  finally
    FLock.Leave;
  end;
end;

function TImageryService.TilePixels(AId: Int64; AZoom, ARow, AColumn: Integer;
  var ADownloaded: Integer): TImageryTilePixels;
var
  LKey, LFile: string;
  LBytes: TBytes;
  LMine: Boolean;
  LWatch: TStopwatch;
begin
  LKey := TileKey(AZoom, ARow, AColumn);
  LWatch := TStopwatch.StartNew;
  // In memory, or being fetched by another worker: wait for it
  repeat
    FLock.Enter;
    try
      if FTiles.TryGetValue(LKey, Result) then
      begin
        FTileOrder.Remove(LKey);
        FTileOrder.Add(LKey);
        Exit;
      end;
      LMine := not FFetching.ContainsKey(LKey);
      if LMine then
        FFetching.Add(LKey, True);
    finally
      FLock.Leave;
    end;
    if not LMine then
    begin
      if LWatch.ElapsedMilliseconds > FETCH_WAIT_LIMIT_MS then
        raise Exception.CreateFmt('Gave up waiting for tile %s', [LKey]);
      Sleep(FETCH_WAIT_MS);
    end;
  until LMine;

  try
    LFile := CacheFile(AZoom, ARow, AColumn);
    if LFile <> '' then
      LBytes := CacheRead(LFile)
    else
      LBytes := nil;
    if Length(LBytes) = 0 then
    begin
      LBytes := Download(AId, AZoom, ARow, AColumn);
      Inc(ADownloaded);
      Result := Decode(LBytes);
      // Kept only once it has decoded, so a broken download is not cached
      if LFile <> '' then
        CacheWrite(LFile, LBytes);
    end
    else
      Result := Decode(LBytes);
    KeepTile(LKey, Result);
  finally
    FLock.Enter;
    try
      FFetching.Remove(LKey);
    finally
      FLock.Leave;
    end;
  end;
end;

function TImageryService.StillWanted(AId: Int64): Boolean;
begin
  FLock.Enter;
  try
    Result := not FClosing and FWanted.ContainsKey(AId);
  finally
    FLock.Leave;
  end;
end;

function TImageryService.GetRate: Double;
begin
  FLock.Enter;
  try
    Result := FRate;
  finally
    FLock.Leave;
  end;
end;

function TImageryService.GetRefusals: Integer;
begin
  FLock.Enter;
  try
    Result := FRefusals;
  finally
    FLock.Leave;
  end;
end;

function TImageryService.WaitForSlot(AId: Int64): Boolean;
var
  LNow, LSlot: Double;
begin
  repeat
    FLock.Enter;
    try
      if FClosing or not FWanted.ContainsKey(AId) then
        Exit(False);
      LNow := FClock.Elapsed.TotalMilliseconds;
      LSlot := Max(LNow, Max(FNextSlotMs, FPausedUntilMs));
      if LSlot <= LNow then
      begin
        // This one goes now; the next waits its turn at the pace allowed
        FNextSlotMs := LNow + 1000 / FRate;
        Exit(True);
      end;
    finally
      FLock.Leave;
    end;
    // A short sleep, so a cancel or a change of pace is noticed
    Sleep(Min(Max(Round(LSlot - LNow), 1), 100));
  until False;
end;

procedure TImageryService.Downloaded;
begin
  FLock.Enter;
  try
    FRate := Min(FRate + IMAGERY_RATE_STEP, IMAGERY_MAX_RATE);
    FPauseMs := IMAGERY_FIRST_PAUSE_MS;
  finally
    FLock.Leave;
  end;
end;

procedure TImageryService.Refused(const AWhy: string);
var
  LText: string;
begin
  FLock.Enter;
  try
    FRate := Max(FRate / 2, IMAGERY_MIN_RATE);
    FPausedUntilMs := Max(FPausedUntilMs, FClock.Elapsed.TotalMilliseconds + FPauseMs);
    Inc(FRefusals);
    if (FRefusals = 1) or (FRefusals mod 50 = 0) then
      LText := Format('Imagery: EOX is limiting requests (%s), so tiles now go at %.1f a ' +
        'second after a pause of %.0f s (%d refused so far)', [AWhy, FRate, FPauseMs / 1000,
         FRefusals]);
    FPauseMs := Min(FPauseMs * 2, IMAGERY_MAX_PAUSE_MS);
  finally
    FLock.Leave;
  end;
  if LText <> '' then
    AddMessage(LText);
end;

function TImageryService.DownloadOnce(AZoom, ARow, AColumn: Integer; out AStatus: Integer;
  out AWhy: string): TBytes;
var
  LClient: THTTPClient;
  LResponse: IHTTPResponse;
  LStream: TMemoryStream;
begin
  Result := nil;
  AStatus := 0;
  AWhy := '';
  LClient := THTTPClient.Create;
  LStream := TMemoryStream.Create;
  try
    LClient.UserAgent := IMAGERY_USER_AGENT;
    LClient.ConnectionTimeout := CONNECT_TIMEOUT_MS;
    LClient.ResponseTimeout := RESPONSE_TIMEOUT_MS;
    // EOX sends a busy service's requests to a "heavy load" page; not
    // followed, so it counts as a refusal rather than a broken tile
    LClient.HandleRedirects := False;
    try
      LResponse := LClient.Get(Format(IMAGERY_URL_FORMAT, [FLayer, AZoom, ARow, AColumn]),
        LStream);
      AStatus := LResponse.StatusCode;
      if AStatus <> 200 then
        AWhy := Format('%d %s', [AStatus, LResponse.StatusText])
      else
      begin
        SetLength(Result, LStream.Size);
        if LStream.Size > 0 then
        begin
          LStream.Position := 0;
          LStream.ReadBuffer(Result[0], LStream.Size);
        end;
        // A page instead of a tile: by its first bytes, which every JPEG
        // ($FF $D8) and PNG ($89 'P') starts with, whatever the headers say
        if (Length(Result) < 2) or not (((Result[0] = $FF) and (Result[1] = $D8)) or
           ((Result[0] = $89) and (Result[1] = $50))) then
        begin
          Result := nil;
          AStatus := 0;
          AWhy := 'a page instead of a tile';
        end;
      end;
    except
      on E: Exception do
      begin
        AStatus := 0;
        AWhy := E.Message.TrimRight(['.']);
      end;
    end;
  finally
    LStream.Free;
    LClient.Free;
  end;
end;

function TImageryService.Download(AId: Int64; AZoom, ARow, AColumn: Integer): TBytes;
var
  LTry, LStatus, LCount: Integer;
  LWhy: string;
begin
  for LTry := 1 to IMAGERY_TRIES do
  begin
    if not WaitForSlot(AId) then
      raise Exception.Create('No longer wanted');
    Result := DownloadOnce(AZoom, ARow, AColumn, LStatus, LWhy);
    if Length(Result) > 0 then
    begin
      Downloaded;
      Exit;
    end;
    // Not there at all: asking again will not help
    if LStatus = 404 then
      Break;
    // Refused, busy or no answer: slow down and try again
    Refused(LWhy);
    if not StillWanted(AId) then
      raise Exception.Create('No longer wanted');
  end;
  FLock.Enter;
  try
    Inc(FErrorCount);
    LCount := FErrorCount;
  finally
    FLock.Leave;
  end;
  if (LCount <= ERRORS_LOGGED) or (LCount mod 100 = 0) then
    AddMessage(Format('WARNING: imagery tile %s could not be downloaded (%s; %d tiles given ' +
      'up so far)', [TileKey(AZoom, ARow, AColumn), LWhy, LCount]));
  raise Exception.CreateFmt('Imagery tile %s could not be downloaded (%s)',
    [TileKey(AZoom, ARow, AColumn), LWhy]);
end;

function TImageryService.Decode(const ABytes: TBytes): TImageryTilePixels;
var
  LImage: ISkImage;
begin
  LImage := TSkImage.MakeFromEncoded(ABytes);
  if (LImage = nil) or (LImage.Width <> IMAGERY_TILE_PIXELS) or
     (LImage.Height <> IMAGERY_TILE_PIXELS) then
    raise Exception.Create('An imagery tile could not be decoded');
  SetLength(Result, IMAGERY_TILE_PIXELS * IMAGERY_TILE_PIXELS);
  // BGRA in memory is TAlphaColor's own layout ($AARRGGBB, little-endian)
  if not LImage.ReadPixels(TSkImageInfo.Create(IMAGERY_TILE_PIXELS, IMAGERY_TILE_PIXELS,
     TSkColorType.BGRA8888, TSkAlphaType.Unpremul), @Result[0],
     IMAGERY_TILE_PIXELS * SizeOf(TAlphaColor)) then
    raise Exception.Create('An imagery tile could not be decoded');
end;

function TImageryService.CacheFile(AZoom, ARow, AColumn: Integer): string;
begin
  if FCacheFolder = '' then
    Exit('');
  Result := TPath.Combine(TPath.Combine(TPath.Combine(FCacheFolder, IntToStr(AZoom)),
    IntToStr(ARow)), IntToStr(AColumn) + '.jpg');
end;

function TImageryService.CacheRead(const AFile: string): TBytes;
var
  LEntry: TImageryCacheEntry;
begin
  Result := nil;
  try
    if not TFile.Exists(AFile) then
      Exit;
    Result := TFile.ReadAllBytes(AFile);
    // Its time marks when it was last used, for trimming
    TFile.SetLastWriteTime(AFile, Now);
    FLock.Enter;
    try
      if FCacheFiles.TryGetValue(AFile, LEntry) then
      begin
        LEntry.Used := Now;
        FCacheFiles[AFile] := LEntry;
      end;
    finally
      FLock.Leave;
    end;
  except
    // Unreadable: downloaded again and written over
    Result := nil;
  end;
end;

procedure TImageryService.CacheWrite(const AFile: string; const ABytes: TBytes);
var
  LTemp: string;
  LEntry: TImageryCacheEntry;
  LOld: TImageryCacheEntry;
begin
  try
    ForceDirectories(TPath.GetDirectoryName(AFile));
    // Written whole, then renamed, so a half-written tile is never read
    LTemp := AFile + '.tmp';
    TFile.WriteAllBytes(LTemp, ABytes);
    if TFile.Exists(AFile) then
      TFile.Delete(AFile);
    TFile.Move(LTemp, AFile);
  except
    on E: Exception do
    begin
      AddMessage(Format('WARNING: an imagery tile could not be kept in %s (%s)',
        [FCacheFolder, E.Message.TrimRight(['.'])]));
      Exit;
    end;
  end;
  FLock.Enter;
  try
    LEntry.Size := Length(ABytes);
    LEntry.Used := Now;
    if FCacheFiles.TryGetValue(AFile, LOld) then
      Dec(FCacheBytes, LOld.Size);
    FCacheFiles.AddOrSetValue(AFile, LEntry);
    Inc(FCacheBytes, LEntry.Size);
    if FCacheScanned and (FCacheBytes > FCacheLimit) then
      TrimCache;
  finally
    FLock.Leave;
  end;
end;

procedure TImageryService.TrimCache;
var
  LFiles: TArray<TPair<string, TImageryCacheEntry>>;
  LTarget: Int64;
  LDeleted, I: Integer;
  LFreed: Int64;
begin
  LFiles := FCacheFiles.ToArray;
  TArray.Sort<TPair<string, TImageryCacheEntry>>(LFiles,
    TComparer<TPair<string, TImageryCacheEntry>>.Construct(
      function(const A, B: TPair<string, TImageryCacheEntry>): Integer
      begin
        Result := CompareValue(A.Value.Used, B.Value.Used);
      end));
  LTarget := Round(FCacheLimit * TRIM_TO);
  LDeleted := 0;
  LFreed := 0;
  I := 0;
  while (FCacheBytes > LTarget) and (I < Length(LFiles)) do
  begin
    try
      if TFile.Exists(LFiles[I].Key) then
        TFile.Delete(LFiles[I].Key);
      FCacheFiles.Remove(LFiles[I].Key);
      Dec(FCacheBytes, LFiles[I].Value.Size);
      Inc(LFreed, LFiles[I].Value.Size);
      Inc(LDeleted);
    except
      // In use or gone: left for the next trim
    end;
    Inc(I);
  end;
  if not FClosing then
    FMessages.Enqueue(Format('Imagery: the cache reached its limit of %d MB, so the %d tiles ' +
      'used least recently (%d MB) were deleted', [FCacheLimit div (1024 * 1024), LDeleted,
       LFreed div (1024 * 1024)]));
end;

procedure TImageryService.ScanCache;
var
  LFiles: TArray<string>;
  LFile: string;
  LEntry: TImageryCacheEntry;
  LFound: TDictionary<string, TImageryCacheEntry>;
  LPair: TPair<string, TImageryCacheEntry>;
  LWatch: TStopwatch;
begin
  LWatch := TStopwatch.StartNew;
  LFound := TDictionary<string, TImageryCacheEntry>.Create;
  try
    try
      if TDirectory.Exists(FCacheFolder) then
      begin
        LFiles := TDirectory.GetFiles(FCacheFolder, '*.*', TSearchOption.soAllDirectories);
        for LFile in LFiles do
        begin
          if FClosing then
            Exit;
          // Left over from a write that did not finish
          if LFile.EndsWith('.tmp', True) then
          begin
            try
              TFile.Delete(LFile);
            except
            end;
            Continue;
          end;
          LEntry.Size := TFile.GetSize(LFile);
          LEntry.Used := TFile.GetLastWriteTime(LFile);
          LFound.AddOrSetValue(LFile, LEntry);
        end;
      end;
    except
      on E: Exception do
        AddMessage(Format('WARNING: the imagery cache %s could not be measured (%s)',
          [FCacheFolder, E.Message.TrimRight(['.'])]));
    end;
    FLock.Enter;
    try
      // Files written while measuring are already counted
      for LPair in LFound do
        if not FCacheFiles.ContainsKey(LPair.Key) then
        begin
          FCacheFiles.Add(LPair.Key, LPair.Value);
          Inc(FCacheBytes, LPair.Value.Size);
        end;
      FCacheScanned := True;
      if not FClosing then
        FMessages.Enqueue(Format('Imagery: %s, %s; cache %s holds %d tiles, %d MB of %d MB ' +
          '(measured in %d ms)', [FLayer, ImageryLicence(FLayer), FCacheFolder,
           FCacheFiles.Count, FCacheBytes div (1024 * 1024), FCacheLimit div (1024 * 1024),
           LWatch.ElapsedMilliseconds]));
      if FCacheBytes > FCacheLimit then
        TrimCache;
    finally
      FLock.Leave;
    end;
  finally
    LFound.Free;
  end;
end;

end.
