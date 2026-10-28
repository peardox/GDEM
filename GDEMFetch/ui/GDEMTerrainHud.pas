{ @abstract(Instruments drawn over the 3D view: the camera's height above
  the ground and above sea level, a compass showing which way it looks,
  the frames drawn a second, the flight's speed and the camera's tilt,
  a banner for a crash, and the imagery's credit.)

  Both are plain FMX controls that paint themselves, laid over the
  Gorilla3D viewport by @code(TTerrainView). They do not take the mouse
  (@code(HitTest) off), so dragging and the wheel still reach the view
  through them. Their colours are fixed, white and orange on a dark
  see-through panel, so they read over sky, sea, snow and the light and
  dark themes alike.

  The values are set from outside; each control repaints only when what
  it shows changes, so setting them on every mouse move costs little. }
unit GDEMTerrainHud;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Math.Vectors, FMX.Types, FMX.Controls, FMX.Graphics;

const
  { The compass's width and height, pixels. }
  COMPASS_SIZE = 116;
  { The height panel's width, pixels. }
  ALTIMETER_WIDTH = 190;
  { The height panel's height, pixels. }
  ALTIMETER_HEIGHT = 88;
  { The frame rate panel's height, pixels; it is as wide as the height
    panel. }
  FRAME_RATE_HEIGHT = 24;
  { The speed panel's height, pixels; it is as wide as the height panel. }
  SPEED_PANEL_HEIGHT = 56;
  { The banner's width, pixels. }
  BANNER_WIDTH = 420;
  { The banner's height, pixels. }
  BANNER_HEIGHT = 64;

type
  { @abstract(A compass card that turns as the view turns.)

    The way the camera looks is always at the top, under the fixed orange
    mark; the card turns beneath it, so north on the card points to north
    on the ground. The heading in degrees is written in the middle. }
  TTerrainCompass = class(TControl)
  private
    { Backing field for @link(Heading). }
    FHeading: Single;
    { Backing field for @link(Known). }
    FKnown: Boolean;

    { Writer for @link(Heading).
      @param(AValue Degrees clockwise from north; any value is brought
        into 0 to 360.) }
    procedure SetHeading(AValue: Single);

    { Writer for @link(Known).
      @param(AValue @true if @link(Heading) holds a measurement.) }
    procedure SetKnown(AValue: Boolean);
  protected
    { Draws the panel, the card, the mark and the heading. }
    procedure Paint; override;
  public
    { Makes the compass, @link(COMPASS_SIZE) square, not taking the mouse.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { The way the camera looks, degrees clockwise from true north, 0 to
      360. }
    property Heading: Single read FHeading write SetHeading;

    { @false until a heading has been measured; the card is drawn with
      north up and no number. }
    property Known: Boolean read FKnown write SetKnown;
  end;

  { @abstract(The camera's height above the ground, its altitude (height
    above sea level), and the ground's own height above sea level.)

    Heights are true heights: when the view stretches heights, both are
    divided back to true scale. Below 10 km they are in metres, above in
    kilometres. }
  TTerrainAltimeter = class(TControl)
  private
    { Backing field for @link(AboveGround). }
    FAboveGround: Double;
    { Backing field for @link(Altitude). }
    FAltitude: Double;
    { Backing field for @link(Ground). }
    FGround: Double;
    { Backing field for @link(Known). }
    FKnown: Boolean;
    { Backing field for @link(AltitudeKnown). }
    FAltitudeKnown: Boolean;
    { Backing field for @link(Exaggeration). }
    FExaggeration: Single;

    { Writer for @link(AboveGround).
      @param(AValue Metres.) }
    procedure SetAboveGround(AValue: Double);

    { Writer for @link(Altitude).
      @param(AValue Metres.) }
    procedure SetAltitude(AValue: Double);

    { Writer for @link(AltitudeKnown).
      @param(AValue @true if @link(Altitude) holds a measurement.) }
    procedure SetAltitudeKnown(AValue: Boolean);

    { Writer for @link(Ground).
      @param(AValue Metres.) }
    procedure SetGround(AValue: Double);

    { Writer for @link(Known).
      @param(AValue @true if the heights hold a measurement.) }
    procedure SetKnown(AValue: Boolean);

    { Writer for @link(Exaggeration).
      @param(AValue Times heights are stretched in the view.) }
    procedure SetExaggeration(AValue: Single);
  protected
    { Draws the panel and the three heights. }
    procedure Paint; override;
  public
    { Makes the panel, @link(ALTIMETER_WIDTH) by @link(ALTIMETER_HEIGHT),
      not taking the mouse.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { The camera's true height above the ground under it, metres. }
    property AboveGround: Double read FAboveGround write SetAboveGround;

    { The camera's true altitude: its height above sea level, metres. }
    property Altitude: Double read FAltitude write SetAltitude;

    { @false until the camera has been placed; dashes are shown instead
      of the altitude. }
    property AltitudeKnown: Boolean read FAltitudeKnown write SetAltitudeKnown;

    { The ground's true height above sea level under the camera, metres. }
    property Ground: Double read FGround write SetGround;

    { @false while the ground under the camera has no heights read yet;
      dashes are shown instead of the height above ground and the
      ground's height. }
    property Known: Boolean read FKnown write SetKnown;

    { Times heights are stretched in the view; when not 1, the panel says
      so, as the ground on screen then looks that much higher than the
      numbers. }
    property Exaggeration: Single read FExaggeration write SetExaggeration;
  end;

  { @abstract(The frames the view draws a second.) }
  TTerrainFrameRate = class(TControl)
  private
    { Backing field for @link(FramesPerSecond). }
    FFramesPerSecond: Single;
    { Backing field for @link(Known). }
    FKnown: Boolean;
    { Backing field for @link(Limit). }
    FLimit: Integer;

    { Writer for @link(Limit).
      @param(AValue Frames a second.) }
    procedure SetLimit(AValue: Integer);

    { Writer for @link(FramesPerSecond).
      @param(AValue Frames a second.) }
    procedure SetFramesPerSecond(AValue: Single);

    { Writer for @link(Known).
      @param(AValue @true if @link(FramesPerSecond) holds a measurement.) }
    procedure SetKnown(AValue: Boolean);
  protected
    { Draws the panel and the rate. }
    procedure Paint; override;
  public
    { Makes the panel, @link(ALTIMETER_WIDTH) by @link(FRAME_RATE_HEIGHT),
      not taking the mouse.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Frames drawn a second. }
    property FramesPerSecond: Single read FFramesPerSecond write SetFramesPerSecond;

    { @false until a rate has been measured. }
    property Known: Boolean read FKnown write SetKnown;

    { The most frames a second the view is drawn at; 0 to leave it out. }
    property Limit: Integer read FLimit write SetLimit;
  end;

  { @abstract(The flight's speed over the ground, and how far the camera
    looks down.) }
  TTerrainSpeedPanel = class(TControl)
  private
    { Backing field for @link(Speed). }
    FSpeed: Double;
    { Backing field for @link(Tilt). }
    FTilt: Double;

    { Writer for @link(Speed).
      @param(AValue Metres a second.) }
    procedure SetSpeed(AValue: Double);

    { Writer for @link(Tilt).
      @param(AValue Degrees below the level.) }
    procedure SetTilt(AValue: Double);
  protected
    { Draws the panel, the speed and the tilt. }
    procedure Paint; override;
  public
    { Makes the panel, @link(ALTIMETER_WIDTH) by
      @link(SPEED_PANEL_HEIGHT), not taking the mouse.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Speed over the ground, metres a second; shown in kilometres an hour,
      or @code(hovering) at 0. }
    property Speed: Double read FSpeed write SetSpeed;

    { The camera's tilt below the level, degrees; negative looks up. }
    property Tilt: Double read FTilt write SetTilt;
  end;

  { @abstract(A banner across the middle of the view, for news such as a
    crash: a line in large letters and one beneath.) }
  TTerrainBanner = class(TControl)
  private
    { Backing field for @link(Title). }
    FTitle: string;
    { Backing field for @link(Detail). }
    FDetail: string;
  protected
    { Draws the panel and the two lines. }
    procedure Paint; override;
  public
    { Makes the banner, @link(BANNER_WIDTH) by @link(BANNER_HEIGHT), hidden
      and not taking the mouse.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Shows the banner.
      @param(ATitle The line in large letters.)
      @param(ADetail The line beneath.) }
    procedure ShowText(const ATitle, ADetail: string);

    { The line in large letters. }
    property Title: string read FTitle;

    { The line beneath. }
    property Detail: string read FDetail;
  end;

  { @abstract(A line of small text in the bottom right corner, on a dark
    panel just wide enough for it: the credit for the imagery.) }
  TTerrainCredit = class(TControl)
  private
    { Backing field for @link(Text). }
    FText: string;

    { Writer for @link(Text).
      @param(AValue The line.) }
    procedure SetText(const AValue: string);
  protected
    { Draws the panel and the line, against the right edge. }
    procedure Paint; override;
  public
    { Makes the line, hidden and not taking the mouse.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { The line. }
    property Text: string read FText write SetText;
  end;

{ Writes a height for the instruments: metres with thousands separated
  below 10 km, kilometres with one decimal above.
  @param(AMetres The height, metres.)
  @returns(Such as @code(1,234 m) or @code(12.5 km).) }
function FormatHudHeight(AMetres: Double): string;

implementation

const
  { The panels' colour: a dark blue-grey, partly see-through. }
  HUD_PANEL = $B8101620;
  { The panels' outline. }
  HUD_EDGE = $80FFFFFF;
  { Text and ticks. }
  HUD_TEXT = $FFFFFFFF;
  { Smaller, less important text. }
  HUD_DIM = $B0FFFFFF;
  { North on the card, and the mark for the way the camera looks. }
  HUD_ACCENT = $FFFF8A3D;
  { The panels' corner radius, pixels. }
  HUD_RADIUS = 8;
  { The least a heading must change to be drawn again, degrees. }
  HEADING_STEP = 0.05;
  { The least a frame rate must change to be drawn again. }
  FPS_STEP = 0.05;
  { The least a speed must change to be drawn again, metres a second. }
  SPEED_STEP = 0.1;
  { The least a tilt must change to be drawn again, degrees. }
  TILT_STEP = 0.1;
  { Metres a second to kilometres an hour. }
  KMH_PER_MPS = 3.6;
  { The banner's colour: a dark red, partly see-through. }
  HUD_ALERT = $D0801010;
  { The least a height must change to be drawn again, metres. }
  HEIGHT_STEP = 0.5;
  { Heights from this many metres up are written in kilometres. }
  KM_FROM_METRES = 10000;
  { The degree sign; source files are ASCII only. }
  DEGREE_SIGN = #$00B0;
  { The cardinal points, from north clockwise. }
  CARDINALS: array[0..3] of string = ('N', 'E', 'S', 'W');

function FormatHudHeight(AMetres: Double): string;
begin
  if Abs(AMetres) >= KM_FROM_METRES then
    Result := FormatFloat('#,##0.0', AMetres / 1000) + ' km'
  else
    Result := FormatFloat('#,##0', AMetres) + ' m';
end;

{ TTerrainCompass }

constructor TTerrainCompass.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  SetBounds(0, 0, COMPASS_SIZE, COMPASS_SIZE);
end;

procedure TTerrainCompass.SetHeading(AValue: Single);
begin
  AValue := AValue - 360 * Floor(AValue / 360);
  // Just under 360 and just over 0 are the same heading
  if Abs(AValue - FHeading) < HEADING_STEP then
    Exit;
  if Abs(Abs(AValue - FHeading) - 360) < HEADING_STEP then
    Exit;
  FHeading := AValue;
  Repaint;
end;

procedure TTerrainCompass.SetKnown(AValue: Boolean);
begin
  if AValue = FKnown then
    Exit;
  FKnown := AValue;
  Repaint;
end;

procedure TTerrainCompass.Paint;
var
  LCentre: TPointF;
  LRadius, LTurn, LTop, LInner, LSin, LCos: Single;
  LBearing, I: Integer;
  LText: string;
  LMark: TPolygon;

  { A point on the card, measured from its centre on the screen.
    @param(ABearing Degrees clockwise from north on the ground.)
    @param(ADistance Pixels from the centre.)
    @returns(The point.) }
  function CardPoint(ABearing, ADistance: Single): TPointF;
  begin
    // The camera's heading is at the top, so a bearing appears turned by
    // the difference, clockwise from the top
    SinCos(DegToRad(ABearing - LTurn), LSin, LCos);
    Result := PointF(LCentre.X + ADistance * LSin, LCentre.Y - ADistance * LCos);
  end;

begin
  LRadius := Min(Width, Height) / 2 - 1;
  if LRadius < 10 then
    Exit;
  LCentre := PointF(Width / 2, Height / 2);
  if FKnown then
    LTurn := FHeading
  else
    LTurn := 0;

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Stroke.Kind := TBrushKind.Solid;

  // The panel
  Canvas.Fill.Color := HUD_PANEL;
  Canvas.FillEllipse(RectF(LCentre.X - LRadius, LCentre.Y - LRadius,
    LCentre.X + LRadius, LCentre.Y + LRadius), 1);
  Canvas.Stroke.Color := HUD_EDGE;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawEllipse(RectF(LCentre.X - LRadius, LCentre.Y - LRadius,
    LCentre.X + LRadius, LCentre.Y + LRadius), 1);

  // Ticks every 10 degrees, longer every 30, longest at the cardinals
  LRadius := LRadius - 3;
  for I := 0 to 35 do
  begin
    LBearing := I * 10;
    if LBearing mod 90 = 0 then
      LInner := LRadius - 10
    else if LBearing mod 30 = 0 then
      LInner := LRadius - 7
    else
      LInner := LRadius - 4;
    if LBearing = 0 then
    begin
      Canvas.Stroke.Color := HUD_ACCENT;
      Canvas.Stroke.Thickness := 2.5;
    end
    else
    begin
      Canvas.Stroke.Color := HUD_TEXT;
      if LBearing mod 90 = 0 then
        Canvas.Stroke.Thickness := 2
      else
        Canvas.Stroke.Thickness := 1;
    end;
    Canvas.DrawLine(CardPoint(LBearing, LInner), CardPoint(LBearing, LRadius), 1);
  end;

  // The cardinal letters, upright wherever the card has turned them
  Canvas.Font.Size := 13;
  Canvas.Font.Style := [TFontStyle.fsBold];
  for I := 0 to 3 do
  begin
    if I = 0 then
      Canvas.Fill.Color := HUD_ACCENT
    else
      Canvas.Fill.Color := HUD_TEXT;
    LCentre := CardPoint(I * 90, LRadius - 21);
    Canvas.FillText(RectF(LCentre.X - 12, LCentre.Y - 10, LCentre.X + 12, LCentre.Y + 10),
      CARDINALS[I], False, 1, [], TTextAlign.Center, TTextAlign.Center);
    LCentre := PointF(Width / 2, Height / 2);
  end;

  // The fixed mark at the top: the way the camera looks
  LTop := LRadius + 2;
  SetLength(LMark, 3);
  LMark[0] := PointF(LCentre.X, LCentre.Y - LTop + 11);
  LMark[1] := PointF(LCentre.X - 6, LCentre.Y - LTop);
  LMark[2] := PointF(LCentre.X + 6, LCentre.Y - LTop);
  Canvas.Fill.Color := HUD_ACCENT;
  Canvas.FillPolygon(LMark, 1);

  // The heading in the middle
  if FKnown then
    LText := Format('%.3d', [Round(FHeading) mod 360]) + DEGREE_SIGN
  else
    LText := '---';
  Canvas.Fill.Color := HUD_TEXT;
  Canvas.Font.Size := 15;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.FillText(RectF(LCentre.X - 30, LCentre.Y - 11, LCentre.X + 30, LCentre.Y + 11),
    LText, False, 1, [], TTextAlign.Center, TTextAlign.Center);
end;

{ TTerrainAltimeter }

constructor TTerrainAltimeter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  FExaggeration := 1;
  SetBounds(0, 0, ALTIMETER_WIDTH, ALTIMETER_HEIGHT);
end;

procedure TTerrainAltimeter.SetAboveGround(AValue: Double);
begin
  if Abs(AValue - FAboveGround) < HEIGHT_STEP then
    Exit;
  FAboveGround := AValue;
  Repaint;
end;

procedure TTerrainAltimeter.SetAltitude(AValue: Double);
begin
  if Abs(AValue - FAltitude) < HEIGHT_STEP then
    Exit;
  FAltitude := AValue;
  Repaint;
end;

procedure TTerrainAltimeter.SetAltitudeKnown(AValue: Boolean);
begin
  if AValue = FAltitudeKnown then
    Exit;
  FAltitudeKnown := AValue;
  Repaint;
end;

procedure TTerrainAltimeter.SetGround(AValue: Double);
begin
  if Abs(AValue - FGround) < HEIGHT_STEP then
    Exit;
  FGround := AValue;
  Repaint;
end;

procedure TTerrainAltimeter.SetKnown(AValue: Boolean);
begin
  if AValue = FKnown then
    Exit;
  FKnown := AValue;
  Repaint;
end;

procedure TTerrainAltimeter.SetExaggeration(AValue: Single);
begin
  if SameValue(AValue, FExaggeration) then
    Exit;
  FExaggeration := AValue;
  Repaint;
end;

procedure TTerrainAltimeter.Paint;
var
  LBounds: TRectF;
  LAbove, LAltitude, LGround: string;

  { Draws one line: a value on the left and its caption on the right.
    @param(ATop The line's top, pixels.)
    @param(AHeight The line's height, pixels.)
    @param(AValue The value.)
    @param(ACaption The caption.)
    @param(ASize The value's font size.) }
  procedure DrawLine(ATop, AHeight: Single; const AValue, ACaption: string; ASize: Single);
  var
    LLine: TRectF;
  begin
    LLine := RectF(10, ATop, Width - 10, ATop + AHeight);
    Canvas.Fill.Color := HUD_TEXT;
    Canvas.Font.Size := ASize;
    Canvas.Font.Style := [TFontStyle.fsBold];
    Canvas.FillText(LLine, AValue, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Canvas.Fill.Color := HUD_ACCENT;
    Canvas.Font.Size := 11;
    Canvas.Font.Style := [];
    Canvas.FillText(LLine, ACaption, False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
  end;

begin
  LBounds := RectF(0.5, 0.5, Width - 0.5, Height - 0.5);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := HUD_PANEL;
  Canvas.FillRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);
  Canvas.Stroke.Color := HUD_EDGE;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);

  if FKnown then
  begin
    // The camera is kept a little above the ground, so anything below 0
    // is only the ground's heights being sampled a little differently
    LAbove := FormatHudHeight(Max(FAboveGround, 0));
    LGround := 'Ground ' + FormatHudHeight(FGround) + ' above sea level';
  end
  else
  begin
    LAbove := '--- m';
    LGround := 'Ground not read yet';
  end;
  if FAltitudeKnown then
    LAltitude := FormatHudHeight(FAltitude)
  else
    LAltitude := '--- m';
  if not SameValue(FExaggeration, 1) then
    LGround := LGround + Format(' (heights x%g)', [FExaggeration]);

  DrawLine(4, 30, LAbove, 'above ground', 20);
  DrawLine(32, 26, LAltitude, 'altitude', 16);

  // The ground's own height beneath
  Canvas.Fill.Color := HUD_DIM;
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [];
  Canvas.FillText(RectF(10, 60, Width - 10, Height - 6), LGround, False, 1, [],
    TTextAlign.Leading, TTextAlign.Center);
end;

{ TTerrainFrameRate }

constructor TTerrainFrameRate.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  SetBounds(0, 0, ALTIMETER_WIDTH, FRAME_RATE_HEIGHT);
end;

procedure TTerrainFrameRate.SetLimit(AValue: Integer);
begin
  if AValue = FLimit then
    Exit;
  FLimit := AValue;
  Repaint;
end;

procedure TTerrainFrameRate.SetFramesPerSecond(AValue: Single);
begin
  if Abs(AValue - FFramesPerSecond) < FPS_STEP then
    Exit;
  FFramesPerSecond := AValue;
  Repaint;
end;

procedure TTerrainFrameRate.SetKnown(AValue: Boolean);
begin
  if AValue = FKnown then
    Exit;
  FKnown := AValue;
  Repaint;
end;

procedure TTerrainFrameRate.Paint;
var
  LBounds, LLine: TRectF;
  LText: string;
begin
  LBounds := RectF(0.5, 0.5, Width - 0.5, Height - 0.5);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := HUD_PANEL;
  Canvas.FillRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);
  Canvas.Stroke.Color := HUD_EDGE;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);

  if FKnown then
    LText := FormatFloat('0.0', FFramesPerSecond)
  else
    LText := '---';
  LLine := RectF(10, 0, Width - 10, Height);
  Canvas.Fill.Color := HUD_TEXT;
  Canvas.Font.Size := 13;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.FillText(LLine, LText, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  Canvas.Fill.Color := HUD_ACCENT;
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [];
  if FLimit > 0 then
    LText := Format('frames a second, of %d', [FLimit])
  else
    LText := 'frames a second';
  Canvas.FillText(LLine, LText, False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
end;

{ TTerrainSpeedPanel }

constructor TTerrainSpeedPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  FTilt := -1000;
  SetBounds(0, 0, ALTIMETER_WIDTH, SPEED_PANEL_HEIGHT);
end;

procedure TTerrainSpeedPanel.SetSpeed(AValue: Double);
begin
  // Always drawn again on reaching a hover, so it never shows a crumb
  if (Abs(AValue - FSpeed) < SPEED_STEP) and ((AValue <> 0) or (FSpeed = 0)) then
    Exit;
  FSpeed := AValue;
  Repaint;
end;

procedure TTerrainSpeedPanel.SetTilt(AValue: Double);
begin
  if Abs(AValue - FTilt) < TILT_STEP then
    Exit;
  FTilt := AValue;
  Repaint;
end;

procedure TTerrainSpeedPanel.Paint;
var
  LBounds, LLine: TRectF;
  LText, LTiltText: string;
begin
  LBounds := RectF(0.5, 0.5, Width - 0.5, Height - 0.5);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := HUD_PANEL;
  Canvas.FillRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);
  Canvas.Stroke.Color := HUD_EDGE;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);

  if FSpeed <= 0 then
    LText := 'Hovering'
  else
    LText := FormatFloat('#,##0', FSpeed * KMH_PER_MPS) + ' km/h';
  LLine := RectF(10, 4, Width - 10, 32);
  Canvas.Fill.Color := HUD_TEXT;
  Canvas.Font.Size := 18;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.FillText(LLine, LText, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  Canvas.Fill.Color := HUD_ACCENT;
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [];
  Canvas.FillText(LLine, 'speed', False, 1, [], TTextAlign.Trailing, TTextAlign.Center);

  if Round(FTilt) > 0 then
    LTiltText := Format('Camera %d%s down', [Round(FTilt), DEGREE_SIGN])
  else if Round(FTilt) < 0 then
    LTiltText := Format('Camera %d%s up', [-Round(FTilt), DEGREE_SIGN])
  else
    LTiltText := 'Camera level';
  Canvas.Fill.Color := HUD_DIM;
  Canvas.FillText(RectF(10, 32, Width - 10, Height - 4), LTiltText, False, 1, [],
    TTextAlign.Leading, TTextAlign.Center);
end;

{ TTerrainBanner }

constructor TTerrainBanner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  Visible := False;
  SetBounds(0, 0, BANNER_WIDTH, BANNER_HEIGHT);
end;

procedure TTerrainBanner.ShowText(const ATitle, ADetail: string);
begin
  FTitle := ATitle;
  FDetail := ADetail;
  Visible := True;
  Repaint;
end;

procedure TTerrainBanner.Paint;
var
  LBounds: TRectF;
begin
  LBounds := RectF(0.5, 0.5, Width - 0.5, Height - 0.5);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := HUD_ALERT;
  Canvas.FillRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);
  Canvas.Stroke.Color := HUD_EDGE;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);
  Canvas.Fill.Color := HUD_TEXT;
  Canvas.Font.Size := 22;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.FillText(RectF(10, 4, Width - 10, 36), FTitle, False, 1, [], TTextAlign.Center,
    TTextAlign.Center);
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [];
  Canvas.FillText(RectF(10, 36, Width - 10, Height - 6), FDetail, False, 1, [], TTextAlign.Center,
    TTextAlign.Center);
end;

{ TTerrainCredit }

constructor TTerrainCredit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  Visible := False;
end;

procedure TTerrainCredit.SetText(const AValue: string);
begin
  if AValue = FText then
    Exit;
  FText := AValue;
  Repaint;
end;

procedure TTerrainCredit.Paint;
var
  LWidth: Single;
  LBounds: TRectF;
begin
  if FText = '' then
    Exit;
  Canvas.Font.Size := 10;
  Canvas.Font.Style := [];
  LWidth := Min(Canvas.TextWidth(FText) + 16, Width);
  LBounds := RectF(Width - LWidth + 0.5, 0.5, Width - 0.5, Height - 0.5);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := HUD_PANEL;
  Canvas.FillRect(LBounds, 4, 4, AllCorners, 1);
  Canvas.Fill.Color := HUD_DIM;
  Canvas.FillText(RectF(LBounds.Left + 8, 0, LBounds.Right - 8, Height), FText, False, 1, [],
    TTextAlign.Trailing, TTextAlign.Center);
end;

end.
