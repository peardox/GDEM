{ @abstract(Downloads a batch of tiles: looks them up in NASA CMR, then
  downloads them several at a time into the data folder.)

  @link(TDownloadBatch) is the whole of a download job apart from showing
  it: it skips tiles already downloaded, asks CMR where the rest are, and
  downloads them on several threads that share one
  @link(TDownloadThrottle), writing every request, redirect and saved file
  to a @link(TDownloadReport). It tells the program what is happening
  through events, so any user interface (or none) can show it.

  It has no FMX dependency. }
unit GDEMDownloadBatch;

interface

uses
  System.SysUtils,
  GDEMCancel, GDEMSettings, GDEMStore, GDEMDownloader;

const
  { Once this many tiles in a row have failed to download, even after
    retries, the batch stops: something is badly wrong. Failures with good
    tiles between them only skip those tiles, however many there are. }
  MAX_DOWNLOAD_FAILURES = 10;

type
  { Reports progress through the batch.
    @param(ADone Steps done.)
    @param(ATotal Steps in all; 0 if not known.)
    @param(AText What is happening, for the user.) }
  TBatchProgressEvent = reference to procedure(ADone, ATotal: Integer; const AText: string);

  { Reports progress through the file being downloaded, or the bytes of
    the whole batch when several download at once.
    @param(ADone Bytes received; 0 with ATotal 0 when only AText matters.)
    @param(ATotal Bytes expected; 0 if not known.)
    @param(AText Such as @code(8 at a time: 1.2 GB downloaded, 52 MB/s).) }
  TBatchItemEvent = reference to procedure(ADone, ATotal: Int64; const AText: string);

  { Reports a tile that is now fully downloaded, or was already.
    @param(ASouth Latitude of the tile's southern edge.)
    @param(AWest Longitude of the tile's western edge.) }
  TBatchTileEvent = reference to procedure(ASouth, AWest: Integer);

  { @abstract(What a batch did.) }
  TDownloadBatchResult = record
    { Tiles downloaded by this batch. }
    Downloaded: Integer;
    { Tiles that were already downloaded, including those the caller left
      out before the batch began. }
    Already: Integer;
    { Tiles CMR has no data for (open ocean, or outside coverage). }
    NoData: Integer;
    { Tiles that failed even after several tries each, and were skipped. }
    Failed: Integer;
    { Bytes saved. }
    Saved: Int64;
    { Time spent downloading, not counting the CMR lookup, in seconds. }
    Seconds: Double;
  end;

  { @abstract(One batch of tile downloads.)

    Create one, set the events, call @link(Run) on a background thread,
    then free it. Events are called on the batch's own threads, several at
    once while downloading, so each handler must be thread-safe and must
    queue anything that touches the user interface to the main thread. }
  TDownloadBatch = class
  private
    { The Earthdata Login bearer token. }
    FBearer: string;
    { The data folder. Not owned. }
    FStore: TGDEMStore;
    { Bytes that must be left free on the data drive. }
    FReserve: Int64;
    { How hard to push NASA's servers. }
    FSpeed: TDownloadSpeed;
    { Backing field for @link(OnLog). }
    FOnLog: TGDEMLogEvent;
    { Backing field for @link(OnStatus). }
    FOnStatus: TGDEMLogEvent;
    { Backing field for @link(OnOverall). }
    FOnOverall: TBatchProgressEvent;
    { Backing field for @link(OnItem). }
    FOnItem: TBatchItemEvent;
    { Backing field for @link(OnTileDownloaded). }
    FOnTileDownloaded: TBatchTileEvent;

    { Fires @link(OnLog) if it is set.
      @param(Msg The line.) }
    procedure DoLog(const Msg: string);

    { Fires @link(OnStatus) if it is set.
      @param(AText The status.) }
    procedure DoStatus(const AText: string);

    { Fires @link(OnOverall) if it is set.
      @param(ADone Steps done.)
      @param(ATotal Steps in all.)
      @param(AText What is happening.) }
    procedure DoOverall(ADone, ATotal: Integer; const AText: string);

    { Fires @link(OnItem) if it is set.
      @param(ADone Bytes received.)
      @param(ATotal Bytes expected.)
      @param(AText What is happening.) }
    procedure DoItem(ADone, ATotal: Int64; const AText: string);

    { Fires @link(OnTileDownloaded) if it is set.
      @param(ASouth Latitude of the tile's southern edge.)
      @param(AWest Longitude of the tile's western edge.) }
    procedure DoTileDownloaded(ASouth, AWest: Integer);
  public
    { Prepares a batch.
      @param(ABearer The Earthdata Login bearer token.)
      @param(AStore The data folder; not owned, and must outlive the
        batch.)
      @param(AReserve Bytes that must be left free on the data drive.)
      @param(ASpeed How hard to push NASA's servers; sets how many files
        download at once to begin with and at most.) }
    constructor Create(const ABearer: string; AStore: TGDEMStore; AReserve: Int64;
      ASpeed: TDownloadSpeed);

    { Downloads tiles. Skips those already in the data folder, asks CMR
      where the rest are, many tiles per request, then downloads them
      several at a time, sharing a @link(TDownloadThrottle) that starts at
      the speed's starting number, climbs towards its most while all goes
      well, and cuts back if NASA objects. A tile that keeps failing is
      logged and skipped; the batch stops early only if the bearer token is
      rejected, free space runs low, the data folder disappears, or
      @link(MAX_DOWNLOAD_FAILURES) tiles in a row fail. Every request,
      redirect and saved file is written to a @link(TDownloadReport);
      @link(OnLog) gets only the start, problems and the summary.
      @param(AToken Cancels the batch.)
      @param(ATiles Tile names such as @code(N50W002).)
      @param(AAlready Tiles the caller left out of ATiles because they were
        already downloaded, so the summary's "already here" covers the
        whole selection.)
      @returns(What was done. Check its @code(Failed) count: those tiles
        were skipped.)
      @raises(EGDEMError if the batch had to stop early, or a tile name is
        not valid.)
      @raises(EOperationCancelled if cancelled.) }
    function Run(AToken: TCancelToken; const ATiles: TArray<string>;
      AAlready: Integer = 0): TDownloadBatchResult;

    { Receives the lines worth showing the user: the report's path, the
      lookup, the start, failures, cut-backs and the summary. The full
      detail goes to the report file, or here too if the report could not
      be created. }
    property OnLog: TGDEMLogEvent read FOnLog write FOnLog;

    { Receives a short description of the current step, such as
      @code(Downloading N50W002). }
    property OnStatus: TGDEMLogEvent read FOnStatus write FOnStatus;

    { Receives progress through the lookup, then through the tiles. }
    property OnOverall: TBatchProgressEvent read FOnOverall write FOnOverall;

    { Receives the bytes downloaded, at most four times a second. }
    property OnItem: TBatchItemEvent read FOnItem write FOnItem;

    { Receives each tile that is now complete in the data folder,
      including those found already there. }
    property OnTileDownloaded: TBatchTileEvent read FOnTileDownloaded write FOnTileDownloaded;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Math, System.Diagnostics, System.SyncObjs,
  System.Generics.Collections, System.StrUtils,
  GDEMTiles, GDEMReport;

{ TDownloadBatch }

constructor TDownloadBatch.Create(const ABearer: string; AStore: TGDEMStore;
  AReserve: Int64; ASpeed: TDownloadSpeed);
begin
  inherited Create;
  FBearer := ABearer;
  FStore := AStore;
  FReserve := AReserve;
  FSpeed := ASpeed;
end;

procedure TDownloadBatch.DoLog(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

procedure TDownloadBatch.DoStatus(const AText: string);
begin
  if Assigned(FOnStatus) then
    FOnStatus(AText);
end;

procedure TDownloadBatch.DoOverall(ADone, ATotal: Integer; const AText: string);
begin
  if Assigned(FOnOverall) then
    FOnOverall(ADone, ATotal, AText);
end;

procedure TDownloadBatch.DoItem(ADone, ATotal: Int64; const AText: string);
begin
  if Assigned(FOnItem) then
    FOnItem(ADone, ATotal, AText);
end;

procedure TDownloadBatch.DoTileDownloaded(ASouth, AWest: Integer);
begin
  if Assigned(FOnTileDownloaded) then
    FOnTileDownloaded(ASouth, AWest);
end;

function TDownloadBatch.Run(AToken: TCancelToken; const ATiles: TArray<string>;
  AAlready: Integer): TDownloadBatchResult;
var
  LTodo, LQueueList, LFolders: TList<string>;
  LTile, LFolder: string;
  LSouth, LWest, LAlready, LNoData, LIndex, LMost: Integer;
  LLookup: TGDEMDownloader;
  LURLs: TDictionary<string, TArray<string>>;
  LQueue: TArray<string>;
  LLock: TObject;
  LWorker: TProc;
  LThreads: TArray<TThread>;
  LClock: TStopwatch;
  // Shared by the workers; counters change only through TInterlocked
  LNext, LDone, LDownloaded, LFailed, LFailRun: Integer;
  LBytes, LSaved, LLastUi: Int64;
  LError, LCutBack: string;
  LStop: Boolean;
  LSeconds: Double;
  LThrottle: TDownloadThrottle;
  LReport: TDownloadReport;
  // Detail goes only to the report; summary lines go to both
  LDetail, LBoth: TGDEMLogEvent;
begin
  Result := Default(TDownloadBatchResult);
  LThrottle := nil;
  LReport := nil;
  LTodo := TList<string>.Create;
  LQueueList := TList<string>.Create;
  LFolders := TList<string>.Create;
  LLock := TObject.Create;
  LURLs := nil;
  try
  try
    // 1. Tiles already in the data folder need nothing from NASA. Those
    // the caller left out are counted too.
    LAlready := AAlready;
    for LTile in ATiles do
    begin
      AToken.Check;
      // Validates the name, raising a clear error if it is wrong
      TGDEMDownloader.TileGranuleName(LTile);
      TryParseTileName(LTile, LSouth, LWest);
      if FStore.TileComplete(LSouth, LWest) then
      begin
        Inc(LAlready);
        DoTileDownloaded(LSouth, LWest);
      end
      else if not LTodo.Contains(TileName(LSouth, LWest)) then
        LTodo.Add(TileName(LSouth, LWest));
    end;
    Result.Already := LAlready;
    if LAlready > 0 then
      DoLog(Format('%d tile(s) already downloaded', [LAlready]));
    if LTodo.Count = 0 then
    begin
      DoLog('Nothing to download.');
      Exit;
    end;

    // The report file; if it cannot be made, the detail goes to OnLog
    // instead
    try
      LReport := TDownloadReport.Create('download');
      LDetail := LReport.Add;
      LBoth :=
        procedure(const Msg: string)
        begin
          DoLog(Msg);
          LReport.Add(Msg);
        end;
      DoLog('Download report: ' + LReport.FileName);
      if LAlready > 0 then
        LReport.Add(Format('%d tile(s) already downloaded', [LAlready]));
    except
      on E: Exception do
      begin
        DoLog('WARNING: could not start a download report (' +
          E.Message.TrimRight(['.']) + '); details follow here instead');
        LDetail := DoLog;
        LBoth := DoLog;
      end;
    end;

    // 2. Ask CMR where they all are, many tiles per request
    DoStatus('Asking NASA CMR where the tiles are ...');
    LClock := TStopwatch.StartNew;
    LLookup := TGDEMDownloader.Create(FBearer);
    try
      LLookup.CancelToken := AToken;
      LLookup.OnLog := LDetail;
      LURLs := LLookup.LookUpTiles(LTodo.ToArray,
        procedure(ABatch, ABatches: Integer)
        begin
          DoOverall(ABatch - 1, ABatches,
            Format('Looking up tiles: request %d of %d', [ABatch, ABatches]));
        end);
    finally
      LLookup.Free;
    end;

    LNoData := 0;
    for LTile in LTodo do
      if LURLs.ContainsKey(LTile) then
        LQueueList.Add(LTile)
      else
      begin
        Inc(LNoData);
        LDetail('  no data for ' + LTile + ' (ocean or outside coverage)');
      end;
    Result.NoData := LNoData;
    LQueue := LQueueList.ToArray;
    LBoth(Format('Looked up %d tile(s) in NASA CMR in %s: %d have data',
      [LTodo.Count, FormatDuration(LClock.Elapsed.TotalSeconds), Length(LQueue)]));

    // 3. Download them, several tiles at a time. From here on LURLs is
    // only read, which is safe from several threads at once.
    LNext := -1;
    LDone := 0;
    LDownloaded := 0;
    LFailed := 0;
    LFailRun := 0;
    LBytes := 0;
    LSaved := 0;
    LLastUi := -1000;
    // Shared by every worker: limits files at once, climbing towards the
    // most while all goes well and backing off if NASA starts cutting off
    // or refusing downloads
    LMost := DOWNLOAD_SPEED_MAX[FSpeed];
    LThrottle := TDownloadThrottle.Create(DOWNLOAD_SPEED_START[FSpeed], LMost);
    LThrottle.OnLog := LBoth;
    LError := '';
    LStop := False;
    LBoth(Format('Downloading %d tile(s) at %s speed: %d at a time to start with, ' +
      'at most %d', [Length(LQueue), DOWNLOAD_SPEED_KEYS[FSpeed].ToLower,
      LThrottle.Allowed, LMost]));
    DoOverall(0, Length(LQueue), Format('Tile 0 of %d', [Length(LQueue)]));
    LClock := TStopwatch.StartNew;

    LWorker :=
      procedure
      var
        LIdx, LCount, LFailures, LS, LW: Integer;
        LName, LTileFolder, LMessage: string;
        LDownloader: TGDEMDownloader;
        LSpace, LPrev: Int64;
        LFatal: Boolean;
      begin
        LPrev := 0;
        LDownloader := TGDEMDownloader.Create(FBearer);
        try
          LDownloader.CancelToken := AToken;
          LDownloader.Throttle := LThrottle;
          LDownloader.OnLog := LDetail;
          LDownloader.OnProgress :=
            procedure(const FileName: string; Received, Total: Int64)
            var
              LNow, LLast: Int64;
              LSeconds: Double;
              LText: string;
              LAllowed: Integer;
            begin
              // Received starts again from 0 for each file and each retry
              if Received < LPrev then
                LPrev := 0;
              TInterlocked.Add(LBytes, Received - LPrev);
              LPrev := Received;

              // At most four updates a second, whichever worker
              LNow := LClock.ElapsedMilliseconds;
              LLast := TInterlocked.Read(LLastUi);
              if (LNow - LLast < 250) or
                 (TInterlocked.CompareExchange(LLastUi, LNow, LLast) <> LLast) then
                Exit;
              LText := FormatByteSize(TInterlocked.Read(LBytes)) + ' downloaded';
              LSeconds := LNow / 1000;
              if LSeconds >= 2 then
                LText := LText + Format(', %s/s',
                  [FormatByteSize(Round(TInterlocked.Read(LBytes) / LSeconds))]);
              LAllowed := LThrottle.Allowed;
              if LAllowed = 1 then
                DoItem(Received, Total, FileName + ': ' + LText)
              else
                DoItem(0, 0, Format('%d at a time: %s', [LAllowed, LText]));
            end;

          while not LStop and not AToken.Cancelled do
          begin
            LIdx := TInterlocked.Increment(LNext);
            if LIdx >= Length(LQueue) then
              Exit;
            LName := LQueue[LIdx];
            TryParseTileName(LName, LS, LW);
            LTileFolder := FStore.TileFolder(LS, LW);
            LMessage := '';
            LFatal := False;
            DoStatus('Downloading ' + LName);

            if not TDirectory.Exists(FStore.Root) then
            begin
              LFatal := True;
              LMessage := Format('Downloading stopped: the data folder %s is no longer ' +
                'available. If it is on a removable drive, check that it is still ' +
                'connected, then fetch again.', [FStore.Root]);
            end
            else
            begin
              // Every worker may be about to write a tile of about this size
              LSpace := FStore.FreeSpace;
              if (LSpace >= 0) and (LSpace - ESTIMATED_TILE_BYTES * LMost < FReserve) then
              begin
                LFatal := True;
                LMessage := Format('Downloading stopped: only %s is free on the data ' +
                  'drive, and %s must be kept free. Free some space or change the ' +
                  'reserve in File > Settings.',
                  [FormatByteSize(LSpace), FormatByteSize(FReserve)]);
              end
              else
                try
                  // Several workers may need the same new block folder at
                  // once, and ForceDirectories is not safe for that
                  TMonitor.Enter(LLock);
                  try
                    if not TDirectory.Exists(LTileFolder) then
                      ForceDirectories(LTileFolder);
                  finally
                    TMonitor.Exit(LLock);
                  end;
                  if not TDirectory.Exists(LTileFolder) then
                    raise EGDEMError.Create('the folder ' + LTileFolder + ' could not be created');

                  TInterlocked.Add(LSaved, LDownloader.DownloadFiles(LURLs[LName], LTileFolder));
                  if FStore.TileComplete(LS, LW) then
                  begin
                    TInterlocked.Increment(LDownloaded);
                    DoTileDownloaded(LS, LW);
                  end;
                  // A good tile ends any run of failures
                  TInterlocked.Exchange(LFailRun, 0);
                except
                  on E: EOperationCancelled do
                    Exit;
                  on E: EGDEMAuthError do
                  begin
                    // Every other tile would fail the same way
                    LFatal := True;
                    LMessage := E.Message;
                  end;
                  on E: Exception do
                  begin
                    // Already tried several times; skip the tile and carry on
                    TInterlocked.Increment(LFailed);
                    LFailures := TInterlocked.Increment(LFailRun);
                    LBoth(Format('  FAILED %s: %s', [LName, E.Message.TrimRight(['.'])]));
                    TMonitor.Enter(LLock);
                    try
                      if not LFolders.Contains(LTileFolder) then
                        LFolders.Add(LTileFolder);
                    finally
                      TMonitor.Exit(LLock);
                    end;
                    if LFailures >= MAX_DOWNLOAD_FAILURES then
                    begin
                      LFatal := True;
                      LMessage := Format('Downloading stopped after %d tiles in a row ' +
                        'failed; the last with: %s. The Debug tab lists them.',
                        [LFailures, E.Message.TrimRight(['.'])]);
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
                if not LFolders.Contains(LTileFolder) then
                  LFolders.Add(LTileFolder);
              finally
                TMonitor.Exit(LLock);
              end;
              Exit;
            end;

            LCount := TInterlocked.Increment(LDone);
            DoOverall(LCount, Length(LQueue), Format('Tile %d of %d', [LCount, Length(LQueue)]));
          end;
        finally
          LDownloader.Free;
        end;
      end;

    // Plain threads rather than the task pool, as this already runs on a
    // pool thread and must wait for the workers. There is one for the most
    // files allowed at once; the throttle holds back any not yet allowed.
    SetLength(LThreads, Min(LMost, Max(1, Length(LQueue))));
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
    for LFolder in LFolders do
      FStore.PruneEmptyFolders(LFolder);

    // LClock was restarted when the downloads began, so the lookup is not
    // counted in the speed
    LSeconds := LClock.Elapsed.TotalSeconds;
    Result.Downloaded := LDownloaded;
    Result.Failed := LFailed;
    Result.Saved := LSaved;
    Result.Seconds := LSeconds;
    // The speed counts everything that arrived, including retries; the
    // size is what was saved
    LCutBack := '';
    if LThrottle.Lowest < LThrottle.Peak then
      LCutBack := Format(' (cut back to %d at worst, %d at the end)',
        [LThrottle.Lowest, LThrottle.Allowed]);
    // "1 was already here", "2 were"; "1 has no data", "2 have"
    LBoth(Format('Downloaded %d tile(s), %s, in %s at %s/s, up to %d at a time%s; %d %s ' +
      'already here, %d %s no data, %d failed.',
      [LDownloaded, FormatByteSize(LSaved), FormatDuration(LSeconds),
       FormatByteSize(Round(LBytes / Max(LSeconds, 0.001))), LThrottle.Peak, LCutBack,
       LAlready, IfThen(LAlready = 1, 'was', 'were'), LNoData,
       IfThen(LNoData = 1, 'has', 'have'), LFailed]));
    if LError <> '' then
      raise EGDEMError.Create(LError);
    AToken.Check;
    DoOverall(Length(LQueue), Length(LQueue), 'Finished');
  except
    // Record why the batch stopped, then let the caller report it
    on E: Exception do
    begin
      if LReport <> nil then
        LReport.Add('Stopped: ' + E.Message);
      raise;
    end;
  end;
  finally
    LReport.Free;
    LThrottle.Free;
    LURLs.Free;
    LLock.Free;
    LFolders.Free;
    LQueueList.Free;
    LTodo.Free;
  end;
end;

end.
