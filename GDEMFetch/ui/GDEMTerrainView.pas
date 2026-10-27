{ @abstract(The 3D view of a tile: a Gorilla3D viewport showing a
  @code(TTerrainGrid) as a surface, which the mouse turns and zooms.)

  @link(TTerrainView) is a layout that fills the 3D tab. It holds:

  @preformatted(
TTerrainView                  takes the mouse
`-- TGorillaViewport          HitTest off, so the mouse reaches the layout
    |-- centre (TDummy)       what the camera looks at: the tile's middle
    |-- terrain (TDummy)      holds the mesh pieces
    |   `-- TGorillaSingletonMesh, one per piece, each with its own
    |       TGorillaVertexColorMaterialSource
    `-- TGorillaCamera        Target is the centre
        `-- TGorillaLight     a point light where the camera is
  )

  The camera sits @link(TTerrainView.Distance) kilometres from the centre,
  at an @link(TTerrainView.Azimuth) round it (0 from the south, 90 from
  the east) and an @link(TTerrainView.Elevation) above the level (5 to 89
  degrees). FMX's @code(TCamera.Target) keeps it facing the centre, which
  starts in the middle of the tile and can be moved across it.
  Left-drag turns the view; right-drag, middle-drag or Shift + left-drag
  moves it, as on the map, the ground following the pointer; the wheel
  zooms; a double click puts the starting view back.

  The surface's colours are worked out in @code(GDEMTerrain), shaded for
  a sun in the north-west, so the vertex-colour material shows the relief
  whether or not it is lit. Each piece is built as Gorilla3D's guide to
  custom meshes shows: its @code(MeshData) filled, then a @code(TMeshDef)
  made static from it. }
unit GDEMTerrainView;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math.Vectors,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Types3D, FMX.Controls3D, FMX.Objects3D,
  Gorilla.Viewport, Gorilla.Camera, Gorilla.Light,
  GDEMTerrain;

type
  { @abstract(A Gorilla3D view of one tile's surface.) }
  TTerrainView = class(TLayout)
  private
    { The Gorilla3D viewport, filling the layout. }
    FViewport: TGorillaViewport;
    { The camera. }
    FCamera: TGorillaCamera;
    { The point the camera looks at, in the middle of the tile. }
    FCentre: TDummy;
    { The light, riding on the camera. }
    FLight: TGorillaLight;
    { Holds the mesh pieces, so they can be freed together. }
    FTerrain: TDummy;
    { The tile shown. }
    FGrid: TTerrainGrid;
    { @true while a tile is shown. }
    FHasGrid: Boolean;
    { Backing field for @link(Exaggeration). }
    FExaggeration: Single;
    { Backing field for @link(Azimuth). }
    FAzimuth: Single;
    { Backing field for @link(Elevation). }
    FElevation: Single;
    { Backing field for @link(Distance). }
    FDistance: Single;
    { @true while the left button is held down on the view, turning it. }
    FDragging: Boolean;
    { @true while a button is held down on the view, moving it. }
    FPanning: Boolean;
    { How far the centre has been moved east of the tile's middle, in
      kilometres. }
    FPanX: Single;
    { How far the centre has been moved north of the tile's middle, in
      kilometres. }
    FPanZ: Single;
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
    { Backing field for @link(VertexCount). }
    FVertexCount: Integer;
    { Backing field for @link(TriangleCount). }
    FTriangleCount: Integer;
    { Backing field for @link(PieceCount). }
    FPieceCount: Integer;

    { The largest of the tile's sizes, west to east or north to south.
      @returns(Kilometres; 100 with no tile.) }
    function Extent: Single;

    { Moves the camera to @link(Distance), @link(Azimuth) and
      @link(Elevation) from the centre, and the centre to the middle
      height of the tile. }
    procedure PlaceCamera;

    { Frees the mesh pieces. }
    procedure ClearMesh;

    { Makes the mesh pieces for @link(FGrid) at @link(Exaggeration).
      @raises(ETerrainError if Gorilla3D gives a mesh no data to fill.) }
    procedure BuildMesh;

    { Writer for @link(Exaggeration): rebuilds the surface, keeping the
      view.
      @param(AValue Times to stretch heights; at least 0.1.) }
    procedure SetExaggeration(AValue: Single);
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
    { Makes the viewport, camera and light; nothing is shown yet.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Shows a tile.
      @param(AGrid The tile's heights.)
      @param(AExaggeration Times to stretch heights.)
      @param(AResetView @true to start from the starting view, as for a new
        tile; @false to keep the camera where it is.)
      @raises(ETerrainError if the surface cannot be made.) }
    procedure ShowTerrain(const AGrid: TTerrainGrid; AExaggeration: Single;
      AResetView: Boolean);

    { Removes the tile shown, leaving an empty view. }
    procedure Clear;

    { The starting view: from the south, 35 degrees up, far enough back
      to see the whole tile, centred on its middle. }
    procedure ResetView;

    { Times to stretch heights; 1 is true scale. Setting it rebuilds the
      surface. }
    property Exaggeration: Single read FExaggeration write SetExaggeration;

    { The camera's direction from the centre, in degrees: 0 from the
      south, 90 from the east. }
    property Azimuth: Single read FAzimuth;

    { The camera's height above the level, in degrees, 5 to 89. }
    property Elevation: Single read FElevation;

    { The camera's distance from the centre, in kilometres. }
    property Distance: Single read FDistance;

    { @true while a tile is shown. }
    property HasTerrain: Boolean read FHasGrid;

    { The tile shown, if @link(HasTerrain). }
    property Grid: TTerrainGrid read FGrid;

    { Vertices in the surface shown. }
    property VertexCount: Integer read FVertexCount;

    { Triangles in the surface shown. }
    property TriangleCount: Integer read FTriangleCount;

    { Pieces the surface shown is made of. }
    property PieceCount: Integer read FPieceCount;
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
  { The starting elevation, in degrees. }
  START_ELEVATION = 35;
  { The starting distance, as a share of the tile's larger side. }
  START_DISTANCE = 1.25;
  { The lowest and highest elevations the mouse can reach, in degrees. }
  MIN_ELEVATION = 5;
  { See @link(MIN_ELEVATION). }
  MAX_ELEVATION = 89;
  { The nearest the camera comes, in kilometres. }
  MIN_DISTANCE = 0.5;
  { The farthest the camera goes, as a share of the tile's larger side. }
  MAX_DISTANCE = 5;
  { Degrees turned for each pixel dragged across. }
  DRAG_AZIMUTH = 0.4;
  { Degrees tilted for each pixel dragged up or down. }
  DRAG_ELEVATION = 0.3;
  { Distance kept for each wheel notch rolled away. }
  WHEEL_ZOOM = 0.88;

{ TTerrainView }

constructor TTerrainView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // The layout takes the mouse; the viewport lets it through
  HitTest := True;
  FExaggeration := 1;

  FViewport := TGorillaViewport.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := TAlignLayout.Client;
  FViewport.HitTest := False;
  FViewport.UseFixedFrameRate := True;
  FViewport.FixedFrameRate := 60;
  FViewport.VSync := False;
  FViewport.Color := TERRAIN_BACKGROUND;
  FViewport.UsingDesignCamera := False;

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

  ResetView;
end;

function TTerrainView.Extent: Single;
begin
  if FHasGrid then
    Result := Max(FGrid.WidthKm, FGrid.DepthKm)
  else
    Result := 100;
end;

procedure TTerrainView.PlaceCamera;
var
  LMiddle: Single;
  LAzimuth, LElevation: Double;
begin
  // The middle height of the tile, so turning stays centred on it; up is -Y
  if FHasGrid then
    LMiddle := -(FGrid.MinHeight + FGrid.MaxHeight) / 2 * FExaggeration / 1000
  else
    LMiddle := 0;
  FCentre.Position.Point := Point3D(FPanX, LMiddle, FPanZ);
  LAzimuth := DegToRad(FAzimuth);
  LElevation := DegToRad(FElevation);
  // At azimuth 0 the camera is to the south (-Z) looking north
  FCamera.Position.Point := Point3D(
    FPanX + FDistance * Sin(LAzimuth) * Cos(LElevation),
    LMiddle - FDistance * Sin(LElevation),
    FPanZ - FDistance * Cos(LAzimuth) * Cos(LElevation));
end;

procedure TTerrainView.ResetView;
begin
  FAzimuth := 0;
  FElevation := START_ELEVATION;
  FPanX := 0;
  FPanZ := 0;
  FDistance := START_DISTANCE * Extent;
  PlaceCamera;
end;

procedure TTerrainView.ClearMesh;
begin
  // Each piece owns its material, so freeing the pieces frees everything
  FTerrain.DeleteChildren;
  FVertexCount := 0;
  FTriangleCount := 0;
  FPieceCount := 0;
end;

procedure TTerrainView.BuildMesh;
var
  LPiece, I: Integer;
  LChunk: TTerrainChunk;
  LMesh: TGorillaSingletonMesh;
  LData: TMeshData;
  LDef: TMeshDef;
  LMaterial: TGorillaVertexColorMaterialSource;
begin
  ClearMesh;
  for LPiece := 0 to TerrainChunkCount(FGrid) - 1 do
  begin
    LChunk := TerrainChunk(FGrid, LPiece, FExaggeration);
    if Length(LChunk.Indices) = 0 then
      Continue;
    LMesh := TGorillaSingletonMesh.Create(nil);
    LMesh.Parent := FTerrain;
    LData := LMesh.MeshData;
    if LData = nil then
      raise ETerrainError.Create('Gorilla3D gave the surface no mesh data to fill');

    LData.VertexBuffer.Length := Length(LChunk.Positions);
    for I := 0 to High(LChunk.Positions) do
    begin
      LData.VertexBuffer.Vertices[I] := LChunk.Positions[I];
      LData.VertexBuffer.Normals[I] := LChunk.Normals[I];
      LData.VertexBuffer.Color0[I] := LChunk.Colours[I];
    end;
    LData.IndexBuffer.Length := Length(LChunk.Indices);
    for I := 0 to High(LChunk.Indices) do
      LData.IndexBuffer.Indices[I] := LChunk.Indices[I];

    // Made static, the data goes to the GPU once and stays there
    LDef := TMeshDef.Create(nil);
    LMesh.Def := LDef;
    LDef.ApplyFromMeshData(LData);
    LDef.IsStatic := True;
    LData.Clear;

    LMaterial := TGorillaVertexColorMaterialSource.Create(LMesh);
    LMaterial.Parent := LMesh;
    LMesh.MaterialSource := LMaterial;

    Inc(FVertexCount, Length(LChunk.Positions));
    Inc(FTriangleCount, Length(LChunk.Indices) div 3);
    Inc(FPieceCount);
  end;
end;

procedure TTerrainView.ShowTerrain(const AGrid: TTerrainGrid; AExaggeration: Single;
  AResetView: Boolean);
begin
  FGrid := AGrid;
  FHasGrid := True;
  FExaggeration := Max(AExaggeration, 0.1);
  BuildMesh;
  if AResetView then
    ResetView
  else
    PlaceCamera;
end;

procedure TTerrainView.Clear;
begin
  ClearMesh;
  FHasGrid := False;
  FGrid := EmptyTerrainGrid;
end;

procedure TTerrainView.SetExaggeration(AValue: Single);
begin
  AValue := Max(AValue, 0.1);
  if SameValue(AValue, FExaggeration) then
    Exit;
  FExaggeration := AValue;
  if FHasGrid then
  begin
    BuildMesh;
    PlaceCamera;
  end;
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
  LScale, LAzimuth, LRightX, LRightZ, LAheadX, LAheadZ, LDX, LDY, LLimitX, LLimitZ: Double;
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
    // No further than half a tile beyond its edges
    if FHasGrid then
    begin
      LLimitX := FGrid.WidthKm;
      LLimitZ := FGrid.DepthKm;
    end
    else
    begin
      LLimitX := Extent;
      LLimitZ := Extent;
    end;
    FPanX := EnsureRange(FPanX, -LLimitX, LLimitX);
    FPanZ := EnsureRange(FPanZ, -LLimitZ, LLimitZ);
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
    MIN_DISTANCE, MAX_DISTANCE * Extent);
  PlaceCamera;
  Handled := True;
end;

procedure TTerrainView.DblClick;
begin
  inherited;
  ResetView;
end;

end.
