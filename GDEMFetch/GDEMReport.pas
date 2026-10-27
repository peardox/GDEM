{ @abstract(Writes the full record of a batch of downloads to a file.)

  A batch of downloads produces several lines for every file: the request,
  the redirect and where it was saved. For a large batch (the whole world
  is 22,912 tiles) that is far too much for the Debug tab, so the detail
  goes to a report file instead, and the Debug tab keeps only what matters:
  the start, any problems, and the summary.

  Reports are kept in a @code(Reports) folder beside the settings file (see
  @code(TGDEMSettings.SettingsFolder)), one per batch, named by the time
  the batch started, such as @code(download-20261026-231500.log). Only the
  newest @link(REPORTS_KEPT) are kept. }
unit GDEMReport;

interface

uses
  System.SysUtils, System.Classes;

const
  { Name of the folder reports are kept in, inside the settings folder. }
  REPORTS_FOLDER_NAME = 'Reports';

  { How many reports are kept; older ones are deleted when a new one is
    started. }
  REPORTS_KEPT = 50;

type
  { @abstract(A report file for one batch.)

    Lines are written as they arrive, each with the time, and flushed at
    once, so the file is complete up to the moment even if the program
    stops unexpectedly. All methods are thread-safe. }
  TDownloadReport = class
  private
    { Guards @link(FWriter). }
    FLock: TObject;
    { The open file. }
    FWriter: TStreamWriter;
    { Backing field for @link(FileName). }
    FFileName: string;
  public
    { Creates the report file, and deletes all but the newest
      @link(REPORTS_KEPT) reports.
      @param(AKind What the batch is, used in the file name, such as
        @code(download).)
      @raises(EInOutError or another exception if the file cannot be
        created.) }
    constructor Create(const AKind: string);

    { Closes the file. }
    destructor Destroy; override;

    { The folder reports are kept in.
      @returns(Full path of the folder, which may not exist yet.) }
    class function Folder: string; static;

    { Adds a line, with the time in front. Query strings in any web
      addresses in it are hidden first (see @link(HideURLQueries)).
      @param(Msg The text.) }
    procedure Add(const Msg: string);

    { Full path of the report file. }
    property FileName: string read FFileName;
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
  System.IOUtils, System.Generics.Collections,
  GDEMSettings;

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

{ TDownloadReport }

class function TDownloadReport.Folder: string;
begin
  Result := TPath.Combine(TGDEMSettings.SettingsFolder, REPORTS_FOLDER_NAME);
end;

constructor TDownloadReport.Create(const AKind: string);
var
  LFiles: TArray<string>;
  LIndex: Integer;
begin
  inherited Create;
  FLock := TObject.Create;
  ForceDirectories(Folder);

  // Names sort by time, so the oldest come first
  LFiles := TDirectory.GetFiles(Folder, AKind + '-*.log');
  TArray.Sort<string>(LFiles);
  for LIndex := 0 to Length(LFiles) - REPORTS_KEPT do
    try
      TFile.Delete(LFiles[LIndex]);
    except
      // An old report that cannot be deleted does no harm
    end;

  FFileName := TPath.Combine(Folder,
    Format('%s-%s.log', [AKind, FormatDateTime('yyyymmdd-hhnnss', Now)]));
  FWriter := TStreamWriter.Create(FFileName, False, TEncoding.UTF8);
  FWriter.AutoFlush := True;
end;

destructor TDownloadReport.Destroy;
begin
  FWriter.Free;
  FLock.Free;
  inherited;
end;

procedure TDownloadReport.Add(const Msg: string);
begin
  TMonitor.Enter(FLock);
  try
    FWriter.WriteLine(FormatDateTime('hh:nn:ss', Now) + '  ' + HideURLQueries(Msg));
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
