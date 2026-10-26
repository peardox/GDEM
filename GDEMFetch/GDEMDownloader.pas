{ @abstract(Downloads ASTER GDEM V3 (ASTGTM.003) tiles from NASA Earthdata.)

  Each tile is a pair of GeoTIFF files: @code(_dem.tif) holds the elevations
  and @code(_num.tif) holds the quality and source information.

  A download happens in two steps:
  @orderedList(
    @item(NASA CMR, which is public and needs no login, is asked where the
      tile's files live. See @link(TCMRGranuleSearch).)
    @item(Each file is downloaded from Earthdata Cloud using an Earthdata
      Login bearer token.)
  )

  Redirects are followed by hand rather than by @code(THTTPClient) so that
  the @code(Authorization) header is only ever sent to NASA hosts. The last
  hop is a pre-signed AWS S3 or CloudFront URL, and S3 rejects a request
  that carries both a signature and a bearer header.

  The class is non-visual and uses only RTL units, so it works on every
  platform FMX supports. Its events are called on whichever thread runs the
  download; a GUI must marshal them to the main thread itself. }
unit GDEMDownloader;

interface

uses
  System.SysUtils, System.Classes, System.Net.HttpClient, System.Net.URLClient,
  GDEMCancel;

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

  { @abstract(Raised for any failure while finding or downloading a tile.) }
  EGDEMError = class(Exception);

  { @abstract(Raised when a download stops because
    @link(TGDEMDownloader.Cancel) was called or its
    @link(TGDEMDownloader.CancelToken) was cancelled.)

    It descends from @link(EOperationCancelled), like every other
    cancellation in the program, so callers can treat all of them alike. }
  EGDEMCancelled = class(EOperationCancelled);

  { @abstract(Finds and downloads ASTER GDEM V3 tiles.)

    Create one with a bearer token, set @link(OnLog) and @link(OnProgress)
    if wanted, then call @link(DownloadTile). An instance is not thread-safe;
    use one per thread. }
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
    { Byte count at the last progress event, used to throttle events. }
    FLastReported: Int64;
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

    { Passes a message to @link(OnLog) if it is assigned.
      @param(Msg The text to pass on.) }
    procedure Log(const Msg: string);

    { @code(THTTPClient.OnReceiveData) handler that turns raw progress into
      throttled @link(OnProgress) events.
      @param(Sender The HTTP client.)
      @param(AContentLength Expected size in bytes, or -1 if unknown.)
      @param(AReadCount Bytes read so far.)
      @param(AAbort Set to @true to cancel; never changed here.) }
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

    { Asks CMR for the download URLs of a granule's data files.
      @param(AGranule Granule name as returned by @link(TileGranuleName).)
      @returns(The https URLs of the @code(_dem.tif) and @code(_num.tif)
        files, @code(_dem.tif) first; empty if CMR has none.)
      @raises(EGDEMError if the CMR request fails.)
      @raises(ECMRError if the CMR response cannot be read.) }
    function FindTileURLs(const AGranule: string): TArray<string>;

    { Downloads one file, following redirects and sending the bearer token
      only to NASA hosts.

      The data is written to @code(ADestFile + '.part') and renamed only
      once it has been checked, so a failed download never leaves a
      broken file under the real name.

      @param(AURL Earthdata Cloud URL of the file.)
      @param(ADestFile Full path to save the file as. An existing file is
        replaced.)
      @returns(Size of the saved file in bytes.)
      @raises(EGDEMError if there is no token, the token is rejected, the
        server returns an error, or the data is not a TIFF.) }
    function DownloadFile(const AURL, ADestFile: string): Int64;

    { Finds and downloads both files of a tile. Files that already exist
      with a non-zero size are skipped.
      @param(ATile Tile name such as @code(N50W002).)
      @param(ADestFolder Folder to save into; created if missing.)
      @raises(EGDEMError if the tile name is invalid, CMR lists no files,
        or a download fails.) }
    procedure DownloadTile(const ATile, ADestFolder: string);

    { Like @link(DownloadTile), but treats a tile with no data as normal
      rather than an error. Use this when working through a selection of
      tiles, many of which may be ocean.
      @param(ATile Tile name such as @code(N50W002).)
      @param(ADestFolder Folder to save into; created if missing.)
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

    { Receives progress text. Called on the downloading thread. }
    property OnLog: TGDEMLogEvent read FOnLog write FOnLog;

    { Receives download progress, at most once per 256 KB. Called on the
      downloading thread. }
    property OnProgress: TGDEMProgressEvent read FOnProgress write FOnProgress;
  end;

implementation

uses
  System.IOUtils, System.StrUtils, System.Math, System.RegularExpressions,
  GDEMCMR;

const
  { Most redirects to follow before giving up on a download. }
  MAX_REDIRECTS = 10;
  { Smallest number of new bytes that triggers another progress event. }
  PROGRESS_STEP = 256 * 1024;
  { Host that Earthdata redirects to when a request is not authenticated. }
  EARTHDATA_LOGIN_HOST = 'urs.earthdata.nasa.gov';

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

procedure TGDEMDownloader.HandleReceiveData(const Sender: TObject; AContentLength,
  AReadCount: Int64; var AAbort: Boolean);
begin
  if IsCancelled then
  begin
    AAbort := True;
    Exit;
  end;
  if (FCurrentFile = '') or not Assigned(FOnProgress) then
    Exit;
  if (AReadCount - FLastReported >= PROGRESS_STEP) or (AReadCount = AContentLength) then
  begin
    FLastReported := AReadCount;
    FOnProgress(FCurrentFile, AReadCount, AContentLength);
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

function TGDEMDownloader.FindTileURLs(const AGranule: string): TArray<string>;
var
  LBody: TStringStream;
  LResp: IHTTPResponse;
  LSearch: TCMRGranuleSearch;
begin
  CheckCancelled;
  FCurrentFile := '';
  Log('Searching NASA CMR for ' + AGranule + ' ...');
  LBody := TStringStream.Create('', TEncoding.UTF8);
  try
    LResp := FClient.Get(TCMRGranuleSearch.SearchURL(AGranule), LBody);
    if LResp.StatusCode <> 200 then
      raise EGDEMError.CreateFmt('CMR search failed: HTTP %d %s',
        [LResp.StatusCode, LResp.StatusText]);
    LSearch := TCMRGranuleSearch.FromJSON(LBody.DataString);
  finally
    LBody.Free;
  end;

  Result := LSearch.DataFileURLs(['_dem.tif', '_num.tif']);
  Log(Format('  found %d file(s)', [Length(Result)]));
end;

function TGDEMDownloader.DownloadFile(const AURL, ADestFile: string): Int64;
var
  LTempFile, LURL, LLocation: string;
  LStream: TFileStream;
  LResp: IHTTPResponse;
  LHeaders: TNetHeaders;
  LCode, LHops: Integer;
begin
  if FToken = '' then
    raise EGDEMError.Create('No Earthdata bearer token supplied.');

  LTempFile := ADestFile + '.part';
  FCurrentFile := TPath.GetFileName(ADestFile);
  LURL := AURL;
  LHops := 0;
  LResp := nil;
  try
    LStream := TFileStream.Create(LTempFile, fmCreate);
    try
      repeat
        LStream.Size := 0;   // discard any redirect body from the last hop
        FLastReported := 0;

        if IsEarthdataHost(LURL) then
          LHeaders := [TNetHeader.Create('Authorization', 'Bearer ' + FToken)]
        else
          LHeaders := nil;   // never send the token to S3 or CloudFront

        CheckCancelled;
        Log('  GET ' + HostOf(LURL));
        try
          LResp := FClient.Get(LURL, LStream, LHeaders);
        except
          // An aborted transfer may surface as a network error
          CheckCancelled;
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
            raise EGDEMError.Create(
              'Redirected to the Earthdata Login page, so the bearer token was not accepted. ' +
              'It may be expired, revoked or mistyped, or LP DAAC is not yet authorised ' +
              'on your Earthdata account.');
          Log(Format('  -> %d redirect to %s', [LCode, HostOf(LURL)]));
          Continue;
        end;
        Break;
      until False;
    finally
      LStream.Free;
    end;

    if LCode <> 200 then
      raise EGDEMError.CreateFmt('HTTP %d %s'#13#10'%s',
        [LCode, LResp.StatusText, TEncoding.ANSI.GetString(ReadHead(LTempFile, 400))]);

    // A dropped connection can end a transfer early without an error
    if (LResp.ContentLength > 0) and (TFile.GetSize(LTempFile) <> LResp.ContentLength) then
      raise EGDEMError.CreateFmt('Download incomplete: received %d of %d bytes.',
        [TFile.GetSize(LTempFile), LResp.ContentLength]);

    if not LooksLikeTIFF(LTempFile) then
      raise EGDEMError.CreateFmt('Downloaded data is not a GeoTIFF (content type "%s"):'#13#10'%s',
        [LResp.MimeType, TEncoding.ANSI.GetString(ReadHead(LTempFile, 400))]);

    if TFile.Exists(ADestFile) then
      TFile.Delete(ADestFile);
    TFile.Move(LTempFile, ADestFile);
    Result := TFile.GetSize(ADestFile);
  except
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
    FCurrentFile := '';
    raise;
  end;
  FCurrentFile := '';
end;

procedure TGDEMDownloader.DownloadTile(const ATile, ADestFolder: string);
begin
  if not DownloadTileIfExists(ATile, ADestFolder) then
    raise EGDEMError.CreateFmt('CMR has no files for %s. The tile may be all ocean, ' +
      'or outside the 83N to 83S coverage.', [TileGranuleName(ATile)]);
end;

function TGDEMDownloader.DownloadTileIfExists(const ATile, ADestFolder: string): Boolean;
var
  LGranule, LURL, LFileName, LDest: string;
  LURLs: TArray<string>;
  LSize: Int64;
  LQuery: Integer;
begin
  LGranule := TileGranuleName(ATile);
  LURLs := FindTileURLs(LGranule);
  Result := Length(LURLs) > 0;
  if not Result then
    Exit;

  ForceDirectories(ADestFolder);
  for LURL in LURLs do
  begin
    LFileName := LURL.Substring(LURL.LastIndexOf('/') + 1);
    LQuery := LFileName.IndexOf('?');
    if LQuery >= 0 then
      LFileName := LFileName.Substring(0, LQuery);
    LDest := TPath.Combine(ADestFolder, LFileName);

    if TFile.Exists(LDest) and (TFile.GetSize(LDest) > 0) then
    begin
      Log('Already have ' + LFileName + ', skipping');
      Continue;
    end;

    Log('Downloading ' + LFileName);
    LSize := DownloadFile(LURL, LDest);
    Log(Format('  saved %s (%.1f MB)', [LDest, LSize / (1024 * 1024)]));
  end;
end;

end.
