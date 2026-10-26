{ @abstract(A zoomable world map for choosing ASTER GDEM tiles.)

  @link(TWorldMapView) shows an equirectangular world image: longitude
  -180 at the left edge, +180 at the right, latitude +90 at the top and -90
  at the bottom. Any image with a 2:1 shape works; the number of pixels per
  degree is worked out from its size, so a larger map can replace the
  1080 by 540 one without code changes.

  Mouse controls:
  @unorderedList(
    @item(Left-drag selects a block of tiles. The selection snaps to whole
      degrees as you drag. A left click selects a single tile.)
    @item(Right-drag, middle-drag or Shift+left-drag moves the map.)
    @item(The mouse wheel zooms in and out around the pointer.)
  )

  A grid is drawn over the map. Its spacing adapts to the zoom level, down
  to individual 1 degree tiles. Areas outside ASTER GDEM coverage (beyond
  83 degrees north and south) are shaded.

  When a @link(TTileIndex) is assigned to @link(TWorldMapView.TileIndex),
  tiles that have data are tinted. The index is drawn as a 360 by 180
  bitmap, one pixel per tile, stretched over the map without smoothing, so
  tiles stay crisp squares at every zoom level and drawing costs the same
  however many tiles exist.

  The control is created in code, so no design-time package is needed. }
unit GDEMWorldMap;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics,
  GDEMTiles, GDEMTileIndex;

type
  { Reports the position under the mouse pointer.
    @param(Sender The map view.)
    @param(ALat Latitude under the pointer, in degrees.)
    @param(ALon Longitude under the pointer, in degrees.)
    @param(AOnMap @false when the pointer is outside the map image, in which
      case ALat and ALon should be ignored.) }
  TMapHoverEvent = procedure(Sender: TObject; ALat, ALon: Double; AOnMap: Boolean) of object;

  { What a mouse drag is currently doing. }
  TMapDragMode = (
    { No drag in progress. }
    mdNone,
    { Drawing a selection. }
    mdSelect,
    { Moving the map. }
    mdPan
  );

  { @abstract(Zoomable world map with tile selection.) }
  TWorldMapView = class(TControl)
  private
    { The map image, owned by this control. @nil until one is loaded. }
    FMap: TBitmap;
    { Screen pixels per map image pixel. }
    FScale: Single;
    { Screen position, in local coordinates, of the map image's top-left
      corner. }
    FOrigin: TPointF;
    { @true until the user zooms or pans, so that resizing keeps the whole
      map in view. }
    FAutoFit: Boolean;
    { The selected tiles. Empty when nothing is selected. }
    FSelection: TTileRect;
    { What the current mouse drag is doing. }
    FDragMode: TMapDragMode;
    { Mouse position where a pan started. }
    FDragStart: TPointF;
    { @link(FOrigin) when a pan started. }
    FDragOrigin: TPointF;
    { Latitude where a selection drag started. }
    FAnchorLat: Double;
    { Longitude where a selection drag started. }
    FAnchorLon: Double;
    { Last mouse position over the control, used as the wheel zoom
      centre. }
    FMousePos: TPointF;
    { @true while the pointer is over the control. }
    FMouseInside: Boolean;
    { Backing field for @link(OnSelectionChanged). }
    FOnSelectionChanged: TNotifyEvent;
    { Backing field for @link(OnHover). }
    FOnHover: TMapHoverEvent;
    { Backing field for @link(TileIndex). Not owned. }
    FTileIndex: TTileIndex;
    { One pixel per tile: tinted where @link(FTileIndex) has data,
      transparent elsewhere. @nil when there is no index to show. }
    FTileOverlay: TBitmap;
    { Backing field for @link(ShowAvailableTiles). }
    FShowAvailableTiles: Boolean;

    { Writer for @link(TileIndex).
      @param(AValue The new index, or @nil.) }
    procedure SetTileIndex(AValue: TTileIndex);

    { Writer for @link(ShowAvailableTiles).
      @param(AValue @true to tint tiles that have data.) }
    procedure SetShowAvailableTiles(AValue: Boolean);

    { Redraws @link(FTileOverlay) from @link(FTileIndex). }
    procedure RebuildTileOverlay;

    { Width of the map image in pixels, or 0 when none is loaded.
      @returns(The width.) }
    function MapWidth: Single;

    { Height of the map image in pixels, or 0 when none is loaded.
      @returns(The height.) }
    function MapHeight: Single;

    { Smallest allowed scale: the whole map fits in the control.
      @returns(Screen pixels per map pixel.) }
    function MinScale: Single;

    { Largest allowed scale: one degree is about 400 screen pixels.
      @returns(Screen pixels per map pixel.) }
    function MaxScale: Single;

    { How many screen pixels one degree of longitude currently takes.
      @returns(Pixels per degree.) }
    function ScreenPixelsPerDegree: Single;

    { Keeps the map on screen: centres it on any axis where it is smaller
      than the control, otherwise stops its edges moving inside the
      control. }
    procedure ClampOrigin;

    { Sets the scale, keeping the map point under AScreenPoint fixed.
      @param(AScale The new scale, clamped to @link(MinScale) and
        @link(MaxScale).)
      @param(AScreenPoint Point in local coordinates to zoom around.) }
    procedure SetScaleAt(AScale: Single; const AScreenPoint: TPointF);

    { Draws the latitude and longitude grid over the visible area.
      @param(AVisible The visible area in degrees: Left is west, Right is
        east, Top is north and Bottom is south.) }
    procedure PaintGrid(const AVisible: TRectF);

    { Draws a filled and outlined block of tiles.
      @param(ATiles The tiles to draw.)
      @param(AColor Fill and outline colour.)
      @param(AFillOpacity Opacity of the fill, from 0 to 1.) }
    procedure PaintTileRect(const ATiles: TTileRect; AColor: TAlphaColor; AFillOpacity: Single);

    { Converts a local point to a map position, clamped to the map's
      edges.
      @param(APoint Point in local coordinates.)
      @param(ALat Receives the latitude.)
      @param(ALon Receives the longitude.) }
    procedure ScreenToGeoClamped(const APoint: TPointF; out ALat, ALon: Double);

    { Fires @link(OnHover) for a local point.
      @param(APoint Point in local coordinates.) }
    procedure DoHover(const APoint: TPointF);
  protected
    { Draws the map, shading, grid and selection. }
    procedure Paint; override;

    { Keeps the map fitted or on screen when the control changes size. }
    procedure Resize; override;

    { Starts a selection or a pan.
      @param(Button Which mouse button was pressed.)
      @param(Shift Modifier keys held.)
      @param(X Horizontal position in local coordinates.)
      @param(Y Vertical position in local coordinates.) }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Updates the hover position and any selection or pan in progress.
      @param(Shift Modifier keys held.)
      @param(X Horizontal position in local coordinates.)
      @param(Y Vertical position in local coordinates.) }
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;

    { Finishes a selection or a pan.
      @param(Button Which mouse button was released.)
      @param(Shift Modifier keys held.)
      @param(X Horizontal position in local coordinates.)
      @param(Y Vertical position in local coordinates.) }
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Zooms around the pointer.
      @param(Shift Modifier keys held.)
      @param(WheelDelta Wheel movement; 120 is one notch on most mice.)
      @param(Handled Set to @true.) }
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;

    { Clears the hover state when the pointer leaves. }
    procedure DoMouseLeave; override;
  public
    { Creates an empty map view.
      @param(AOwner Owner of the control.) }
    constructor Create(AOwner: TComponent); override;

    { Frees the map image. }
    destructor Destroy; override;

    { Loads the map image from a stream in any format FMX can decode, such
      as JPEG or PNG, and zooms to show all of it.
      @param(AStream Stream positioned at the start of the image.) }
    procedure LoadMapFromStream(AStream: TStream);

    { Loads the map image from a file and zooms to show all of it.
      @param(AFileName Path of the image.) }
    procedure LoadMapFromFile(const AFileName: string);

    { Converts a local point to a map position.
      @param(APoint Point in local coordinates.)
      @param(ALat Receives the latitude.)
      @param(ALon Receives the longitude.)
      @returns(@true if the point is over the map image.) }
    function ScreenToGeo(const APoint: TPointF; out ALat, ALon: Double): Boolean;

    { Converts a map position to a local point.
      @param(ALat Latitude in degrees.)
      @param(ALon Longitude in degrees.)
      @returns(The point in local coordinates.) }
    function GeoToScreen(ALat, ALon: Double): TPointF;

    { Zooms out to show the whole map. }
    procedure ZoomToFit;

    { Zooms in or out around the centre of the control.
      @param(AFactor Greater than 1 zooms in, less than 1 zooms out.) }
    procedure ZoomBy(AFactor: Single);

    { Zooms and pans so the current selection fills most of the control.
      Does nothing when there is no selection. }
    procedure ZoomToSelection;

    { Clears the selection and fires @link(OnSelectionChanged). }
    procedure ClearSelection;

    { Call after changing the contents of @link(TileIndex) in place, so the
      map shows the change. Not needed after assigning a new index. }
    procedure TileIndexChanged;

    { Which tiles have data, used to tint them on the map. Not owned: the
      caller frees it, after setting this property to @nil or freeing the
      map view. @nil shows no tint. }
    property TileIndex: TTileIndex read FTileIndex write SetTileIndex;

    { Whether tiles that have data are tinted. On by default; has no
      effect until @link(TileIndex) is set. }
    property ShowAvailableTiles: Boolean read FShowAvailableTiles write SetShowAvailableTiles;

    { The selected block of tiles. Changed by dragging on the map or by
      @link(ClearSelection). Empty when nothing is selected. }
    property Selection: TTileRect read FSelection;

    { Fired when a selection drag finishes or the selection is cleared. }
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;

    { Fired as the pointer moves over the control. }
    property OnHover: TMapHoverEvent read FOnHover write FOnHover;
  end;

implementation

uses
  System.Math;

const
  { Colour drawn behind the map, visible when it is smaller than the
    control. }
  MAP_BACKGROUND = $FF101820;
  { Colour of the selection. }
  SELECTION_COLOR = $FFFFC107;
  { Colour of the outline around the tile under the pointer. }
  HOVER_COLOR = $FFFFFFFF;
  { Colour of grid lines. }
  GRID_COLOR = $FFFFFFFF;
  { Tint for tiles that have data. }
  AVAILABLE_COLOR = $FF00E5FF;
  { Opacity of the tint for tiles that have data. }
  AVAILABLE_OPACITY = 0.35;
  { Zoom step for one mouse wheel notch. }
  WHEEL_ZOOM_STEP = 1.25;
  { Approximate largest size of one degree on screen, in pixels. }
  MAX_PIXELS_PER_DEGREE = 400;
  { Smallest screen spacing between grid lines, in pixels. }
  MIN_GRID_SPACING = 12;
  { Smallest size of a degree on screen before the tile under the pointer
    is outlined, in pixels. }
  MIN_HOVER_TILE_SIZE = 6;

{ TWorldMapView }

constructor TWorldMapView.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  AutoCapture := True;
  ClipChildren := True;
  FScale := 1;
  FAutoFit := True;
  FSelection := TTileRect.Empty;
  FShowAvailableTiles := True;
end;

destructor TWorldMapView.Destroy;
begin
  FTileOverlay.Free;
  FMap.Free;
  inherited;
end;

procedure TWorldMapView.SetTileIndex(AValue: TTileIndex);
begin
  FTileIndex := AValue;
  RebuildTileOverlay;
end;

procedure TWorldMapView.SetShowAvailableTiles(AValue: Boolean);
begin
  if FShowAvailableTiles <> AValue then
  begin
    FShowAvailableTiles := AValue;
    Repaint;
  end;
end;

procedure TWorldMapView.TileIndexChanged;
begin
  RebuildTileOverlay;
end;

procedure TWorldMapView.RebuildTileOverlay;
var
  LData: TBitmapData;
  LRow, LCol: Integer;
begin
  FreeAndNil(FTileOverlay);
  if (FTileIndex <> nil) and not FTileIndex.IsEmpty then
  begin
    FTileOverlay := TBitmap.Create(TILE_INDEX_WIDTH, TILE_INDEX_HEIGHT);
    if FTileOverlay.Map(TMapAccess.Write, LData) then
    try
      // Row 0 is the northernmost row of tiles, whose southern edge is 89
      for LRow := 0 to TILE_INDEX_HEIGHT - 1 do
        for LCol := 0 to TILE_INDEX_WIDTH - 1 do
          if FTileIndex.Has(89 - LRow, LCol - 180) then
            LData.SetPixel(LCol, LRow, AVAILABLE_COLOR)
          else
            LData.SetPixel(LCol, LRow, TAlphaColors.Null);
    finally
      FTileOverlay.Unmap(LData);
    end;
  end;
  Repaint;
end;

procedure TWorldMapView.LoadMapFromStream(AStream: TStream);
begin
  if FMap = nil then
    FMap := TBitmap.Create;
  FMap.LoadFromStream(AStream);
  ZoomToFit;
end;

procedure TWorldMapView.LoadMapFromFile(const AFileName: string);
begin
  if FMap = nil then
    FMap := TBitmap.Create;
  FMap.LoadFromFile(AFileName);
  ZoomToFit;
end;

function TWorldMapView.MapWidth: Single;
begin
  if FMap = nil then
    Result := 0
  else
    Result := FMap.Width;
end;

function TWorldMapView.MapHeight: Single;
begin
  if FMap = nil then
    Result := 0
  else
    Result := FMap.Height;
end;

function TWorldMapView.MinScale: Single;
begin
  if (MapWidth = 0) or (MapHeight = 0) or (Width <= 0) or (Height <= 0) then
    Exit(1);
  Result := Min(Width / MapWidth, Height / MapHeight);
end;

function TWorldMapView.MaxScale: Single;
begin
  if MapWidth = 0 then
    Exit(1);
  Result := Max(MinScale, MAX_PIXELS_PER_DEGREE / (MapWidth / 360));
end;

function TWorldMapView.ScreenPixelsPerDegree: Single;
begin
  Result := FScale * MapWidth / 360;
end;

procedure TWorldMapView.ClampOrigin;
var
  LContentWidth, LContentHeight: Single;
begin
  LContentWidth := MapWidth * FScale;
  LContentHeight := MapHeight * FScale;

  if LContentWidth <= Width then
    FOrigin.X := (Width - LContentWidth) / 2
  else
    FOrigin.X := EnsureRange(FOrigin.X, Width - LContentWidth, 0);

  if LContentHeight <= Height then
    FOrigin.Y := (Height - LContentHeight) / 2
  else
    FOrigin.Y := EnsureRange(FOrigin.Y, Height - LContentHeight, 0);
end;

procedure TWorldMapView.SetScaleAt(AScale: Single; const AScreenPoint: TPointF);
var
  LMapPoint: TPointF;
begin
  if FMap = nil then
    Exit;
  // Map pixel under the point before zooming
  LMapPoint := (AScreenPoint - FOrigin) / FScale;
  FScale := EnsureRange(AScale, MinScale, MaxScale);
  // Move the origin so the same map pixel stays under the point
  FOrigin := AScreenPoint - LMapPoint * FScale;
  ClampOrigin;
  Repaint;
end;

procedure TWorldMapView.ZoomToFit;
begin
  FAutoFit := True;
  FScale := MinScale;
  ClampOrigin;
  Repaint;
end;

procedure TWorldMapView.ZoomBy(AFactor: Single);
begin
  FAutoFit := False;
  SetScaleAt(FScale * AFactor, PointF(Width / 2, Height / 2));
end;

procedure TWorldMapView.ZoomToSelection;
var
  LTopLeft, LBottomRight, LCentre: TPointF;
  LFactor: Single;
begin
  if (FMap = nil) or FSelection.IsEmpty then
    Exit;
  FAutoFit := False;
  LTopLeft := GeoToScreen(FSelection.North, FSelection.West);
  LBottomRight := GeoToScreen(FSelection.South, FSelection.East);
  // Leave a margin of a fifth of the control around the selection
  LFactor := 0.8 * Min(Width / Max(1, LBottomRight.X - LTopLeft.X),
                       Height / Max(1, LBottomRight.Y - LTopLeft.Y));
  LCentre := (LTopLeft + LBottomRight) / 2;
  SetScaleAt(FScale * LFactor, LCentre);
  // SetScaleAt kept the selection centre fixed; now move it to the middle
  LCentre := (GeoToScreen(FSelection.North, FSelection.West) +
              GeoToScreen(FSelection.South, FSelection.East)) / 2;
  FOrigin := FOrigin + (PointF(Width / 2, Height / 2) - LCentre);
  ClampOrigin;
  Repaint;
end;

procedure TWorldMapView.ClearSelection;
begin
  FSelection := TTileRect.Empty;
  Repaint;
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

procedure TWorldMapView.Resize;
begin
  inherited;
  if FAutoFit then
    FScale := MinScale
  else
    FScale := EnsureRange(FScale, MinScale, MaxScale);
  ClampOrigin;
end;

function TWorldMapView.GeoToScreen(ALat, ALon: Double): TPointF;
begin
  Result.X := FOrigin.X + (ALon + 180) * MapWidth / 360 * FScale;
  Result.Y := FOrigin.Y + (90 - ALat) * MapHeight / 180 * FScale;
end;

function TWorldMapView.ScreenToGeo(const APoint: TPointF; out ALat, ALon: Double): Boolean;
begin
  if (FMap = nil) or (FScale <= 0) then
  begin
    ALat := 0;
    ALon := 0;
    Exit(False);
  end;
  ALon := (APoint.X - FOrigin.X) / FScale * 360 / MapWidth - 180;
  ALat := 90 - (APoint.Y - FOrigin.Y) / FScale * 180 / MapHeight;
  Result := InRange(ALon, -180, 180) and InRange(ALat, -90, 90);
end;

procedure TWorldMapView.ScreenToGeoClamped(const APoint: TPointF; out ALat, ALon: Double);
begin
  ScreenToGeo(APoint, ALat, ALon);
  // Stay just inside the edges so Floor never yields 180 or 90
  ALon := EnsureRange(ALon, -180, 179.999999);
  ALat := EnsureRange(ALat, -89.999999, 89.999999);
end;

procedure TWorldMapView.DoHover(const APoint: TPointF);
var
  LLat, LLon: Double;
  LOnMap: Boolean;
begin
  if not Assigned(FOnHover) then
    Exit;
  LOnMap := ScreenToGeo(APoint, LLat, LLon);
  FOnHover(Self, LLat, LLon, LOnMap);
end;

procedure TWorldMapView.PaintGrid(const AVisible: TRectF);
const
  STEPS: array[0..4] of Integer = (1, 5, 10, 30, 90);
var
  LStep, LIndex, LDegree: Integer;
  LPixels: Single;
  LFrom, LTo: TPointF;

  { Sets the pen for one grid line and returns its opacity. The equator
    and prime meridian are drawn thicker and brighter.
    @param(ADegree The line's latitude or longitude.)
    @returns(Opacity for @code(DrawLine).) }
  function LineStyle(ADegree: Integer): Single;
  begin
    if ADegree = 0 then
    begin
      Canvas.Stroke.Thickness := 1.5;
      Result := 0.6;
    end
    else
    begin
      Canvas.Stroke.Thickness := 1;
      Result := 0.25;
    end;
  end;

begin
  // Pick the finest grid whose lines are at least MIN_GRID_SPACING apart
  LPixels := ScreenPixelsPerDegree;
  LStep := STEPS[High(STEPS)];
  for LIndex := Low(STEPS) to High(STEPS) do
    if STEPS[LIndex] * LPixels >= MIN_GRID_SPACING then
    begin
      LStep := STEPS[LIndex];
      Break;
    end;

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := GRID_COLOR;

  // Meridians
  LDegree := Ceil(AVisible.Left / LStep) * LStep;
  while LDegree <= AVisible.Right do
  begin
    LFrom := GeoToScreen(Min(90, AVisible.Top), LDegree);
    LTo := GeoToScreen(Max(-90, AVisible.Bottom), LDegree);
    Canvas.DrawLine(LFrom, LTo, LineStyle(LDegree));
    Inc(LDegree, LStep);
  end;

  // Parallels
  LDegree := Ceil(AVisible.Bottom / LStep) * LStep;
  while LDegree <= AVisible.Top do
  begin
    LFrom := GeoToScreen(LDegree, Max(-180, AVisible.Left));
    LTo := GeoToScreen(LDegree, Min(180, AVisible.Right));
    Canvas.DrawLine(LFrom, LTo, LineStyle(LDegree));
    Inc(LDegree, LStep);
  end;
end;

procedure TWorldMapView.PaintTileRect(const ATiles: TTileRect; AColor: TAlphaColor;
  AFillOpacity: Single);
var
  LRect: TRectF;
begin
  if ATiles.IsEmpty then
    Exit;
  LRect := TRectF.Create(GeoToScreen(ATiles.North, ATiles.West),
                         GeoToScreen(ATiles.South, ATiles.East));
  if AFillOpacity > 0 then
  begin
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := AColor;
    Canvas.FillRect(LRect, 0, 0, AllCorners, AFillOpacity);
  end;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := AColor;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawRect(LRect, 0, 0, AllCorners, 1);
end;

procedure TWorldMapView.Paint;
var
  LClient, LSource, LDest: TRectF;
  LNorth, LWest, LSouth, LEast, LLat, LLon: Double;
  LShade: TRectF;
begin
  LClient := LocalRect;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := MAP_BACKGROUND;
  Canvas.FillRect(LClient, 0, 0, AllCorners, 1);

  if FMap = nil then
    Exit;

  // Draw only the part of the image that is on screen
  LSource := TRectF.Create((LClient.TopLeft - FOrigin) / FScale,
                           (LClient.BottomRight - FOrigin) / FScale);
  LSource.Intersect(TRectF.Create(0, 0, MapWidth, MapHeight));
  if LSource.IsEmpty then
    Exit;
  LDest := TRectF.Create(FOrigin + LSource.TopLeft * FScale,
                         FOrigin + LSource.BottomRight * FScale);
  Canvas.DrawBitmap(FMap, LSource, LDest, 1, False);

  // Visible area in degrees
  ScreenToGeoClamped(LDest.TopLeft, LNorth, LWest);
  ScreenToGeoClamped(LDest.BottomRight, LSouth, LEast);

  // Tint tiles that have data; overlay pixels are whole degrees
  if FShowAvailableTiles and (FTileOverlay <> nil) then
    Canvas.DrawBitmap(FTileOverlay,
      TRectF.Create(LWest + 180, 90 - LNorth, LEast + 180, 90 - LSouth),
      TRectF.Create(GeoToScreen(LNorth, LWest), GeoToScreen(LSouth, LEast)),
      AVAILABLE_OPACITY, True);

  // Shade the areas ASTER GDEM does not cover
  Canvas.Fill.Color := TAlphaColors.Black;
  if LNorth > GDEM_MAX_LAT then
  begin
    LShade := TRectF.Create(LDest.Left, LDest.Top, LDest.Right,
      GeoToScreen(GDEM_MAX_LAT, 0).Y);
    Canvas.FillRect(LShade, 0, 0, AllCorners, 0.45);
  end;
  if LSouth < GDEM_MIN_LAT then
  begin
    LShade := TRectF.Create(LDest.Left, GeoToScreen(GDEM_MIN_LAT, 0).Y,
      LDest.Right, LDest.Bottom);
    Canvas.FillRect(LShade, 0, 0, AllCorners, 0.45);
  end;

  PaintGrid(TRectF.Create(LWest, LNorth, LEast, LSouth));

  // Outline the tile under the pointer once tiles are big enough to see
  if FMouseInside and (FDragMode = mdNone) and
     (ScreenPixelsPerDegree >= MIN_HOVER_TILE_SIZE) and
     ScreenToGeo(FMousePos, LLat, LLon) and
     InRange(LLat, GDEM_MIN_LAT, GDEM_MAX_LAT) then
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := HOVER_COLOR;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawRect(TRectF.Create(GeoToScreen(Floor(LLat) + 1, Floor(LLon)),
      GeoToScreen(Floor(LLat), Floor(LLon) + 1)), 0, 0, AllCorners, 0.8);
  end;

  PaintTileRect(FSelection, SELECTION_COLOR, 0.25);
end;

procedure TWorldMapView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if FMap = nil then
    Exit;
  FMousePos := PointF(X, Y);
  if (Button = TMouseButton.mbLeft) and not (ssShift in Shift) then
  begin
    FDragMode := mdSelect;
    ScreenToGeoClamped(FMousePos, FAnchorLat, FAnchorLon);
    FSelection := TTileRect.FromPoints(FAnchorLon, FAnchorLat, FAnchorLon, FAnchorLat);
  end
  else
  begin
    FDragMode := mdPan;
    FDragStart := FMousePos;
    FDragOrigin := FOrigin;
  end;
  Repaint;
end;

procedure TWorldMapView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  LLat, LLon: Double;
begin
  inherited;
  FMousePos := PointF(X, Y);
  FMouseInside := True;
  case FDragMode of
    mdSelect:
      begin
        ScreenToGeoClamped(FMousePos, LLat, LLon);
        FSelection := TTileRect.FromPoints(FAnchorLon, FAnchorLat, LLon, LLat);
      end;
    mdPan:
      begin
        FAutoFit := False;
        FOrigin := FDragOrigin + (FMousePos - FDragStart);
        ClampOrigin;
      end;
  end;
  DoHover(FMousePos);
  Repaint;
end;

procedure TWorldMapView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  LWasSelecting: Boolean;
begin
  inherited;
  LWasSelecting := FDragMode = mdSelect;
  FDragMode := mdNone;
  Repaint;
  if LWasSelecting and Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

procedure TWorldMapView.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  inherited;
  if FMap = nil then
    Exit;
  FAutoFit := False;
  SetScaleAt(FScale * Power(WHEEL_ZOOM_STEP, WheelDelta / 120), FMousePos);
  DoHover(FMousePos);
  Handled := True;
end;

procedure TWorldMapView.DoMouseLeave;
begin
  inherited;
  FMouseInside := False;
  Repaint;
end;

end.
