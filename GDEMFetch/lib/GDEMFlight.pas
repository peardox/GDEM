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
  DEFAULT_FLIGHT_START_HEIGHT = 1000;

  { The least distance a flight started looking at a place starts from
    it, metres. }
  MIN_FLIGHT_START_BACK = 200;

  { The speed of sound in air at sea level at 15 degrees C, metres a
    second: Mach 1, the speed M goes to. }
  MACH_1_SPEED = 340.3;

  { Seconds M takes to reach Mach 1 from a hover; less from nearer it. }
  MACH_1_SECONDS = 5;

  { The least height the autopilot keeps above the ground, now and ahead,
    metres. }
  AUTOPILOT_CLEARANCE = 50;

  { How far ahead the autopilot looks: the distance flown in this many
    seconds at the speed now, at least @link(AUTOPILOT_MIN_LOOK). }
  AUTOPILOT_LOOK_SECONDS = 20;

  { The least distance the autopilot looks ahead, metres. }
  AUTOPILOT_MIN_LOOK = 1000;

  { Places along the way ahead whose ground the autopilot looks at. }
  AUTOPILOT_SAMPLES = 32;

  { How much faster than just enough the autopilot climbs, so it is
    clear of the ground ahead before it gets there. }
  AUTOPILOT_CLIMB_MARGIN = 1.5;

  { The farthest a start looking at a place is from it, metres, however
    high and however shallow the tilt. }
  MAX_FLIGHT_START_BACK = 30000;

  { The shallowest tilt used to work out how far back a start looking at
    a place goes, degrees; a shallower one would put it far away. }
  MIN_FLIGHT_START_TILT = 5;

  { The least a start at a height above the sea is kept above the ground
    there, metres, so it never starts underground. }
  MIN_FLIGHT_START_CLEARANCE = 20;

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
    { @true while the start waits to aim at a place
      (@link(StartLookingAt)). }
    FTargetSet: Boolean;
    { The height above the ground the pending start lifts the flight to,
      once that ground is known, metres. }
    FPendingHeight: Double;
    { @true if @link(FPendingHeight) is above the ground; @false if it is
      above the sea, kept at least @link(MIN_FLIGHT_START_CLEARANCE) above
      the ground. }
    FPendingAboveGround: Boolean;
    { The place aimed at, latitude, degrees. }
    FTargetLatitude: Double;
    { The place aimed at, longitude, degrees. }
    FTargetLongitude: Double;
    { How far the start is from the place aimed at, metres. }
    FStartBack: Double;
    { Backing field for @link(LookStretch). }
    FLookStretch: Double;
    { The speed being gone to by @link(SpeedTo), metres a second; less than
      0 when none. }
    FSpeedTarget: Double;
    { How fast the speed changes on the way to @link(FSpeedTarget), metres
      a second each second. }
    FSpeedChange: Double;
    { Backing field for @link(Autopilot). }
    FAutopilot: Boolean;
    { Backing field for @link(AutopilotClimbing). }
    FAutopilotClimbing: Boolean;

    { The height above the ground now, metres, for the climb rate; the
      altitude if the ground is not known.
      @returns(Metres, at least 0.) }
    function HeightAboveGround: Double;

    { Moves along a great circle, turning the heading as the circle does.
      @param(AMetres How far, along the ground.) }
    procedure MoveOn(AMetres: Double);

    { The autopilot: keeps at least @link(AUTOPILOT_CLEARANCE) above the
      ground below at once, and climbs ahead of time for higher ground
      along the way ahead, fast enough to be that far above each place
      looked at before reaching it. It never descends.
      @param(ASeconds The time of this step.)
      @returns(@true if it climbed.) }
    function KeepClear(ASeconds: Double): Boolean;
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

    { Starts again looking at a place: hovering, facing north, a short way
      south of it (@link(StartHeight) over the tangent of the starting
      tilt, so from that height it is in the middle of the view), at
      @link(StartHeight) above the ground there or at the place, whichever
      is higher. Once the ground at both is known the tilt is set to look straight at the place, as drawn
      with heights stretched by @link(LookStretch).
      @param(ATargetLatitude The place's latitude, degrees.)
      @param(ATargetLongitude Its longitude, degrees.) }
    procedure StartLookingAt(ATargetLatitude, ATargetLongitude: Double);

    { Starts again looking at a place from a heading, height and tilt, as
      a bookmark keeps them: hovering, back from the place along the
      heading by the height over the tangent of the tilt (at least
      @link(MIN_FLIGHT_START_TILT), between @link(MIN_FLIGHT_START_BACK)
      and @link(MAX_FLIGHT_START_BACK)), facing it. Once the ground at both
      is known the height is set and the tilt is made to look straight at
      the place, so it is in the middle of the view.
      @param(ATargetLatitude The place's latitude, degrees.)
      @param(ATargetLongitude Its longitude, degrees.)
      @param(AHeading The way to face, degrees clockwise from north.)
      @param(AHeight The height, metres.)
      @param(AAboveGround @true if the height is above the ground at the
        start or at the place, whichever is higher; @false if above the
        sea.)
      @param(ATilt The camera's tilt below the level, degrees, from which
        the distance back is worked out.) }
    procedure StartLookingAlong(ATargetLatitude, ATargetLongitude, AHeading, AHeight: Double;
      AAboveGround: Boolean; ATilt: Double);

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

    { Changes the speed smoothly to a target over a time, as M does for
      Mach 1; Up, Down or a hover take over from it.
      @param(ATarget The speed, metres a second.)
      @param(ASeconds How long a change from a hover would take; nearer the
        target it takes as much less.) }
    procedure SpeedTo(ATarget, ASeconds: Double);

    { Sets the speed at once.
      @param(AValue Metres a second, 0 to @link(MAX_FLIGHT_SPEED).) }
    procedure SetSpeed(AValue: Double);

    { Puts the flight exactly where and as it was, as a bookmark holds it:
      not crashed, and not waiting to lift to its start height.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @param(AAltitude True height above sea level, metres.)
      @param(AHeading Degrees clockwise from true north.)
      @param(ASpeed Metres a second, 0 to @link(MAX_FLIGHT_SPEED).)
      @param(ATilt The camera's tilt below the level, degrees, from
        @link(MIN_FLIGHT_TILT) to @link(MAX_FLIGHT_TILT).) }
    procedure SetState(ALatitude, ALongitude, AAltitude, AHeading, ASpeed, ATilt: Double);

    { As @link(SetState), but at a height above the ground rather than
      above the sea: the flight waits there, at that height above sea level,
      until the ground under it is known, then lifts to that height above
      it.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @param(AAboveGround Height above the ground, metres.)
      @param(AHeading Degrees clockwise from true north.)
      @param(ASpeed Metres a second.)
      @param(ATilt The camera's tilt below the level, degrees.) }
    procedure SetStateAboveGround(ALatitude, ALongitude, AAboveGround, AHeading, ASpeed,
      ATilt: Double);

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

    { @true to keep clear of the ground: at least
      @link(AUTOPILOT_CLEARANCE) above it, climbing ahead of time for
      higher ground on the way. }
    property Autopilot: Boolean read FAutopilot write FAutopilot;

    { @true if the autopilot climbed in the last step. }
    property AutopilotClimbing: Boolean read FAutopilotClimbing;

    { How far above the ground the flight starts, metres. }
    property StartHeight: Double read FStartHeight write FStartHeight;

    { How much heights are stretched where they are drawn, 1 or more, so a
      start looking at a place (@link(StartLookingAt)) aims at it as
      drawn. }
    property LookStretch: Double read FLookStretch write FLookStretch;
  end;

{ The place a distance away along a heading, on a great circle at sea
  level: where a flight there would be, for looking ahead.
  @param(ALatitude Where it starts, latitude, degrees.)
  @param(ALongitude Where it starts, longitude, degrees.)
  @param(AHeading The heading, degrees clockwise from north.)
  @param(AMetres How far, metres.)
  @param(AToLatitude The latitude reached.)
  @param(AToLongitude The longitude reached, -180 to 180.) }
procedure DestinationPoint(ALatitude, ALongitude, AHeading, AMetres: Double;
  out AToLatitude, AToLongitude: Double);

{ Brings an angle into 0 to 360 degrees.
  @param(ADegrees The angle.)
  @returns(The same angle, 0 or more and under 360.) }
function WrapDegrees(ADegrees: Double): Double;

implementation

function WrapDegrees(ADegrees: Double): Double;
begin
  Result := ADegrees - 360 * Floor(ADegrees / 360);
end;

procedure DestinationPoint(ALatitude, ALongitude, AHeading, AMetres: Double;
  out AToLatitude, AToLongitude: Double);
var
  LAngle, LSinLat1, LCosLat1, LSinAngle, LCosAngle, LSinHeading, LCosHeading, LSinLat2: Double;
begin
  // As TFlight.MoveOn, at sea level
  LAngle := AMetres / FLIGHT_EARTH_RADIUS;
  SinCos(DegToRad(ALatitude), LSinLat1, LCosLat1);
  SinCos(LAngle, LSinAngle, LCosAngle);
  SinCos(DegToRad(AHeading), LSinHeading, LCosHeading);
  LSinLat2 := EnsureRange(LSinLat1 * LCosAngle + LCosLat1 * LSinAngle * LCosHeading, -1, 1);
  AToLatitude := RadToDeg(ArcSin(LSinLat2));
  AToLongitude := WrapDegrees(ALongitude + RadToDeg(ArcTan2(LSinHeading * LSinAngle * LCosLat1,
    LCosAngle - LSinLat1 * LSinLat2)) + 180) - 180;
end;

{ TFlight }

constructor TFlight.Create(AGround: TGroundHeightFunc);
begin
  inherited Create;
  FGround := AGround;
  FStartHeight := DEFAULT_FLIGHT_START_HEIGHT;
  FTilt := DEFAULT_FLIGHT_TILT;
  FLookStretch := 1;
  FSpeedTarget := -1;
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
  FPendingHeight := FStartHeight;
  FPendingAboveGround := True;
  FStartPending := True;
  FTargetSet := False;
end;

procedure TFlight.StartLookingAt(ATargetLatitude, ATargetLongitude: Double);
begin
  // From the south, at the start height, at the starting tilt
  StartLookingAlong(ATargetLatitude, ATargetLongitude, 0, FStartHeight, True,
    DEFAULT_FLIGHT_TILT);
end;

procedure TFlight.StartLookingAlong(ATargetLatitude, ATargetLongitude, AHeading, AHeight: Double;
  AAboveGround: Boolean; ATilt: Double);
var
  LTilt: Double;
begin
  Start(ATargetLatitude, ATargetLongitude);
  LTilt := EnsureRange(ATilt, MIN_FLIGHT_START_TILT, MAX_FLIGHT_TILT);
  AHeight := Max(AHeight, 0);
  // Back from the place along the ground, the opposite way to the
  // heading; the heading on arrival is the way on, so turned round it
  // faces the place along the same great circle
  FStartBack := EnsureRange(AHeight / Tan(DegToRad(LTilt)), MIN_FLIGHT_START_BACK,
    MAX_FLIGHT_START_BACK);
  FAltitude := 0;
  FHeading := WrapDegrees(AHeading + 180);
  MoveOn(FStartBack);
  FHeading := WrapDegrees(FHeading + 180);
  FTilt := LTilt;
  FAltitude := Min(AHeight, MAX_FLIGHT_ALTITUDE);
  FPendingHeight := AHeight;
  FPendingAboveGround := AAboveGround;
  FTargetLatitude := ATargetLatitude;
  FTargetLongitude := ATargetLongitude;
  FTargetSet := True;
end;

function TFlight.KeepClear(ASeconds: Double): Boolean;
var
  LGround, LLook, LDistance, LLatitude, LLongitude, LRate, LNeeded: Double;
  I: Integer;
begin
  Result := False;
  if not Assigned(FGround) then
    Exit;
  // Below the clearance now: straight up to it
  if FGround(FLatitude, FLongitude, LGround) and
     (FAltitude < LGround + AUTOPILOT_CLEARANCE) then
  begin
    FAltitude := LGround + AUTOPILOT_CLEARANCE;
    Result := True;
  end;
  if (FSpeed <= 0) or (ASeconds <= 0) then
    Exit;
  // Ahead: the steepest climb any place on the way needs, to be clear of
  // it on arrival
  LLook := Max(FSpeed * AUTOPILOT_LOOK_SECONDS, AUTOPILOT_MIN_LOOK);
  LNeeded := 0;
  for I := 1 to AUTOPILOT_SAMPLES do
  begin
    LDistance := LLook * I / AUTOPILOT_SAMPLES;
    DestinationPoint(FLatitude, FLongitude, FHeading, LDistance, LLatitude, LLongitude);
    if not FGround(LLatitude, LLongitude, LGround) then
      Continue;
    LRate := (LGround + AUTOPILOT_CLEARANCE - FAltitude) / (LDistance / FSpeed);
    LNeeded := Max(LNeeded, LRate);
  end;
  if LNeeded > 0 then
  begin
    FAltitude := Min(FAltitude + LNeeded * AUTOPILOT_CLIMB_MARGIN * ASeconds,
      MAX_FLIGHT_ALTITUDE);
    Result := True;
  end;
end;

procedure TFlight.SetSpeed(AValue: Double);
begin
  FSpeed := EnsureRange(AValue, 0, MAX_FLIGHT_SPEED);
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
  LRate, LGround, LTargetGround, LBefore: Double;
begin
  Result := False;
  ASeconds := EnsureRange(ASeconds, 0, 0.1);

  // The start's height above the ground, once the ground is known; the
  // height keys take over from it
  if FStartPending then
  begin
    if AControls * [fcClimb, fcDescend] <> [] then
    begin
      FStartPending := False;
      FTargetSet := False;
    end
    else if Assigned(FGround) and FGround(FLatitude, FLongitude, LGround) then
    begin
      if not FTargetSet then
      begin
        FAltitude := LGround + FPendingHeight;
        FStartPending := False;
        Result := True;
      end
      else if FGround(FTargetLatitude, FTargetLongitude, LTargetGround) then
      begin
        // The tilt that looks straight at the place, as drawn
        // Above the higher of the two, so a place above the start (a
        // summit seen from its slopes) is looked down on, not up at
        if FPendingAboveGround then
          FAltitude := Max(LGround, LTargetGround) + FPendingHeight
        else
          FAltitude := Max(FPendingHeight, LGround + MIN_FLIGHT_START_CLEARANCE);
        FTilt := EnsureRange(RadToDeg(ArcTan2((FAltitude - LTargetGround) * Max(FLookStretch, 0.1),
          FStartBack)), MIN_FLIGHT_TILT, MAX_FLIGHT_TILT);
        FTargetSet := False;
        FStartPending := False;
        Result := True;
      end;
    end;
  end;

  if FCrashed or (ASeconds <= 0) then
    Exit;

  // Speed: faster the faster already, never backwards
  LBefore := FSpeed;
  LRate := Max(FLIGHT_ACCEL_MIN, FLIGHT_ACCEL_SHARE * FSpeed) * ASeconds;
  // The speed keys take over from a change to a target speed
  if AControls * [fcFaster, fcSlower] <> [] then
    FSpeedTarget := -1;
  if fcFaster in AControls then
    FSpeed := FSpeed + LRate;
  if fcSlower in AControls then
    FSpeed := FSpeed - LRate;
  if FSpeedTarget >= 0 then
  begin
    if Abs(FSpeedTarget - FSpeed) <= FSpeedChange * ASeconds then
    begin
      FSpeed := FSpeedTarget;
      FSpeedTarget := -1;
    end
    else if FSpeedTarget > FSpeed then
      FSpeed := FSpeed + FSpeedChange * ASeconds
    else
      FSpeed := FSpeed - FSpeedChange * ASeconds;
  end;
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

  // The autopilot before the crash test, so it never lets one happen
  FAutopilotClimbing := False;
  if FAutopilot and not FStartPending and KeepClear(ASeconds) then
  begin
    FAutopilotClimbing := True;
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
  FSpeedTarget := -1;
end;

procedure TFlight.SpeedTo(ATarget, ASeconds: Double);
begin
  if FCrashed then
    Exit;
  FSpeedTarget := EnsureRange(ATarget, 0, MAX_FLIGHT_SPEED);
  FSpeedChange := Max(FSpeedTarget, 1) / Max(ASeconds, 0.1);
end;

procedure TFlight.SetState(ALatitude, ALongitude, AAltitude, AHeading, ASpeed, ATilt: Double);
begin
  FLatitude := EnsureRange(ALatitude, -90, 90);
  FLongitude := WrapDegrees(ALongitude + 180) - 180;
  FAltitude := Min(AAltitude, MAX_FLIGHT_ALTITUDE);
  FHeading := WrapDegrees(AHeading);
  FSpeed := EnsureRange(ASpeed, 0, MAX_FLIGHT_SPEED);
  FTilt := EnsureRange(ATilt, MIN_FLIGHT_TILT, MAX_FLIGHT_TILT);
  FCrashed := False;
  FStartPending := False;
end;

procedure TFlight.SetStateAboveGround(ALatitude, ALongitude, AAboveGround, AHeading, ASpeed,
  ATilt: Double);
begin
  SetState(ALatitude, ALongitude, Max(AAboveGround, 0), AHeading, ASpeed, ATilt);
  FPendingHeight := Max(AAboveGround, 0);
  FPendingAboveGround := True;
  FTargetSet := False;
  FStartPending := True;
end;

end.
