{ @abstract(Writes logs to report files: the full record of a batch of
  downloads, and the 3D view's flight log; rotates them and archives the
  old ones.)

  A batch of downloads produces several lines for every file: the request,
  the redirect and where it was saved. For a large batch (the whole world
  is 22,912 tiles) that is far too much for the Debug tab, so the detail
  goes to a report file instead, and the Debug tab keeps only what matters:
  the start, any problems, and the summary. The flight log is kept the same
  way.

  Reports are kept in a @code(Reports) folder beside the settings file (see
  @code(TGDEMSettings.SettingsFolder)), in a folder for each kind of
  report, such as @code(Reports/download) and @code(Reports/flight). Each
  report is named by the kind and the time it started, and numbered from
  01, such as @code(download-20261026-231500-01.log); when a file reaches
  @link(REPORT_ROTATE_BYTES) it is closed and the report carries on in the
  next number (@code(-02), and so on), each file saying where it carries on
  or came from.

  The newest @link(REPORTS_KEPT) files of each kind are kept as they are.
  Older ones go into an archive for the month they were started in,
  @code(Reports/<kind>/archive/<kind>-yyyy-mm.zip), and are deleted only
  once the archive has been checked to hold them whole. Archives more than
  @link(REPORT_ARCHIVE_MONTHS) months old are deleted, and so are reports
  from those months that were never archived. This tidying runs
  in the background each time a report starts or moves to its next file;
  @link(TDownloadReport.StopHousekeeping) waits for it before the program
  closes. Reports left loose in @code(Reports) by earlier versions are
  moved into their kind's folder the first time. }
unit GDEMReport;

interface

uses
  System.SysUtils, System.Classes;

const
  { Name of the folder reports are kept in, inside the settings folder. }
  REPORTS_FOLDER_NAME = 'Reports';

  { Name of the folder, inside each kind's folder, that holds its
    archives. }
  REPORT_ARCHIVE_FOLDER_NAME = 'archive';

  { How many report files of each kind are kept as they are; older ones
    are archived. }
  REPORTS_KEPT = 50;

  { The size at which a report file is closed and the report carries on
    in the next one, bytes. }
  REPORT_ROTATE_BYTES = 10 * 1024 * 1024;

  { How many months of archives are kept before the current month's;
    older archives are deleted. }
  REPORT_ARCHIVE_MONTHS = 12;

type
  { @abstract(Takes a line about the tidying of reports, for the log.)
    @param(AText The line.) }
  TReportLogProc = reference to procedure(const AText: string);

  { @abstract(A report: a log file for one batch, or the flight log of a
    run, carried on in further files as it grows.)

    Lines are written as they arrive, each with the time, and flushed at
    once, so the file is complete up to the moment even if the program
    stops unexpectedly. All methods are thread-safe. }
  TDownloadReport = class
  private
    { Guards @link(FWriter) and @link(FFileName). }
    FLock: TObject;
    { The open file; @nil if the next file could not be opened, nor the
      last one again. }
    FWriter: TStreamWriter;
    { Backing field for @link(FileName). }
    FFileName: string;
    { The kind of report, such as @code(download). }
    FKind: string;
    { When the report started, as in its file names. }
    FStamp: string;
    { The number of the file being written, from 1. }
    FPart: Integer;
    { @true once moving to a next file has failed, so it is not tried again
      for every line. }
    FRotateFailed: Boolean;

    { The next file's name: the next number not already taken.
      @returns(Full path.) }
    function NextFileName: string;

    { Closes the file and carries on in the next one, each saying where the
      other is. If the next cannot be made, carries on in this one and
      says so. Called with @link(FLock) held. }
    procedure Rotate;

    { Reader for @link(FileName). @returns(The file being written.) }
    function GetFileName: string;
  public
    { Creates the report's first file, in its kind's folder, and starts
      tidying that kind's reports in the background.
      @param(AKind What the report is, used for its folder and file names,
        such as @code(download) or @code(flight): letters, digits, hyphens
        and underscores.)
      @raises(EArgumentException if the kind has other characters.)
      @raises(EInOutError or another exception if the file cannot be
        created.) }
    constructor Create(const AKind: string);

    { Closes the file. }
    destructor Destroy; override;

    { The folder all reports are kept in.
      @returns(Full path of the folder, which may not exist yet.) }
    class function Folder: string; static;

    { The folder one kind of report is kept in.
      @param(AKind The kind, such as @code(download).)
      @returns(Full path of the folder, which may not exist yet.) }
    class function KindFolder(const AKind: string): string; static;

    { The folder one kind of report's archives are kept in.
      @param(AKind The kind, such as @code(download).)
      @returns(Full path of the folder, which may not exist yet.) }
    class function ArchiveFolder(const AKind: string): string; static;

    { Tidies one kind of report now, on this thread: moves loose reports
      from earlier versions into its folder, archives all but the newest
      @link(REPORTS_KEPT) files, and deletes archives older than
      @link(REPORT_ARCHIVE_MONTHS) months. Problems are told to the
      housekeeping log (@link(SetHousekeepingLog)) and never raised.
      Nothing once @link(StopHousekeeping) has been called.
      @param(AKind The kind.) }
    class procedure Tidy(const AKind: string); static;

    { Sets where lines about tidying go: moving old reports, a large first
      archiving, and problems. Routine archiving is not told.
      @param(AProc Takes each line, on any thread; @nil for nowhere.) }
    class procedure SetHousekeepingLog(const AProc: TReportLogProc); static;

    { Stops tidying for good: tidying not yet started is skipped, and
      tidying under way stops after the archive it is writing, which this
      waits for. Call before the program closes. }
    class procedure StopHousekeeping; static;

    { Adds a line, with the time in front. Query strings in any web
      addresses in it are hidden first (see @link(HideURLQueries)). Moves
      to the next file once this one reaches @link(REPORT_ROTATE_BYTES).
      @param(Msg The text.) }
    procedure Add(const Msg: string);

    { Full path of the file being written now; it changes when the report
      moves to its next file. }
    property FileName: string read GetFileName;
  end;

{ @abstract(Hides the query string of every web address in a piece of
  text, so it can be logged.)

  Some error messages carry the full address that failed. NASA's download
  links are signed CloudFront addresses whose query string holds the
  Earthdata user name, a signature and other access details, none of which
  belong in a log. The query string (from @code(?) or @code(#) to the end
  of the address) becomes @code(?...); the host and path are kept, since
  they say which file failed. An address ends at a space, a control
  character, a quote or an angle or round bracket, and a colon, full stop,
  comma or semicolon at its very end is treated as punctuation after it.
  @param(AText The text, such as an exception's message.)
  @returns(The text with query strings hidden, or @code(AText) unchanged
    if it holds no web address.) }
function HideURLQueries(const AText: string): string;

implementation

uses
  System.IOUtils, System.Generics.Collections, System.Threading, System.Zip,
  System.DateUtils, System.Math,
  GDEMSettings;

const
  { The longest closing waits for tidying tasks to finish, milliseconds;
    they finish as soon as they see tidying has stopped, unless one is
    writing an archive. }
  HOUSEKEEPING_STOP_WAIT_MS = 30000;

var
  { Held while reports are tidied, so only one tidying runs at a time;
    also guards @link(GHousekeepingLog). }
  GHousekeepingLock: TObject;
  { Tidying tasks started and not yet finished, counted from before each
    is queued, so closing can wait for every one, not only one already
    holding the lock. }
  GHousekeepingTasks: Integer;
  { Where lines about tidying go; @nil for nowhere. }
  GHousekeepingLog: TReportLogProc;
  { @true once @link(TDownloadReport.StopHousekeeping) has been called, or
    the unit is being finalized. }
  GHousekeepingStopped: Boolean;

{ Says whether a web address starts at a position in some text.
  @param(AText The text.)
  @param(AIndex Position in @code(AText), counting from 1.)
  @returns(@true if @code(http://) or @code(https://), in any case,
    starts there.) }
function URLStartsAt(const AText: string; AIndex: Integer): Boolean;
begin
  Result := SameText(Copy(AText, AIndex, 8), 'https://') or
    SameText(Copy(AText, AIndex, 7), 'http://');
end;

{ Says whether a character ends a web address in running text.
  @param(AChar The character.)
  @returns(@true for spaces, control characters, quotes and angle or
    round brackets.) }
function EndsURL(AChar: Char): Boolean;
begin
  case AChar of
    #0..' ', '"', '''', '<', '>', '(', ')':
      Result := True;
  else
    Result := False;
  end;
end;

function HideURLQueries(const AText: string): string;
var
  LBuilder: TStringBuilder;
  LIndex, LEnd, LLength, LQuery: Integer;
  LURL: string;
begin
  // Most lines hold no address at all
  if Pos('://', AText) = 0 then
    Exit(AText);
  LLength := Length(AText);
  LBuilder := TStringBuilder.Create(LLength);
  try
    LIndex := 1;
    while LIndex <= LLength do
      if URLStartsAt(AText, LIndex) then
      begin
        LEnd := LIndex;
        while (LEnd <= LLength) and not EndsURL(AText[LEnd]) do
          Inc(LEnd);
        // Punctuation right after the address, as in "...?a=b: timed out"
        while (LEnd > LIndex) and CharInSet(AText[LEnd - 1], [':', '.', ',', ';']) do
          Dec(LEnd);
        LURL := Copy(AText, LIndex, LEnd - LIndex);
        LQuery := LURL.IndexOfAny(['?', '#']);
        if LQuery >= 0 then
          LURL := LURL.Substring(0, LQuery) + '?...';
        LBuilder.Append(LURL);
        LIndex := LEnd;
      end
      else
      begin
        LBuilder.Append(AText[LIndex]);
        Inc(LIndex);
      end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

{ Housekeeping }

{ Tells the housekeeping log a line, if there is one. Called with
  @link(GHousekeepingLock) held.
  @param(AText The line.) }
procedure HousekeepingLog(const AText: string);
begin
  if Assigned(GHousekeepingLog) then
    try
      GHousekeepingLog(AText);
    except
      // The log is a nicety; tidying carries on without it
    end;
end;

{ Says whether a kind of report has a name that is safe in a file name.
  @param(AKind The kind.)
  @returns(@true if it is letters, digits, hyphens and underscores, and
    not empty.) }
function IsValidKind(const AKind: string): Boolean;
var
  LChar: Char;
begin
  Result := AKind <> '';
  for LChar in AKind do
    if not CharInSet(LChar, ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) then
      Exit(False);
end;

{ The month a report file was started in, from its name, or failing that
  from when it was last written.
  @param(AKind The kind, which starts the name.)
  @param(AFile The file's full path.)
  @returns(Such as @code(2026-10).) }
function ReportMonth(const AKind, AFile: string): string;
var
  LName: string;
  LYear, LMonth: Integer;
begin
  LName := ExtractFileName(AFile);
  // kind-yyyymmdd-hhnnss...
  if TryStrToInt(Copy(LName, Length(AKind) + 2, 4), LYear) and
     TryStrToInt(Copy(LName, Length(AKind) + 6, 2), LMonth) and InRange(LMonth, 1, 12) and
     (LYear >= 2000) then
    Exit(Format('%.4d-%.2d', [LYear, LMonth]));
  try
    Result := FormatDateTime('yyyy-mm', TFile.GetLastWriteTime(AFile));
  except
    Result := FormatDateTime('yyyy-mm', Now);
  end;
end;

{ Moves reports of a kind left loose in the reports folder by earlier
  versions into the kind's folder.
  @param(AKind The kind.)
  @returns(How many were moved.) }
function MoveLooseReports(const AKind: string): Integer;
var
  LFile, LTarget: string;
begin
  Result := 0;
  if not TDirectory.Exists(TDownloadReport.Folder) then
    Exit;
  for LFile in TDirectory.GetFiles(TDownloadReport.Folder, AKind + '-*.log') do
  begin
    LTarget := TPath.Combine(TDownloadReport.KindFolder(AKind), ExtractFileName(LFile));
    try
      if not TFile.Exists(LTarget) then
      begin
        TFile.Move(LFile, LTarget);
        Inc(Result);
      end;
    except
      on E: Exception do
        HousekeepingLog(Format('WARNING: reports: could not move %s into %s (%s)',
          [LFile, TDownloadReport.KindFolder(AKind), E.Message.TrimRight(['.'])]));
    end;
  end;
end;

{ Puts report files into a month's archive, whole or not at all (the
  archive is made again as a temporary file and then put in place), then
  deletes each file the archive is found to hold at its full size. A file
  the archive already holds is not added again, so a file whose deletion
  failed last time is only deleted now.
  @param(AKind The kind.)
  @param(AMonth The month, such as @code(2026-10).)
  @param(AFiles The files, all started in that month.)
  @returns(How many files were archived and deleted.)
  @raises(Exception if the archive cannot be written.) }
function ArchiveReports(const AKind, AMonth: string; const AFiles: TArray<string>): Integer;
var
  LArchive, LTemp, LFile, LName: string;
  LZip: TZipFile;
  LIndex: Integer;
  LSize: Int64;
begin
  Result := 0;
  ForceDirectories(TDownloadReport.ArchiveFolder(AKind));
  LArchive := TPath.Combine(TDownloadReport.ArchiveFolder(AKind),
    Format('%s-%s.zip', [AKind, AMonth]));
  LTemp := LArchive + '.tmp';
  if TFile.Exists(LTemp) then
    TFile.Delete(LTemp);
  LZip := TZipFile.Create;
  try
    if TFile.Exists(LArchive) then
    begin
      TFile.Copy(LArchive, LTemp);
      LZip.Open(LTemp, zmReadWrite);
    end
    else
      LZip.Open(LTemp, zmWrite);
    for LFile in AFiles do
    begin
      LName := ExtractFileName(LFile);
      if LZip.IndexOf(LName) >= 0 then
        Continue;
      try
        LZip.Add(LFile, LName);
      except
        on E: Exception do
          HousekeepingLog(Format('WARNING: reports: could not archive %s (%s); it is left ' +
            'as it is', [LFile, E.Message.TrimRight(['.'])]));
      end;
    end;
    LZip.Close;
  finally
    LZip.Free;
  end;
  if TFile.Exists(LArchive) then
    TFile.Delete(LArchive);
  TFile.Move(LTemp, LArchive);

  // Each file goes only once the archive is seen to hold all of it
  LZip := TZipFile.Create;
  try
    LZip.Open(LArchive, zmRead);
    for LFile in AFiles do
    begin
      LIndex := LZip.IndexOf(ExtractFileName(LFile));
      if LIndex < 0 then
        Continue;
      try
        LSize := TFile.GetSize(LFile);
        if UInt64(LZip.FileInfo[LIndex].UncompressedSize) = UInt64(LSize) then
        begin
          TFile.Delete(LFile);
          Inc(Result);
        end
        else
          HousekeepingLog(Format('WARNING: reports: %s is not the size archived in %s, so ' +
            'it is kept', [LFile, LArchive]));
      except
        // Still open elsewhere, say: deleted next time
      end;
    end;
    LZip.Close;
  finally
    LZip.Free;
  end;
end;

{ Deletes a kind's archives from before the months kept, and temporary
  archives left an hour or more ago by a run that stopped while writing
  one.
  @param(AKind The kind.)
  @returns(How many archives were deleted.) }
function DeleteOldArchives(const AKind: string): Integer;
var
  LFile, LName: string;
  LYear, LMonth: Integer;
  LOldest: TDateTime;
begin
  Result := 0;
  if not TDirectory.Exists(TDownloadReport.ArchiveFolder(AKind)) then
    Exit;
  LOldest := IncMonth(StartOfTheMonth(Now), -REPORT_ARCHIVE_MONTHS);
  for LFile in TDirectory.GetFiles(TDownloadReport.ArchiveFolder(AKind), AKind + '-*.zip') do
  begin
    // kind-yyyy-mm.zip
    LName := ExtractFileName(LFile);
    if not TryStrToInt(Copy(LName, Length(AKind) + 2, 4), LYear) or
       not TryStrToInt(Copy(LName, Length(AKind) + 7, 2), LMonth) or
       not InRange(LMonth, 1, 12) or (LYear < 2000) then
      Continue;
    if EncodeDate(LYear, LMonth, 1) < LOldest then
      try
        TFile.Delete(LFile);
        Inc(Result);
      except
        on E: Exception do
          HousekeepingLog(Format('WARNING: reports: could not delete the old archive %s (%s)',
            [LFile, E.Message.TrimRight(['.'])]));
      end;
  end;
  for LFile in TDirectory.GetFiles(TDownloadReport.ArchiveFolder(AKind), '*.zip.tmp') do
    try
      if TFile.GetLastWriteTime(LFile) < IncHour(Now, -1) then
        TFile.Delete(LFile);
    except
      // Tried again next time
    end;
end;

{ Tidies one kind of report on a task, unless tidying has been stopped.
  @param(AKind The kind.) }
procedure StartHousekeeping(const AKind: string);
var
  LKind: string;
begin
  if GHousekeepingStopped then
    Exit;
  LKind := AKind;
  // Counted before it is queued, so it cannot start after closing has
  // stopped waiting for it and freed the lock
  AtomicIncrement(GHousekeepingTasks);
  try
    TTask.Run(
      procedure
      begin
        try
          TDownloadReport.Tidy(LKind);
        finally
          AtomicDecrement(GHousekeepingTasks);
        end;
      end);
  except
    AtomicDecrement(GHousekeepingTasks);
  end;
end;

{ Stops tidying and waits, up to @link(HOUSEKEEPING_STOP_WAIT_MS), for
  every tidying task started to finish.
  @returns(@true if they all finished.) }
function WaitForHousekeeping: Boolean;
var
  LWaited: Integer;
begin
  GHousekeepingStopped := True;
  LWaited := 0;
  while (AtomicCmpExchange(GHousekeepingTasks, 0, 0) > 0) and
        (LWaited < HOUSEKEEPING_STOP_WAIT_MS) do
  begin
    TThread.Sleep(10);
    Inc(LWaited, 10);
  end;
  Result := AtomicCmpExchange(GHousekeepingTasks, 0, 0) = 0;
end;

{ TDownloadReport }

class function TDownloadReport.Folder: string;
begin
  Result := TPath.Combine(TGDEMSettings.SettingsFolder, REPORTS_FOLDER_NAME);
end;

class function TDownloadReport.KindFolder(const AKind: string): string;
begin
  Result := TPath.Combine(Folder, AKind);
end;

class function TDownloadReport.ArchiveFolder(const AKind: string): string;
begin
  Result := TPath.Combine(KindFolder(AKind), REPORT_ARCHIVE_FOLDER_NAME);
end;

class procedure TDownloadReport.Tidy(const AKind: string);
var
  LFiles, LMonthFiles: TArray<string>;
  LMonths: TDictionary<string, TArray<string>>;
  LMonth, LOldestMonth, LFile: string;
  LMoved, LArchived, LDeleted, LIndex: Integer;
begin
  if not IsValidKind(AKind) or GHousekeepingStopped then
    Exit;
  TMonitor.Enter(GHousekeepingLock);
  try
    if GHousekeepingStopped then
      Exit;
    try
      ForceDirectories(KindFolder(AKind));
      LMoved := MoveLooseReports(AKind);
      if LMoved > 0 then
        HousekeepingLog(Format('Reports: moved %d %s report(s) from earlier versions into %s',
          [LMoved, AKind, KindFolder(AKind)]));

      // Names sort by when they started, then by number, so the oldest
      // come first; the newest are kept as they are, the report being
      // written among them
      LFiles := TDirectory.GetFiles(KindFolder(AKind), AKind + '-*.log');
      TArray.Sort<string>(LFiles);
      LArchived := 0;
      LDeleted := 0;
      // Months older than the archives kept are not archived, only deleted
      LOldestMonth := FormatDateTime('yyyy-mm', IncMonth(StartOfTheMonth(Now),
        -REPORT_ARCHIVE_MONTHS));
      if Length(LFiles) > REPORTS_KEPT then
      begin
        LMonths := TDictionary<string, TArray<string>>.Create;
        try
          for LIndex := 0 to Length(LFiles) - REPORTS_KEPT - 1 do
          begin
            LMonth := ReportMonth(AKind, LFiles[LIndex]);
            if not LMonths.TryGetValue(LMonth, LMonthFiles) then
              LMonthFiles := nil;
            LMonths.AddOrSetValue(LMonth, LMonthFiles + [LFiles[LIndex]]);
          end;
          for LMonth in LMonths.Keys do
          begin
            // Closing waits for no more than the archive being written
            if GHousekeepingStopped then
              Break;
            if LMonth < LOldestMonth then
            begin
              for LFile in LMonths[LMonth] do
                try
                  TFile.Delete(LFile);
                  Inc(LDeleted);
                except
                  // Still open elsewhere, say: deleted next time
                end;
              Continue;
            end;
            try
              LArchived := LArchived + ArchiveReports(AKind, LMonth, LMonths[LMonth]);
            except
              on E: Exception do
                HousekeepingLog(Format('WARNING: reports: could not archive %s reports for %s ' +
                  'into %s (%s); they are left as they are', [AKind, LMonth,
                   ArchiveFolder(AKind), E.Message.TrimRight(['.'])]));
            end;
          end;
        finally
          LMonths.Free;
        end;
      end;
      // Usually one at a time, not worth a line; many at once (the first
      // tidy after an update) is
      if LArchived > 1 then
        HousekeepingLog(Format('Reports: archived %d %s report(s) into %s', [LArchived, AKind,
          ArchiveFolder(AKind)]));
      if LDeleted > 0 then
        HousekeepingLog(Format('Reports: deleted %d %s report(s) from before %s, older than ' +
          'the archives kept', [LDeleted, AKind, LOldestMonth]));
      DeleteOldArchives(AKind);
    except
      on E: Exception do
        HousekeepingLog(Format('WARNING: reports: tidying the %s reports failed (%s)',
          [AKind, E.Message.TrimRight(['.'])]));
    end;
  finally
    TMonitor.Exit(GHousekeepingLock);
  end;
end;

class procedure TDownloadReport.SetHousekeepingLog(const AProc: TReportLogProc);
begin
  TMonitor.Enter(GHousekeepingLock);
  try
    GHousekeepingLog := AProc;
  finally
    TMonitor.Exit(GHousekeepingLock);
  end;
end;

class procedure TDownloadReport.StopHousekeeping;
begin
  // Tasks see the stop and end at once, except one writing an archive,
  // which ends after it
  WaitForHousekeeping;
  TMonitor.Enter(GHousekeepingLock);
  try
    GHousekeepingLog := nil;
  finally
    TMonitor.Exit(GHousekeepingLock);
  end;
end;

constructor TDownloadReport.Create(const AKind: string);
begin
  inherited Create;
  if not IsValidKind(AKind) then
    raise EArgumentException.CreateFmt('"%s" is not a kind of report', [AKind]);
  FLock := TObject.Create;
  FKind := AKind;
  FStamp := FormatDateTime('yyyymmdd-hhnnss', Now);
  ForceDirectories(KindFolder(FKind));
  FFileName := NextFileName;
  FWriter := TStreamWriter.Create(FFileName, False, TEncoding.UTF8);
  FWriter.AutoFlush := True;
  StartHousekeeping(FKind);
end;

destructor TDownloadReport.Destroy;
begin
  FWriter.Free;
  FLock.Free;
  inherited;
end;

function TDownloadReport.NextFileName: string;
begin
  // Two reports of a kind started in the same second take different
  // numbers rather than one writing over the other
  repeat
    Inc(FPart);
    Result := TPath.Combine(KindFolder(FKind), Format('%s-%s-%.2d.log', [FKind, FStamp, FPart]));
  until not TFile.Exists(Result);
end;

function TDownloadReport.GetFileName: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFileName;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TDownloadReport.Rotate;
var
  LOld, LNext: string;
begin
  LOld := FFileName;
  try
    LNext := NextFileName;
    FWriter.WriteLine(FormatDateTime('hh:nn:ss', Now) + '  Continued in ' +
      ExtractFileName(LNext));
    FreeAndNil(FWriter);
    FWriter := TStreamWriter.Create(LNext, False, TEncoding.UTF8);
    FWriter.AutoFlush := True;
    FFileName := LNext;
    FWriter.WriteLine(FormatDateTime('hh:nn:ss', Now) + '  Continued from ' +
      ExtractFileName(LOld));
    StartHousekeeping(FKind);
  except
    on E: Exception do
    begin
      // On in the file there was, which goes on growing
      FRotateFailed := True;
      if FWriter = nil then
        try
          FWriter := TStreamWriter.Create(LOld, True, TEncoding.UTF8);
          FWriter.AutoFlush := True;
          FFileName := LOld;
        except
          FWriter := nil;
        end;
      if FWriter <> nil then
        FWriter.WriteLine(FormatDateTime('hh:nn:ss', Now) + '  WARNING: could not start the ' +
          'next report file (' + E.Message.TrimRight(['.']) + '); carrying on in this one');
    end;
  end;
end;

procedure TDownloadReport.Add(const Msg: string);
begin
  TMonitor.Enter(FLock);
  try
    if FWriter = nil then
      Exit;
    FWriter.WriteLine(FormatDateTime('hh:nn:ss', Now) + '  ' + HideURLQueries(Msg));
    if not FRotateFailed and (FWriter.BaseStream.Size >= REPORT_ROTATE_BYTES) then
      Rotate;
  finally
    TMonitor.Exit(FLock);
  end;
end;

initialization
  GHousekeepingLock := TObject.Create;

finalization
  // Every tidying task started has ended, so none can reach the lock once
  // it is freed; if one has not ended after the wait, the lock is left
  // rather than freed under it
  if WaitForHousekeeping then
  begin
    GHousekeepingLog := nil;
    FreeAndNil(GHousekeepingLock);
  end;

end.
