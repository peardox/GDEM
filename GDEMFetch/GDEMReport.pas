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

    { Adds a line, with the time in front.
      @param(Msg The text.) }
    procedure Add(const Msg: string);

    { Full path of the report file. }
    property FileName: string read FFileName;
  end;

implementation

uses
  System.IOUtils, System.Generics.Collections,
  GDEMSettings;

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
    FWriter.WriteLine(FormatDateTime('hh:nn:ss', Now) + '  ' + Msg);
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
