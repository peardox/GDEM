unit GDEMDownloader;

{ Non-visual downloader for ASTER GDEM V3 (ASTGTM.003) tiles.

  Step 1: ask NASA CMR (public, no login) where the tile's files live.
  Step 2: download each file from Earthdata Cloud using an Earthdata Login
          bearer token.

  Redirects are followed by hand rather than by THTTPClient so the
  Authorization header is only ever sent to NASA hosts. The final hop is a
  pre-signed AWS S3/CloudFront URL, and S3 rejects a request that carries
  both a signature and a Bearer header. }

interface

uses
  System.SysUtils, System.Classes, System.Net.HttpClient, System.Net.URLClient;

type
  TGDEMLogEvent = reference to procedure(const Msg: string);
  TGDEMProgressEvent = reference to procedure(const FileName: string; Received, Total: Int64);

  EGDEMError = class(Exception);

  TGDEMDownloader = class
  private
    FClient: THTTPClient;
    FToken: string;
    FOnLog: TGDEMLogEvent;
    FOnProgress: TGDEMProgressEvent;
    FCurrentFile: string;
    FLastReported: Int64;
    procedure Log(const Msg: string);
    procedure HandleReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64;
      var AAbort: Boolean);
    class function HostOf(const AURL: string): string; static;
    class function IsEarthdataHost(const AURL: string): Boolean; static;
    class function ResolveLocation(const ABaseURL, ALocation: string): string; static;
    class function ReadHead(const AFileName: string; AMaxBytes: Integer): TBytes; static;
  public
    constructor Create(const AToken: string);
    destructor Destroy; override;

    { 'N50W002' or 'ASTGTMV003_N50W002' -> 'ASTGTMV003_N50W002' }
    class function TileGranuleName(const ATile: string): string; static;

    { Returns the https URLs of the _dem.tif and _num.tif files for a granule }
    function FindTileURLs(const AGranule: string): TArray<string>;

    { Downloads one file; returns its size in bytes }
    function DownloadFile(const AURL, ADestFile: string): Int64;

    { Finds and downloads both files of a tile into ADestFolder }
    procedure DownloadTile(const ATile, ADestFolder: string);

    property OnLog: TGDEMLogEvent read FOnLog write FOnLog;
    property OnProgress: TGDEMProgressEvent read FOnProgress write FOnProgress;
  end;

implementation

uses
  System.JSON, System.IOUtils, System.StrUtils, System.Math,
  System.RegularExpressions, System.Generics.Collections;

const
  CMR_GRANULE_SEARCH =
    'https://cmr.earthdata.nasa.gov/search/granules.json' +
    '?short_name=ASTGTM&version=003&page_size=20' +
    '&options%5Breadable_granule_name%5D%5Bpattern%5D=true' +
    '&readable_granule_name=';
  MAX_REDIRECTS = 10;
  PROGRESS_STEP = 256 * 1024;

{ TGDEMDownloader }

constructor TGDEMDownloader.Create(const AToken: string);
begin
  inherited Create;
  FToken := Trim(AToken);
  FClient := THTTPClient.Create;
  FClient.HandleRedirects := False;   // we follow redirects ourselves
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

procedure TGDEMDownloader.HandleReceiveData(const Sender: TObject; AContentLength,
  AReadCount: Int64; var AAbort: Boolean);
begin
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
  H: string;
begin
  H := LowerCase(HostOf(AURL));
  Result := H.EndsWith('.earthdata.nasa.gov') or H.EndsWith('.earthdatacloud.nasa.gov');
end;

class function TGDEMDownloader.ResolveLocation(const ABaseURL, ALocation: string): string;
var
  U: TURI;
begin
  if StartsText('http://', ALocation) or StartsText('https://', ALocation) then
    Exit(ALocation);
  U := TURI.Create(ABaseURL);
  if ALocation.StartsWith('/') then
    Result := U.Scheme + '://' + U.Host + ALocation
  else
    Result := ABaseURL.Substring(0, ABaseURL.LastIndexOf('/') + 1) + ALocation;
end;

class function TGDEMDownloader.ReadHead(const AFileName: string; AMaxBytes: Integer): TBytes;
var
  FS: TFileStream;
begin
  Result := nil;
  if not TFile.Exists(AFileName) then
    Exit;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Min(Int64(AMaxBytes), FS.Size));
    if Length(Result) > 0 then
      FS.Read(Result, Length(Result));
  finally
    FS.Free;
  end;
end;

class function TGDEMDownloader.TileGranuleName(const ATile: string): string;
var
  S: string;
begin
  S := UpperCase(Trim(ATile));
  if S.StartsWith('ASTGTMV003_') then
    S := S.Substring(Length('ASTGTMV003_'));
  if not TRegEx.IsMatch(S, '^[NS]\d{2}[EW]\d{3}$') then
    raise EGDEMError.CreateFmt('"%s" is not a tile name. Use the form N50W002.', [ATile]);
  Result := 'ASTGTMV003_' + S;
end;

function TGDEMDownloader.FindTileURLs(const AGranule: string): TArray<string>;
var
  Body: TStringStream;
  Resp: IHTTPResponse;
  Root: TJSONValue;
  Entries, Links: TJSONArray;
  Entry, Link: TJSONValue;
  Href, L: string;
  Found: TList<string>;
begin
  FCurrentFile := '';
  Log('Searching NASA CMR for ' + AGranule + ' ...');
  Found := TList<string>.Create;
  Body := TStringStream.Create('', TEncoding.UTF8);
  try
    Resp := FClient.Get(CMR_GRANULE_SEARCH + AGranule + '*', Body);
    if Resp.StatusCode <> 200 then
      raise EGDEMError.CreateFmt('CMR search failed: HTTP %d %s',
        [Resp.StatusCode, Resp.StatusText]);

    Root := TJSONObject.ParseJSONValue(Body.DataString);
    if Root = nil then
      raise EGDEMError.Create('CMR returned something that is not JSON.');
    try
      if Root.TryGetValue<TJSONArray>('feed.entry', Entries) then
        for Entry in Entries do
          if Entry.TryGetValue<TJSONArray>('links', Links) then
            for Link in Links do
              if Link.TryGetValue<string>('href', Href) then
              begin
                L := LowerCase(Href);
                if L.StartsWith('https://') and
                   (L.EndsWith('_dem.tif') or L.EndsWith('_num.tif')) and
                   not Found.Contains(Href) then
                  Found.Add(Href);
              end;
    finally
      Root.Free;
    end;

    Found.Sort;   // _dem before _num
    Result := Found.ToArray;
    Log(Format('  found %d file(s)', [Length(Result)]));
  finally
    Body.Free;
    Found.Free;
  end;
end;

function TGDEMDownloader.DownloadFile(const AURL, ADestFile: string): Int64;
var
  TempFile, URL, Location: string;
  Stream: TFileStream;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  Code, Hops: Integer;
  Head: TBytes;
begin
  if FToken = '' then
    raise EGDEMError.Create('No Earthdata bearer token supplied.');

  TempFile := ADestFile + '.part';
  FCurrentFile := TPath.GetFileName(ADestFile);
  URL := AURL;
  Hops := 0;
  Code := 0;
  Resp := nil;
  try
    Stream := TFileStream.Create(TempFile, fmCreate);
    try
      repeat
        Stream.Size := 0;
        FLastReported := 0;

        if IsEarthdataHost(URL) then
          Headers := [TNetHeader.Create('Authorization', 'Bearer ' + FToken)]
        else
          Headers := nil;   // never leak the token to S3 / CloudFront

        Log('  GET ' + HostOf(URL));
        Resp := FClient.Get(URL, Stream, Headers);
        Code := Resp.StatusCode;

        if (Code = 301) or (Code = 302) or (Code = 303) or (Code = 307) or (Code = 308) then
        begin
          Inc(Hops);
          if Hops > MAX_REDIRECTS then
            raise EGDEMError.Create('Too many redirects.');
          Location := Resp.HeaderValue['Location'];
          if Location = '' then
            raise EGDEMError.CreateFmt('HTTP %d redirect with no Location header.', [Code]);
          URL := ResolveLocation(URL, Location);
          if SameText(HostOf(URL), 'urs.earthdata.nasa.gov') then
            raise EGDEMError.Create(
              'Redirected to the Earthdata Login page, so the bearer token was not accepted. ' +
              'It may be expired, revoked or mistyped, or LP DAAC is not yet authorised ' +
              'on your Earthdata account.');
          Log(Format('  -> %d redirect to %s', [Code, HostOf(URL)]));
          Continue;
        end;
        Break;
      until False;
    finally
      Stream.Free;
    end;

    if Code <> 200 then
      raise EGDEMError.CreateFmt('HTTP %d %s'#13#10'%s',
        [Code, Resp.StatusText, TEncoding.ANSI.GetString(ReadHead(TempFile, 400))]);

    // A GeoTIFF starts with "II" (little-endian) or "MM" (big-endian).
    // Anything else is most likely an HTML login or error page.
    Head := ReadHead(TempFile, 4);
    if (Length(Head) < 4) or
       not (((Head[0] = Ord('I')) and (Head[1] = Ord('I'))) or
            ((Head[0] = Ord('M')) and (Head[1] = Ord('M')))) then
      raise EGDEMError.CreateFmt('Downloaded data is not a GeoTIFF (content type "%s"):'#13#10'%s',
        [Resp.MimeType, TEncoding.ANSI.GetString(ReadHead(TempFile, 400))]);

    if TFile.Exists(ADestFile) then
      TFile.Delete(ADestFile);
    TFile.Move(TempFile, ADestFile);
    Result := TFile.GetSize(ADestFile);
  except
    if TFile.Exists(TempFile) then
      TFile.Delete(TempFile);
    FCurrentFile := '';
    raise;
  end;
  FCurrentFile := '';
end;

procedure TGDEMDownloader.DownloadTile(const ATile, ADestFolder: string);
var
  Granule, URL, FileName, Dest: string;
  URLs: TArray<string>;
  Size: Int64;
  Q: Integer;
begin
  Granule := TileGranuleName(ATile);
  ForceDirectories(ADestFolder);

  URLs := FindTileURLs(Granule);
  if Length(URLs) = 0 then
    raise EGDEMError.CreateFmt('CMR has no files for %s. The tile may be all ocean, ' +
      'or outside the 83N to 83S coverage.', [Granule]);

  for URL in URLs do
  begin
    FileName := URL.Substring(URL.LastIndexOf('/') + 1);
    Q := FileName.IndexOf('?');
    if Q >= 0 then
      FileName := FileName.Substring(0, Q);
    Dest := TPath.Combine(ADestFolder, FileName);

    if TFile.Exists(Dest) and (TFile.GetSize(Dest) > 0) then
    begin
      Log('Already have ' + FileName + ', skipping');
      Continue;
    end;

    Log('Downloading ' + FileName);
    Size := DownloadFile(URL, Dest);
    Log(Format('  saved %s (%.1f MB)', [Dest, Size / (1024 * 1024)]));
  end;
end;

end.
