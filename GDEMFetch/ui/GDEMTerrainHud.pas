{ @abstract(Instruments drawn over the 3D view: the camera's height above
  the ground and above sea level, a compass showing which way it looks,
  the frames drawn a second, the flight's speed and the camera's tilt,
  banners for a crash or a pause, the imagery's credit, a collapsible
  list of the keys, and the names of places standing on poles above the
  ground.)

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
  { The controls panel's width, pixels. }
  CONTROLS_WIDTH = 286;
  { The controls panel's title bar height, pixels: all that shows when
    it is collapsed. }
  CONTROLS_TITLE_HEIGHT = 26;
  { The height of each line in the controls panel, pixels. }
  CONTROLS_LINE_HEIGHT = 18;
  { A crash banner's colour: a dark red, partly see-through. }
  BANNER_ALERT = $D0801010;
  { A pause banner's colour: a dark blue-grey, partly see-through. }
  BANNER_NOTE = $D0203048;
  { A place label's pole, from the ground up to the name, pixels. }
  LABEL_POLE = 34;
  { The most place labels drawn at once. }
  MAX_LABELS = 60;

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
    { Backing field for @link(AutopilotText). }
    FAutopilotText: string;

    { Writer for @link(AutopilotText).
      @param(AValue The text.) }
    procedure SetAutopilotText(const AValue: string);

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

    { What the autopilot is doing, shown at the right of the camera line:
      empty when it is off. }
    property AutopilotText: string read FAutopilotText write SetAutopilotText;
  end;

  { @abstract(A banner across the middle of the view, for news such as a
    crash: a line in large letters and one beneath.) }
  TTerrainBanner = class(TControl)
  private
    { Backing field for @link(Title). }
    FTitle: string;
    { Backing field for @link(Detail). }
    FDetail: string;
    { Backing field for @link(Colour). }
    FColour: TAlphaColor;
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

    { The panel's colour: @link(BANNER_ALERT) unless set. }
    property Colour: TAlphaColor read FColour write FColour;
  end;

  { @abstract(One line of the controls panel: a key and what it does.) }
  TControlLine = record
    { The key or mouse action. }
    Key: string;
    { What it does. }
    Action: string;
  end;

  { @abstract(The keys and mouse actions of the 3D view, in a panel that
    collapses to its title bar.)

    A click on the title bar opens or closes it; the arrow at its right
    points the way it will go (up to open, down to close). The rest of the
    panel lets the mouse through. }
  TTerrainControls = class(TControl)
  private
    { Backing field for @link(Collapsed). }
    FCollapsed: Boolean;
    { Backing field for @link(OnToggle). }
    FOnToggle: TNotifyEvent;

    { Writer for @link(Collapsed).
      @param(AValue @true to show only the title bar.) }
    procedure SetCollapsed(AValue: Boolean);
  protected
    { Draws the title bar, its arrow and, when open, the lines.}
    procedure Paint; override;

    { Opens or closes the panel when its title bar is clicked.
      @param(Button The button.)
      @param(Shift The keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    { Makes the panel, open, @link(CONTROLS_WIDTH) wide.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { The panel's height as it is: the title bar alone when collapsed.
      @returns(Pixels.) }
    function PanelHeight: Single;

    { @true while only the title bar shows. }
    property Collapsed: Boolean read FCollapsed write SetCollapsed;

    { Told when a click opens or closes the panel. }
    property OnToggle: TNotifyEvent read FOnToggle write FOnToggle;
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

  { @abstract(Hides the view while it is being got ready, so the ground
    and its imagery are not seen coming in: the view's background colour
    and a line saying what is happening. Takes the mouse while shown.) }
  TTerrainCover = class(TControl)
  private
    { Backing field for @link(Colour). }
    FColour: TAlphaColor;
    { A picture of the view as it was, drawn instead of the colour and
      the line; owned; @nil for none. }
    FPicture: TBitmap;
    { Backing field for @link(Text). }
    FText: string;

    { Writer for @link(Text).
      @param(AValue The line.) }
    procedure SetText(const AValue: string);
  protected
    { Fills the control and draws the line in the middle. }
    procedure Paint; override;
  public
    { Makes the cover, hidden.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Frees the picture. }
    destructor Destroy; override;

    { Shows a picture of the view as it was, so the view seems to stay
      still while it is got ready underneath; the cover takes ownership.
      @param(APicture The picture, or @nil for the colour and the line.) }
    procedure SetPicture(APicture: TBitmap);

    { The colour it fills with. }
    property Colour: TAlphaColor read FColour write FColour;

    { The line in the middle. }
    property Text: string read FText write SetText;
  end;

  { @abstract(What a place label names, which sets its colour.) }
  TTerrainLabelKind = (
    { A town or city. }
    tlkPlace,
    { A mountain or other named point of the land. }
    tlkPeak,
    { One of the user's markers. }
    tlkMarker,
    { One of the user's bookmarks, where it was made. }
    tlkBookmark,
    { A hidden place the user has found in the search (an easter egg),
      flagged only once found. }
    tlkFound);

  { @abstract(A place label where it falls on the screen.) }
  TTerrainScreenLabel = record
    { The ground under the place, on the screen, pixels. }
    Ground: TPointF;
    { The name to show. }
    Text: string;
    { What it names. }
    Kind: TTerrainLabelKind;
  end;

  { @abstract(The names of places, each on a pole standing on the ground
    under it.)

    The view gives the labels in the order they matter, most first; as
    many as fit without overlapping are drawn, up to @link(MAX_LABELS).
    It lets the mouse through. }
  TTerrainLabelLayer = class(TControl)
  private
    { The labels, most important first. }
    FLabels: TArray<TTerrainScreenLabel>;
  protected
    { Draws the poles and names that fit. }
    procedure Paint; override;
  public
    { Makes the layer, not taking the mouse.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Shows a new set of labels.
      @param(ALabels The labels, most important first.) }
    procedure SetLabels(const ALabels: TArray<TTerrainScreenLabel>);
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
  { A town's label colour. }
  LABEL_PLACE = $FFFFFFFF;
  { A mountain's label colour: a light orange. }
  LABEL_PEAK = $FFFFC48A;
  { A marker's label colour: a light yellow. }
  LABEL_MARKER = $FFFFE066;
  { A found hidden place's label colour: a mint green. }
  LABEL_FOUND = $FF7CFFB2;
  { A bookmark's label colour: a light blue. }
  LABEL_BOOKMARK = $FF8AD4FF;

  { The lines of the controls panel. }
  CONTROL_LINES: array[0..12] of TControlLine = (
    (Key: 'Up / Down'; Action: 'faster / slower'),
    (Key: 'Left / Right'; Action: 'turn'),
    (Key: 'PgUp / PgDn'; Action: 'climb / descend'),
    (Key: 'Q / A'; Action: 'camera up / down'),
    (Key: 'H'; Action: 'hover (stop)'),
    (Key: 'M'; Action: 'Mach 1'),
    (Key: 'Space'; Action: 'pause / carry on'),
    (Key: 'B'; Action: 'bookmark this view'),
    (Key: 'L'; Action: 'flags on / off'),
    (Key: 'R'; Action: 'start again'),
    (Key: 'Left-drag'; Action: 'look round'),
    (Key: 'Wheel'; Action: 'climb / descend'),
    (Key: 'Double-click'; Action: 'start again'));
  { The speed of sound used for the Mach number shown, metres a second
    (as @code(MACH_1_SPEED) in @code(GDEMFlight)). }
  MACH_SPEED = 340.3;
  { The Mach number is shown from this speed, metres a second (Mach 0.8). }
  MACH_SHOWN_FROM = 272;
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

procedure TTerrainSpeedPanel.SetAutopilotText(const AValue: string);
begin
  if AValue = FAutopilotText then
    Exit;
  FAutopilotText := AValue;
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
  // Near and past the speed of sound, the Mach number in place of the word
  if FSpeed >= MACH_SHOWN_FROM then
    Canvas.FillText(LLine, Format('Mach %.2f', [FSpeed / MACH_SPEED]), False, 1, [],
      TTextAlign.Trailing, TTextAlign.Center)
  else
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
  if FAutopilotText <> '' then
  begin
    Canvas.Fill.Color := HUD_ACCENT;
    Canvas.FillText(RectF(10, 32, Width - 10, Height - 4), FAutopilotText, False, 1, [],
      TTextAlign.Trailing, TTextAlign.Center);
  end;
end;

{ TTerrainBanner }

constructor TTerrainBanner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  Visible := False;
  FColour := BANNER_ALERT;
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
  Canvas.Fill.Color := FColour;
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

{ TTerrainCover }

constructor TTerrainCover.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // So clicks do not reach the view underneath
  HitTest := True;
  Visible := False;
  FColour := TAlphaColors.Black;
end;

destructor TTerrainCover.Destroy;
begin
  FPicture.Free;
  inherited;
end;

procedure TTerrainCover.SetPicture(APicture: TBitmap);
begin
  if APicture <> FPicture then
    FPicture.Free;
  FPicture := APicture;
  Repaint;
end;

procedure TTerrainCover.SetText(const AValue: string);
begin
  if AValue = FText then
    Exit;
  FText := AValue;
  Repaint;
end;

procedure TTerrainCover.Paint;
begin
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := FColour;
  Canvas.FillRect(LocalRect, 0, 0, AllCorners, 1);
  // The view as it was, stretched if the window has changed size since
  if (FPicture <> nil) and not FPicture.IsEmpty then
  begin
    Canvas.DrawBitmap(FPicture, RectF(0, 0, FPicture.Width, FPicture.Height), LocalRect, 1);
    Exit;
  end;
  if FText = '' then
    Exit;
  Canvas.Font.Size := 16;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := HUD_DIM;
  Canvas.FillText(LocalRect, FText, False, 1, [], TTextAlign.Center, TTextAlign.Center);
end;

{ TTerrainControls }

constructor TTerrainControls.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Takes clicks, for its title bar; MouseDown ignores the rest
  HitTest := True;
  SetBounds(0, 0, CONTROLS_WIDTH, PanelHeight);
end;

function TTerrainControls.PanelHeight: Single;
begin
  if FCollapsed then
    Result := CONTROLS_TITLE_HEIGHT
  else
    Result := CONTROLS_TITLE_HEIGHT + Length(CONTROL_LINES) * CONTROLS_LINE_HEIGHT + 8;
end;

procedure TTerrainControls.SetCollapsed(AValue: Boolean);
begin
  if AValue = FCollapsed then
    Exit;
  FCollapsed := AValue;
  Height := PanelHeight;
  Repaint;
end;

procedure TTerrainControls.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if (Button = TMouseButton.mbLeft) and (Y <= CONTROLS_TITLE_HEIGHT) then
  begin
    Collapsed := not FCollapsed;
    if Assigned(FOnToggle) then
      FOnToggle(Self);
  end;
end;

procedure TTerrainControls.Paint;
var
  LBounds: TRectF;
  LArrow: TPolygon;
  LMidX, LMidY, LTop: Single;
  I: Integer;
begin
  LBounds := RectF(0.5, 0.5, Width - 0.5, Height - 0.5);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := HUD_PANEL;
  Canvas.FillRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);
  Canvas.Stroke.Color := HUD_EDGE;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LBounds, HUD_RADIUS, HUD_RADIUS, AllCorners, 1);

  // The title, and an arrow the way a click will move it
  Canvas.Fill.Color := HUD_TEXT;
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.FillText(RectF(10, 0, Width - 30, CONTROLS_TITLE_HEIGHT), 'Controls', False, 1, [],
    TTextAlign.Leading, TTextAlign.Center);
  LMidX := Width - 16;
  LMidY := CONTROLS_TITLE_HEIGHT / 2;
  SetLength(LArrow, 3);
  if FCollapsed then
  begin
    LArrow[0] := PointF(LMidX - 6, LMidY + 3);
    LArrow[1] := PointF(LMidX + 6, LMidY + 3);
    LArrow[2] := PointF(LMidX, LMidY - 4);
  end
  else
  begin
    LArrow[0] := PointF(LMidX - 6, LMidY - 3);
    LArrow[1] := PointF(LMidX + 6, LMidY - 3);
    LArrow[2] := PointF(LMidX, LMidY + 4);
  end;
  Canvas.Fill.Color := HUD_ACCENT;
  Canvas.FillPolygon(LArrow, 1);
  if FCollapsed then
    Exit;

  // The keys in the accent colour, what they do beside them
  Canvas.Font.Size := 11;
  LTop := CONTROLS_TITLE_HEIGHT;
  for I := 0 to High(CONTROL_LINES) do
  begin
    Canvas.Font.Style := [TFontStyle.fsBold];
    Canvas.Fill.Color := HUD_ACCENT;
    Canvas.FillText(RectF(10, LTop, 120, LTop + CONTROLS_LINE_HEIGHT), CONTROL_LINES[I].Key,
      False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Canvas.Font.Style := [];
    Canvas.Fill.Color := HUD_DIM;
    Canvas.FillText(RectF(124, LTop, Width - 10, LTop + CONTROLS_LINE_HEIGHT),
      CONTROL_LINES[I].Action, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    LTop := LTop + CONTROLS_LINE_HEIGHT;
  end;
end;

{ TTerrainLabelLayer }

constructor TTerrainLabelLayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
end;

procedure TTerrainLabelLayer.SetLabels(const ALabels: TArray<TTerrainScreenLabel>);
begin
  // Nothing to draw before or after: no need to paint
  if (Length(ALabels) = 0) and (Length(FLabels) = 0) then
    Exit;
  FLabels := ALabels;
  Repaint;
end;

procedure TTerrainLabelLayer.Paint;
var
  LTaken: TArray<TRectF>;
  LLabel: TTerrainScreenLabel;
  LBox, LOther: TRectF;
  LWidth: Single;
  LFree: Boolean;
  LCount: Integer;
begin
  Canvas.Font.Size := 11;
  Canvas.Font.Style := [TFontStyle.fsBold];
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  LTaken := nil;
  LCount := 0;
  for LLabel in FLabels do
  begin
    if LCount >= MAX_LABELS then
      Break;
    // The name centred over the pole's top; a label that would overlap one
    // more important is left out
    LWidth := Canvas.TextWidth(LLabel.Text) + 10;
    LBox := RectF(LLabel.Ground.X - LWidth / 2, LLabel.Ground.Y - LABEL_POLE - 18,
      LLabel.Ground.X + LWidth / 2, LLabel.Ground.Y - LABEL_POLE);
    LFree := True;
    for LOther in LTaken do
      if LBox.IntersectsWith(LOther) then
      begin
        LFree := False;
        Break;
      end;
    if not LFree then
      Continue;
    LTaken := LTaken + [RectF(LBox.Left - 2, LBox.Top - 2, LBox.Right + 2,
      LLabel.Ground.Y + 2)];
    Inc(LCount);

    // The pole and its foot
    Canvas.Stroke.Color := HUD_DIM;
    Canvas.Stroke.Thickness := 1.5;
    Canvas.DrawLine(LLabel.Ground, PointF(LLabel.Ground.X, LLabel.Ground.Y - LABEL_POLE), 1);
    Canvas.Fill.Color := HUD_TEXT;
    Canvas.FillEllipse(RectF(LLabel.Ground.X - 2.5, LLabel.Ground.Y - 2.5,
      LLabel.Ground.X + 2.5, LLabel.Ground.Y + 2.5), 1);

    // The name on a dark panel, in its kind's colour
    Canvas.Fill.Color := HUD_PANEL;
    Canvas.FillRect(LBox, 4, 4, AllCorners, 1);
    case LLabel.Kind of
      tlkPeak: Canvas.Fill.Color := LABEL_PEAK;
      tlkMarker: Canvas.Fill.Color := LABEL_MARKER;
      tlkFound: Canvas.Fill.Color := LABEL_FOUND;
      tlkBookmark: Canvas.Fill.Color := LABEL_BOOKMARK;
    else
      Canvas.Fill.Color := LABEL_PLACE;
    end;
    Canvas.FillText(LBox, LLabel.Text, False, 1, [], TTextAlign.Center, TTextAlign.Center);
  end;
end;

end.
