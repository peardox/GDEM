{ @abstract(A simple flight over the ground: where the camera is, which way
  it goes and how fast, how it climbs and turns, and whether it has hit
  the ground.)

  @link(TFlight) keeps its position as latitude, longitude and altitude
  (true metres above sea level), and its heading against true north, so
  it does not depend on where the 3D view measures its positions from.
  It moves along a great circle, the heading turning with it, so flying
  straight on keeps going straight over the globe.

  The controls are held, not pressed: @link(TFlight.Step) is given the
  controls held and the seconds since the last step, and changes speed,
  heading, height and the camera's tilt at a rate per second. Speed and
  height change faster the faster or higher the flight already is, so the
  same keys serve from hovering over a field to crossing a continent.

  Heights are true: the 3D view stretches them for drawing, but the
  flight, the ground under it and the crash test are all on the ground's
  true scale. No FMX. }
unit GDEMFlight;

interface

uses
  System.SysUtils, System.Math;

const
  { The starting height above the ground, metres, when the settings give
    none. }
  DEFAULT_FLIGHT_START_HEIGHT = 10000;

  { The most speed, metres a second: about 10,800 km/h, three times the
    speed of sound, enough to cross a tile in 40 seconds. }
  MAX_FLIGHT_SPEED = 3000;

  { The least speed gained or lost each second a speed key is held,
    metres a second: about 72 km/h a second, so a hover starts moving at
    once. }
  FLIGHT_ACCEL_MIN = 20;

  { The share of the speed gained or lost each second a speed key is held,
    above @link(FLIGHT_ACCEL_MIN); 0.6 makes the speed nearly double in a
    second when fast. }
  FLIGHT_ACCEL_SHARE = 0.6;

  { Degrees turned each second a turn key is held. }
  FLIGHT_TURN_RATE = 45;

  { The least height gained or lost each second a height key is held,
    metres. }
  FLIGHT_CLIMB_MIN = 50;

  { The share of the height above the ground gained or lost each second a
    height key is held, above @link(FLIGHT_CLIMB_MIN). }
  FLIGHT_CLIMB_SHARE = 0.5;

  { The highest the flight may go, metres above sea level. }
  MAX_FLIGHT_ALTITUDE = 500000;

  { Degrees the camera tilts each second a tilt key is held. }
  FLIGHT_TILT_RATE = 30;

  { The camera's starting tilt: degrees below the level, a shallow look
    down ahead. }
  DEFAULT_FLIGHT_TILT = 20;

  { The camera's least tilt, degrees: a little above the level. }
  MIN_FLIGHT_TILT = -30;

  { The camera's most tilt, degrees: almost straight down. }
  MAX_FLIGHT_TILT = 89;

  { The Earth's mean radius, metres, for moving over it. }
  FLIGHT_EARTH_RADIUS = 6371008.8;

type
  { @abstract(One control the flight can be given.) }
  TFlightControl = (
    { Go faster. }
    fcFaster,
    { Go slower, down to a hover. }
    fcSlower,
    { Turn to the left. }
    fcTurnLeft,
    { Turn to the right. }
    fcTurnRight,
    { Go up. }
    fcClimb,
    { Go down. }
    fcDescend,
    { Tilt the camera up, towards the level and above. }
    fcTiltUp,
    { Tilt the camera down, towards the ground below. }
    fcTiltDown);

  { @abstract(The controls held.) }
  TFlightControls = set of TFlightControl;

  { @abstract(Gives the ground's true height at a place.)
    @param(ALatitude Latitude, degrees.)
    @param(ALongitude Longitude, degrees.)
    @param(AMetres The height above sea level, metres.)
    @returns(@false if the ground there is not known yet.) }
  TGroundHeightFunc = function(ALatitude, ALongitude: Double; out AMetres: Double): Boolean of object;

  { @abstract(The flight: position, heading, speed, the camera's tilt, and
    whether it has crashed.) }
  TFlight = class
  private
    { Backing field for @link(Latitude). }
    FLatitude: Double;
    { Backing field for @link(Longitude). }
    FLongitude: Double;
    { Backing field for @link(Altitude). }
    FAltitude: Double;
    { Backing field for @link(Heading). }
    FHeading: Double;
    { Backing field for @link(Speed). }
    FSpeed: Double;
    { Backing field for @link(Tilt). }
    FTilt: Double;
    { Backing field for @link(Crashed). }
    FCrashed: Boolean;
    { Backing field for @link(StartHeight). }
    FStartHeight: Double;
    { @true until the ground under the start has been known, so the
      height above it can be set; the flight hovers at
      @link(StartHeight) above sea level meanwhile. }
    FStartPending: Boolean;
    { Backing field for @link(Ground). }
    FGround: TGroundHeightFunc;

    { The height above the ground now, metres, for the climb rate; the
      altitude if the ground is not known.
      @returns(Metres, at least 0.) }
    function HeightAboveGround: Double;

    { Moves along a great circle, turning the heading as the circle does.
      @param(AMetres How far, along the ground.) }
    procedure MoveOn(AMetres: Double);
  public
    { Makes a flight hovering at 0, 0; call @link(Start).
      @param(AGround Gives the ground's height; required for the start
        height and the crash test.) }
    constructor Create(AGround: TGroundHeightFunc);

    { Starts again: hovering, facing north, the camera at its starting
      tilt, @link(StartHeight) above the ground at a place (above sea
      level until that ground is known).
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.) }
    procedure Start(ALatitude, ALongitude: Double);

    { Moves on by a length of time with some controls held, and tests for
      the ground.
      @param(AControls The controls held.)
      @param(ASeconds The time since the last step; kept to at most a
        tenth of a second, so a pause does not jump the flight.)
      @returns(@true if anything changed: position, heading, height, tilt
        or speed.) }
    function Step(AControls: TFlightControls; ASeconds: Double): Boolean;

    { Changes the height at once, as the mouse wheel does, by a share of
      the height above the ground; the next @link(Step) tests for the
      ground.
      @param(ANotches Wheel notches: positive climbs, negative descends.) }
    procedure Climb(ANotches: Double);

    { Turns and tilts at once, as dragging does.
      @param(ADegreesRight Degrees to turn to the right.)
      @param(ADegreesDown Degrees to tilt the camera down.) }
    procedure Look(ADegreesRight, ADegreesDown: Double);

    { Stops at once, to a hover. }
    procedure Stop;

    { Latitude, degrees. }
    property Latitude: Double read FLatitude;

    { Longitude, degrees, -180 to 180. }
    property Longitude: Double read FLongitude;

    { True height above sea level, metres. }
    property Altitude: Double read FAltitude;

    { The way the flight goes, degrees clockwise from true north, 0 to
      360. }
    property Heading: Double read FHeading;

    { Speed over the ground, metres a second; 0 is a hover, never less. }
    property Speed: Double read FSpeed;

    { The camera's tilt below the level, degrees, from
      @link(MIN_FLIGHT_TILT) to @link(MAX_FLIGHT_TILT). }
    property Tilt: Double read FTilt;

    { @true once the flight has gone below the ground; it then stays where
      it hit, on the ground, and does nothing until @link(Start). }
    property Crashed: Boolean read FCrashed;

    { How far above the ground the flight starts, metres. }
    property StartHeight: Double read FStartHeight write FStartHeight;
  end;

{ Brings an angle into 0 to 360 degrees.
  @param(ADegrees The angle.)
  @returns(The same angle, 0 or more and under 360.) }
function WrapDegrees(ADegrees: Double): Double;

implementation

function WrapDegrees(ADegrees: Double): Double;
begin
  Result := ADegrees - 360 * Floor(ADegrees / 360);
end;

{ TFlight }

constructor TFlight.Create(AGround: TGroundHeightFunc);
begin
  inherited Create;
  FGround := AGround;
  FStartHeight := DEFAULT_FLIGHT_START_HEIGHT;
  FTilt := DEFAULT_FLIGHT_TILT;
end;

procedure TFlight.Start(ALatitude, ALongitude: Double);
begin
  FLatitude := ALatitude;
  FLongitude := ALongitude;
  FHeading := 0;
  FSpeed := 0;
  FTilt := DEFAULT_FLIGHT_TILT;
  FCrashed := False;
  FAltitude := FStartHeight;
  FStartPending := True;
end;

function TFlight.HeightAboveGround: Double;
var
  LGround: Double;
begin
  if Assigned(FGround) and FGround(FLatitude, FLongitude, LGround) then
    Result := Max(FAltitude - LGround, 0)
  else
    Result := Max(FAltitude, 0);
end;

procedure TFlight.MoveOn(AMetres: Double);
var
  LAngle, LSinLat1, LCosLat1, LSinLat2, LCosLat2, LSinAngle, LCosAngle, LSinHeading,
    LCosHeading, LLat2, LDeltaLon: Double;
begin
  // The angle travelled round the Earth's centre, at the flight's height
  LAngle := AMetres / (FLIGHT_EARTH_RADIUS + Max(FAltitude, 0));
  SinCos(DegToRad(FLatitude), LSinLat1, LCosLat1);
  SinCos(LAngle, LSinAngle, LCosAngle);
  SinCos(DegToRad(FHeading), LSinHeading, LCosHeading);
  LSinLat2 := EnsureRange(LSinLat1 * LCosAngle + LCosLat1 * LSinAngle * LCosHeading, -1, 1);
  LLat2 := ArcSin(LSinLat2);
  LCosLat2 := Cos(LLat2);
  LDeltaLon := ArcTan2(LSinHeading * LSinAngle * LCosLat1, LCosAngle - LSinLat1 * LSinLat2);
  // The heading on arrival: the way back to where it started, turned
  // round
  if LCosLat2 > 1E-9 then
    FHeading := WrapDegrees(RadToDeg(ArcTan2(Sin(-LDeltaLon) * LCosLat1,
      LCosLat2 * LSinLat1 - LSinLat2 * LCosLat1 * Cos(-LDeltaLon))) + 180);
  FLatitude := RadToDeg(LLat2);
  FLongitude := FLongitude + RadToDeg(LDeltaLon);
  FLongitude := WrapDegrees(FLongitude + 180) - 180;
end;

function TFlight.Step(AControls: TFlightControls; ASeconds: Double): Boolean;
var
  LRate, LGround, LBefore: Double;
begin
  Result := False;
  ASeconds := EnsureRange(ASeconds, 0, 0.1);

  // The start's height above the ground, once the ground is known; the
  // height keys take over from it
  if FStartPending then
  begin
    if AControls * [fcClimb, fcDescend] <> [] then
      FStartPending := False
    else if Assigned(FGround) and FGround(FLatitude, FLongitude, LGround) then
    begin
      FAltitude := LGround + FStartHeight;
      FStartPending := False;
      Result := True;
    end;
  end;

  if FCrashed or (ASeconds <= 0) then
    Exit;

  // Speed: faster the faster already, never backwards
  LBefore := FSpeed;
  LRate := Max(FLIGHT_ACCEL_MIN, FLIGHT_ACCEL_SHARE * FSpeed) * ASeconds;
  if fcFaster in AControls then
    FSpeed := FSpeed + LRate;
  if fcSlower in AControls then
    FSpeed := FSpeed - LRate;
  FSpeed := EnsureRange(FSpeed, 0, MAX_FLIGHT_SPEED);
  if FSpeed <> LBefore then
    Result := True;

  if fcTurnLeft in AControls then
    FHeading := FHeading - FLIGHT_TURN_RATE * ASeconds;
  if fcTurnRight in AControls then
    FHeading := FHeading + FLIGHT_TURN_RATE * ASeconds;
  FHeading := WrapDegrees(FHeading);

  if fcTiltUp in AControls then
    FTilt := FTilt - FLIGHT_TILT_RATE * ASeconds;
  if fcTiltDown in AControls then
    FTilt := FTilt + FLIGHT_TILT_RATE * ASeconds;
  FTilt := EnsureRange(FTilt, MIN_FLIGHT_TILT, MAX_FLIGHT_TILT);

  // Height: a share of the height above the ground, so it is quick high
  // up and gentle low down, but never so gentle the ground cannot be hit
  LRate := Max(FLIGHT_CLIMB_MIN, FLIGHT_CLIMB_SHARE * HeightAboveGround) * ASeconds;
  if fcClimb in AControls then
    FAltitude := FAltitude + LRate;
  if fcDescend in AControls then
    FAltitude := FAltitude - LRate;
  FAltitude := Min(FAltitude, MAX_FLIGHT_ALTITUDE);

  if AControls * [fcTurnLeft, fcTurnRight, fcTiltUp, fcTiltDown, fcClimb, fcDescend] <> [] then
    Result := True;

  if FSpeed > 0 then
  begin
    MoveOn(FSpeed * ASeconds);
    Result := True;
  end;

  // Below the ground is a crash: stop there, on the ground
  if not FStartPending and Assigned(FGround) and FGround(FLatitude, FLongitude, LGround) and
     (FAltitude < LGround) then
  begin
    FAltitude := LGround;
    FSpeed := 0;
    FCrashed := True;
    Result := True;
  end;
end;

procedure TFlight.Climb(ANotches: Double);
begin
  if FCrashed then
    Exit;
  FStartPending := False;
  // A tenth of the height above the ground a notch, at least 20 m
  FAltitude := Min(FAltitude + ANotches * Max(20, 0.1 * HeightAboveGround),
    MAX_FLIGHT_ALTITUDE);
end;

procedure TFlight.Look(ADegreesRight, ADegreesDown: Double);
begin
  if FCrashed then
    Exit;
  FHeading := WrapDegrees(FHeading + ADegreesRight);
  FTilt := EnsureRange(FTilt + ADegreesDown, MIN_FLIGHT_TILT, MAX_FLIGHT_TILT);
end;

procedure TFlight.Stop;
begin
  FSpeed := 0;
end;

end.
