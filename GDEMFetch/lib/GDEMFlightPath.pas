{ @abstract(Records the paths flown in the 3D view and saves them as
  @code(.flt) files.)

  A flight path is a list of points, each a place and the heading there:
  one where the flight starts, and another each time the heading changes
  (by at least @link(FLIGHT_PATH_TURN) degrees, once the flight has moved
  on from the last point). Height is not kept. Between points the flight
  went straight on, so the points are the corners of the path; while the
  flight is still going, the place it is at now is the end of the last
  line.

  A path ends in one of three ways (@link(FLIGHT_END_CRASHED),
  @link(FLIGHT_END_ENDED), @link(FLIGHT_END_IN_FLIGHT)): a crash, a new
  flight started (which ends the one before), or not at all yet. Saved
  while still in flight, the place the flight is at is added as the last
  point.

  A @code(.flt) file is JSON, written with Neon: a format number, when it
  was saved, and the flights, each with when it started and ended, why it
  ended, its length and its points. }
unit GDEMFlightPath;

interface

uses
  System.SysUtils, System.Types, System.Generics.Collections, Neon.Core.Attributes;

const
  { The extension of flight path files. }
  FLIGHT_PATH_EXTENSION = '.flt';

  { The version of the flight path file written. }
  FLIGHT_PATH_FORMAT = 1;

  { Why a path ended: the flight crashed into the ground. }
  FLIGHT_END_CRASHED = 'Crashed';

  { Why a path ended: a new flight was started. }
  FLIGHT_END_ENDED = 'Flight Ended';

  { Why a path ended: it has not; the flight is still going. }
  FLIGHT_END_IN_FLIGHT = 'In Flight';

  { The least change of heading that makes a new point, degrees. }
  FLIGHT_PATH_TURN = 1.0;

  { The least distance from the last point at which a new point is made,
    metres, so turning while hovering does not pile points up in one
    place. }
  FLIGHT_PATH_MIN_MOVE = 1.0;

type
  { @abstract(A corner of a flight path.) }
  TFlightPoint = record
    { Latitude, degrees. }
    [NeonProperty('lat')]
    Latitude: Double;
    { Longitude, degrees, -180 to 180. }
    [NeonProperty('lon')]
    Longitude: Double;
    { The heading from here, degrees clockwise from true north. }
    [NeonProperty('heading')]
    Heading: Double;
    { When the flight was here, ISO 8601 in UTC. }
    [NeonProperty('time')]
    Time: string;
  end;

  { @abstract(One flight path, as saved.) }
  TFlightPathRecord = record
    { Where it started, such as the place launched at; may be empty. }
    [NeonProperty('name')]
    Name: string;
    { When it started, ISO 8601 in UTC. }
    [NeonProperty('started')]
    Started: string;
    { When it ended, ISO 8601 in UTC; when saved, for a flight still
      going. }
    [NeonProperty('ended')]
    Ended: string;
    { Why it ended: @link(FLIGHT_END_CRASHED), @link(FLIGHT_END_ENDED) or
      @link(FLIGHT_END_IN_FLIGHT). }
    [NeonProperty('endReason')]
    EndReason: string;
    { Its length along the ground, kilometres. }
    [NeonProperty('distanceKm')]
    DistanceKm: Double;
    { Its corners, in order; the last is where it ended, or where the
      flight was when saved. }
    [NeonProperty('points')]
    Points: TArray<TFlightPoint>;
  end;

  { @abstract(A flight path file's contents.) }
  TFlightPathFile = record
    { Version of the file; see @link(FLIGHT_PATH_FORMAT). }
    [NeonProperty('format')]
    Format: Integer;
    { The program that wrote it. }
    [NeonProperty('program')]
    ProgramName: string;
    { When it was saved, ISO 8601 in UTC. }
    [NeonProperty('saved')]
    Saved: string;
    { The flights, oldest first. }
    [NeonProperty('flights')]
    Flights: TArray<TFlightPathRecord>;
  end;

  { @abstract(A flight path being recorded, or ended.) }
  TFlightPath = class
  private
    { The corners so far. }
    FPoints: TList<TFlightPoint>;
    { Backing field for @link(Name). }
    FName: string;
    { When it started. }
    FStarted: TDateTime;
    { When it ended; 0 while in flight. }
    FEnded: TDateTime;
    { Backing field for @link(EndReason). }
    FEndReason: string;
    { Where the flight is now, latitude. }
    FCurrentLatitude: Double;
    { Where the flight is now, longitude. }
    FCurrentLongitude: Double;
    { The heading now. }
    FCurrentHeading: Double;

    { Adds a corner.
      @param(ALatitude Latitude.)
      @param(ALongitude Longitude.)
      @param(AHeading Heading.) }
    procedure AddPoint(ALatitude, ALongitude, AHeading: Double);

    { Reader for @link(Ended). @returns(@true once it has ended.) }
    function GetEnded: Boolean;

    { Reader for @link(PointCount). @returns(Corners so far.) }
    function GetPointCount: Integer;
  public
    { Starts a path at a place.
      @param(ALatitude Latitude.)
      @param(ALongitude Longitude.)
      @param(AHeading Heading.)
      @param(AName Where it started, such as the place launched at.) }
    constructor Create(ALatitude, ALongitude, AHeading: Double; const AName: string);

    { Frees the path. }
    destructor Destroy; override;

    { Tells the path where the flight is now: a corner is made if the
      heading has changed by @link(FLIGHT_PATH_TURN) or more since the last
      corner and the flight has moved on from it. Nothing once ended.
      @param(ALatitude Latitude.)
      @param(ALongitude Longitude.)
      @param(AHeading Heading.) }
    procedure Update(ALatitude, ALongitude, AHeading: Double);

    { Ends the path where the flight is, for a reason. Nothing if it has
      ended already.
      @param(AReason @link(FLIGHT_END_CRASHED) or @link(FLIGHT_END_ENDED).)
      @param(ALatitude Latitude.)
      @param(ALongitude Longitude.)
      @param(AHeading Heading.) }
    procedure Finish(const AReason: string; ALatitude, ALongitude, AHeading: Double);

    { The path's corners, and while in flight the place the flight is at,
      as X = longitude and Y = latitude, for drawing.
      @returns(The points, in order.) }
    function Track: TArray<TPointF>;

    { The path as saved: still in flight, the place the flight is at is
      the last point and the end time is now.
      @returns(The record.) }
    function ToRecord: TFlightPathRecord;

    { Its length along the ground so far, kilometres, to where the flight
      is now. }
    function DistanceKm: Double;

    { Where it started, such as the place launched at. }
    property Name: string read FName;

    { Why it ended; @link(FLIGHT_END_IN_FLIGHT) while it has not. }
    property EndReason: string read FEndReason;

    { @true once it has ended. }
    property Ended: Boolean read GetEnded;

    { Corners so far. }
    property PointCount: Integer read GetPointCount;
  end;

{ Saves flight paths to a @code(.flt) file, whole or not at all (written
  to a temporary file, then put in place).
  @param(AFileName The file.)
  @param(AFlights The flights, oldest first.)
  @raises(Exception if it cannot be written.) }
procedure SaveFlightPaths(const AFileName: string; const AFlights: TArray<TFlightPathRecord>);

{ The distance between two places along the ground, on a sphere.
  @param(ALat1 First latitude, degrees.)
  @param(ALon1 First longitude, degrees.)
  @param(ALat2 Second latitude, degrees.)
  @param(ALon2 Second longitude, degrees.)
  @returns(Metres.) }
function GroundDistance(ALat1, ALon1, ALat2, ALon2: Double): Double;

implementation

uses
  System.IOUtils, System.Math, System.Rtti, System.DateUtils,
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON;

const
  { The Earth's mean radius, metres. }
  EARTH_RADIUS_METRES = 6371008.8;

{ The Neon configuration for flight path files: names as in the
  [NeonProperty] attributes, laid out readably, exceptions raised.
  @returns(The configuration.) }
function FlightPathNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Create
    .SetMemberCase(TNeonCase.Unchanged)
    .SetPrettyPrint(True)
    .SetRaiseExceptions(True);
end;

{ A time as ISO 8601 in UTC.
  @param(ATime A local time.)
  @returns(Such as @code(2026-10-28T18:30:00.000Z).) }
function UtcText(ATime: TDateTime): string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(ATime), True);
end;

function GroundDistance(ALat1, ALon1, ALat2, ALon2: Double): Double;
var
  LDLat, LDLon, LA: Double;
begin
  // Haversine
  LDLat := DegToRad(ALat2 - ALat1);
  LDLon := DegToRad(ALon2 - ALon1);
  LA := Sqr(Sin(LDLat / 2)) + Cos(DegToRad(ALat1)) * Cos(DegToRad(ALat2)) * Sqr(Sin(LDLon / 2));
  Result := 2 * EARTH_RADIUS_METRES * ArcSin(Min(Sqrt(LA), 1));
end;

{ The smallest angle between two headings.
  @param(A One heading, degrees.)
  @param(B The other.)
  @returns(0 to 180 degrees.) }
function HeadingDifference(A, B: Double): Double;
begin
  Result := Abs(A - B);
  Result := Result - 360 * Floor(Result / 360);
  if Result > 180 then
    Result := 360 - Result;
end;

{ TFlightPath }

constructor TFlightPath.Create(ALatitude, ALongitude, AHeading: Double; const AName: string);
begin
  inherited Create;
  FPoints := TList<TFlightPoint>.Create;
  FName := AName;
  FStarted := Now;
  FEndReason := FLIGHT_END_IN_FLIGHT;
  FCurrentLatitude := ALatitude;
  FCurrentLongitude := ALongitude;
  FCurrentHeading := AHeading;
  AddPoint(ALatitude, ALongitude, AHeading);
end;

destructor TFlightPath.Destroy;
begin
  FPoints.Free;
  inherited;
end;

procedure TFlightPath.AddPoint(ALatitude, ALongitude, AHeading: Double);
var
  LPoint: TFlightPoint;
begin
  LPoint.Latitude := ALatitude;
  LPoint.Longitude := ALongitude;
  LPoint.Heading := AHeading;
  LPoint.Time := UtcText(Now);
  FPoints.Add(LPoint);
end;

function TFlightPath.GetEnded: Boolean;
begin
  Result := FEndReason <> FLIGHT_END_IN_FLIGHT;
end;

function TFlightPath.GetPointCount: Integer;
begin
  Result := FPoints.Count;
end;

procedure TFlightPath.Update(ALatitude, ALongitude, AHeading: Double);
var
  LLast: TFlightPoint;
begin
  if Ended then
    Exit;
  FCurrentLatitude := ALatitude;
  FCurrentLongitude := ALongitude;
  FCurrentHeading := AHeading;
  LLast := FPoints.Last;
  if (HeadingDifference(AHeading, LLast.Heading) >= FLIGHT_PATH_TURN) and
     (GroundDistance(LLast.Latitude, LLast.Longitude, ALatitude, ALongitude) >=
      FLIGHT_PATH_MIN_MOVE) then
    AddPoint(ALatitude, ALongitude, AHeading);
end;

procedure TFlightPath.Finish(const AReason: string; ALatitude, ALongitude, AHeading: Double);
begin
  if Ended then
    Exit;
  FCurrentLatitude := ALatitude;
  FCurrentLongitude := ALongitude;
  FCurrentHeading := AHeading;
  AddPoint(ALatitude, ALongitude, AHeading);
  FEnded := Now;
  FEndReason := AReason;
end;

function TFlightPath.Track: TArray<TPointF>;
var
  I: Integer;
begin
  SetLength(Result, FPoints.Count);
  for I := 0 to FPoints.Count - 1 do
    Result[I] := PointF(FPoints[I].Longitude, FPoints[I].Latitude);
  if not Ended then
    Result := Result + [PointF(FCurrentLongitude, FCurrentLatitude)];
end;

function TFlightPath.DistanceKm: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to FPoints.Count - 1 do
    Result := Result + GroundDistance(FPoints[I - 1].Latitude, FPoints[I - 1].Longitude,
      FPoints[I].Latitude, FPoints[I].Longitude);
  if not Ended and (FPoints.Count > 0) then
    Result := Result + GroundDistance(FPoints.Last.Latitude, FPoints.Last.Longitude,
      FCurrentLatitude, FCurrentLongitude);
  Result := Result / 1000;
end;

function TFlightPath.ToRecord: TFlightPathRecord;
var
  LPoint: TFlightPoint;
begin
  Result.Name := FName;
  Result.Started := UtcText(FStarted);
  Result.EndReason := FEndReason;
  Result.DistanceKm := RoundTo(DistanceKm, -3);
  Result.Points := FPoints.ToArray;
  if Ended then
    Result.Ended := UtcText(FEnded)
  else
  begin
    // Still going: it ends, for now, where the flight is
    Result.Ended := UtcText(Now);
    LPoint.Latitude := FCurrentLatitude;
    LPoint.Longitude := FCurrentLongitude;
    LPoint.Heading := FCurrentHeading;
    LPoint.Time := Result.Ended;
    Result.Points := Result.Points + [LPoint];
  end;
end;

procedure SaveFlightPaths(const AFileName: string; const AFlights: TArray<TFlightPathRecord>);
var
  LFile: TFlightPathFile;
  LTempName, LJSON: string;
begin
  LFile.Format := FLIGHT_PATH_FORMAT;
  LFile.ProgramName := 'GDEMFetch';
  LFile.Saved := UtcText(Now);
  LFile.Flights := AFlights;
  LTempName := AFileName + '.tmp';
  try
    if ExtractFileDir(AFileName) <> '' then
      ForceDirectories(ExtractFileDir(AFileName));
    LJSON := TNeon.ValueToJSONString(TValue.From<TFlightPathFile>(LFile), FlightPathNeonConfig);
    TFile.WriteAllBytes(LTempName, TEncoding.UTF8.GetBytes(LJSON));
    if TFile.Exists(AFileName) then
      TFile.Delete(AFileName);
    TFile.Move(LTempName, AFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise Exception.CreateFmt('Could not write %s: %s', [AFileName, E.Message]);
    end;
  end;
end;

end.
