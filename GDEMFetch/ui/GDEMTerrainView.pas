{ @abstract(The 3D view: a Gorilla3D viewport showing the ground round a
  tile, fine near the camera and coarser further away, which the mouse
  turns, moves and zooms.)

  @link(TTerrainView) is a layout that fills the 3D tab. It holds:

  @preformatted(
TTerrainView                  takes the mouse
`-- TGorillaViewport          HitTest off, so the mouse reaches the layout
    |-- centre (TDummy)       what the camera looks at, on the ground
    |-- terrain (TDummy)      holds the patches' meshes
    |   `-- TGorillaSingletonMesh, one per patch, all sharing one
    |       TGorillaVertexColorMaterialSource
    `-- TGorillaCamera        Target is the centre
        `-- TGorillaLight     a point light where the camera is
  )

  Which patches to draw is decided by @code(TTerrainLod) (in
  @code(GDEMTerrainLod)), which has them made on worker threads; this view
  turns each one made into a mesh on the main thread, a few at a time
  (@link(UPLOAD_BUDGET_MS) each tick of a 15 ms timer), so the window keeps
  responding while the ground sharpens. The vertices are copied straight
  into FMX's vertex buffer where its layout can be found, and the one list
  of triangles every patch shares is copied in a single move.

  The camera sits @link(TTerrainView.Distance) kilometres from the centre,
  at an @link(TTerrainView.Azimuth) round it (0 from the south, 90 from
  the east) and an @link(TTerrainView.Elevation) above the level (5 to 89
  degrees); the centre is on the ground, at the height of the surface
  below it. Left-drag turns the view; right-drag, middle-drag or Shift +
  left-drag moves it, as on the map, the ground following the pointer; the
  wheel zooms; a double click puts the starting view back. Moving far
  enough from where the view started measures everything again from there
  (@code(TERRAIN_REBASE_KM)), so the view can travel as far as there are
  tiles. }
unit GDEMTerrainView;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math.Vectors,
  System.Diagnostics,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Types3D, FMX.Controls3D, FMX.Objects3D,
  Gorilla.Viewport, Gorilla.Camera, Gorilla.Light,
  GDEMTerrain, GDEMTerrainLod;

const
  { The most milliseconds a timer tick spends turning patches into meshes;
    what is left waits for the next tick. }
  UPLOAD_BUDGET_MS = 12;

type
  { @abstract(Reports a line for the log.)
    @param(Sender The view.)
    @param(AText The line.) }
  TTerrainReportEvent = procedure(Sender: TObject; const AText: string) of object;

  { @abstract(A Gorilla3D view of the ground round a tile.) }
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
    FMaterial: TMaterialSource;
    { Decides which patches to draw; made by the first @link(ShowArea). }
    FLod: TTerrainLod;
    { Turns patches into meshes and looks again, every 15 ms. }
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
    { Backing field for @link(Azimuth). }
    FAzimuth: Single;
    { Backing field for @link(Elevation). }
    FElevation: Single;
    { Backing field for @link(Distance). }
    FDistance: Single;
    { Where the centre is, kilometres east of the frame's point. }
    FPanX: Single;
    { Where the centre is, kilometres north of the frame's point. }
    FPanZ: Single;
    { The centre's Y: the surface's height there. }
    FTargetY: Single;
    { @true while the left button is held down on the view, turning it. }
    FDragging: Boolean;
    { @true while a button is held down on the view, moving it. }
    FPanning: Boolean;
    { @link(FPanX) when the move started. }
    FDragPanX: Single;
    { @link(FPanZ) when the move started. }
    FDragPanZ: Single;
    { Where the drag started. }
    FDragStart: TPointF;
    { @link(Azimuth) when the drag started. }
    FDragAzimuth: Single;
    { @link(Elevation) when the drag started. }
    FDragElevation: Single;
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
    { Backing field for @link(OnSettled). }
    FOnSettled: TTerrainReportEvent;
    { Backing field for @link(OnLog). }
    FOnLog: TTerrainReportEvent;

    { Moves the centre to @link(FPanX), @link(FPanZ) at the surface's
      height, and the camera to @link(Distance), @link(Azimuth) and
      @link(Elevation) from it, never below the ground. }
    procedure PlaceCamera;

    { The camera, for the tree.
      @returns(Its position, directions and view.) }
    function MakeEye: TTerrainEye;

    { Turns made patches into meshes, measures again from a new point if
      the view has travelled far, and has the tree look again.
      @param(Sender The timer.) }
    procedure TimerTick(Sender: TObject);

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

    { Measures everything again from the tile under the centre. }
    procedure Rebase;

    { Writer for @link(Exaggeration): every patch is made again, keeping
      the view.
      @param(AValue Times to stretch heights; at least 0.1.) }
    procedure SetExaggeration(AValue: Single);

    { Writer for @link(MaxDetail).
      @param(AValue Samples across a tile, from @code(TERRAIN_DETAILS).) }
    procedure SetMaxDetail(AValue: Integer);

    { Writer for @link(Range).
      @param(AValue Tenths, from @code(TERRAIN_RANGES).) }
    procedure SetRange(AValue: Integer);

    { Reader for @link(ShownPatches). @returns(Patches on show.) }
    function GetShownPatches: Integer;
  protected
    { Starts turning the view with the left button, or moving it with the
      right or middle button or Shift + left.
      @param(Button The button.)
      @param(Shift The keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Turns or moves the view while dragging.
      @param(Shift The keys and buttons held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;

    { Stops turning or moving the view.
      @param(Button The button.)
      @param(Shift The keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Zooms: rolling away brings the camera nearer.
      @param(Shift The keys held.)
      @param(WheelDelta 120 a notch.)
      @param(Handled Set to @true.) }
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;

    { Puts the starting view back. }
    procedure DblClick; override;
  public
    { Makes the viewport, camera, light and material; nothing is shown
      yet.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Stops the timer and frees every mesh. }
    destructor Destroy; override;

    { Shows the ground round a tile.
      @param(ASouth The latitude of the tile's south edge.)
      @param(AWest The longitude of its west edge.)
      @param(AResetView @true to start from the starting view; @false to
        keep the camera's angle and distance.)
      @raises(ETerrainError if @link(TileLookup) is not set.) }
    procedure ShowArea(ASouth, AWest: Integer; AResetView: Boolean);

    { The starting view: from the south, 35 degrees up, far enough back
      to see the tile asked for and its neighbours, centred on it. }
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

    { The camera's direction from the centre, in degrees: 0 from the
      south, 90 from the east. }
    property Azimuth: Single read FAzimuth;

    { The camera's height above the level, in degrees, 5 to 89. }
    property Elevation: Single read FElevation;

    { The camera's distance from the centre, in kilometres. }
    property Distance: Single read FDistance;

    { @true once a tile has been shown. }
    property HasTerrain: Boolean read FHasArea;

    { Patches on show. }
    property ShownPatches: Integer read GetShownPatches;

    { Says what a round of work did, once every patch wanted has been
      made: patches, triangles, tiles and times. }
    property OnSettled: TTerrainReportEvent read FOnSettled write FOnSettled;

    { Reports problems and changes of frame. }
    property OnLog: TTerrainReportEvent read FOnLog write FOnLog;
  end;

implementation

uses
  // Gorilla.DefTypes declares enumeration values with common names (such as
  // Default), so it comes before System.Math, whose names then win; and
  // Default() is not used in this unit
  Gorilla.Mesh, Gorilla.DefTypes, Gorilla.Material.VertexColor,
  // For FMX's vertex and index buffer setters to be expanded inline
  System.RTLConsts,
  System.Math;

const
  { The viewport's background, a dark blue-grey that reads as sky. }
  TERRAIN_BACKGROUND = $FF1B2230;
  { The camera's field of view, in degrees. }
  TERRAIN_FOV = 45;
  { The nearest the view draws, kilometres: 50 m. }
  NEAR_PLANE_KM = 0.05;
  { The farthest the view draws, kilometres. }
  FAR_PLANE_KM = 3000;
  { The starting elevation, in degrees. }
  START_ELEVATION = 35;
  { The starting distance, kilometres: a tile and a quarter. }
  START_DISTANCE = 140;
  { The lowest and highest elevations the mouse can reach, in degrees. }
  MIN_ELEVATION = 5;
  { See @link(MIN_ELEVATION). }
  MAX_ELEVATION = 89;
  { The nearest the camera comes to the centre, kilometres. }
  MIN_DISTANCE = 0.3;
  { The farthest the camera goes, kilometres. }
  MAX_DISTANCE = 600;
  { The least the camera keeps above the ground, kilometres. }
  MIN_CLEARANCE = 0.03;
  { Degrees turned for each pixel dragged across. }
  DRAG_AZIMUTH = 0.4;
  { Degrees tilted for each pixel dragged up or down. }
  DRAG_ELEVATION = 0.3;
  { Distance kept for each wheel notch rolled away. }
  WHEEL_ZOOM = 0.88;
  { The view is treated as this much wider and taller than it is when
    deciding what is in view, so nothing at its edges is missed. }
  VIEW_MARGIN = 1.1;
  { Ticks of the timer, milliseconds. }
  TICK_MS = 15;

{ TTerrainView }

constructor TTerrainView.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited Create(AOwner);
  // The layout takes the mouse; the viewport lets it through
  HitTest := True;
  FExaggeration := DEFAULT_TERRAIN_HEIGHTS;
  FMaxDetail := DEFAULT_TERRAIN_DETAIL;
  FRange := DEFAULT_TERRAIN_RANGE;

  FViewport := TGorillaViewport.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := TAlignLayout.Client;
  FViewport.HitTest := False;
  FViewport.UseFixedFrameRate := True;
  FViewport.FixedFrameRate := 60;
  FViewport.VSync := False;
  FViewport.Color := TERRAIN_BACKGROUND;
  FViewport.UsingDesignCamera := False;
  // The scene is in kilometres: from 50 m to beyond the farthest tile
  FViewport.NearPlane := NEAR_PLANE_KM;
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

  FTimer := TTimer.Create(Self);
  FTimer.Interval := TICK_MS;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;

  ResetView;
end;

destructor TTerrainView.Destroy;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  // The meshes go with the tree, before the material they use
  FreeAndNil(FLod);
  inherited;
end;

procedure TTerrainView.PlaceCamera;
var
  LAzimuth, LElevation: Double;
  LPosition: TPoint3D;
  LGround: Single;
begin
  FCentre.Position.Point := Point3D(FPanX, FTargetY, FPanZ);
  LAzimuth := DegToRad(FAzimuth);
  LElevation := DegToRad(FElevation);
  // At azimuth 0 the camera is to the south (-Z) looking north; up is -Y
  LPosition := Point3D(
    FPanX + FDistance * Sin(LAzimuth) * Cos(LElevation),
    FTargetY - FDistance * Sin(LElevation),
    FPanZ - FDistance * Cos(LAzimuth) * Cos(LElevation));
  // Never in the ground
  if (FLod <> nil) and FLod.SurfaceY(LPosition.X, LPosition.Z, LGround) and
     (LPosition.Y > LGround - MIN_CLEARANCE) then
    LPosition.Y := LGround - MIN_CLEARANCE;
  FCamera.Position.Point := LPosition;
  FCameraMoved := True;
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
  LPoint: TPoint3D;
begin
  FAzimuth := 0;
  FElevation := START_ELEVATION;
  FDistance := START_DISTANCE;
  if FHasArea and (FLod <> nil) then
  begin
    LPoint := FLod.Frame.ToLocal(FAreaSouth + 0.5, FAreaWest + 0.5, 0);
    FPanX := LPoint.X;
    FPanZ := LPoint.Z;
  end
  else
  begin
    FPanX := 0;
    FPanZ := 0;
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
  FLod.Start(ASouth, AWest);
  FAreaSouth := ASouth;
  FAreaWest := AWest;
  FHasArea := True;
  FTargetY := 0;
  if AResetView then
    ResetView
  else
  begin
    // The tile's middle is the frame's point
    FPanX := 0;
    FPanZ := 0;
    PlaceCamera;
  end;
  BeginWork;
  FLod.Update(MakeEye);
  FCameraMoved := False;
  FTimer.Enabled := True;
end;

procedure TTerrainView.Rebase;
var
  LLatitude, LLongitude: Double;
  LPoint: TPoint3D;
  LShiftX, LShiftZ: Single;
begin
  FLod.Frame.ToGeo(FPanX, FPanZ, LLatitude, LLongitude);
  FLod.Start(Floor(LLatitude), Floor(LLongitude));
  LPoint := FLod.Frame.ToLocal(LLatitude, LLongitude, 0);
  // A move under way carries on from the same place
  LShiftX := LPoint.X - FPanX;
  LShiftZ := LPoint.Z - FPanZ;
  FPanX := LPoint.X;
  FPanZ := LPoint.Z;
  FDragPanX := FDragPanX + LShiftX;
  FDragPanZ := FDragPanZ + LShiftZ;
  if Assigned(FOnLog) then
    FOnLog(Self, Format('3D: the view moved more than %d km, so it is measured again from ' +
      '%.4f, %.4f', [TERRAIN_REBASE_KM, LLatitude, LLongitude]));
  BeginWork;
  PlaceCamera;
end;

procedure TTerrainView.TimerTick(Sender: TObject);
var
  LWatch: TStopwatch;
  LNode: TTerrainNode;
  LPatch: TTerrainPatch;
  LMesh: TObject;
  LChanged, LBusy: Boolean;
  LY: Single;
  LReport, LCopy: string;
begin
  if (FLod = nil) or not FLod.Started then
    Exit;
  try
    if FLod.NeedsRebase(FPanX, FPanZ) then
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

    // The centre on the ground, as finer heights arrive
    if FLod.SurfaceY(FPanX, FPanZ, LY) and (Abs(LY - FTargetY) > 0.002) then
    begin
      FTargetY := LY;
      PlaceCamera;
      LChanged := True;
    end;

    if LChanged then
    begin
      FCameraMoved := False;
      FLod.Update(MakeEye);
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
    Move(FIndices16[0], LBase^, LCount * SizeOf(Word))
  else if (LBase <> nil) and (PCardinal(LBase + 4)^ = 2) then
    Move(FIndices32[0], LBase^, LCount * SizeOf(Cardinal))
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
    FCameraMoved := True;
  end;
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
  FDragStart := PointF(X, Y);
  // As on the map: right, middle or Shift + left moves; left turns
  if (Button in [TMouseButton.mbRight, TMouseButton.mbMiddle]) or
     ((Button = TMouseButton.mbLeft) and (ssShift in Shift)) then
  begin
    FPanning := True;
    FDragPanX := FPanX;
    FDragPanZ := FPanZ;
  end
  else if Button = TMouseButton.mbLeft then
  begin
    FDragging := True;
    FDragAzimuth := FAzimuth;
    FDragElevation := FElevation;
  end;
end;

procedure TTerrainView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  LScale, LAzimuth, LRightX, LRightZ, LAheadX, LAheadZ, LDX, LDY: Double;
  LHeight: Single;
begin
  inherited;
  if FPanning then
  begin
    // Kilometres of ground for a pixel at the centre: the view's height
    // there is 2 tan(FOV / 2) times the distance; looking down at a slant,
    // a pixel up the screen covers more ground, by 1 / sin(elevation)
    LHeight := Height;
    if LHeight < 1 then
      LHeight := 1;
    LScale := 2 * Tan(DegToRad(TERRAIN_FOV / 2)) * FDistance / LHeight;
    LAzimuth := DegToRad(FAzimuth);
    // The camera's right and its way ahead, along the ground (X east,
    // Z north); at azimuth 0 it looks north, with east to its right
    LRightX := Cos(LAzimuth);
    LRightZ := Sin(LAzimuth);
    LAheadX := -Sin(LAzimuth);
    LAheadZ := Cos(LAzimuth);
    LDX := (X - FDragStart.X) * LScale;
    LDY := (Y - FDragStart.Y) * LScale / Max(Sin(DegToRad(FElevation)), 0.2);
    // The ground follows the pointer, so the centre moves the other way
    // across, and ahead as the pointer comes down
    FPanX := FDragPanX - LDX * LRightX + LDY * LAheadX;
    FPanZ := FDragPanZ - LDX * LRightZ + LDY * LAheadZ;
    PlaceCamera;
    Exit;
  end;
  if not FDragging then
    Exit;
  // The surface turns with the drag, as if held: dragging right swings the
  // camera round to the west, dragging down lifts it to look more from
  // above
  FAzimuth := FDragAzimuth - (X - FDragStart.X) * DRAG_AZIMUTH;
  FElevation := EnsureRange(FDragElevation + (Y - FDragStart.Y) * DRAG_ELEVATION,
    MIN_ELEVATION, MAX_ELEVATION);
  PlaceCamera;
end;

procedure TTerrainView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FDragging := False;
  FPanning := False;
end;

procedure TTerrainView.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  inherited;
  FDistance := EnsureRange(FDistance * Power(WHEEL_ZOOM, WheelDelta / 120),
    MIN_DISTANCE, MAX_DISTANCE);
  PlaceCamera;
  Handled := True;
end;

procedure TTerrainView.DblClick;
begin
  inherited;
  ResetView;
end;

end.
