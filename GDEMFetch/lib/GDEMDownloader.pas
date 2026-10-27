{ @abstract(Downloads ASTER GDEM V3 (ASTGTM.003) tiles from NASA Earthdata.)

  Each tile is a pair of GeoTIFF files: @code(_dem.tif) holds the elevations
  and @code(_num.tif) holds the quality and source information.

  A download happens in two steps:
  @orderedList(
    @item(NASA CMR, which is public and needs no login, is asked where the
      tiles' files live. For a batch, @link(TGDEMDownloader.LookUpTiles)
      lists every granule in the block the tiles cover, 2000 at a time, or
      for tiles scattered far apart asks about up to
      @link(CMR_NAMES_PER_REQUEST) by name in one request. See
      @link(TCMRGranuleSearch).)
    @item(Each file is downloaded from Earthdata Cloud using an Earthdata
      Login bearer token.)
  )

  Redirects are followed by hand rather than by @code(THTTPClient) so that
  the @code(Authorization) header is only ever sent to NASA hosts. The last
  hop is a pre-signed AWS S3 or CloudFront URL, and S3 rejects a request
  that carries both a signature and a bearer header.

  @bold(Coping with problems.) NASA limits how fast its servers are used,
  answering HTTP 429 ("Too Many Requests") when asked too often; the
  limit changes with load and is not published. Both CMR searches and file
  downloads wait for as long as NASA asks (its @code(Retry-After) header,
  or @link(DEFAULT_RATE_LIMIT_SECONDS)) and try again, up to
  @link(MAX_RATE_LIMIT_WAITS) times. Other passing problems, such as a
  dropped connection, a server error or an incomplete file, are tried
  @link(DOWNLOAD_ATTEMPTS) times. A rejected bearer token
  (@link(EGDEMAuthError)) is never retried, since trying again cannot help.

  The class is non-visual and uses only RTL units, so it works on every
  platform FMX supports. An instance is not thread-safe: to download
  several files at once, give each thread its own, sharing one
  @link(TCancelToken). Events are called on whichever thread runs the
  download; a GUI must marshal them to the main thread itself. }
unit GDEMDownloader;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Diagnostics,
  System.Net.HttpClient, System.Net.URLClient,
  GDEMCancel;

const
  { How many times a file download or CMR search is tried when it fails
    for a passing reason. }
  DOWNLOAD_ATTEMPTS = 3;
  { Pause after a failed try, in milliseconds, multiplied by the number of
    tries so far. }
  DOWNLOAD_RETRY_DELAY_MS = 2000;
  { How many times one request may be asked to slow down (HTTP 429 or 503)
    before giving up. }
  MAX_RATE_LIMIT_WAITS = 10;
  { How long to wait when asked to slow down without being told how long,
    in seconds. }
  DEFAULT_RATE_LIMIT_SECONDS = 10;
  { Longest wait to honour from a @code(Retry-After) header, in seconds. }
  MAX_RATE_LIMIT_SECONDS = 300;
  { How many tries that each got further than the last a file may have,
    on top of @link(DOWNLOAD_ATTEMPTS): a download cut off part-way
    carries on from where it stopped, and that is not held against it. }
  MAX_DOWNLOAD_RESUMES = 10;
  { Problems within @link(THROTTLE_WINDOW_MS) that make
    @link(TDownloadThrottle) halve the downloads allowed at once. }
  THROTTLE_PROBLEMS = 3;
  { The window over which @link(TDownloadThrottle) counts problems, in
    milliseconds. }
  THROTTLE_WINDOW_MS = 30000;
  { How long every download pauses after @link(TDownloadThrottle) cuts
    back, in milliseconds. }
  THROTTLE_PAUSE_MS = 5000;
  { Successful files in a row before @link(TDownloadThrottle) allows one
    more download at once, once NASA has objected at least once. Before
    then it allows one more after every good file. }
  THROTTLE_RAISE_SUCCESSES = 20;
  { How long after a cut-back @link(TDownloadThrottle) waits before
    allowing more downloads at once again, in milliseconds. }
  THROTTLE_RAISE_AFTER_MS = 60000;
  { How many tiles @link(TGDEMDownloader.LookUpTiles) asks CMR about in
    one request. Keeps the request's address well under the length CMR
    accepts. }
  CMR_NAMES_PER_REQUEST = 100;
  { @link(TGDEMDownloader.LookUpTiles) lists the whole block the tiles
    cover, rather than asking for them by name, when the block has fewer
    than this many one-degree cells for each tile wanted. A page of a block
    listing returns up to 2000 granules, against 100 tiles per request by
    name, and name searches (which use wildcards) are much slower for CMR
    to answer; 20 keeps the block listing the cheaper of the two even if
    every cell of the block had data. }
  CMR_BOX_CELLS_PER_TILE = 20;

type
  { Called with a line of progress text for the user.
    @param(Msg The text to show.) }
  TGDEMLogEvent = reference to procedure(const Msg: string);

  { Called repeatedly while a file downloads.
    @param(FileName Name of the file being downloaded, without its folder.)
    @param(Received Bytes received so far.)
    @param(Total Expected size in bytes, or a value of 0 or less if the
      server did not say.) }
  TGDEMProgressEvent = reference to procedure(const FileName: string; Received, Total: Int64);

  { Called as @link(TGDEMDownloader.LookUpTiles) works through its
    batches.
    @param(ABatch The batch about to be looked up, from 1.)
    @param(ABatches How many batches there are.) }
  TGDEMBatchEvent = reference to procedure(ABatch, ABatches: Integer);

  { @abstract(Raised for any failure while finding or downloading a tile.) }
  EGDEMError = class(Exception);

  { @abstract(Raised when NASA rejects the bearer token.)

    Trying again cannot help, so a batch of downloads should stop and ask
    the user for a new token. }
  EGDEMAuthError = class(EGDEMError);

  { @abstract(Raised inside @link(TGDEMDownloader) when NASA asks for
    requests to slow down; handled there by waiting and trying again.) }
  EGDEMRateLimited = class(EGDEMError)
  private
    { Backing field for @link(RetryAfter). }
    FRetryAfter: Integer;
  public
    { Creates the exception.
      @param(ASeconds How long NASA asked to wait, in seconds.) }
    constructor CreateWait(ASeconds: Integer);

    { How long NASA asked to wait, in seconds. }
    property RetryAfter: Integer read FRetryAfter;
  end;

  { @abstract(Raised when a download stops because
    @link(TGDEMDownloader.Cancel) was called or its
    @link(TGDEMDownloader.CancelToken) was cancelled.)

    It descends from @link(EOperationCancelled), like every other
    cancellation in the program, so callers can treat all of them alike. }
  EGDEMCancelled = class(EOperationCancelled);

  { @abstract(Shares connections out among several downloaders, and backs
    off when NASA objects.)

    One throttle is shared by every @link(TGDEMDownloader) in a batch (see
    @link(TGDEMDownloader.Throttle)). Each file download asks it for a turn
    first, so at most @link(Allowed) files download at once.

    NASA does not say how much it allows; it cuts off or refuses
    connections when it has had enough, and sometimes answers "slow down".
    So the throttle feels its way, as TCP does on a network (additive
    increase, multiplicative decrease):
    @unorderedList(
      @item(it begins at a modest number, and until NASA first objects,
        each good file allows one more at once, so a batch soon reaches the
        most allowed if all is well;)
      @item(a "slow down" pauses every download for as long as NASA asks;)
      @item(@link(THROTTLE_PROBLEMS) problems within
        @link(THROTTLE_WINDOW_MS) halve @link(Allowed), down to 1, and
        pause every download for @link(THROTTLE_PAUSE_MS);)
      @item(after a cut, it climbs back more carefully: one more at once
        after @link(THROTTLE_RAISE_SUCCESSES) good files in a row, and at
        least @link(THROTTLE_RAISE_AFTER_MS) since the last cut.)
    )
    @link(Allowed) never goes above the most given to @link(Create).
    All methods are thread-safe. }
  TDownloadThrottle = class
  private
    { Guards every field below. }
    FLock: TObject;
    { The most at once, which @link(Allowed) never exceeds. }
    FMax: Integer;
    { Backing field for @link(Allowed). }
    FAllowed: Integer;
    { Backing field for @link(Lowest). }
    FLowest: Integer;
    { Backing field for @link(Peak). }
    FPeak: Integer;
    { @true until the first cut: each good file then allows one more. }
    FSlowStart: Boolean;
    { Downloads under way. }
    FActive: Integer;
    { Clock for pauses and windows. }
    FClock: TStopwatch;
    { No new download starts before this time, in clock milliseconds. }
    FPauseUntil: Int64;
    { When the current problem-counting window began. }
    FWindowStart: Int64;
    { Problems in the current window. }
    FProblems: Integer;
    { Good files in a row. }
    FSuccesses: Integer;
    { When @link(Allowed) was last cut. }
    FLastCut: Int64;
    { Backing field for @link(OnLog). }
    FOnLog: TGDEMLogEvent;

    { The clock's reading.
      @returns(Milliseconds since the throttle was made.) }
    function Now: Int64;

    { Passes a message to @link(OnLog), outside the lock.
      @param(Msg The text.) }
    procedure Log(const Msg: string);

    { Reader for @link(Allowed).
      @returns(The current limit.) }
    function GetAllowed: Integer;

    { Reader for @link(Lowest).
      @returns(The lowest limit so far.) }
    function GetLowest: Integer;

    { Reader for @link(Peak).
      @returns(The highest limit so far.) }
    function GetPeak: Integer;
  public
    { Creates a throttle.
      @param(AStart Downloads allowed at once to begin with; kept between 1
        and AMax.)
      @param(AMax The most downloads ever allowed at once.) }
    constructor Create(AStart, AMax: Integer);

    { Frees the lock. }
    destructor Destroy; override;

    { Waits for a turn: until fewer than @link(Allowed) downloads are under
      way and no pause is in force. Every call must be matched by
      @link(Release).
      @param(ACancelled Asked several times a second whether to give up.)
      @raises(EGDEMCancelled if ACancelled returns @true while waiting.) }
    procedure Acquire(const ACancelled: TFunc<Boolean>);

    { Ends a turn begun by @link(Acquire). }
    procedure Release;

    { Records a file downloaded without trouble. }
    procedure ReportSuccess;

    { Records a failed download.
      @param(AWhy What went wrong, for the log.)
      @param(APauseMs How long every download should pause, in
        milliseconds; 0 for no pause unless the limit is cut.) }
    procedure ReportProblem(const AWhy: string; APauseMs: Integer);

    { How many files may download at once now. }
    property Allowed: Integer read GetAllowed;

    { The lowest @link(Allowed) has been after a cut, to report at the
      end; the same as @link(Peak) if NASA never objected. }
    property Lowest: Integer read GetLowest;

    { The highest @link(Allowed) has been, to report at the end. }
    property Peak: Integer read GetPeak;

    { Receives a line when @link(Allowed) first reaches the most, and each
      time it is cut or raised after a cut. Called on whichever thread
      caused it. }
    property OnLog: TGDEMLogEvent read FOnLog write FOnLog;
  end;

  { @abstract(Finds and downloads ASTER GDEM V3 tiles.)

    Create one with a bearer token, set @link(OnLog) and @link(OnProgress)
    if wanted, then call @link(DownloadTile), or @link(LookUpTiles) and
    @link(DownloadFiles) for a batch. An instance is not thread-safe; use
    one per thread. }
  TGDEMDownloader = class
  private
    { HTTP client used for every request. Automatic redirects are off. }
    FClient: THTTPClient;
    { Earthdata Login bearer token, trimmed. }
    FToken: string;
    { Backing field for @link(OnLog). }
    FOnLog: TGDEMLogEvent;
    { Backing field for @link(OnProgress). }
    FOnProgress: TGDEMProgressEvent;
    { Name of the file being downloaded; empty when no file download is in
      progress, which suppresses progress events for other requests. }
    FCurrentFile: string;
    { Byte count at the last progress event, used to throttle events;
      counted from the start of the file. }
    FLastReported: Int64;
    { Bytes of the file already on disk when the current request began,
      added to the request's own counts in progress events. }
    FResumeOffset: Int64;
    { @true while a request's data is the file itself, rather than a
      redirect, so progress is only reported for real data. }
    FProgressOn: Boolean;
    { Backing field for @link(Throttle). Not owned. }
    FThrottle: TDownloadThrottle;
    { Set by @link(Cancel) from any thread; checked between requests and
      while data arrives. }
    FCancelled: Boolean;
    { Backing field for @link(CancelToken). Not owned. }
    FCancelToken: TCancelToken;

    { Checks whether this downloader or its token has been cancelled.
      @returns(@true if work should stop.) }
    function IsCancelled: Boolean;

    { Raises @link(EGDEMCancelled) if @link(Cancel) has been called. }
    procedure CheckCancelled;

    { Waits, checking for cancellation four times a second.
      @param(AMilliseconds How long to wait.)
      @raises(EGDEMCancelled if cancelled while waiting.) }
    procedure Wait(AMilliseconds: Integer);

    { Passes a message to @link(OnLog) if it is assigned.
      @param(Msg The text to pass on.) }
    procedure Log(const Msg: string);

    { @code(THTTPClient.OnReceiveData) handler that turns raw progress into
      throttled @link(OnProgress) events, and aborts the transfer once
      cancelled.
      @param(Sender The HTTP client.)
      @param(AContentLength Expected size in bytes, or -1 if unknown.)
      @param(AReadCount Bytes read so far.)
      @param(AAbort Set to @true to stop the transfer.) }
    procedure HandleReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64;
      var AAbort: Boolean);

    { Extracts the host name from a URL.
      @param(AURL Any URL.)
      @returns(The host, or AURL itself if it cannot be parsed.) }
    class function HostOf(const AURL: string): string; static;

    { Decides whether a URL belongs to NASA Earthdata, and so may receive
      the bearer token.
      @param(AURL Any URL.)
      @returns(@true for hosts under @code(earthdata.nasa.gov) or
        @code(earthdatacloud.nasa.gov).) }
    class function IsEarthdataHost(const AURL: string): Boolean; static;

    { Turns a redirect's @code(Location) header into an absolute URL.
      @param(ABaseURL URL of the request that was redirected.)
      @param(ALocation Value of the @code(Location) header, absolute or
        relative.)
      @returns(The absolute URL to request next.) }
    class function ResolveLocation(const ABaseURL, ALocation: string): string; static;

    { Reads the first bytes of a file, for error messages and format checks.
      @param(AFileName File to read.)
      @param(AMaxBytes Largest number of bytes to return.)
      @returns(Up to AMaxBytes bytes; empty if the file does not exist.) }
    class function ReadHead(const AFileName: string; AMaxBytes: Integer): TBytes; static;

    { Checks whether a file starts like a TIFF: @code(II) for little-endian
      or @code(MM) for big-endian. An HTML login or error page fails this.
      @param(AFileName File to check.)
      @returns(@true if the file looks like a TIFF.) }
    class function LooksLikeTIFF(const AFileName: string): Boolean; static;

    { How long a slow-down response asks us to wait.
      @param(AResponse A response with status 429 or 503.)
      @returns(Seconds to wait: the @code(Retry-After) header if it gives a
        number, otherwise @link(DEFAULT_RATE_LIMIT_SECONDS), never more than
        @link(MAX_RATE_LIMIT_SECONDS).) }
    class function RetryAfterSeconds(const AResponse: IHTTPResponse): Integer; static;

    { Reads where a partial response starts, from its @code(Content-Range)
      header, such as @code(bytes 1000-1999/5000).
      @param(AHeader The header's value.)
      @returns(The first byte's position, or -1 if it cannot be read.) }
    class function ContentRangeStart(const AHeader: string): Int64; static;

    { Reads the start of a response body, for an error message.
      @param(AStream Holds the body.)
      @param(AFrom Where the body starts in AStream.)
      @returns(Up to 400 characters of it.) }
    class function StreamText(AStream: TStream; AFrom: Int64): string; static;

    { The file name at the end of a download URL, without any query.
      @param(AURL The URL.)
      @returns(For example @code(ASTGTMV003_N50W002_dem.tif).) }
    class function FileNameFromURL(const AURL: string): string; static;

    { Requests one page of CMR results, waiting when asked to slow down and
      trying again after passing failures.
      @param(AURL The search URL.)
      @param(ASearchAfter The @code(CMR-Search-After) value from the
        previous page; empty for the first page.)
      @param(ABody Receives the response body.)
      @returns(The response, always with status 200.)
      @raises(EGDEMError if CMR keeps failing.)
      @raises(EGDEMCancelled if cancelled.) }
    function GetCMRPage(const AURL, ASearchAfter: string; ABody: TStream): IHTTPResponse;

    { Downloads one file, once, with no retries; see @link(DownloadFile).

      If an earlier try was cut off part-way and AResume is @true, the part
      already in @code(ADestFile + '.part') is kept, and only the rest is
      asked for (an HTTP Range request). Should this try also be cut off,
      the part is kept again for the next; on any other failure it is
      deleted.

      @param(AURL Earthdata Cloud URL of the file.)
      @param(ADestFile Full path to save the file as.)
      @param(AResume @true to carry on from a part left by an earlier try;
        @false to start afresh.)
      @returns(Size of the saved file in bytes.)
      @raises(EGDEMAuthError if the bearer token is rejected.)
      @raises(EGDEMRateLimited if NASA asks us to slow down.)
      @raises(EGDEMError for any other failure.) }
    function DownloadOnce(const AURL, ADestFile: string; AResume: Boolean): Int64;
  public
    { Creates a downloader.
      @param(AToken Earthdata Login bearer token, generated at
        @url(https://urs.earthdata.nasa.gov). Surrounding spaces are
        removed.) }
    constructor Create(const AToken: string);

    { Frees the HTTP client. }
    destructor Destroy; override;

    { Converts a tile name to its ASTER GDEM V3 granule name.
      @param(ATile Tile name such as @code(N50W002) or
        @code(ASTGTMV003_N50W002), in any letter case.)
      @returns(The granule name, for example @code(ASTGTMV003_N50W002).)
      @raises(EGDEMError if ATile is not a valid tile name.) }
    class function TileGranuleName(const ATile: string): string; static;

    { Asks CMR for the download URLs of one granule's data files.
      @param(AGranule Granule name as returned by @link(TileGranuleName).)
      @returns(The https URLs of the @code(_dem.tif) and @code(_num.tif)
        files, @code(_dem.tif) first; empty if CMR has none.)
      @raises(EGDEMError if the CMR request keeps failing.)
      @raises(ECMRError if the CMR response cannot be read.) }
    function FindTileURLs(const AGranule: string): TArray<string>;

    { Asks CMR for the download URLs of many tiles, in one of two ways:
      @unorderedList(
        @item(When the tiles fill a good part of the block they lie in, as a
          selection on the map does, every granule in that block is listed,
          up to 2000 per request, and the ones wanted are kept. The whole
          world takes about a dozen requests this way.)
        @item(Otherwise, when they are few and far apart, they are asked
          for by name, @link(CMR_NAMES_PER_REQUEST) in each request.)
      )
      See @link(CMR_BOX_CELLS_PER_TILE) for the choice. Should a block
      listing find none of the tiles, they are asked for by name instead;
      should a search by name find nothing at all for several tiles, each
      is looked up on its own. So a CMR that does not understand a search
      costs time but never loses tiles.

      @param(ATiles Tile names such as @code(N50W002), in any letter case.)
      @param(AOnBatch Called before each request or batch, with how many
        there are thought to be; a block listing learns its page count from
        the first answer. May be @nil.)
      @returns(A new dictionary, which the caller frees, from each tile
        that has data, named as @code(TileName) names it (such as
        @code(N50W002)), to its file URLs. Tiles with no data are not in
        it.)
      @raises(EGDEMError if a tile name is invalid or CMR keeps failing.)
      @raises(EGDEMCancelled if cancelled.) }
    function LookUpTiles(const ATiles: TArray<string>;
      const AOnBatch: TGDEMBatchEvent): TDictionary<string, TArray<string>>;

    { Downloads one file, following redirects and sending the bearer token
      only to NASA hosts.

      The data is written to @code(ADestFile + '.part') and renamed only
      once it has been checked, so a failed download never leaves a
      broken file under the real name. When NASA asks us to slow down, the
      download waits and tries again; other passing failures are tried
      @link(DOWNLOAD_ATTEMPTS) times. A download cut off part-way carries
      on from where it stopped, and a try that got further than the last
      is not counted among those attempts (up to
      @link(MAX_DOWNLOAD_RESUMES) of them). With a @link(Throttle), the
      download waits its turn and reports how it went.

      @param(AURL Earthdata Cloud URL of the file.)
      @param(ADestFile Full path to save the file as. An existing file is
        replaced. Its folder must exist.)
      @returns(Size of the saved file in bytes.)
      @raises(EGDEMAuthError if the bearer token is rejected.)
      @raises(EGDEMError if there is no token, or the download keeps
        failing.)
      @raises(EGDEMCancelled if cancelled.) }
    function DownloadFile(const AURL, ADestFile: string): Int64;

    { Downloads files into a folder, skipping any that are already there
      with a non-zero size.
      @param(AURLs The files' URLs, as from @link(LookUpTiles).)
      @param(ADestFolder Folder to save into. It must exist; when several
        threads download into the same tree, create folders under a lock
        first.)
      @returns(Bytes downloaded.)
      @raises(EGDEMAuthError if the bearer token is rejected.)
      @raises(EGDEMError if a download keeps failing.)
      @raises(EGDEMCancelled if cancelled.) }
    function DownloadFiles(const AURLs: TArray<string>; const ADestFolder: string): Int64;

    { Finds and downloads both files of a tile. Files that already exist
      with a non-zero size are skipped.
      @param(ATile Tile name such as @code(N50W002).)
      @param(ADestFolder Folder to save into; created if missing.)
      @raises(EGDEMError if the tile name is invalid, CMR lists no files,
        or a download fails.) }
    procedure DownloadTile(const ATile, ADestFolder: string);

    { Like @link(DownloadTile), but treats a tile with no data as normal
      rather than an error. Use this when working through a selection of
      tiles one at a time, many of which may be ocean.
      @param(ATile Tile name such as @code(N50W002).)
      @param(ADestFolder Folder to save into; created if missing. Not safe
        if other threads may be creating the same folder.)
      @returns(@true if the tile exists (its files were downloaded or were
        already present); @false if CMR has no files for it.)
      @raises(EGDEMError if the tile name is invalid or a download fails.)
      @raises(EGDEMCancelled if @link(Cancel) was called.) }
    function DownloadTileIfExists(const ATile, ADestFolder: string): Boolean;

    { Asks a download in progress to stop as soon as possible. Safe to call
      from any thread. The downloading thread then raises
      @link(EGDEMCancelled), and no partly downloaded file is kept. }
    procedure Cancel;

    { @true once @link(Cancel) has been called or @link(CancelToken) has
      been cancelled. }
    property Cancelled: Boolean read IsCancelled;

    { An optional token shared with other work in the same job. Cancelling
      it stops the downloader just like @link(Cancel). Not owned; may be
      @nil. }
    property CancelToken: TCancelToken read FCancelToken write FCancelToken;

    { An optional throttle shared by every downloader in a batch; see
      @link(TDownloadThrottle). Not owned; may be @nil, for no limit. }
    property Throttle: TDownloadThrottle read FThrottle write FThrottle;

    { Receives progress text. Called on the downloading thread. }
    property OnLog: TGDEMLogEvent read FOnLog write FOnLog;

    { Receives download progress, at most once per 256 KB. Called on the
      downloading thread. }
    property OnProgress: TGDEMProgressEvent read FOnProgress write FOnProgress;
  end;

implementation

uses
  System.IOUtils, System.StrUtils, System.Math, System.RegularExpressions,
  GDEMCMR, GDEMTiles, GDEMReport;

const
  { Most redirects to follow before giving up on a download. }
  MAX_REDIRECTS = 10;
  { Smallest number of new bytes that triggers another progress event. }
  PROGRESS_STEP = 256 * 1024;
  { Host that Earthdata redirects to when a request is not authenticated. }
  EARTHDATA_LOGIN_HOST = 'urs.earthdata.nasa.gov';
  { The file name endings of a tile's two files. }
  TILE_FILE_SUFFIXES: array[0..1] of string = ('_dem.tif', '_num.tif');

{ EGDEMRateLimited }

constructor EGDEMRateLimited.CreateWait(ASeconds: Integer);
begin
  inherited CreateFmt('NASA asked for requests to slow down for %d s.', [ASeconds]);
  FRetryAfter := ASeconds;
end;

{ TDownloadThrottle }

constructor TDownloadThrottle.Create(AStart, AMax: Integer);
begin
  inherited Create;
  FLock := TObject.Create;
  FMax := Max(1, AMax);
  FAllowed := EnsureRange(AStart, 1, FMax);
  FPeak := FAllowed;
  // Only a cut sets the lowest; until then it follows the peak
  FLowest := MaxInt;
  FSlowStart := True;
  FClock := TStopwatch.StartNew;
  FPauseUntil := 0;
  FWindowStart := 0;
  FLastCut := -THROTTLE_RAISE_AFTER_MS;
end;

destructor TDownloadThrottle.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TDownloadThrottle.Now: Int64;
begin
  Result := FClock.ElapsedMilliseconds;
end;

procedure TDownloadThrottle.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

procedure TDownloadThrottle.Acquire(const ACancelled: TFunc<Boolean>);
begin
  repeat
    TMonitor.Enter(FLock);
    try
      if (FActive < FAllowed) and (Now >= FPauseUntil) then
      begin
        Inc(FActive);
        Exit;
      end;
    finally
      TMonitor.Exit(FLock);
    end;
    if Assigned(ACancelled) and ACancelled() then
      raise EGDEMCancelled.Create('Cancelled.');
    Sleep(100);
  until False;
end;

procedure TDownloadThrottle.Release;
begin
  TMonitor.Enter(FLock);
  try
    if FActive > 0 then
      Dec(FActive);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TDownloadThrottle.ReportSuccess;
var
  LMessage: string;
begin
  LMessage := '';
  TMonitor.Enter(FLock);
  try
    Inc(FSuccesses);
    if FAllowed < FMax then
      if FSlowStart then
      begin
        // NASA has not objected yet: one more for every good file
        Inc(FAllowed);
        FSuccesses := 0;
        if FAllowed = FMax then
          LMessage := Format('Downloads going well: now %d at a time, the most allowed',
            [FAllowed]);
      end
      else if (FSuccesses >= THROTTLE_RAISE_SUCCESSES) and
              (Now - FLastCut >= THROTTLE_RAISE_AFTER_MS) then
      begin
        // After a cut, win connections back slowly after a quiet spell
        Inc(FAllowed);
        FSuccesses := 0;
        LMessage := Format('Downloads going well again: now %d at a time', [FAllowed]);
      end;
    FPeak := Max(FPeak, FAllowed);
  finally
    TMonitor.Exit(FLock);
  end;
  if LMessage <> '' then
    Log(LMessage);
end;

procedure TDownloadThrottle.ReportProblem(const AWhy: string; APauseMs: Integer);
var
  LMessage: string;
  LNow: Int64;
begin
  LMessage := '';
  TMonitor.Enter(FLock);
  try
    LNow := Now;
    FSuccesses := 0;
    if APauseMs > 0 then
      FPauseUntil := Max(FPauseUntil, LNow + APauseMs);

    // Count problems in a sliding window, so one now and then is ignored
    if LNow - FWindowStart > THROTTLE_WINDOW_MS then
    begin
      FWindowStart := LNow;
      FProblems := 0;
    end;
    Inc(FProblems);
    if (FProblems >= THROTTLE_PROBLEMS) and (FAllowed > 1) then
    begin
      FAllowed := Max(1, FAllowed div 2);
      FLowest := Min(FLowest, FAllowed);
      FSlowStart := False;
      FProblems := 0;
      FWindowStart := LNow;
      FLastCut := LNow;
      FPauseUntil := Max(FPauseUntil, LNow + THROTTLE_PAUSE_MS);
      LMessage := Format('NASA is cutting off or refusing downloads (%s): now %d at a time',
        [AWhy.TrimRight(['.']), FAllowed]);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if LMessage <> '' then
    Log(LMessage);
end;

function TDownloadThrottle.GetAllowed: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FAllowed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TDownloadThrottle.GetLowest: Integer;
begin
  TMonitor.Enter(FLock);
  try
    if FLowest = MaxInt then
      Result := FPeak
    else
      Result := FLowest;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TDownloadThrottle.GetPeak: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FPeak;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TGDEMDownloader }

constructor TGDEMDownloader.Create(const AToken: string);
begin
  inherited Create;
  FToken := Trim(AToken);
  FClient := THTTPClient.Create;
  FClient.HandleRedirects := False;   // redirects are followed by hand
  FClient.AllowCookies := True;
  FClient.UserAgent := 'GDEMFetch/0.1 (Delphi FMX)';
  FClient.ConnectionTimeout := 30000;
  FClient.ResponseTimeout := 120000;
  FClient.OnReceiveData := HandleReceiveData;
end;

destructor TGDEMDownloader.Destroy;
begin
  FClient.Free;
  inherited;
end;

procedure TGDEMDownloader.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

procedure TGDEMDownloader.Cancel;
begin
  FCancelled := True;
end;

function TGDEMDownloader.IsCancelled: Boolean;
begin
  Result := FCancelled or ((FCancelToken <> nil) and FCancelToken.Cancelled);
end;

procedure TGDEMDownloader.CheckCancelled;
begin
  if IsCancelled then
    raise EGDEMCancelled.Create('Cancelled.');
end;

procedure TGDEMDownloader.Wait(AMilliseconds: Integer);
var
  LLeft: Integer;
begin
  LLeft := AMilliseconds;
  while LLeft > 0 do
  begin
    CheckCancelled;
    Sleep(Min(250, LLeft));
    Dec(LLeft, 250);
  end;
  CheckCancelled;
end;

procedure TGDEMDownloader.HandleReceiveData(const Sender: TObject; AContentLength,
  AReadCount: Int64; var AAbort: Boolean);
var
  LReceived, LTotal: Int64;
begin
  if IsCancelled then
  begin
    AAbort := True;
    Exit;
  end;
  if not FProgressOn or (FCurrentFile = '') or not Assigned(FOnProgress) then
    Exit;
  // Counted from the start of the file, including any part fetched earlier
  LReceived := FResumeOffset + AReadCount;
  if AContentLength > 0 then
    LTotal := FResumeOffset + AContentLength
  else
    LTotal := AContentLength;
  if (LReceived - FLastReported >= PROGRESS_STEP) or (AReadCount = AContentLength) then
  begin
    FLastReported := LReceived;
    FOnProgress(FCurrentFile, LReceived, LTotal);
  end;
end;

class function TGDEMDownloader.HostOf(const AURL: string): string;
begin
  try
    Result := TURI.Create(AURL).Host;
  except
    Result := AURL;
  end;
end;

class function TGDEMDownloader.IsEarthdataHost(const AURL: string): Boolean;
var
  LHost: string;
begin
  LHost := LowerCase(HostOf(AURL));
  Result := LHost.EndsWith('.earthdata.nasa.gov') or LHost.EndsWith('.earthdatacloud.nasa.gov');
end;

class function TGDEMDownloader.ResolveLocation(const ABaseURL, ALocation: string): string;
var
  LBase: TURI;
begin
  if StartsText('http://', ALocation) or StartsText('https://', ALocation) then
    Exit(ALocation);
  LBase := TURI.Create(ABaseURL);
  if ALocation.StartsWith('/') then
    Result := LBase.Scheme + '://' + LBase.Host + ALocation
  else
    Result := ABaseURL.Substring(0, ABaseURL.LastIndexOf('/') + 1) + ALocation;
end;

class function TGDEMDownloader.ReadHead(const AFileName: string; AMaxBytes: Integer): TBytes;
var
  LStream: TFileStream;
begin
  Result := nil;
  if not TFile.Exists(AFileName) then
    Exit;
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Min(Int64(AMaxBytes), LStream.Size));
    if Length(Result) > 0 then
      LStream.Read(Result, Length(Result));
  finally
    LStream.Free;
  end;
end;

class function TGDEMDownloader.LooksLikeTIFF(const AFileName: string): Boolean;
var
  LHead: TBytes;
begin
  LHead := ReadHead(AFileName, 4);
  Result := (Length(LHead) = 4) and
    (((LHead[0] = Ord('I')) and (LHead[1] = Ord('I'))) or
     ((LHead[0] = Ord('M')) and (LHead[1] = Ord('M'))));
end;

class function TGDEMDownloader.RetryAfterSeconds(const AResponse: IHTTPResponse): Integer;
begin
  // Retry-After may also be a date; anything but a number gets the default
  Result := StrToIntDef(Trim(AResponse.HeaderValue['Retry-After']), DEFAULT_RATE_LIMIT_SECONDS);
  Result := EnsureRange(Result, 1, MAX_RATE_LIMIT_SECONDS);
end;

class function TGDEMDownloader.ContentRangeStart(const AHeader: string): Int64;
var
  LMatch: TMatch;
begin
  LMatch := TRegEx.Match(AHeader, '^\s*bytes\s+(\d+)\s*-', [roIgnoreCase]);
  if LMatch.Success then
    Result := StrToInt64Def(LMatch.Groups[1].Value, -1)
  else
    Result := -1;
end;

class function TGDEMDownloader.StreamText(AStream: TStream; AFrom: Int64): string;
var
  LBytes: TBytes;
begin
  AStream.Position := AFrom;
  SetLength(LBytes, Min(Int64(400), Max(Int64(0), AStream.Size - AFrom)));
  if Length(LBytes) > 0 then
    AStream.ReadBuffer(LBytes, Length(LBytes));
  Result := TEncoding.ANSI.GetString(LBytes);
end;

class function TGDEMDownloader.FileNameFromURL(const AURL: string): string;
var
  LQuery: Integer;
begin
  Result := AURL.Substring(AURL.LastIndexOf('/') + 1);
  LQuery := Result.IndexOf('?');
  if LQuery >= 0 then
    Result := Result.Substring(0, LQuery);
end;

class function TGDEMDownloader.TileGranuleName(const ATile: string): string;
var
  LTile: string;
begin
  LTile := UpperCase(Trim(ATile));
  if LTile.StartsWith(ASTGTM_GRANULE_PREFIX) then
    LTile := LTile.Substring(Length(ASTGTM_GRANULE_PREFIX));
  if not TRegEx.IsMatch(LTile, '^[NS]\d{2}[EW]\d{3}$') then
    raise EGDEMError.CreateFmt('"%s" is not a tile name. Use the form N50W002.', [ATile]);
  Result := ASTGTM_GRANULE_PREFIX + LTile;
end;

function TGDEMDownloader.GetCMRPage(const AURL, ASearchAfter: string;
  ABody: TStream): IHTTPResponse;
var
  LHeaders: TNetHeaders;
  LAttempt, LRateWaits, LWait: Integer;
  LProblem: string;
begin
  if ASearchAfter <> '' then
    LHeaders := [TNetHeader.Create(CMR_SEARCH_AFTER_HEADER, ASearchAfter)]
  else
    LHeaders := nil;
  FCurrentFile := '';
  LAttempt := 0;
  LRateWaits := 0;
  repeat
    CheckCancelled;
    ABody.Size := 0;
    LProblem := '';
    try
      Result := FClient.Get(AURL, ABody, LHeaders);
    except
      on E: Exception do
      begin
        CheckCancelled;
        // The message may hold the address with its query string
        LProblem := HideURLQueries(E.Message);
        Result := nil;
      end;
    end;

    if Result <> nil then
    begin
      if (Result.StatusCode = 429) or (Result.StatusCode = 503) then
      begin
        Inc(LRateWaits);
        if LRateWaits > MAX_RATE_LIMIT_WAITS then
          raise EGDEMError.CreateFmt('NASA CMR kept asking us to slow down (%d times). ' +
            'Try again later.', [MAX_RATE_LIMIT_WAITS]);
        LWait := RetryAfterSeconds(Result);
        Log(Format('  NASA CMR asked us to slow down; waiting %d s', [LWait]));
        Wait(LWait * 1000);
        Continue;
      end;
      if Result.StatusCode = 200 then
      begin
        if not SameText(Result.HeaderValue[CMR_TIMEOUT_HEADER], 'true') then
          Exit;
        LProblem := 'the search timed out and returned partial results';
      end
      else if Result.StatusCode >= 500 then
        LProblem := Format('HTTP %d %s', [Result.StatusCode, Result.StatusText])
      else
        // A 4xx other than 429 is a mistake in the request; trying again won't help
        raise EGDEMError.CreateFmt('CMR search failed: HTTP %d %s',
          [Result.StatusCode, Result.StatusText]);
    end;

    Inc(LAttempt);
    if LAttempt >= DOWNLOAD_ATTEMPTS then
      raise EGDEMError.CreateFmt('Could not search NASA CMR after %d tries: %s',
        [LAttempt, LProblem]);
    Log(Format('  NASA CMR search failed (%s); trying again', [LProblem]));
    Wait(DOWNLOAD_RETRY_DELAY_MS * LAttempt);
  until False;
end;

function TGDEMDownloader.FindTileURLs(const AGranule: string): TArray<string>;
var
  LBody: TStringStream;
  LSearch: TCMRGranuleSearch;
begin
  CheckCancelled;
  Log('Searching NASA CMR for ' + AGranule + ' ...');
  LBody := TStringStream.Create('', TEncoding.UTF8);
  try
    GetCMRPage(TCMRGranuleSearch.SearchURL(AGranule), '', LBody);
    LSearch := TCMRGranuleSearch.FromJSON(LBody.DataString);
  finally
    LBody.Free;
  end;

  Result := LSearch.DataFileURLs(TILE_FILE_SUFFIXES);
  Log(Format('  found %d file(s)', [Length(Result)]));
end;

function TGDEMDownloader.LookUpTiles(const ATiles: TArray<string>;
  const AOnBatch: TGDEMBatchEvent): TDictionary<string, TArray<string>>;
var
  // The dictionary returned; named so the nested routines can reach it
  LResult: TDictionary<string, TArray<string>>;
  LWanted: TDictionary<string, Boolean>;
  LTile: string;
  LSouth, LWest, LMinS, LMaxS, LMinW, LMaxW: Integer;
  LCells: Int64;

  { Fetches every page of a search, keeping the tiles in LWanted that have
    data files. Stops at a page that is not full, so the empty page CMR
    would otherwise send last is never asked for.
    @param(AURL The search URL.)
    @param(ABoxPages @true to report each page through AOnBatch, working
      out the page count from the CMR-Hits header.)
    @returns(How many wanted tiles were found.) }
  function FetchAll(const AURL: string; ABoxPages: Boolean): Integer;
  var
    LBody: TStringStream;
    LResp: IHTTPResponse;
    LSearch: TCMRGranuleSearch;
    LGranule: TCMRGranule;
    LURLs: TArray<string>;
    LSearchAfter, LName: string;
    LPage, LPages, LS, LW, LEntries: Integer;
    LHits: Int64;
  begin
    Result := 0;
    LSearchAfter := '';
    LPage := 0;
    LPages := 1;
    LBody := TStringStream.Create('', TEncoding.UTF8);
    try
      repeat
        Inc(LPage);
        if ABoxPages and Assigned(AOnBatch) then
          AOnBatch(LPage, Max(LPage, LPages));
        LResp := GetCMRPage(AURL, LSearchAfter, LBody);
        if (LPage = 1) and TryStrToInt64(LResp.HeaderValue[CMR_HITS_HEADER], LHits) then
          LPages := Max(1, Integer((LHits + CMR_MAX_PAGE_SIZE - 1) div CMR_MAX_PAGE_SIZE));
        LSearch := TCMRGranuleSearch.FromJSON(LBody.DataString);
        LEntries := Length(LSearch.Feed.Entry);
        for LGranule in LSearch.Feed.Entry do
          if TryParseTileName(LGranule.Title, LS, LW) or
             TryParseTileName(LGranule.ProducerGranuleId, LS, LW) then
          begin
            LName := TileName(LS, LW);
            if not LWanted.ContainsKey(LName) or LResult.ContainsKey(LName) then
              Continue;
            LURLs := LGranule.DataFileURLs(TILE_FILE_SUFFIXES);
            if Length(LURLs) > 0 then
            begin
              LResult.Add(LName, LURLs);
              Inc(Result);
            end;
          end;
        if ABoxPages then
          Log(Format('  page %d of %d: %d granule(s)', [LPage, LPages, LEntries]));
        LSearchAfter := LResp.HeaderValue[CMR_SEARCH_AFTER_HEADER];
      until (LEntries < CMR_MAX_PAGE_SIZE) or (LSearchAfter = '');
    finally
      LBody.Free;
    end;
  end;

  { Looks the tiles up by name, @link(CMR_NAMES_PER_REQUEST) at a time,
    falling back to one at a time for a batch where nothing is found.
    @param(ANames The tile names to look up.) }
  procedure ByName(const ANames: TArray<string>);
  var
    LBatches, LBatch, LFrom, LCount, LIndex, LFound, LS, LW: Integer;
    LNames: TArray<string>;
    LURLs: TArray<string>;
  begin
    LBatches := (Length(ANames) + CMR_NAMES_PER_REQUEST - 1) div CMR_NAMES_PER_REQUEST;
    for LBatch := 0 to LBatches - 1 do
    begin
      CheckCancelled;
      LFrom := LBatch * CMR_NAMES_PER_REQUEST;
      LCount := Min(CMR_NAMES_PER_REQUEST, Length(ANames) - LFrom);
      SetLength(LNames, LCount);
      for LIndex := 0 to LCount - 1 do
        LNames[LIndex] := TileGranuleName(ANames[LFrom + LIndex]);
      if Assigned(AOnBatch) then
        AOnBatch(LBatch + 1, LBatches);
      Log(Format('Asking NASA CMR about %d tile(s) by name (batch %d of %d) ...',
        [LCount, LBatch + 1, LBatches]));

      LFound := FetchAll(TCMRGranuleSearch.NamesURL(LNames), False);
      if (LFound = 0) and (LCount > 1) then
      begin
        // Either all ocean, or CMR did not take the names together: ask
        // about each one so no tile is missed
        Log('  the combined search found nothing; asking about each tile in turn');
        for LIndex := 0 to LCount - 1 do
        begin
          LURLs := FindTileURLs(LNames[LIndex]);
          if (Length(LURLs) > 0) and TryParseTileName(LNames[LIndex], LS, LW) then
          begin
            LResult.AddOrSetValue(TileName(LS, LW), LURLs);
            Inc(LFound);
          end;
        end;
      end;
      Log(Format('  %d of %d tile(s) have data', [LFound, LCount]));
    end;
  end;

begin
  LResult := TDictionary<string, TArray<string>>.Create;
  Result := LResult;
  LWanted := TDictionary<string, Boolean>.Create;
  try
    try
      // Validate and tidy the names, and find the block they lie in
      LMinS := MaxInt;
      LMaxS := -MaxInt;
      LMinW := MaxInt;
      LMaxW := -MaxInt;
      for LTile in ATiles do
      begin
        TileGranuleName(LTile);
        TryParseTileName(LTile, LSouth, LWest);
        LWanted.AddOrSetValue(TileName(LSouth, LWest), True);
        LMinS := Min(LMinS, LSouth);
        LMaxS := Max(LMaxS, LSouth);
        LMinW := Min(LMinW, LWest);
        LMaxW := Max(LMaxW, LWest);
      end;
      if LWanted.Count = 0 then
        Exit;

      // A selection that crosses 180 degrees spans the whole width here,
      // which only makes the block listing less likely to be chosen
      LCells := Int64(LMaxS - LMinS + 1) * (LMaxW - LMinW + 1);
      if LCells < Int64(LWanted.Count) * CMR_BOX_CELLS_PER_TILE then
      begin
        Log(Format('Asking NASA CMR for every tile from %s to %s ' +
          '(%d tile(s) wanted) ...', [TileName(LMinS, LMinW), TileName(LMaxS, LMaxW),
          LWanted.Count]));
        if FetchAll(TCMRGranuleSearch.BoxURL(LMinW, LMinS, LMaxW + 1, LMaxS + 1), True) > 0 then
        begin
          Log(Format('  %d of %d tile(s) have data', [LResult.Count, LWanted.Count]));
          Exit;
        end;
        Log('  the block search found none of them; asking by name instead');
      end;
      ByName(LWanted.Keys.ToArray);
    except
      LResult.Free;
      raise;
    end;
  finally
    LWanted.Free;
  end;
end;

function TGDEMDownloader.DownloadOnce(const AURL, ADestFile: string; AResume: Boolean): Int64;
var
  LTempFile, LURL, LLocation, LNote: string;
  LFile: TFileStream;
  LMemory: TMemoryStream;
  LResp: IHTTPResponse;
  LHeaders: TNetHeaders;
  LCode, LHops: Integer;
  LOffset, LExpected: Int64;
  LToFile, LKeepPart: Boolean;
begin
  LTempFile := ADestFile + '.part';
  if not AResume and TFile.Exists(LTempFile) then
    TFile.Delete(LTempFile);
  FCurrentFile := TPath.GetFileName(ADestFile);
  LURL := AURL;
  LHops := 0;
  LResp := nil;
  LKeepPart := False;
  LMemory := TMemoryStream.Create;
  try
    try
      if TFile.Exists(LTempFile) then
        LFile := TFileStream.Create(LTempFile, fmOpenReadWrite or fmShareDenyWrite)
      else
        LFile := TFileStream.Create(LTempFile, fmCreate);
      try
        // What an earlier, cut-off try already fetched
        LOffset := LFile.Size;

        repeat
          // NASA's own hosts get the token and answer with a redirect, kept
          // in memory; the last hop (S3 or CloudFront) gets no token, and
          // its data goes straight into the file
          LToFile := not IsEarthdataHost(LURL);
          if LToFile then
          begin
            LFile.Size := LOffset;   // drop anything from a failed hop
            LFile.Position := LOffset;
            if LOffset > 0 then
              LHeaders := [TNetHeader.Create('Range', Format('bytes=%d-', [LOffset]))]
            else
              LHeaders := nil;
          end
          else
          begin
            LMemory.Clear;
            LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + FToken)];
          end;
          FProgressOn := LToFile;
          FResumeOffset := LOffset;
          FLastReported := LOffset;

          CheckCancelled;
          LNote := '';
          if LToFile and (LOffset > 0) then
            LNote := Format(' (resuming at %.1f MB)', [LOffset / (1024 * 1024)]);
          Log('  GET ' + HostOf(LURL) + LNote);
          try
            if LToFile then
              LResp := FClient.Get(LURL, LFile, LHeaders)
            else
              LResp := FClient.Get(LURL, LMemory, LHeaders);
          except
            // An aborted transfer may surface as a network error
            CheckCancelled;
            // A connection dropped during the file itself: what arrived is
            // good, so the next try carries on from there
            LKeepPart := LToFile;
            raise;
          end;
          // An aborted transfer may also return normally with partial data
          CheckCancelled;
          LCode := LResp.StatusCode;

          if (LCode = 301) or (LCode = 302) or (LCode = 303) or (LCode = 307) or (LCode = 308) then
          begin
            Inc(LHops);
            if LHops > MAX_REDIRECTS then
              raise EGDEMError.Create('Too many redirects.');
            LLocation := LResp.HeaderValue['Location'];
            if LLocation = '' then
              raise EGDEMError.CreateFmt('HTTP %d redirect with no Location header.', [LCode]);
            LURL := ResolveLocation(LURL, LLocation);
            if SameText(HostOf(LURL), EARTHDATA_LOGIN_HOST) then
              raise EGDEMAuthError.Create(
                'Redirected to the Earthdata Login page, so the bearer token was not accepted. ' +
                'It may be expired, revoked or mistyped, or LP DAAC is not yet authorised ' +
                'on your Earthdata account. Generate a new token and enter it in ' +
                'File > Settings.');
            Log(Format('  -> %d redirect to %s', [LCode, HostOf(LURL)]));
            Continue;
          end;
          Break;
        until False;

        if (LCode = 429) or (LCode = 503) then
        begin
          // Keep what earlier tries fetched, without this answer's body
          if LToFile then
          begin
            LFile.Size := LOffset;
            LKeepPart := LOffset > 0;
          end;
          raise EGDEMRateLimited.CreateWait(RetryAfterSeconds(LResp));
        end;

        if not LToFile then
        begin
          if LCode = 401 then
            raise EGDEMAuthError.Create('NASA rejected the bearer token (HTTP 401). It may ' +
              'be expired or revoked. Generate a new token and enter it in File > Settings.');
          if LCode <> 200 then
            raise EGDEMError.CreateFmt('HTTP %d %s'#13#10'%s',
              [LCode, LResp.StatusText, StreamText(LMemory, 0)]);
          // NASA sent the file itself rather than a redirect
          LFile.Size := 0;
          LFile.CopyFrom(LMemory, 0);
          LExpected := LMemory.Size;
        end
        else if LCode = 206 then
        begin
          // The rest of a file that was cut off earlier
          if ContentRangeStart(LResp.HeaderValue['Content-Range']) <> LOffset then
            raise EGDEMError.Create('the server resumed from the wrong place');
          if LResp.ContentLength > 0 then
            LExpected := LOffset + LResp.ContentLength
          else
            LExpected := -1;
        end
        else if LCode = 200 then
        begin
          // The server sent the whole file rather than the rest; it was
          // written after the old part, so start again from nothing
          if LOffset > 0 then
            raise EGDEMError.Create('the server could not resume the download');
          LExpected := LResp.ContentLength;
        end
        else
        begin
          // An error from the last hop, such as an expired signature; the
          // next try asks NASA for a fresh one, and can still carry on
          // from what earlier tries fetched
          LNote := StreamText(LFile, LOffset);
          LFile.Size := LOffset;
          LKeepPart := LOffset > 0;
          raise EGDEMError.CreateFmt('HTTP %d %s'#13#10'%s', [LCode, LResp.StatusText, LNote]);
        end;

        // A dropped connection can end a transfer early without an error
        if (LExpected > 0) and (LFile.Size <> LExpected) then
        begin
          LKeepPart := True;
          raise EGDEMError.CreateFmt('Download incomplete: received %d of %d bytes.',
            [LFile.Size, LExpected]);
        end;
      finally
        LFile.Free;
      end;

      if not LooksLikeTIFF(LTempFile) then
        raise EGDEMError.CreateFmt('Downloaded data is not a GeoTIFF (content type "%s"):'#13#10'%s',
          [LResp.MimeType, TEncoding.ANSI.GetString(ReadHead(LTempFile, 400))]);

      if TFile.Exists(ADestFile) then
        TFile.Delete(ADestFile);
      TFile.Move(LTempFile, ADestFile);
      Result := TFile.GetSize(ADestFile);
    except
      on E: Exception do
      begin
        if (not LKeepPart or (E is EOperationCancelled)) and TFile.Exists(LTempFile) then
          TFile.Delete(LTempFile);
        FCurrentFile := '';
        FProgressOn := False;
        raise;
      end;
    end;
  finally
    LMemory.Free;
  end;
  FCurrentFile := '';
  FProgressOn := False;
end;

function TGDEMDownloader.DownloadFile(const AURL, ADestFile: string): Int64;
var
  LFailures, LResumes, LRateWaits, LWaitMs: Integer;
  LName, LTempFile, LProblem: string;
  LBefore, LAfter: Int64;
  LCancelled: TFunc<Boolean>;
begin
  if FToken = '' then
    raise EGDEMError.Create('No Earthdata bearer token supplied.');

  LName := TPath.GetFileName(ADestFile);
  LTempFile := ADestFile + '.part';
  LFailures := 0;
  LResumes := 0;
  LRateWaits := 0;
  LCancelled :=
    function: Boolean
    begin
      Result := IsCancelled;
    end;
  try
    repeat
      // No pause before the next try unless a handler below asks for one
      LWaitMs := 0;
      if TFile.Exists(LTempFile) then
        LBefore := TFile.GetSize(LTempFile)
      else
        LBefore := 0;

      if FThrottle <> nil then
        FThrottle.Acquire(LCancelled);
      try
        try
          // The first try starts afresh; later ones carry on from any part
          Result := DownloadOnce(AURL, ADestFile, (LFailures + LResumes + LRateWaits) > 0);
        finally
          if FThrottle <> nil then
            FThrottle.Release;
        end;
        if FThrottle <> nil then
          FThrottle.ReportSuccess;
        Exit;
      except
        on E: EOperationCancelled do
          raise;
        on E: EGDEMAuthError do
          raise;
        on E: EGDEMRateLimited do
        begin
          // Every worker pauses, through the throttle when there is one;
          // without one, this download waits by itself
          if FThrottle <> nil then
            FThrottle.ReportProblem('NASA asked us to slow down', E.RetryAfter * 1000)
          else
            LWaitMs := E.RetryAfter * 1000;
          Log(Format('  NASA asked us to slow down; waiting %d s before trying %s again',
            [E.RetryAfter, LName]));
          Inc(LRateWaits);
          if LRateWaits > MAX_RATE_LIMIT_WAITS then
            raise EGDEMError.CreateFmt('NASA kept asking us to slow down while ' +
              'downloading %s. Try a slower download speed in File > Settings, or try again later',
              [LName]);
        end;
        on E: Exception do
        begin
          CheckCancelled;
          // Some platforms put the signed download address in the message;
          // its query string holds the user name and signature
          LProblem := HideURLQueries(E.Message).TrimRight(['.']);
          if FThrottle <> nil then
            FThrottle.ReportProblem(LProblem, 0);
          if TFile.Exists(LTempFile) then
            LAfter := TFile.GetSize(LTempFile)
          else
            LAfter := 0;
          // A try that got further than the last is not held against the
          // file, up to a point
          if (LAfter > LBefore) and (LResumes < MAX_DOWNLOAD_RESUMES) then
            Inc(LResumes)
          else
            Inc(LFailures);
          if LFailures >= DOWNLOAD_ATTEMPTS then
            raise EGDEMError.CreateFmt('Could not download %s after %d tries: %s',
              [LName, LFailures + LResumes, LProblem]);
          Log(Format('  downloading %s failed (%s); trying again',
            [LName, LProblem]));
          LWaitMs := DOWNLOAD_RETRY_DELAY_MS * LFailures;
        end;
      end;
      // Wait outside the handler, so the exception has been freed
      if LWaitMs > 0 then
        Wait(LWaitMs);
    until False;
  except
    // Giving up, or cancelled: no part file is left behind
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
    raise;
  end;
end;

function TGDEMDownloader.DownloadFiles(const AURLs: TArray<string>;
  const ADestFolder: string): Int64;
var
  LURL, LFileName, LDest: string;
  LSize: Int64;
begin
  Result := 0;
  for LURL in AURLs do
  begin
    CheckCancelled;
    LFileName := FileNameFromURL(LURL);
    LDest := TPath.Combine(ADestFolder, LFileName);

    if TFile.Exists(LDest) and (TFile.GetSize(LDest) > 0) then
    begin
      Log('Already have ' + LFileName + ', skipping');
      Continue;
    end;

    Log('Downloading ' + LFileName);
    LSize := DownloadFile(LURL, LDest);
    Inc(Result, LSize);
    Log(Format('  saved %s (%.1f MB)', [LDest, LSize / (1024 * 1024)]));
  end;
end;

procedure TGDEMDownloader.DownloadTile(const ATile, ADestFolder: string);
begin
  if not DownloadTileIfExists(ATile, ADestFolder) then
    raise EGDEMError.CreateFmt('CMR has no files for %s. The tile may be all ocean, ' +
      'or outside the 83N to 83S coverage.', [TileGranuleName(ATile)]);
end;

function TGDEMDownloader.DownloadTileIfExists(const ATile, ADestFolder: string): Boolean;
var
  LURLs: TArray<string>;
begin
  LURLs := FindTileURLs(TileGranuleName(ATile));
  Result := Length(LURLs) > 0;
  if not Result then
    Exit;
  ForceDirectories(ADestFolder);
  DownloadFiles(LURLs, ADestFolder);
end;

end.
