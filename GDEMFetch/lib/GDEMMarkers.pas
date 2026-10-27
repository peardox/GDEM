{ @abstract(The user's own named places on the map, such as Home or Work.)

  A @link(TMarkerList) holds the markers and keeps them in
  @link(MARKERS_FILE_NAME) in the settings folder (see
  @code(TGDEMSettings.SettingsFolder)), written with Neon as an object with
  a @code(format) number (see @link(MARKERS_FORMAT)) and a @code(markers)
  array, each marker an object with @code(name), @code(lat) and @code(lon)
  (see @link(TMapMarker)).
  The file is written whole each time, to a temporary file first and then
  renamed over the old one, so it is never left half written. Names are
  kept as typed; two markers may share a name.

  No FMX: any program can use it. }
unit GDEMMarkers;

interface

uses
  System.SysUtils,
  Neon.Core.Attributes;

const
  { The markers file, in the settings folder. }
  MARKERS_FILE_NAME = 'markers.json';

  { Version of the markers file this unit writes and reads. }
  MARKERS_FORMAT = 1;

  { Longest name kept, in characters; longer names are cut short. }
  MAX_MARKER_NAME_LENGTH = 80;

type
  { @abstract(Raised when the markers file cannot be read or written.) }
  EMarkerError = class(Exception);

  { @abstract(One marker.) }
  TMapMarker = record
    { What the user called it, such as @code(Home). }
    [NeonProperty('name')]
    Name: string;
    { Latitude, in degrees. }
    [NeonProperty('lat')]
    Lat: Double;
    { Longitude, from -180 to 180. }
    [NeonProperty('lon')]
    Lon: Double;
  end;

  { @abstract(The markers file's contents.) }
  TMarkerFile = record
    { Version of the file; see @link(MARKERS_FORMAT). }
    [NeonProperty('format')]
    Format: Integer;
    { The markers, in the order they were added. }
    [NeonProperty('markers')]
    Markers: TArray<TMapMarker>;
  end;

  { @abstract(The user's markers, kept in a file.) }
  TMarkerList = class
  private
    { The markers. }
    FItems: TArray<TMapMarker>;
    { Backing field for @link(FileName). }
    FFileName: string;

    { Reader for @link(Count).
      @returns(How many markers there are.) }
    function GetCount: Integer;

    { Reader for @link(Items).
      @param(AIndex Which marker, from 0.)
      @returns(The marker.) }
    function GetItem(AIndex: Integer): TMapMarker;
  public
    { Makes an empty list, kept in a file.
      @param(AFileName The file; empty for @link(MARKERS_FILE_NAME) in the
        settings folder.) }
    constructor Create(const AFileName: string = '');

    { Tidies a name as typed: spaces trimmed, line breaks and other control
      characters dropped, and cut to @link(MAX_MARKER_NAME_LENGTH).
      @param(AName The name.)
      @returns(The tidied name; may be empty.) }
    class function CleanName(const AName: string): string; static;

    { Reads the file, replacing any markers held. A missing file is not an
      error: the list is just empty.
      @returns(@true if the file was there and read.)
      @raises(EMarkerError if the file is there but cannot be read.) }
    function Load: Boolean;

    { Writes the file.
      @raises(EMarkerError if it cannot be written.) }
    procedure Save;

    { Adds a marker. Does not save.
      @param(AName Its name, tidied by @link(CleanName); must not be
        empty after tidying.)
      @param(ALat Latitude, in degrees.)
      @param(ALon Longitude, in degrees; wrapped into -180 to 180.)
      @returns(Its index.)
      @raises(EMarkerError if the name is empty.) }
    function Add(const AName: string; ALat, ALon: Double): Integer;

    { Renames a marker. Does not save.
      @param(AIndex Which marker.)
      @param(AName The new name, tidied by @link(CleanName); must not be
        empty after tidying.)
      @raises(EMarkerError if the name is empty.) }
    procedure Rename(AIndex: Integer; const AName: string);

    { Removes a marker. Does not save.
      @param(AIndex Which marker.) }
    procedure Delete(AIndex: Integer);

    { The file the markers are kept in. }
    property FileName: string read FFileName;

    { How many markers there are. }
    property Count: Integer read GetCount;

    { The markers. }
    property Items[AIndex: Integer]: TMapMarker read GetItem; default;
  end;

implementation

uses
  System.IOUtils, System.Math, System.Rtti,
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON,
  GDEMSettings;

{ The Neon configuration for the markers file: names exactly as in the
  [NeonProperty] attributes, laid out readably, and exceptions raised so a
  bad file is reported.
  @returns(The configuration.) }
function MarkersNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Create
    .SetMemberCase(TNeonCase.Unchanged)
    .SetPrettyPrint(True)
    .SetRaiseExceptions(True);
end;

{ Wraps a longitude into -180 to 180.
  @param(ALon The longitude, in degrees.)
  @returns(The same meridian, from -180 up to but not including 180.) }
function WrapLon(ALon: Double): Double;
begin
  Result := ALon - Floor((ALon + 180) / 360) * 360;
end;

{ TMarkerList }

constructor TMarkerList.Create(const AFileName: string);
begin
  inherited Create;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := TPath.Combine(TGDEMSettings.SettingsFolder, MARKERS_FILE_NAME);
end;

class function TMarkerList.CleanName(const AName: string): string;
var
  LChar: Char;
begin
  Result := '';
  for LChar in AName do
    if LChar >= ' ' then
      Result := Result + LChar
    else
      Result := Result + ' ';
  Result := Result.Trim;
  if Length(Result) > MAX_MARKER_NAME_LENGTH then
    Result := Result.Substring(0, MAX_MARKER_NAME_LENGTH).TrimRight;
end;

function TMarkerList.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TMarkerList.GetItem(AIndex: Integer): TMapMarker;
begin
  Result := FItems[AIndex];
end;

function TMarkerList.Load: Boolean;
var
  LFile: TMarkerFile;
  LMarker: TMapMarker;
  LItems: TArray<TMapMarker>;
begin
  if not TFile.Exists(FFileName) then
  begin
    FItems := nil;
    Exit(False);
  end;
  try
    LFile := TNeon.JSONToValue<TMarkerFile>(
      TEncoding.UTF8.GetString(TFile.ReadAllBytes(FFileName)), MarkersNeonConfig);
  except
    on E: Exception do
      raise EMarkerError.CreateFmt('Could not read %s: %s', [FFileName, E.Message]);
  end;
  if LFile.Format > MARKERS_FORMAT then
    raise EMarkerError.CreateFmt('%s is format %d; this program reads format %d.',
      [FFileName, LFile.Format, MARKERS_FORMAT]);
  // Keep only markers that make sense, so a hand-edited file cannot put
  // one off the map
  LItems := nil;
  for LMarker in LFile.Markers do
    if (CleanName(LMarker.Name) <> '') and InRange(LMarker.Lat, -90, 90) and
       not IsNan(LMarker.Lon) and not IsInfinite(LMarker.Lon) then
    begin
      LItems := LItems + [LMarker];
      LItems[High(LItems)].Name := CleanName(LMarker.Name);
      LItems[High(LItems)].Lon := WrapLon(LMarker.Lon);
    end;
  FItems := LItems;
  Result := True;
end;

procedure TMarkerList.Save;
var
  LFile: TMarkerFile;
  LTempName, LJSON: string;
begin
  LFile.Format := MARKERS_FORMAT;
  LFile.Markers := FItems;
  LTempName := FFileName + '.tmp';
  try
    ForceDirectories(ExtractFileDir(FFileName));
    LJSON := TNeon.ValueToJSONString(TValue.From<TMarkerFile>(LFile), MarkersNeonConfig);
    TFile.WriteAllBytes(LTempName, TEncoding.UTF8.GetBytes(LJSON));
    if TFile.Exists(FFileName) then
      TFile.Delete(FFileName);
    TFile.Move(LTempName, FFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise EMarkerError.CreateFmt('Could not write %s: %s', [FFileName, E.Message]);
    end;
  end;
end;

function TMarkerList.Add(const AName: string; ALat, ALon: Double): Integer;
var
  LMarker: TMapMarker;
begin
  LMarker.Name := CleanName(AName);
  if LMarker.Name = '' then
    raise EMarkerError.Create('A marker needs a name.');
  LMarker.Lat := EnsureRange(ALat, -90, 90);
  LMarker.Lon := WrapLon(ALon);
  FItems := FItems + [LMarker];
  Result := High(FItems);
end;

procedure TMarkerList.Rename(AIndex: Integer; const AName: string);
var
  LName: string;
begin
  LName := CleanName(AName);
  if LName = '' then
    raise EMarkerError.Create('A marker needs a name.');
  FItems[AIndex].Name := LName;
end;

procedure TMarkerList.Delete(AIndex: Integer);
begin
  System.Delete(FItems, AIndex, 1);
end;

end.
