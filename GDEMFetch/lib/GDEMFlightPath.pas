{ @abstract(Records the paths flown in the 3D view, saves them as
  @code(.flt) files, reads them back, and replays them
  (@link(TFlightReplay)).)

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

  { The slowest a replay flies a leg, metres a second. A leg flown slower
    than this on average had a hover or a pause in it (hovering makes no
    corners), so it is flown at this speed instead of sitting still. }
  REPLAY_MIN_SPEED = 10;

  { The speed a replay flies a leg whose times cannot be read, metres a
    second. }
  REPLAY_UNTIMED_SPEED = 200;

  { The least change of heading at a corner that a replay turns for on
    the spot, degrees. Turns made while flying leave corners about a
    degree apart and need none; a turn made while hovering leaves one
    large corner, which without this would swing the view round in a
    single frame. }
  REPLAY_TURN_FROM = 5;

  { Legs shorter than this are left out of a replay, metres. }
  REPLAY_MIN_LEG = 1;

type
  { @abstract(A flight path file that cannot be read.) }
  EFlightPathError = class(Exception);

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

  { @abstract(What a part of a replay does.) }
  TFlightReplayPhaseKind = (
    { Turns on the spot, hovering, at a corner. }
    rpkTurn,
    { Flies a leg from one corner to the next along a great circle. }
    rpkMove);

  { @abstract(A part of a replay: a turn on the spot or a leg.) }
  TFlightReplayPhase = record
    { What it does. }
    Kind: TFlightReplayPhaseKind;
    { When it starts, seconds from the start of the replay. }
    StartSeconds: Double;
    { How long it takes, seconds. }
    Seconds: Double;
    { Where it starts (a turn: where it is), latitude, degrees. }
    FromLatitude: Double;
    { Where it starts, longitude, degrees. }
    FromLongitude: Double;
    { Where a leg ends, latitude, degrees. }
    ToLatitude: Double;
    { Where a leg ends, longitude, degrees. }
    ToLongitude: Double;
    { A leg's length along the ground, metres. }
    Metres: Double;
    { A turn's heading at its start, degrees. }
    FromHeading: Double;
    { How far a turn turns, degrees: positive to the right. }
    Turn: Double;
  end;

  { @abstract(A saved flight path as a replay: where the flight is, which
    way it heads and how fast, at any time from its start.)

    The path is flown corner to corner along great circles, each leg in
    the time it was flown in (so at its average speed), except that a
    leg slower than @link(REPLAY_MIN_SPEED) is flown at that speed (it
    held a hover or a pause) and one faster than the flight's most speed
    at that. At a corner whose heading changes by more than
    @link(REPLAY_TURN_FROM) the replay hovers and turns at the flight's
    turning rate, as it was flown. Heights are not in the path; the
    flight that follows the replay keeps clear of the ground itself. No
    FMX. }
  TFlightReplay = class
  private
    { The turns and legs, in order. }
    FPhases: TArray<TFlightReplayPhase>;
    { The phase the last @link(PositionAt) was in, where the next search
      starts. }
    FCursor: Integer;
    { Backing field for @link(Duration). }
    FDuration: Double;
    { Backing field for @link(Name). }
    FName: string;
    { Backing field for @link(EndReason). }
    FEndReason: string;
    { Backing field for @link(PointCount). }
    FPointCount: Integer;
    { Backing field for @link(DistanceKm). }
    FDistanceKm: Double;
    { Backing field for @link(TurnCount). }
    FTurnCount: Integer;
    { Backing field for @link(StartLatitude). }
    FStartLatitude: Double;
    { Backing field for @link(StartLongitude). }
    FStartLongitude: Double;
    { Backing field for @link(StartHeading). }
    FStartHeading: Double;
    { Where the replay ends, latitude, degrees. }
    FEndLatitude: Double;
    { Where the replay ends, longitude, degrees. }
    FEndLongitude: Double;
    { The heading at the end, degrees. }
    FEndHeading: Double;
    { The time the replay has reached while being made, seconds. }
    FBuildSeconds: Double;

    { Adds a turn on the spot, if the heading changes enough.
      @param(ALatitude Where, latitude.)
      @param(ALongitude Where, longitude.)
      @param(AFrom The heading before.)
      @param(ATo The heading after.) }
    procedure AddTurn(ALatitude, ALongitude, AFrom, ATo: Double);
  public
    { Makes the replay of a saved path. Points that are not real places
      are left out, and so are legs shorter than @link(REPLAY_MIN_LEG).
      @param(ARecord The path.) }
    constructor Create(const ARecord: TFlightPathRecord);

    { Where the replay is at a time. Before the start it is at the start;
      from @link(Duration) on, at the end, hovering.
      @param(ASeconds Seconds from the start.)
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees, -180 to 180.)
      @param(AHeading Heading, degrees clockwise from north, 0 to 360.)
      @param(ASpeed Speed over the ground, metres a second; 0 while
        turning on the spot or at the end.) }
    procedure PositionAt(ASeconds: Double; out ALatitude, ALongitude, AHeading,
      ASpeed: Double);

    { How long it takes, seconds; 0 if there is nothing to fly (fewer
      than two places at least @link(REPLAY_MIN_LEG) apart). }
    property Duration: Double read FDuration;

    { The path's name. }
    property Name: string read FName;

    { Why the path ended, as saved. }
    property EndReason: string read FEndReason;

    { The places in the path that were used. }
    property PointCount: Integer read FPointCount;

    { Its length along the ground, kilometres, worked out again from the
      places. }
    property DistanceKm: Double read FDistanceKm;

    { How many turns on the spot it has. }
    property TurnCount: Integer read FTurnCount;

    { Where it starts, latitude, degrees. }
    property StartLatitude: Double read FStartLatitude;

    { Where it starts, longitude, degrees. }
    property StartLongitude: Double read FStartLongitude;

    { The heading it starts with, degrees. }
    property StartHeading: Double read FStartHeading;
  end;

{ Reads the flight paths in a @code(.flt) file.
  @param(AFileName The file.)
  @returns(The flights, as saved, oldest first.)
  @raises(EFlightPathError if the file cannot be read, is not a flight
    path file, or is of a later format.) }
function LoadFlightPaths(const AFileName: string): TArray<TFlightPathRecord>;

{ Reads a time as saved in a flight path file.
  @param(AText ISO 8601, as written by @link(TFlightPath.ToRecord).)
  @param(ATime The time, in UTC.)
  @returns(@false if it cannot be read.) }
function TryReadFlightTime(const AText: string; out ATime: TDateTime): Boolean;

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
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON, GDEMFlight;

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

function LoadFlightPaths(const AFileName: string): TArray<TFlightPathRecord>;
var
  LFile: TFlightPathFile;
begin
  try
    LFile := TNeon.JSONToValue<TFlightPathFile>(
      TEncoding.UTF8.GetString(TFile.ReadAllBytes(AFileName)), FlightPathNeonConfig);
  except
    on E: Exception do
      raise EFlightPathError.CreateFmt('Could not read %s: %s', [AFileName, E.Message]);
  end;
  if LFile.Format < 1 then
    raise EFlightPathError.CreateFmt('%s is not a flight path file: it has no format number.',
      [AFileName]);
  if LFile.Format > FLIGHT_PATH_FORMAT then
    raise EFlightPathError.CreateFmt('%s is format %d; this program reads format %d.',
      [AFileName, LFile.Format, FLIGHT_PATH_FORMAT]);
  Result := LFile.Flights;
end;

function TryReadFlightTime(const AText: string; out ATime: TDateTime): Boolean;
begin
  ATime := 0;
  Result := (AText <> '') and TryISO8601ToDate(AText, ATime, True);
end;

{ The heading at the start of the great circle from one place to another.
  @param(ALat1 From, latitude, degrees.)
  @param(ALon1 From, longitude, degrees.)
  @param(ALat2 To, latitude, degrees.)
  @param(ALon2 To, longitude, degrees.)
  @returns(Degrees clockwise from north, 0 to 360.) }
function InitialBearing(ALat1, ALon1, ALat2, ALon2: Double): Double;
var
  LPhi1, LPhi2, LDLon: Double;
begin
  LPhi1 := DegToRad(ALat1);
  LPhi2 := DegToRad(ALat2);
  LDLon := DegToRad(ALon2 - ALon1);
  Result := WrapDegrees(RadToDeg(ArcTan2(Sin(LDLon) * Cos(LPhi2),
    Cos(LPhi1) * Sin(LPhi2) - Sin(LPhi1) * Cos(LPhi2) * Cos(LDLon))));
end;

{ The heading on arrival along the great circle from one place to another:
  the way back, turned round.
  @param(ALat1 From, latitude, degrees.)
  @param(ALon1 From, longitude, degrees.)
  @param(ALat2 To, latitude, degrees.)
  @param(ALon2 To, longitude, degrees.)
  @returns(Degrees clockwise from north, 0 to 360.) }
function FinalBearing(ALat1, ALon1, ALat2, ALon2: Double): Double;
begin
  Result := WrapDegrees(InitialBearing(ALat2, ALon2, ALat1, ALon1) + 180);
end;

{ The place a share of the way along the great circle between two places.
  @param(ALat1 From, latitude, degrees.)
  @param(ALon1 From, longitude, degrees.)
  @param(ALat2 To, latitude, degrees.)
  @param(ALon2 To, longitude, degrees.)
  @param(AFraction The share of the way, 0 to 1.)
  @param(ALatitude The place, latitude, degrees.)
  @param(ALongitude The place, longitude, degrees, -180 to 180.) }
procedure IntermediatePoint(ALat1, ALon1, ALat2, ALon2, AFraction: Double;
  out ALatitude, ALongitude: Double);
var
  LDelta, LSinDelta, LA, LB, LX, LY, LZ, LCosPhi1, LCosPhi2: Double;
begin
  LDelta := GroundDistance(ALat1, ALon1, ALat2, ALon2) / EARTH_RADIUS_METRES;
  LSinDelta := Sin(LDelta);
  if LSinDelta < 1E-12 then
  begin
    ALatitude := ALat1;
    ALongitude := ALon1;
    Exit;
  end;
  LA := Sin((1 - AFraction) * LDelta) / LSinDelta;
  LB := Sin(AFraction * LDelta) / LSinDelta;
  LCosPhi1 := Cos(DegToRad(ALat1));
  LCosPhi2 := Cos(DegToRad(ALat2));
  LX := LA * LCosPhi1 * Cos(DegToRad(ALon1)) + LB * LCosPhi2 * Cos(DegToRad(ALon2));
  LY := LA * LCosPhi1 * Sin(DegToRad(ALon1)) + LB * LCosPhi2 * Sin(DegToRad(ALon2));
  LZ := LA * Sin(DegToRad(ALat1)) + LB * Sin(DegToRad(ALat2));
  ALatitude := RadToDeg(ArcTan2(LZ, Sqrt(Sqr(LX) + Sqr(LY))));
  ALongitude := RadToDeg(ArcTan2(LY, LX));
end;

{ The turn from one heading to another the short way round.
  @param(AFrom The heading before, degrees.)
  @param(ATo The heading after, degrees.)
  @returns(Degrees, -180 to 180: positive to the right.) }
function ShortestTurn(AFrom, ATo: Double): Double;
begin
  Result := WrapDegrees(ATo - AFrom);
  if Result > 180 then
    Result := Result - 360;
end;

{ Whether a saved point is a real place.
  @param(APoint The point.)
  @returns(@true if its latitude and longitude are numbers in range.) }
function IsPlace(const APoint: TFlightPoint): Boolean;
begin
  Result := not IsNan(APoint.Latitude) and not IsNan(APoint.Longitude) and
    InRange(APoint.Latitude, -90, 90) and InRange(APoint.Longitude, -180, 180);
end;

{ TFlightReplay }

constructor TFlightReplay.Create(const ARecord: TFlightPathRecord);
var
  LPoints: TArray<TFlightPoint>;
  LPoint, LFrom, LTo: TFlightPoint;
  LPhase: TFlightReplayPhase;
  LHeading, LMetres, LRecorded, LSeconds, LBearing: Double;
  LFromTime, LToTime: TDateTime;
  I: Integer;
begin
  inherited Create;
  FName := ARecord.Name;
  FEndReason := ARecord.EndReason;
  LPoints := nil;
  for LPoint in ARecord.Points do
    if IsPlace(LPoint) then
      LPoints := LPoints + [LPoint];
  FPointCount := Length(LPoints);
  if FPointCount = 0 then
    Exit;
  FStartLatitude := LPoints[0].Latitude;
  FStartLongitude := LPoints[0].Longitude;
  if IsNan(LPoints[0].Heading) or IsInfinite(LPoints[0].Heading) then
    FStartHeading := 0
  else
    FStartHeading := WrapDegrees(LPoints[0].Heading);
  FEndLatitude := FStartLatitude;
  FEndLongitude := FStartLongitude;
  LHeading := FStartHeading;
  LFrom := LPoints[0];
  for I := 1 to High(LPoints) do
  begin
    LTo := LPoints[I];
    LMetres := GroundDistance(LFrom.Latitude, LFrom.Longitude, LTo.Latitude, LTo.Longitude);
    // A short leg is left out, and its time goes into the next
    if LMetres < REPLAY_MIN_LEG then
      Continue;
    if TryReadFlightTime(LFrom.Time, LFromTime) and TryReadFlightTime(LTo.Time, LToTime) then
      LRecorded := Max((LToTime - LFromTime) * SecsPerDay, 0)
    else
      LRecorded := LMetres / REPLAY_UNTIMED_SPEED;
    // A hover or a pause in the leg is not sat through
    LSeconds := EnsureRange(LRecorded, LMetres / MAX_FLIGHT_SPEED, LMetres / REPLAY_MIN_SPEED);
    LBearing := InitialBearing(LFrom.Latitude, LFrom.Longitude, LTo.Latitude, LTo.Longitude);
    AddTurn(LFrom.Latitude, LFrom.Longitude, LHeading, LBearing);
    LPhase := Default(TFlightReplayPhase);
    LPhase.Kind := rpkMove;
    LPhase.StartSeconds := FBuildSeconds;
    LPhase.Seconds := LSeconds;
    LPhase.FromLatitude := LFrom.Latitude;
    LPhase.FromLongitude := LFrom.Longitude;
    LPhase.ToLatitude := LTo.Latitude;
    LPhase.ToLongitude := LTo.Longitude;
    LPhase.Metres := LMetres;
    LPhase.FromHeading := LBearing;
    FPhases := FPhases + [LPhase];
    FBuildSeconds := FBuildSeconds + LSeconds;
    FDistanceKm := FDistanceKm + LMetres / 1000;
    LHeading := FinalBearing(LFrom.Latitude, LFrom.Longitude, LTo.Latitude, LTo.Longitude);
    FEndLatitude := LTo.Latitude;
    FEndLongitude := LTo.Longitude;
    LFrom := LTo;
  end;
  FEndHeading := LHeading;
  // Turns come only before legs, so without a leg there is nothing
  FDuration := FBuildSeconds;
end;

procedure TFlightReplay.AddTurn(ALatitude, ALongitude, AFrom, ATo: Double);
var
  LTurn: Double;
  LPhase: TFlightReplayPhase;
begin
  LTurn := ShortestTurn(AFrom, ATo);
  if Abs(LTurn) <= REPLAY_TURN_FROM then
    Exit;
  LPhase := Default(TFlightReplayPhase);
  LPhase.Kind := rpkTurn;
  LPhase.StartSeconds := FBuildSeconds;
  LPhase.Seconds := Abs(LTurn) / FLIGHT_TURN_RATE;
  LPhase.FromLatitude := ALatitude;
  LPhase.FromLongitude := ALongitude;
  LPhase.ToLatitude := ALatitude;
  LPhase.ToLongitude := ALongitude;
  LPhase.FromHeading := AFrom;
  LPhase.Turn := LTurn;
  FPhases := FPhases + [LPhase];
  FBuildSeconds := FBuildSeconds + LPhase.Seconds;
  Inc(FTurnCount);
end;

procedure TFlightReplay.PositionAt(ASeconds: Double; out ALatitude, ALongitude, AHeading,
  ASpeed: Double);
var
  LPhase: TFlightReplayPhase;
  LFraction: Double;
begin
  if (FDuration <= 0) or (Length(FPhases) = 0) or (ASeconds >= FDuration) then
  begin
    ALatitude := FEndLatitude;
    ALongitude := FEndLongitude;
    AHeading := FEndHeading;
    ASpeed := 0;
    Exit;
  end;
  ASeconds := Max(ASeconds, 0);
  // Times usually only go forward, so the search starts where it was
  if (FCursor > High(FPhases)) or (ASeconds < FPhases[FCursor].StartSeconds) then
    FCursor := 0;
  while (FCursor < High(FPhases)) and (ASeconds >= FPhases[FCursor + 1].StartSeconds) do
    Inc(FCursor);
  LPhase := FPhases[FCursor];
  if LPhase.Seconds > 0 then
    LFraction := EnsureRange((ASeconds - LPhase.StartSeconds) / LPhase.Seconds, 0, 1)
  else
    LFraction := 1;
  if LPhase.Kind = rpkTurn then
  begin
    ALatitude := LPhase.FromLatitude;
    ALongitude := LPhase.FromLongitude;
    AHeading := WrapDegrees(LPhase.FromHeading + LPhase.Turn * LFraction);
    ASpeed := 0;
  end
  else
  begin
    IntermediatePoint(LPhase.FromLatitude, LPhase.FromLongitude, LPhase.ToLatitude,
      LPhase.ToLongitude, LFraction, ALatitude, ALongitude);
    // The way on to the leg's end; at the end itself, the way it arrives
    if GroundDistance(ALatitude, ALongitude, LPhase.ToLatitude, LPhase.ToLongitude) > 0.01 then
      AHeading := InitialBearing(ALatitude, ALongitude, LPhase.ToLatitude, LPhase.ToLongitude)
    else
      AHeading := FinalBearing(LPhase.FromLatitude, LPhase.FromLongitude, LPhase.ToLatitude,
        LPhase.ToLongitude);
    ASpeed := LPhase.Metres / LPhase.Seconds;
  end;
  ALongitude := WrapDegrees(ALongitude + 180) - 180;
end;

end.
