{ @abstract(The 3D view: a Gorilla3D viewport showing the ground round a
  tile, fine near the camera and coarser further away, flown over with
  the keyboard and the mouse.)

  @link(TTerrainView) is a layout that fills the 3D tab. It holds:

  @preformatted(
TTerrainView                  takes the mouse and the keys
`-- TGorillaViewport          HitTest off, so the mouse reaches the layout
    |-- target (TDummy)       the point the camera looks at
    |-- terrain (TDummy)      holds the patches' meshes
    |   `-- TGorillaSingletonMesh, one per patch, all sharing one
    |       TGorillaVertexColorMaterialSource
    `-- TGorillaCamera        where the flight is; Target is the target
        `-- TGorillaLight     a point light where the camera is
TTerrainAltimeter, TTerrainFrameRate, TTerrainSpeedPanel (top left),
TTerrainCompass (top right) and TTerrainBanner (middle, for a crash), over
the viewport, letting the mouse through
  )

  Which patches to draw is decided by @code(TTerrainLod) (in
  @code(GDEMTerrainLod)), which has them made on worker threads; this view
  turns each one made into a mesh on the main thread, a few at a time
  (@link(UPLOAD_BUDGET_MS) each tick of a 15 ms timer), so the window keeps
  responding while the ground sharpens. The vertices are copied straight
  into FMX's vertex buffer where its layout can be found, and the one list
  of triangles every patch shares is copied in a single move.

  The camera is a flight (@code(TFlight), in @code(GDEMFlight)): it starts
  hovering, facing north, @link(TTerrainView.StartHeight) metres above the
  middle of the tile asked for, and looks ahead and a little down. Keys,
  held: Up and Down change the speed (never below a hover), Left and Right
  turn, Page Up and Page Down climb and descend, Q and A tilt the camera
  up and down; Space stops to a hover; R starts again. Going below the
  ground is a crash, which stops the flight until R. Left-drag looks round
  (turns and tilts), the wheel climbs and descends, a double click starts
  again. Each tick moves the flight by the time gone, so its speed does not
  depend on the frame rate. Flying far from where positions are measured
  from measures everything again from there (@code(TERRAIN_REBASE_KM)), so
  the flight can go as far as there are tiles.

  The view draws no more frames a second than the display the window is
  on refreshes at (@code(GDEMDisplays)), and checks four times a second
  whether the window has moved to another display.

  The instruments (@code(GDEMTerrainHud)) show the flight's height above
  the ground under it and above sea level, the ground's height there, its
  heading against true north, its speed and the camera's tilt, and the
  frames drawn a second. Heights are true heights: when heights are
  stretched for drawing, the flight is drawn that much higher too, so it
  stays the same height above the ground as drawn. }
unit GDEMTerrainView;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math.Vectors,
  System.Diagnostics,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Types3D, FMX.Controls3D, FMX.Objects3D,
  Gorilla.Viewport, Gorilla.Camera, Gorilla.Light, Gorilla.Material.VertexColor,
  GDEMTerrain, GDEMTerrainLod, GDEMTerrainHud, GDEMFlight;

const
  { The most milliseconds a timer tick spends turning patches into meshes;
    what is left waits for the next tick. }
  UPLOAD_BUDGET_MS = 12;

type
  { @abstract(Reports a line for the log.)
    @param(Sender The view.)
    @param(AText The line.) }
  TTerrainReportEvent = procedure(Sender: TObject; const AText: string) of object;

  { @abstract(A Gorilla3D view of the ground round a tile, flown over.) }
  TTerrainView = class(TLayout)
  private
    { The Gorilla3D viewport, filling the layout. }
    FViewport: TGorillaViewport;
    { The camera. }
    FCamera: TGorillaCamera;
    { The point the camera looks at. }
    FCentre: TDummy;
    { The light, riding on the camera. }
    FLight: TGorillaLight;
    { Holds the patches' meshes. }
    FTerrain: TDummy;
    { The material every patch is drawn with: its vertex colours. }
    FMaterial: TGorillaVertexColorMaterialSource;
    { Decides which patches to draw; made by the first @link(ShowArea). }
    FLod: TTerrainLod;
    { Turns patches into meshes, moves the flight, and looks again, every
      15 ms. }
    FTimer: TTimer;
    { Backing field for @link(TileLookup). }
    FTileLookup: TTerrainTileLookup;
    { The shared triangles. }
    FIndices: TArray<Integer>;
    { The same as 16-bit numbers, for a 16-bit index buffer. }
    FIndices16: TArray<Word>;
    { The same as 32-bit numbers. }
    FIndices32: TArray<Cardinal>;
    { The latitude of the south edge of the tile asked for. }
    FAreaSouth: Integer;
    { The longitude of its west edge. }
    FAreaWest: Integer;
    { @true once a tile has been asked for. }
    FHasArea: Boolean;
    { Backing field for @link(Exaggeration). }
    FExaggeration: Single;
    { Backing field for @link(MaxDetail). }
    FMaxDetail: Integer;
    { Backing field for @link(Range). }
    FRange: Integer;
    { The flight: where the camera is and where it is going. }
    FFlight: TFlight;
    { The flight's controls held down on the keyboard. }
    FHeld: TFlightControls;
    { Times the gap between moves of the flight. }
    FFlightWatch: TStopwatch;
    { @true while the left button is held down on the view, looking round. }
    FDragging: Boolean;
    { Where the pointer was at the last move of the drag. }
    FDragLast: TPointF;
    { @true when the camera has moved since the tree last looked. }
    FCameraMoved: Boolean;
    { @true while patches were being made at the last tick. }
    FWasBusy: Boolean;
    { Times the work since it started. }
    FBusyWatch: TStopwatch;
    { Milliseconds spent turning patches into meshes since the work
      started. }
    FUploadMs: Double;
    { Patches turned into meshes since the work started. }
    FUploads: Integer;
    { @true if the last patch's vertices were copied straight into the
      buffer; @false if FMX's setters had to be used for some. }
    FDirectCopy: Boolean;
    { The nearest the view draws, kilometres, as last set: it follows the
      flight down, so the ground is not cut away when flying low. }
    FNearPlane: Single;
    { The camera's heights, over the top left of the viewport. }
    FAltimeter: TTerrainAltimeter;
    { The frames drawn a second, under @link(FAltimeter). }
    FFrameRate: TTerrainFrameRate;
    { The speed and the camera's tilt, under @link(FFrameRate). }
    FSpeedPanel: TTerrainSpeedPanel;
    { The compass, over the top right of the viewport. }
    FCompass: TTerrainCompass;
    { News across the middle of the view: a crash. }
    FBanner: TTerrainBanner;
    { Times the gap between readings of the frame rate and checks of the
      display. }
    FRateWatch: TStopwatch;
    { The display the window was on at the last check; empty before the
      first. }
    FDisplayName: string;
    { Backing field for @link(StartHeight). }
    FStartHeight: Integer;
    { Backing field for @link(OnSettled). }
    FOnSettled: TTerrainReportEvent;
    { Backing field for @link(OnLog). }
    FOnLog: TTerrainReportEvent;

    { Puts the camera where the flight is, looking along its heading and
      down by its tilt, and has the instruments show it. }
    procedure PlaceCamera;

    { The camera, for the tree.
      @returns(Its position, directions and view.) }
    function MakeEye: TTerrainEye;

    { The ground's true height at a place, for the flight: from the tree's
      heights, once there is a tree.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @param(AMetres The height above sea level, metres.)
      @returns(@false if the ground there is not known yet.) }
    function FlightGround(ALatitude, ALongitude: Double; out AMetres: Double): Boolean;

    { Moves the flight on by the time since the last tick, turns made
      patches into meshes, measures again from a new point if the flight
      has gone far, and has the tree look again.
      @param(Sender The timer.) }
    procedure TimerTick(Sender: TObject);

    { Shows the crash banner and logs where it happened.
      @param(ASpeed The speed just before, metres a second.) }
    procedure ReportCrash(ASpeed: Double);

    { Gives the instruments the flight's heights, heading, speed and tilt;
      dashes while there is nothing to measure from. }
    procedure UpdateInstruments;

    { Puts the instruments in the corners of the view, and the banner in
      the middle. }
    procedure PlaceInstruments;

    { Reads the frame rate for its panel, and if the window has moved to
      another display, draws no faster than that display refreshes. }
    procedure CheckFrameRate;

    { Makes a patch's mesh, hidden.
      @param(APatch The patch.)
      @returns(The mesh.)
      @raises(ETerrainError if Gorilla3D gives it no mesh data.) }
    function MakeMesh(const APatch: TTerrainPatch): TObject;

    { Copies a patch's vertices into a vertex buffer, straight into its
      memory where the layout can be found, otherwise through FMX's
      setters.
      @param(ABuffer The buffer, already the right length.)
      @param(APatch The patch.)
      @returns(@true if every attribute was copied straight.) }
    function FillVertices(ABuffer: TVertexBuffer; const APatch: TTerrainPatch): Boolean;

    { Copies the shared triangles into an index buffer.
      @param(ABuffer The buffer.) }
    procedure FillIndices(ABuffer: TIndexBuffer);

    { Shows or hides a mesh, for the tree.
      @param(AMesh The mesh.)
      @param(AVisible @true to show it.) }
    procedure ShowMesh(AMesh: TObject; AVisible: Boolean);

    { Frees a mesh, for the tree.
      @param(AMesh The mesh.) }
    procedure ReleaseMesh(AMesh: TObject);

    { Passes the tree's problems to @link(OnLog).
      @param(AText The line.) }
    procedure LodLog(const AText: string);

    { Starts timing a round of work. }
    procedure BeginWork;

    { Measures everything again from the tile under the flight. }
    procedure Rebase;

    { Writer for @link(Exaggeration): every patch is made again, and the
      flight drawn as much higher.
      @param(AValue Times to stretch heights; at least 0.1.) }
    procedure SetExaggeration(AValue: Single);

    { Writer for @link(MaxDetail).
      @param(AValue Samples across a tile, from @code(TERRAIN_DETAILS).) }
    procedure SetMaxDetail(AValue: Integer);

    { Writer for @link(Range).
      @param(AValue Tenths, from @code(TERRAIN_RANGES).) }
    procedure SetRange(AValue: Integer);

    { Writer for @link(StartHeight).
      @param(AValue Metres; less than 0 is taken as 0.) }
    procedure SetStartHeight(AValue: Integer);

    { Reader for @link(ShownPatches). @returns(Patches on show.) }
    function GetShownPatches: Integer;
  protected
    { Keeps the instruments in place when the view changes size. }
    procedure Resize; override;

    { Takes the keyboard and starts looking round with the left button.
      @param(Button The button.)
      @param(Shift The keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Turns and tilts while dragging: across turns, up and down tilts.
      @param(Shift The keys and buttons held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;

    { Stops looking round.
      @param(Button The button.)
      @param(Shift The keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Climbs (rolling away) or descends.
      @param(Shift The keys held.)
      @param(WheelDelta 120 a notch.)
      @param(Handled Set to @true.) }
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;

    { Starts the flight again. }
    procedure DblClick; override;

    { Holds a flight control down, or stops (Space) or starts again (R).
      @param(Key The key's code; set to 0 when used.)
      @param(KeyChar The character typed; set to #0 when used.)
      @param(Shift The keys held.) }
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;

    { Lets a flight control go.
      @param(Key The key's code; set to 0 when used.)
      @param(KeyChar The character typed; set to #0 when used.)
      @param(Shift The keys held.) }
    procedure KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;

    { Lets every flight control go when the keyboard goes elsewhere, since
      the keys' release would not arrive here. }
    procedure DoExit; override;
  public
    { Makes the viewport, camera, light, material, flight and
      instruments; nothing is shown yet.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Stops the timer and frees every mesh and the flight. }
    destructor Destroy; override;

    { Shows the ground round a tile.
      @param(ASouth The latitude of the tile's south edge.)
      @param(AWest The longitude of its west edge.)
      @param(AResetView @true to start the flight again over the tile;
        @false to keep flying where it is.)
      @raises(ETerrainError if @link(TileLookup) is not set.) }
    procedure ShowArea(ASouth, AWest: Integer; AResetView: Boolean);

    { Starts the flight again: hovering, facing north,
      @link(StartHeight) above the middle of the tile asked for. }
    procedure ResetView;

    { Says what each tile holds; set before @link(ShowArea). Called on the
      main thread. }
    property TileLookup: TTerrainTileLookup read FTileLookup write FTileLookup;

    { Times to stretch heights; 1 is true scale. Setting it makes every
      patch again. }
    property Exaggeration: Single read FExaggeration write SetExaggeration;

    { The most samples across a tile used near the camera, from
      @code(TERRAIN_DETAILS). }
    property MaxDetail: Integer read FMaxDetail write SetMaxDetail;

    { The distance detail, in tenths, from @code(TERRAIN_RANGES). }
    property Range: Integer read FRange write SetRange;

    { How far above the ground the flight starts, metres; used from the
      next start. }
    property StartHeight: Integer read FStartHeight write SetStartHeight;

    { @true once a tile has been shown. }
    property HasTerrain: Boolean read FHasArea;

    { Patches on show. }
    property ShownPatches: Integer read GetShownPatches;

    { Says what a round of work did, once every patch wanted has been
      made: patches, triangles, tiles and times. }
    property OnSettled: TTerrainReportEvent read FOnSettled write FOnSettled;

    { Reports problems, changes of frame, of display and crashes. }
    property OnLog: TTerrainReportEvent read FOnLog write FOnLog;
  end;

implementation

uses
  // Gorilla.DefTypes declares enumeration values with common names (such as
  // Default), so it comes before System.Math, whose names then win; and
  // Default() is not used in this unit
  Gorilla.Mesh, Gorilla.DefTypes,
  // For FMX's vertex and index buffer setters to be expanded inline
  System.RTLConsts,
  System.Math, FMX.Forms, GDEMDisplays;

const
  { The viewport's background, a dark blue-grey that reads as sky. }
  TERRAIN_BACKGROUND = $FF1B2230;
  { The camera's field of view, in degrees. }
  TERRAIN_FOV = 45;
  { The nearest the view draws, kilometres: 50 m, when high up. }
  NEAR_PLANE_KM = 0.05;
  { The nearest the view draws when low down, kilometres: 5 m. }
  MIN_NEAR_PLANE_KM = 0.005;
  { The nearest the view draws is this share of the height above the
    ground, between @link(MIN_NEAR_PLANE_KM) and @link(NEAR_PLANE_KM), so
    the ground below is not cut away when flying low. }
  NEAR_PLANE_SHARE = 0.25;
  { The farthest the view draws, kilometres. }
  FAR_PLANE_KM = 3000;
  { How far ahead of the camera the point it looks at is, kilometres;
    typed, as @code(TPoint3D) multiplies by Single. }
  LOOK_AHEAD_KM: Single = 1;
  { Degrees turned for each pixel dragged across. }
  DRAG_TURN = 0.25;
  { Degrees tilted for each pixel dragged up or down. }
  DRAG_TILT = 0.2;
  { The view is treated as this much wider and taller than it is when
    deciding what is in view, so nothing at its edges is missed. }
  VIEW_MARGIN = 1.1;
  { Ticks of the timer, milliseconds. }
  TICK_MS = 15;
  { The instruments' distance from the view's edges, pixels. }
  HUD_MARGIN = 12;
  { The gap between instruments, pixels. }
  HUD_GAP = 6;
  { How often the frame rate is read and the display checked,
    milliseconds. }
  FPS_REFRESH_MS = 250;
  { The frames a second drawn when the display does not say how fast it
    refreshes, as on Linux. }
  DEFAULT_FRAME_RATE = 60;
  { Refresh rates below this are not believed. }
  MIN_FRAME_RATE = 24;

{ TTerrainView }

constructor TTerrainView.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited Create(AOwner);
  // The layout takes the mouse and the keys; the viewport lets them through
  HitTest := True;
  CanFocus := True;
  FExaggeration := DEFAULT_TERRAIN_HEIGHTS;
  FMaxDetail := DEFAULT_TERRAIN_DETAIL;
  FRange := DEFAULT_TERRAIN_RANGE;
  FStartHeight := DEFAULT_FLIGHT_START_HEIGHT;
  FFlight := TFlight.Create(FlightGround);
  FFlight.StartHeight := FStartHeight;

  FViewport := TGorillaViewport.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := TAlignLayout.Client;
  FViewport.HitTest := False;
  FViewport.UseFixedFrameRate := True;
  FViewport.FixedFrameRate := DEFAULT_FRAME_RATE;
  FViewport.VSync := False;
  FViewport.Color := TERRAIN_BACKGROUND;
  FViewport.UsingDesignCamera := False;
  // The scene is in kilometres: from 50 m to beyond the farthest tile
  FNearPlane := NEAR_PLANE_KM;
  FViewport.NearPlane := FNearPlane;
  FViewport.FarPlane := FAR_PLANE_KM;

  FCentre := TDummy.Create(Self);
  FCentre.Parent := FViewport;

  FTerrain := TDummy.Create(Self);
  FTerrain.Parent := FViewport;

  FCamera := TGorillaCamera.Create(Self);
  FCamera.Parent := FViewport;
  FCamera.FOV := TERRAIN_FOV;
  FCamera.Target := FCentre;
  FViewport.Camera := FCamera;

  // As in Sprite3D, the light rides on the camera, lighting whatever side
  // is in view
  FLight := TGorillaLight.Create(Self);
  FLight.Parent := FCamera;
  FLight.Position.Point := TPoint3D.Zero;
  FLight.LightType := TLightType.Point;

  // One material for every patch
  FMaterial := TGorillaVertexColorMaterialSource.Create(Self);
  FMaterial.Parent := FViewport;

  FIndices := TerrainPatchIndices;
  SetLength(FIndices16, Length(FIndices));
  SetLength(FIndices32, Length(FIndices));
  for I := 0 to High(FIndices) do
  begin
    FIndices16[I] := FIndices[I];
    FIndices32[I] := FIndices[I];
  end;

  // The instruments, made after the viewport so they are drawn over it
  FAltimeter := TTerrainAltimeter.Create(Self);
  FAltimeter.Parent := Self;
  FFrameRate := TTerrainFrameRate.Create(Self);
  FFrameRate.Parent := Self;
  FSpeedPanel := TTerrainSpeedPanel.Create(Self);
  FSpeedPanel.Parent := Self;
  FCompass := TTerrainCompass.Create(Self);
  FCompass.Parent := Self;
  FBanner := TTerrainBanner.Create(Self);
  FBanner.Parent := Self;
  PlaceInstruments;
  FRateWatch := TStopwatch.StartNew;
  FFlightWatch := TStopwatch.StartNew;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := TICK_MS;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
end;

destructor TTerrainView.Destroy;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  // The meshes go with the tree, before the material they use
  FreeAndNil(FLod);
  FreeAndNil(FFlight);
  inherited;
end;

function TTerrainView.FlightGround(ALatitude, ALongitude: Double; out AMetres: Double): Boolean;
begin
  AMetres := 0;
  Result := (FLod <> nil) and FLod.GroundHeight(ALatitude, ALongitude, AMetres);
end;

procedure TTerrainView.PlaceCamera;
var
  LPosition, LEast, LNorth, LUp, LAhead, LLook: TPoint3D;
  LSinHeading, LCosHeading, LSinTilt, LCosTilt, LGround: Double;
  LNear, LSH, LCH, LST, LCT: Single;
begin
  if (FLod = nil) or not FLod.Started then
  begin
    UpdateInstruments;
    Exit;
  end;
  // Heights are drawn stretched, so the flight is too, keeping its height
  // above the ground as drawn
  LPosition := FLod.Frame.ToLocal(FFlight.Latitude, FFlight.Longitude,
    FFlight.Altitude * FExaggeration / 1000);
  // Its own east, north and up, which turn from the frame's away from the
  // frame's point; east x north is up (-Y at the frame's point)
  FLod.Frame.Directions(FFlight.Latitude, FFlight.Longitude, LEast, LNorth);
  LUp := LEast.CrossProduct(LNorth);
  SinCos(DegToRad(FFlight.Heading), LSinHeading, LCosHeading);
  SinCos(DegToRad(FFlight.Tilt), LSinTilt, LCosTilt);
  // TPoint3D multiplies by Single
  LSH := LSinHeading;
  LCH := LCosHeading;
  LST := LSinTilt;
  LCT := LCosTilt;
  LAhead := LEast * LSH + LNorth * LCH;
  LLook := LAhead * LCT - LUp * LST;
  FCamera.Position.Point := LPosition;
  FCentre.Position.Point := LPosition + LLook * LOOK_AHEAD_KM;

  // The nearest the view draws follows the flight down, so low over the
  // ground it is not cut away; high up it stays at 50 m
  if FLod.GroundHeight(FFlight.Latitude, FFlight.Longitude, LGround) then
    LNear := EnsureRange(NEAR_PLANE_SHARE * (FFlight.Altitude - LGround) * FExaggeration / 1000,
      MIN_NEAR_PLANE_KM, NEAR_PLANE_KM)
  else
    LNear := NEAR_PLANE_KM;
  if Abs(LNear - FNearPlane) > 0.1 * FNearPlane then
  begin
    FNearPlane := LNear;
    FViewport.NearPlane := FNearPlane;
  end;

  FCameraMoved := True;
  UpdateInstruments;
end;

procedure TTerrainView.UpdateInstruments;
var
  LGround: Double;
begin
  if (FAltimeter = nil) or (FFrameRate = nil) or (FSpeedPanel = nil) or (FCompass = nil) then
    Exit;
  if (FLod = nil) or not FLod.Started then
  begin
    FAltimeter.AltitudeKnown := False;
    FAltimeter.Known := False;
    FCompass.Known := False;
    Exit;
  end;
  FAltimeter.Exaggeration := FExaggeration;
  FAltimeter.Altitude := FFlight.Altitude;
  FAltimeter.AltitudeKnown := True;
  if FLod.GroundHeight(FFlight.Latitude, FFlight.Longitude, LGround) then
  begin
    FAltimeter.Ground := LGround;
    FAltimeter.AboveGround := FFlight.Altitude - LGround;
    FAltimeter.Known := True;
  end
  else
    FAltimeter.Known := False;
  FCompass.Heading := FFlight.Heading;
  FCompass.Known := True;
  FSpeedPanel.Speed := FFlight.Speed;
  FSpeedPanel.Tilt := FFlight.Tilt;
end;

procedure TTerrainView.PlaceInstruments;
var
  LTop: Single;
begin
  if (FAltimeter = nil) or (FFrameRate = nil) or (FSpeedPanel = nil) or (FCompass = nil) or
     (FBanner = nil) then
    Exit;
  LTop := HUD_MARGIN;
  FAltimeter.Position.Point := PointF(HUD_MARGIN, LTop);
  LTop := LTop + ALTIMETER_HEIGHT + HUD_GAP;
  FSpeedPanel.Position.Point := PointF(HUD_MARGIN, LTop);
  LTop := LTop + SPEED_PANEL_HEIGHT + HUD_GAP;
  FFrameRate.Position.Point := PointF(HUD_MARGIN, LTop);
  FCompass.Position.Point := PointF(Max(Width - HUD_MARGIN - COMPASS_SIZE,
    HUD_MARGIN + ALTIMETER_WIDTH + HUD_GAP), HUD_MARGIN);
  FBanner.Position.Point := PointF(Max((Width - BANNER_WIDTH) / 2, 0),
    Max(Height * 0.35 - BANNER_HEIGHT / 2, 0));
end;

procedure TTerrainView.Resize;
begin
  inherited;
  PlaceInstruments;
end;

procedure TTerrainView.CheckFrameRate;
var
  LForm: TCommonCustomForm;
  LDisplay: TFormDisplay;
  LRate: Integer;
begin
  // Gorilla3D's own count: with a fixed frame rate, the frames drawn in
  // the last second
  FFrameRate.FramesPerSecond := FViewport.FPS;
  FFrameRate.Known := True;

  // Which display the window is on: naming it is quick, its refresh rate
  // is read only when it changes
  if (Root = nil) or not (Root.GetObject is TCommonCustomForm) then
    Exit;
  LForm := TCommonCustomForm(Root.GetObject);
  LDisplay := DisplayOfForm(LForm, False);
  if (LDisplay.Name = '') or (LDisplay.Name = FDisplayName) then
    Exit;
  FDisplayName := LDisplay.Name;
  LDisplay := DisplayOfForm(LForm, True);
  LRate := LDisplay.RefreshRate;
  if LRate >= MIN_FRAME_RATE then
    FViewport.FixedFrameRate := LRate
  else
    FViewport.FixedFrameRate := DEFAULT_FRAME_RATE;
  FFrameRate.Limit := Round(FViewport.FixedFrameRate);
  if Assigned(FOnLog) then
  begin
    if LRate >= MIN_FRAME_RATE then
      FOnLog(Self, Format('3D: the window is on %s, which refreshes at %d Hz, so the view is ' +
        'drawn at up to %d frames a second', [FDisplayName, LRate, LRate]))
    else
      FOnLog(Self, Format('3D: the window is on %s, which does not say how fast it refreshes, ' +
        'so the view is drawn at up to %d frames a second', [FDisplayName, DEFAULT_FRAME_RATE]));
  end;
end;

function TTerrainView.MakeEye: TTerrainEye;
var
  LHeight: Single;
begin
  Result.Position := FCamera.Position.Point;
  Result.Target := FCentre.Position.Point;
  Result.Forward := (Result.Target - Result.Position).Normalize;
  // Up is -Y
  Result.Right := Point3D(0, -1, 0).CrossProduct(Result.Forward).Normalize;
  Result.Up := Result.Forward.CrossProduct(Result.Right);
  LHeight := Max(Height, 1);
  Result.TanY := Tan(DegToRad(TERRAIN_FOV / 2)) * VIEW_MARGIN;
  Result.TanX := Result.TanY * Max(Width, 1) / LHeight;
end;

procedure TTerrainView.ResetView;
var
  LStart: TPoint3D;
begin
  FBanner.Visible := False;
  FHeld := [];
  if not FHasArea then
    Exit;
  FFlight.StartHeight := FStartHeight;
  FFlight.Start(FAreaSouth + 0.5, FAreaWest + 0.5);
  // Measured again from the tile asked for if the flight had gone far
  if FLod <> nil then
  begin
    LStart := FLod.Frame.ToLocal(FFlight.Latitude, FFlight.Longitude, 0);
    if FLod.NeedsRebase(LStart.X, LStart.Z) then
    begin
      FLod.Start(FAreaSouth, FAreaWest);
      BeginWork;
    end;
  end;
  PlaceCamera;
end;

procedure TTerrainView.BeginWork;
begin
  FBusyWatch := TStopwatch.StartNew;
  FUploadMs := 0;
  FUploads := 0;
  if FLod <> nil then
    FLod.ResetCounts;
  FWasBusy := True;
end;

procedure TTerrainView.ShowArea(ASouth, AWest: Integer; AResetView: Boolean);
begin
  if not Assigned(FTileLookup) then
    raise ETerrainError.Create('The 3D view was not told where to find tiles');
  if FLod = nil then
  begin
    FLod := TTerrainLod.Create(FTileLookup);
    FLod.OnShowMesh := ShowMesh;
    FLod.OnReleaseMesh := ReleaseMesh;
    FLod.OnLog := LodLog;
  end;
  FLod.MaxDepth := TerrainMaxDepth(FMaxDetail);
  FLod.Range := FRange / 10;
  FLod.Exaggeration := FExaggeration;
  FAreaSouth := ASouth;
  FAreaWest := AWest;
  if AResetView or not FHasArea then
  begin
    FLod.Start(ASouth, AWest);
    FHasArea := True;
    FFlight.StartHeight := FStartHeight;
    FFlight.Start(ASouth + 0.5, AWest + 0.5);
    FBanner.Visible := False;
  end
  else
    // Flying on from where it is, measured from the tile under it
    FLod.Start(Floor(FFlight.Latitude), Floor(FFlight.Longitude));
  FHeld := [];
  PlaceCamera;
  BeginWork;
  FLod.Update(MakeEye);
  FCameraMoved := False;
  FFlightWatch := TStopwatch.StartNew;
  FTimer.Enabled := True;
end;

procedure TTerrainView.Rebase;
begin
  FLod.Start(Floor(FFlight.Latitude), Floor(FFlight.Longitude));
  if Assigned(FOnLog) then
    FOnLog(Self, Format('3D: the flight went more than %d km, so the view is measured again ' +
      'from %.4f, %.4f', [TERRAIN_REBASE_KM, FFlight.Latitude, FFlight.Longitude]));
  BeginWork;
  PlaceCamera;
end;

procedure TTerrainView.ReportCrash(ASpeed: Double);
var
  LWhere: string;
begin
  FHeld := [];
  LWhere := Format('%.4f, %.4f', [FFlight.Latitude, FFlight.Longitude]);
  FBanner.ShowText('Crashed',
    Format('Into the ground at %s, %s km/h. Press R to start again.',
      [FormatHudHeight(FFlight.Altitude), FormatFloat('#,##0', ASpeed * 3.6)]));
  PlaceInstruments;
  if Assigned(FOnLog) then
    FOnLog(Self, Format('3D: crashed into the ground at %s (ground %s), heading %.0f, ' +
      '%s km/h', [LWhere, FormatHudHeight(FFlight.Altitude), FFlight.Heading,
       FormatFloat('#,##0', ASpeed * 3.6)]));
end;

procedure TTerrainView.TimerTick(Sender: TObject);
var
  LWatch: TStopwatch;
  LNode: TTerrainNode;
  LPatch: TTerrainPatch;
  LMesh: TObject;
  LChanged, LBusy, LWasCrashed: Boolean;
  LSeconds, LSpeed: Double;
  LReport, LCopy: string;
begin
  if (FLod = nil) or not FLod.Started then
    Exit;
  try
    if FRateWatch.ElapsedMilliseconds >= FPS_REFRESH_MS then
    begin
      FRateWatch := TStopwatch.StartNew;
      CheckFrameRate;
    end;

    // The flight moves on by the time gone, whatever the frame rate
    LSeconds := FFlightWatch.Elapsed.TotalSeconds;
    FFlightWatch := TStopwatch.StartNew;
    LWasCrashed := FFlight.Crashed;
    LSpeed := FFlight.Speed;
    if FFlight.Step(FHeld, LSeconds) then
      PlaceCamera;
    if FFlight.Crashed and not LWasCrashed then
      ReportCrash(LSpeed);

    if FLod.NeedsRebase(FCamera.Position.X, FCamera.Position.Z) then
      Rebase;

    LChanged := FCameraMoved;
    LWatch := TStopwatch.StartNew;
    while (LWatch.ElapsedMilliseconds < UPLOAD_BUDGET_MS) and FLod.TakeBuilt(LNode, LPatch) do
    begin
      try
        LMesh := MakeMesh(LPatch);
        FLod.Attach(LNode, LMesh, LPatch);
        Inc(FUploads);
      except
        on E: Exception do
          FLod.MarkFailed(LNode, E.ClassName + ': ' + E.Message);
      end;
      LChanged := True;
    end;
    if LChanged then
      FUploadMs := FUploadMs + LWatch.Elapsed.TotalMilliseconds;

    if LChanged then
    begin
      FCameraMoved := False;
      FLod.Update(MakeEye);
      // Finer heights under the flight change its height above them
      UpdateInstruments;
    end;

    LBusy := FLod.Busy;
    if LBusy and not FWasBusy then
      BeginWork
    else if not LBusy and FWasBusy then
    begin
      FWasBusy := False;
      if Assigned(FOnSettled) then
      begin
        if FDirectCopy then
          LCopy := 'copied straight'
        else
          LCopy := 'through FMX''s setters';
        LReport := Format('3D: settled in %d ms: %d patches on show (%s triangles) of %d kept, ' +
          'over %d tiles (%d with heights); %d made by up to %d workers, %.1f ms each; ' +
          '%d meshes in %.0f ms, %.2f ms each (vertices %s)',
          [FBusyWatch.ElapsedMilliseconds, FLod.ShownCount,
           FormatFloat('#,##0', Int64(FLod.ShownCount) * PATCH_TRIANGLES), FLod.NodeCount,
           FLod.TileCount, FLod.LandTileCount, FLod.BuiltCount, FLod.MaxInFlight,
           FLod.BuildMilliseconds / Max(FLod.BuiltCount, 1), FUploads, FUploadMs,
           FUploadMs / Max(FUploads, 1),
           LCopy]);
        if FLod.FailedCount > 0 then
          LReport := LReport + Format('; %d could not be made', [FLod.FailedCount]);
        FOnSettled(Self, LReport);
      end;
    end;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      if Assigned(FOnLog) then
        FOnLog(Self, 'WARNING: the 3D view stopped (' + E.ClassName + ': ' +
          E.Message.TrimRight(['.']) + ')');
    end;
  end;
end;

function TTerrainView.FillVertices(ABuffer: TVertexBuffer; const APatch: TTerrainPatch): Boolean;
const
  // A colour no patch has, to find where FMX keeps a vertex's colour
  SENTINEL: TAlphaColor = $A1B2C3D4;
var
  LBase, LVertex: PByte;
  LSize, LVertexOffset, LNormalOffset, LColourOffset, I: Integer;
  LPointsDirect: Boolean;

  { @true if a colour at an offset would overlap a position or normal.
    @param(AOffset The offset.)
    @returns(@true if it overlaps.) }
  function Overlaps(AOffset: Integer): Boolean;
  begin
    Result :=
      ((AOffset + SizeOf(TAlphaColor) > LVertexOffset) and (AOffset < LVertexOffset + SizeOf(TPoint3D))) or
      ((AOffset + SizeOf(TAlphaColor) > LNormalOffset) and (AOffset < LNormalOffset + SizeOf(TPoint3D)));
  end;

begin
  LBase := PByte(ABuffer.Buffer);
  LSize := ABuffer.VertexSize;
  // Where the first vertex's position and normal are, from FMX's own
  // pointers; where its colour is, by setting it and looking for it
  LVertexOffset := Integer(PByte(ABuffer.VerticesPtr[0]) - LBase);
  LNormalOffset := Integer(PByte(ABuffer.NormalsPtr[0]) - LBase);
  LPointsDirect := (LBase <> nil) and InRange(LVertexOffset, 0, LSize - SizeOf(TPoint3D)) and
    InRange(LNormalOffset, 0, LSize - SizeOf(TPoint3D));
  LColourOffset := -1;
  if LPointsDirect then
  begin
    ABuffer.Color0[0] := SENTINEL;
    for I := 0 to LSize - SizeOf(TAlphaColor) do
      if (PCardinal(LBase + I)^ = SENTINEL) and not Overlaps(I) then
      begin
        LColourOffset := I;
        Break;
      end;
  end;

  if LPointsDirect then
    for I := 0 to High(APatch.Positions) do
    begin
      LVertex := LBase + I * LSize;
      PPoint3D(LVertex + LVertexOffset)^ := APatch.Positions[I];
      PPoint3D(LVertex + LNormalOffset)^ := APatch.Normals[I];
      if LColourOffset >= 0 then
        PAlphaColor(LVertex + LColourOffset)^ := APatch.Colours[I]
      else
        ABuffer.Color0[I] := APatch.Colours[I];
    end
  else
    for I := 0 to High(APatch.Positions) do
    begin
      ABuffer.Vertices[I] := APatch.Positions[I];
      ABuffer.Normals[I] := APatch.Normals[I];
      ABuffer.Color0[I] := APatch.Colours[I];
    end;
  Result := LPointsDirect and (LColourOffset >= 0);
end;

procedure TTerrainView.FillIndices(ABuffer: TIndexBuffer);
var
  LBase: PByte;
  I, LCount: Integer;
begin
  LCount := Length(FIndices);
  ABuffer.Length := LCount;
  // Which size FMX gave the indices: 16 bits puts the second at byte 2
  ABuffer.Indices[0] := 1;
  ABuffer.Indices[1] := 2;
  LBase := PByte(ABuffer.Buffer);
  if (LBase <> nil) and (PWord(LBase + 2)^ = 2) then
    System.Move(FIndices16[0], LBase^, LCount * SizeOf(Word))
  else if (LBase <> nil) and (PCardinal(LBase + 4)^ = 2) then
    System.Move(FIndices32[0], LBase^, LCount * SizeOf(Cardinal))
  else
    for I := 0 to LCount - 1 do
      ABuffer.Indices[I] := FIndices[I];
end;

function TTerrainView.MakeMesh(const APatch: TTerrainPatch): TObject;
var
  LMesh: TGorillaSingletonMesh;
  LData: TMeshData;
  LDef: TMeshDef;
begin
  LMesh := TGorillaSingletonMesh.Create(nil);
  try
    LMesh.Visible := False;
    LMesh.Parent := FTerrain;
    LData := LMesh.MeshData;
    if LData = nil then
      raise ETerrainError.Create('Gorilla3D gave a patch no mesh data to fill');
    LData.VertexBuffer.Length := Length(APatch.Positions);
    FDirectCopy := FillVertices(LData.VertexBuffer, APatch);
    FillIndices(LData.IndexBuffer);

    // Made static, the data goes to the GPU once and stays there; the mesh
    // frees its definition with it
    LDef := TMeshDef.Create(nil);
    LMesh.IsDefOwner := True;
    LMesh.Def := LDef;
    LDef.ApplyFromMeshData(LData);
    LDef.IsStatic := True;
    LData.Clear;
    LMesh.MaterialSource := FMaterial;
  except
    LMesh.Free;
    raise;
  end;
  Result := LMesh;
end;

procedure TTerrainView.ShowMesh(AMesh: TObject; AVisible: Boolean);
begin
  TControl3D(AMesh).Visible := AVisible;
end;

procedure TTerrainView.ReleaseMesh(AMesh: TObject);
begin
  AMesh.Free;
end;

procedure TTerrainView.LodLog(const AText: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, AText);
end;

procedure TTerrainView.SetExaggeration(AValue: Single);
begin
  AValue := Max(AValue, 0.1);
  if SameValue(AValue, FExaggeration) then
    Exit;
  FExaggeration := AValue;
  if FLod <> nil then
  begin
    FLod.Exaggeration := AValue;
    BeginWork;
    PlaceCamera;
  end;
end;

procedure TTerrainView.SetStartHeight(AValue: Integer);
begin
  FStartHeight := Max(AValue, 0);
end;

procedure TTerrainView.SetMaxDetail(AValue: Integer);
begin
  FMaxDetail := AValue;
  if FLod <> nil then
  begin
    FLod.MaxDepth := TerrainMaxDepth(AValue);
    FCameraMoved := True;
  end;
end;

procedure TTerrainView.SetRange(AValue: Integer);
begin
  FRange := Max(AValue, 5);
  if FLod <> nil then
  begin
    FLod.Range := FRange / 10;
    FCameraMoved := True;
  end;
end;

function TTerrainView.GetShownPatches: Integer;
begin
  if FLod <> nil then
    Result := FLod.ShownCount
  else
    Result := 0;
end;

procedure TTerrainView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  // A click on the view gives it the keyboard, for flying
  SetFocus;
  if Button = TMouseButton.mbLeft then
  begin
    FDragging := True;
    FDragLast := PointF(X, Y);
  end;
end;

procedure TTerrainView.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if not FDragging then
    Exit;
  // As looking round with the head: dragging right turns right, dragging
  // down looks further down
  FFlight.Look((X - FDragLast.X) * DRAG_TURN, (Y - FDragLast.Y) * DRAG_TILT);
  FDragLast := PointF(X, Y);
  PlaceCamera;
end;

procedure TTerrainView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FDragging := False;
end;

procedure TTerrainView.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  inherited;
  FFlight.Climb(WheelDelta / 120);
  PlaceCamera;
  Handled := True;
end;

procedure TTerrainView.DblClick;
begin
  inherited;
  FDragging := False;
  ResetView;
end;

{ Which flight control a key is.
  @param(AKey The key's code; 0 for a character typed.)
  @param(AKeyChar The character typed.)
  @param(AControl The control.)
  @returns(@false if the key is not a flight control.) }
function KeyControl(AKey: Word; AKeyChar: WideChar; out AControl: TFlightControl): Boolean;
begin
  Result := True;
  case AKey of
    vkUp: AControl := fcFaster;
    vkDown: AControl := fcSlower;
    vkLeft: AControl := fcTurnLeft;
    vkRight: AControl := fcTurnRight;
    vkPrior: AControl := fcClimb;
    vkNext: AControl := fcDescend;
    vkQ: AControl := fcTiltUp;
    vkA: AControl := fcTiltDown;
  else
    // Some systems send letters only as characters
    case UpCase(AKeyChar) of
      'Q': AControl := fcTiltUp;
      'A': AControl := fcTiltDown;
    else
      Result := False;
    end;
  end;
end;

procedure TTerrainView.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  LControl: TFlightControl;
begin
  inherited;
  if KeyControl(Key, KeyChar, LControl) then
  begin
    // A crash holds everything until the flight starts again
    if not FFlight.Crashed then
      Include(FHeld, LControl);
  end
  else if (Key = vkR) or (UpCase(KeyChar) = 'R') then
    ResetView
  else if (Key = vkSpace) or (KeyChar = ' ') then
  begin
    FFlight.Stop;
    UpdateInstruments;
  end
  else
    Exit;
  Key := 0;
  KeyChar := #0;
end;

procedure TTerrainView.KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  LControl: TFlightControl;
begin
  inherited;
  if not KeyControl(Key, KeyChar, LControl) then
    Exit;
  Exclude(FHeld, LControl);
  Key := 0;
  KeyChar := #0;
end;

procedure TTerrainView.DoExit;
begin
  inherited;
  FHeld := [];
  FDragging := False;
end;

end.
