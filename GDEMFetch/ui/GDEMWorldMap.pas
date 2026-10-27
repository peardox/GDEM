{ @abstract(A zoomable world map for choosing ASTER GDEM tiles.)

  @link(TWorldMapView) shows an equirectangular world image: longitude
  -180 at the left edge, +180 at the right, latitude +90 at the top and -90
  at the bottom. Any image with a 2:1 shape works; the number of pixels per
  degree is worked out from its size, so a larger map can replace the
  1080 by 540 one without code changes.

  The map wraps east to west, as the world does: panning past 180 degrees
  shows the other side, the image is drawn as many times as needed to fill
  the control, and a selection can be dragged across the 180 degree
  meridian (see @link(TTileRect)). It does not wrap north to south, because
  past a pole the world does not continue on the other side; the map stops
  at the poles, and selections stop at the edge of ASTER GDEM coverage.

  Mouse controls:
  @unorderedList(
    @item(Left-drag selects a block of tiles. The selection snaps to whole
      degrees as you drag. A left click selects a single tile. While
      dragging, moving the pointer near or past an edge of the control
      scrolls the map that way, faster the further out the pointer is, and
      the mouse wheel still zooms, so a selection can reach beyond what is
      on screen.)
    @item(Right-drag, middle-drag or Shift+left-drag moves the map.)
    @item(A right click, without moving, fires
      @link(TWorldMapView.OnRightClick), with the modifier keys held;
      GDEMFetch uses it to select the country under the pointer, or with
      Shift to add it to the selection.)
    @item(The mouse wheel zooms in and out around the pointer.)
  )

  A grid is drawn over the map. Its spacing adapts to the zoom level, down
  to individual 1 degree tiles. Areas outside ASTER GDEM coverage (beyond
  83 degrees north and south) are shaded.

  Two @link(TTileIndex) bitmaps can be shown over the map: tiles that have
  data (@link(TWorldMapView.TileIndex), tinted cyan) and tiles already
  downloaded (@link(TWorldMapView.DownloadedIndex), tinted green). Both are
  combined into one 360 by 180 bitmap, one pixel per tile, stretched over
  the map without smoothing, so tiles stay crisp squares at every zoom level
  and drawing costs the same however many tiles exist.

  Country borders and coastlines from a @link(TWorldVectors) can be drawn
  over the map (@link(TWorldMapView.Vectors)): the 1:110m data while much of
  the world is in view, the more detailed 1:50m data once a degree is at
  least @code(FINE_DETAIL_PIXELS_PER_DEGREE) pixels across.

  When FMX draws with Skia (@code(GlobalUseSkia), and the project's
  @code(SKIA) define), each layer is turned into Skia paths once, in
  degrees, one for each @code(LINE_PIECE_DEGREES) square of the world that
  its lines pass through (see @link(TLinePiece)). Every frame draws only the
  pieces on screen, with a matrix that moves and scales them into place
  (@link(TWorldMapView.UseSkiaPaths)). Otherwise, as before, each frame
  builds a path of only the lines on screen, skipping points closer
  together than a pixel. The 1:50m coastline alone is about 60,000 points,
  and drawing all of it every frame, even from a cached path, was slower
  when zoomed in than building just the visible part.

  @link(TWorldMapView.OnPaintStats) reports how long frames take to draw
  while the map is dragged, panned or zoomed, for comparing ways of
  drawing.

  The control is created in code, so no design-time package is needed. }
unit GDEMWorldMap;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Generics.Collections,
  {$IFDEF SKIA}
  System.Skia,
  {$ENDIF}
  FMX.Types, FMX.Controls, FMX.Graphics,
  GDEMTiles, GDEMTileIndex, GDEMVectors;

type
  { Reports the position under the mouse pointer.
    @param(Sender The map view.)
    @param(ALat Latitude under the pointer, in degrees.)
    @param(ALon Longitude under the pointer, in degrees.)
    @param(AOnMap @false when the pointer is outside the map image, in which
      case ALat and ALon should be ignored.) }
  TMapHoverEvent = procedure(Sender: TObject; ALat, ALon: Double; AOnMap: Boolean) of object;

  { Reports a point clicked on the map.
    @param(Sender The map view.)
    @param(ALat Latitude clicked, in degrees.)
    @param(ALon Longitude clicked, from -180 to 180.)
    @param(AShift The modifier keys held when the button was released.) }
  TMapPointEvent = procedure(Sender: TObject; ALat, ALon: Double; AShift: TShiftState) of object;

  { @abstract(How long the map took to draw during one stretch of
    movement.)

    A stretch starts when a drag or pan starts, or with a wheel zoom, and
    ends when the button is released, or a second after the last wheel
    zoom. Only frames drawn during it are counted, so frames drawn just to
    move the outline of the tile under the pointer are not.

    The times are what the program spent in @code(Paint). When Skia draws
    on the CPU (@code(TSkRasterCanvas)) that includes the drawing itself;
    on a GPU canvas much of the work happens later, on the graphics card,
    so compare @link(Seconds) and @link(Frames) (the frame rate) as
    well. }
  TMapPaintStats = record
    { Frames drawn. }
    Frames: Integer;
    { Time from the start of the first frame to the end of the last, in
      seconds. }
    Seconds: Double;
    { Average time to draw a frame, in milliseconds. }
    AverageMs: Double;
    { Longest time to draw a frame, in milliseconds. }
    WorstMs: Double;
    { Average time per frame spent on borders and coastlines, in
      milliseconds; part of @link(AverageMs). }
    LinesMs: Double;
    { @true if borders and coastlines were drawn from cached Skia paths in
      every frame, @false if they were built afresh in any of them. }
    SkiaLines: Boolean;
    { Class name of the canvas drawn on, which says how FMX draws:
      @code(TSkRasterCanvas) is Skia on the CPU; other @code(TSk...) or
      @code(TGl...), @code(TMtl...) and Vulkan canvases are Skia on the
      GPU; anything else is FMX's own canvas, without Skia. }
    CanvasName: string;
  end;

  { Reports how long the map took to draw.
    @param(Sender The map view.)
    @param(AStats The times.) }
  TMapPaintStatsEvent = procedure(Sender: TObject; const AStats: TMapPaintStats) of object;

  {$IFDEF SKIA}
  { @abstract(The lines of a vector layer inside one square of the world,
    as a Skia path.)

    A layer is cut into squares @code(LINE_PIECE_DEGREES) on a side, so a
    frame can skip the squares that are off screen. A line that crosses
    from one square into the next is cut there: the segment that crosses
    belongs to the square it starts in, and the next piece starts where it
    ends, so the line has no gaps. Coordinates are those of
    @link(TWorldMapView.LayerPieces): degrees from the map's top-left
    corner. }
  TLinePiece = record
    { The lines. }
    Path: ISkPath;
    { The smallest rectangle holding every point of @link(Path), including
      the ends of segments that cross out of the square, so a piece is
      never skipped while part of it is on screen. }
    Bounds: TRectF;
  end;
  {$ENDIF}

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
    { Screen position, in local coordinates, of the top-left corner of the
      copy of the map image that holds longitudes -180 to 180. Other copies
      sit a whole map width to either side. Horizontally it is kept within
      one map width of zero, except during a selection drag, when it is left
      alone so the drag's anchor keeps its meaning. }
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
    { The button that started a pan, so a right click can be told apart. }
    FPanButton: TMouseButton;
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
    { Scrolls the map while a selection is dragged near or past an edge. }
    FScrollTimer: TTimer;
    { Backing field for @link(OnSelectionChanged). }
    FOnSelectionChanged: TNotifyEvent;
    { Backing field for @link(OnSelectionChanging). }
    FOnSelectionChanging: TNotifyEvent;
    { Backing field for @link(OnHover). }
    FOnHover: TMapHoverEvent;
    { Backing field for @link(OnRightClick). }
    FOnRightClick: TMapPointEvent;
    { The tiles of a selection made of separate tiles (see
      @link(SelectTiles)); owned. Only meaningful while
      @link(FHasSelectionMask) is @true. }
    FSelectionMask: TTileIndex;
    { @true while the selection is the tiles in @link(FSelectionMask)
      rather than the whole of @link(FSelection). }
    FHasSelectionMask: Boolean;
    { Backing field for @link(SelectionName). }
    FSelectionName: string;
    { One pixel per tile of @link(FSelectionMask), in the selection colour;
      @nil when there is no mask. }
    FSelectionOverlay: TBitmap;
    { Backing field for @link(TileIndex). Not owned. }
    FTileIndex: TTileIndex;
    { Backing field for @link(DownloadedIndex). Not owned. }
    FDownloadedIndex: TTileIndex;
    { One pixel per tile: green where downloaded, cyan where data exists,
      transparent elsewhere, following @link(ShowAvailableTiles) and
      @link(ShowDownloadedTiles). @nil when there is nothing to show. }
    FTileOverlay: TBitmap;

    { Backing field for @link(ShowAvailableTiles). }
    FShowAvailableTiles: Boolean;
    { Backing field for @link(ShowDownloadedTiles). }
    FShowDownloadedTiles: Boolean;
    { Backing field for @link(Vectors). Not owned. }
    FVectors: TWorldVectors;
    { Backing field for @link(ShowBorders). }
    FShowBorders: Boolean;
    { Backing field for @link(ShowCoastlines). }
    FShowCoastlines: Boolean;
    { Backing field for @link(UseSkiaPaths). }
    FUseSkiaPaths: Boolean;
    {$IFDEF SKIA}
    { Each vector layer as Skia paths, one per square of the world, built
      the first time the layer is drawn (see @link(LayerPieces)). Keyed by
      layer, which @link(FVectors) owns; emptied when @link(Vectors)
      changes. }
    FLayerPaths: TDictionary<TGeoLayer, TArray<TLinePiece>>;
    {$ENDIF}
    { Backing field for @link(OnPaintStats). }
    FOnPaintStats: TMapPaintStatsEvent;
    { @true during a stretch of movement whose frames are being timed. }
    FMeasuring: Boolean;
    { The times so far in the current stretch; @code(AverageMs) and
      @code(LinesMs) hold totals until the stretch ends. }
    FStats: TMapPaintStats;
    { @code(TStopwatch) time stamp at the start of the stretch's first
      frame. }
    FFirstFrameStamp: Int64;
    { @code(TStopwatch) time stamp at the end of the stretch's last frame. }
    FLastFrameStamp: Int64;
    { Milliseconds spent on borders and coastlines in the frame being
      drawn. }
    FFrameLinesMs: Double;
    { Whether the frame being drawn has drawn a layer from a cached Skia
      path. }
    FFrameSkiaLines: Boolean;
    { Whether the frame being drawn has built a layer's path afresh. }
    FFrameBuiltLines: Boolean;
    { Ends a stretch of wheel zooming a second after the last notch. }
    FStatsTimer: TTimer;

    { Ends a selection made of separate tiles, leaving
      @link(FSelection) as it is. }
    procedure ClearSelectionMask;

    { Reader for @link(SelectionMask).
      @returns(The mask, or @nil for a plain block.) }
    function GetSelectionMask: TTileIndex;

    { Stretches a 360 by 180 bitmap, one pixel per tile, over one copy of
      the map.
      @param(ABitmap The bitmap; row 0 is latitude 89 to 90, column 0
        longitude -180 to -179.)
      @param(AOpacity Opacity, from 0 to 1.)
      @param(ACopy Which copy of the map, as for @link(PaintMapCopy).)
      @param(ANorth Northernmost latitude on screen.)
      @param(ASouth Southernmost latitude on screen.)
      @param(AWest Westernmost longitude on screen, not wrapped.)
      @param(AEast Easternmost longitude on screen, not wrapped.) }
    procedure PaintTileBitmap(ABitmap: TBitmap; AOpacity: Single; ACopy: Integer;
      ANorth, ASouth, AWest, AEast: Double);

    { Writer for @link(Vectors).
      @param(AValue The borders and coastlines, or @nil.) }
    procedure SetVectors(AValue: TWorldVectors);

    { Writer for @link(ShowBorders).
      @param(AValue @true to draw country borders.) }
    procedure SetShowBorders(AValue: Boolean);

    { Writer for @link(ShowCoastlines).
      @param(AValue @true to draw coastlines.) }
    procedure SetShowCoastlines(AValue: Boolean);

    { Writer for @link(DownloadedIndex).
      @param(AValue The new index, or @nil.) }
    procedure SetDownloadedIndex(AValue: TTileIndex);

    { Writer for @link(ShowDownloadedTiles).
      @param(AValue @true to tint downloaded tiles.) }
    procedure SetShowDownloadedTiles(AValue: Boolean);

    { Writer for @link(TileIndex).
      @param(AValue The new index, or @nil.) }
    procedure SetTileIndex(AValue: TTileIndex);

    { Writer for @link(ShowAvailableTiles).
      @param(AValue @true to tint tiles that have data.) }
    procedure SetShowAvailableTiles(AValue: Boolean);

    { Redraws @link(FTileOverlay) from @link(FTileIndex) and
      @link(FDownloadedIndex). }
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

    { Keeps the map in view. Vertically, centres the map if it is shorter
      than the control, otherwise stops its top and bottom moving inside
      the control. Horizontally the map wraps, so it is only centred while
      the whole world is shown (@link(FAutoFit)), and otherwise brought
      back within one map width of zero. }
    procedure ClampOrigin;

    { Converts a local point to a map position without wrapping the
      longitude, so positions to the right of the 180 meridian come out
      above 180. Used while dragging, so a selection can cross it.
      @param(APoint Point in local coordinates.)
      @param(ALat Receives the latitude, not clamped.)
      @param(ALon Receives the longitude, not wrapped.) }
    procedure ScreenToGeoRaw(const APoint: TPointF; out ALat, ALon: Double);

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
      @param(AFillOpacity Opacity of the fill, from 0 to 1.)
      @param(ALonShift Degrees to move the block east, a multiple of 360,
        to draw it on another copy of the map.) }
    procedure PaintTileRect(const ATiles: TTileRect; AColor: TAlphaColor;
      AFillOpacity: Single; ALonShift: Integer);

    { Draws one copy of the map image and its tile tint.
      @param(ACopy Which copy: 0 is the one holding longitudes -180 to 180,
        -1 the one to its west, 1 the one to its east.)
      @param(ANorth Northernmost latitude on screen.)
      @param(ASouth Southernmost latitude on screen.)
      @param(AWest Westernmost longitude on screen, not wrapped.)
      @param(AEast Easternmost longitude on screen, not wrapped.) }
    procedure PaintMapCopy(ACopy: Integer; ANorth, ASouth, AWest, AEast: Double);

    { Draws the lines of a vector layer that are on screen, on every copy
      of the map that is showing, as one path.
      @param(ALayer The layer; nothing is drawn if it is @nil.)
      @param(AColor Line colour.)
      @param(AOpacity Line opacity, from 0 to 1.)
      @param(AThickness Line width, in pixels.)
      @param(ANorth Northernmost latitude on screen.)
      @param(ASouth Southernmost latitude on screen.)
      @param(AWest Westernmost longitude on screen, not wrapped.)
      @param(AEast Easternmost longitude on screen, not wrapped.) }
    procedure PaintLayer(ALayer: TGeoLayer; AColor: TAlphaColor;
      AOpacity, AThickness: Single; ANorth, ASouth, AWest, AEast: Double);

    {$IFDEF SKIA}
    { A vector layer cut into Skia paths, one per square of the world its
      lines pass through (see @link(TLinePiece)), built and kept the first
      time it is asked for. Points are in degrees from the map's top-left
      corner: x is longitude + 180 and y is 90 - latitude, so one matrix
      puts them on the screen.
      @param(ALayer The layer.)
      @returns(The pieces, in no particular order.) }
    function LayerPieces(ALayer: TGeoLayer): TArray<TLinePiece>;

    { Draws the pieces of a vector layer that are on screen from their
      cached Skia paths (see @link(LayerPieces)), on every copy of the map
      that is showing, when the canvas is a Skia canvas.
      @param(ALayer The layer.)
      @param(AColor Line colour.)
      @param(AOpacity Line opacity, from 0 to 1.)
      @param(AThickness Line width, in pixels.)
      @param(ANorth Northernmost latitude on screen.)
      @param(ASouth Southernmost latitude on screen.)
      @param(AWest Westernmost longitude on screen, not wrapped.)
      @param(AEast Easternmost longitude on screen, not wrapped.)
      @returns(@true if it was drawn; @false if the canvas is not a Skia
        canvas, so the caller should draw it another way.) }
    function PaintLayerSkia(ALayer: TGeoLayer; AColor: TAlphaColor;
      AOpacity, AThickness: Single; ANorth, ASouth, AWest, AEast: Double): Boolean;
    {$ENDIF}

    { Draws everything: the map, tints, shading, borders and coastlines,
      grid, hover outline and selection. Called by @link(Paint), which
      times it. }
    procedure PaintMap;

    { Writer for @link(UseSkiaPaths).
      @param(AValue @true to draw borders and coastlines from cached Skia
        paths when the canvas allows.) }
    procedure SetUseSkiaPaths(AValue: Boolean);

    { Starts timing frames, if @link(OnPaintStats) is set and timing has
      not already started. }
    procedure BeginMeasuring;

    { Ends timing and fires @link(OnPaintStats) if any frames were drawn. }
    procedure EndMeasuring;

    { Ends a stretch of wheel zooming, unless a drag has started meanwhile.
      @param(Sender The timer.) }
    procedure StatsTimerTick(Sender: TObject);

    { Converts a local point to a map position for dragging: the latitude
      is clamped to just inside the poles, and the longitude is not wrapped.
      @param(APoint Point in local coordinates.)
      @param(ALat Receives the latitude.)
      @param(ALon Receives the longitude, not wrapped.) }
    procedure ScreenToGeoClamped(const APoint: TPointF; out ALat, ALon: Double);

    { Fires @link(OnHover) for a local point.
      @param(APoint Point in local coordinates.) }
    procedure DoHover(const APoint: TPointF);

    { Recalculates the selection being dragged from the anchor and the
      current pointer position, firing @link(OnSelectionChanging) if it now
      covers different tiles. }
    procedure UpdateDragSelection;

    { How far to move the map for one auto-scroll step, given where the
      pointer is. Zero on an axis where the pointer is not near an edge.
      @returns(Change to apply to @link(FOrigin), in local pixels.) }
    function EdgeScrollStep: TPointF;

    { Starts or stops @link(FScrollTimer) to match where the pointer is
      during a selection drag. }
    procedure UpdateEdgeScroll;

    { Auto-scroll timer tick: moves the map one step towards the edge the
      pointer is at, and extends the selection to match.
      @param(Sender The timer.) }
    procedure ScrollTimerTick(Sender: TObject);
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
      @param(ALon Receives the longitude, wrapped into -180 to 180.)
      @returns(@true if the point is between the poles; since the map wraps
        east to west, every horizontal position is on the map.) }
    function ScreenToGeo(const APoint: TPointF; out ALat, ALon: Double): Boolean;

    { Converts a map position to a local point on the copy of the map that
      holds longitudes -180 to 180. Longitudes outside that range give
      points on the neighbouring copies.
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

    { Selects a set of separate tiles, such as the tiles a country covers,
      rather than a whole block. @link(Selection) becomes the smallest block
      holding them, @link(SelectionMask) the tiles themselves and
      @link(SelectionName) the name given; they are shown tinted. Starting
      a drag or calling @link(ClearSelection) ends it. Fires
      @link(OnSelectionChanged).
      @param(ATiles The tiles; copied, so the caller keeps and frees it. An
        empty set clears the selection.)
      @param(AName What the tiles are, such as a country's name.) }
    procedure SelectTiles(ATiles: TTileIndex; const AName: string);

    { Call after changing the contents of @link(TileIndex) or
      @link(DownloadedIndex) in place, so the map shows the change. Not
      needed after assigning a new index. }
    procedure TileIndexChanged;

    { Which tiles have data, used to tint them on the map. Not owned: the
      caller frees it, after setting this property to @nil or freeing the
      map view. @nil shows no tint. }
    property TileIndex: TTileIndex read FTileIndex write SetTileIndex;

    { Whether tiles that have data are tinted. On by default; has no
      effect until @link(TileIndex) is set. }
    property ShowAvailableTiles: Boolean read FShowAvailableTiles write SetShowAvailableTiles;

    { Which tiles are already downloaded, used to tint them on the map. Not
      owned, like @link(TileIndex). @nil shows no tint. }
    property DownloadedIndex: TTileIndex read FDownloadedIndex write SetDownloadedIndex;

    { Whether downloaded tiles are tinted. On by default; has no effect
      until @link(DownloadedIndex) is set. }
    property ShowDownloadedTiles: Boolean read FShowDownloadedTiles write SetShowDownloadedTiles;

    { Country borders and coastlines to draw over the map. Not owned, like
      @link(TileIndex). @nil draws none. }
    property Vectors: TWorldVectors read FVectors write SetVectors;

    { Whether country borders are drawn. On by default; has no effect
      until @link(Vectors) is set. }
    property ShowBorders: Boolean read FShowBorders write SetShowBorders;

    { Whether coastlines are drawn. On by default; has no effect until
      @link(Vectors) is set. }
    property ShowCoastlines: Boolean read FShowCoastlines write SetShowCoastlines;

    { The selected block of tiles. Changed by dragging on the map or by
      @link(ClearSelection). Empty when nothing is selected. }
    property Selection: TTileRect read FSelection;

    { Fired when a selection drag finishes or the selection is cleared. }
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;

    { Fired during a selection drag each time the selection grows or
      shrinks to cover different tiles, including when the map scrolls by
      itself at an edge or is zoomed mid-drag. Fired often, so a handler
      should be quick; @link(OnSelectionChanged) still fires when the drag
      ends. }
    property OnSelectionChanging: TNotifyEvent read FOnSelectionChanging write FOnSelectionChanging;

    { Fired as the pointer moves over the control. }
    property OnHover: TMapHoverEvent read FOnHover write FOnHover;

    { When the selection is a set of separate tiles (see
      @link(SelectTiles)), those tiles, all inside @link(Selection);
      otherwise @nil, and every tile of @link(Selection) is selected. Owned
      by the map view: do not free or keep it. }
    property SelectionMask: TTileIndex read GetSelectionMask;

    { The name given to @link(SelectTiles), or an empty string for a
      selection dragged on the map. }
    property SelectionName: string read FSelectionName;

    { Fired by a right click that does not move the map: a right-drag still
      moves it. }
    property OnRightClick: TMapPointEvent read FOnRightClick write FOnRightClick;

    { Whether borders and coastlines are drawn from Skia paths built once
      and kept, rather than paths built afresh for every frame. On by
      default. It only has an effect when FMX draws with Skia; turning it
      off is for comparing the two ways with @link(OnPaintStats). }
    property UseSkiaPaths: Boolean read FUseSkiaPaths write SetUseSkiaPaths;

    { Fired at the end of each drag, pan or run of wheel zooms with how
      long its frames took to draw. Frames are only timed while this is
      set. }
    property OnPaintStats: TMapPaintStatsEvent read FOnPaintStats write FOnPaintStats;
  end;

implementation

uses
  System.Math, System.Math.Vectors, System.Diagnostics
  {$IFDEF SKIA}
  , FMX.Skia.Canvas
  {$ENDIF}
  ;

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
  { Tint for tiles that are downloaded. }
  DOWNLOADED_COLOR = $FF4CDB5C;
  { Opacity of the tile tints. }
  TILE_TINT_OPACITY = 0.4;
  { Opacity of the tiles of a selection made of separate tiles. }
  SELECTION_TINT_OPACITY = 0.5;
  { How far the pointer may move between pressing and releasing the right
    button for it still to count as a click, in pixels. }
  CLICK_SLOP = 4;
  { Colour of country borders: pink, unlike anything else on the map. }
  BORDER_COLOR = $FFFF80AB;
  { Opacity of country borders. }
  BORDER_OPACITY = 0.9;
  { Colour of coastlines. }
  COAST_COLOR = $FFFFFFFF;
  { Opacity of coastlines; lower than the borders, as the map image already
    shows where the land is. }
  COAST_OPACITY = 0.55;
  { Screen pixels per degree from which the 1:50m borders and coastlines
    are drawn instead of the 1:110m ones. }
  FINE_DETAIL_PIXELS_PER_DEGREE = 8;
  { Points of a line closer than this to the last one drawn are skipped,
    in pixels. }
  MIN_SEGMENT_PIXELS = 0.75;
  { Zoom step for one mouse wheel notch. }
  WHEEL_ZOOM_STEP = 1.25;
  { Approximate largest size of one degree on screen, in pixels. }
  MAX_PIXELS_PER_DEGREE = 400;
  { Smallest screen spacing between grid lines, in pixels. }
  MIN_GRID_SPACING = 12;
  { Smallest size of a degree on screen before the tile under the pointer
    is outlined, in pixels. }
  MIN_HOVER_TILE_SIZE = 6;
  { Width of the band inside each edge where a selection drag starts to
    scroll the map, in pixels. }
  EDGE_SCROLL_MARGIN = 24;
  { Auto-scroll speed when the pointer has just entered the edge band, in
    pixels per tick. }
  EDGE_SCROLL_MIN_STEP = 2;
  { Fastest auto-scroll speed, in pixels per tick. }
  EDGE_SCROLL_MAX_STEP = 40;
  { Time between auto-scroll steps, in milliseconds. }
  EDGE_SCROLL_INTERVAL = 30;
  { How long after the last wheel zoom its frame times are reported, in
    milliseconds. }
  STATS_IDLE_INTERVAL = 1000;
  { Size of the squares vector layers are cut into for drawing with Skia,
    in degrees (see @link(TLinePiece)). Smaller squares skip more of the
    lines off screen but mean more paths to draw when zoomed out. }
  LINE_PIECE_DEGREES = 10;
  { Number of squares across the world. }
  LINE_PIECE_COLUMNS = 360 div LINE_PIECE_DEGREES;
  { Number of squares from pole to pole. }
  LINE_PIECE_ROWS = 180 div LINE_PIECE_DEGREES;

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
  FShowDownloadedTiles := True;
  FShowBorders := True;
  FShowCoastlines := True;
  FUseSkiaPaths := True;
  {$IFDEF SKIA}
  FLayerPaths := TDictionary<TGeoLayer, TArray<TLinePiece>>.Create;
  {$ENDIF}
  FSelectionMask := TTileIndex.Create;
  FScrollTimer := TTimer.Create(Self);
  FScrollTimer.Enabled := False;
  FScrollTimer.Interval := EDGE_SCROLL_INTERVAL;
  FScrollTimer.OnTimer := ScrollTimerTick;
  FStatsTimer := TTimer.Create(Self);
  FStatsTimer.Enabled := False;
  FStatsTimer.Interval := STATS_IDLE_INTERVAL;
  FStatsTimer.OnTimer := StatsTimerTick;
end;

destructor TWorldMapView.Destroy;
begin
  FSelectionOverlay.Free;
  FSelectionMask.Free;
  FTileOverlay.Free;
  FMap.Free;
  {$IFDEF SKIA}
  FLayerPaths.Free;
  {$ENDIF}
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
    RebuildTileOverlay;
  end;
end;

procedure TWorldMapView.SetDownloadedIndex(AValue: TTileIndex);
begin
  FDownloadedIndex := AValue;
  RebuildTileOverlay;
end;

procedure TWorldMapView.SetShowDownloadedTiles(AValue: Boolean);
begin
  if FShowDownloadedTiles <> AValue then
  begin
    FShowDownloadedTiles := AValue;
    RebuildTileOverlay;
  end;
end;

procedure TWorldMapView.SetVectors(AValue: TWorldVectors);
begin
  FVectors := AValue;
  // The cached paths belong to the old layers
  {$IFDEF SKIA}
  FLayerPaths.Clear;
  {$ENDIF}
  Repaint;
end;

procedure TWorldMapView.SetUseSkiaPaths(AValue: Boolean);
begin
  if FUseSkiaPaths <> AValue then
  begin
    FUseSkiaPaths := AValue;
    Repaint;
  end;
end;

procedure TWorldMapView.SetShowBorders(AValue: Boolean);
begin
  if FShowBorders <> AValue then
  begin
    FShowBorders := AValue;
    Repaint;
  end;
end;

procedure TWorldMapView.SetShowCoastlines(AValue: Boolean);
begin
  if FShowCoastlines <> AValue then
  begin
    FShowCoastlines := AValue;
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
  LRow, LCol, LSouth, LWest: Integer;
  LAvailable, LDownloaded: Boolean;
  LColor: TAlphaColor;
begin
  FreeAndNil(FTileOverlay);
  LAvailable := FShowAvailableTiles and (FTileIndex <> nil) and not FTileIndex.IsEmpty;
  LDownloaded := FShowDownloadedTiles and (FDownloadedIndex <> nil) and
    not FDownloadedIndex.IsEmpty;
  if LAvailable or LDownloaded then
  begin
    FTileOverlay := TBitmap.Create(TILE_INDEX_WIDTH, TILE_INDEX_HEIGHT);
    if FTileOverlay.Map(TMapAccess.Write, LData) then
    try
      // Row 0 is the northernmost row of tiles, whose southern edge is 89
      for LRow := 0 to TILE_INDEX_HEIGHT - 1 do
      begin
        LSouth := 89 - LRow;
        for LCol := 0 to TILE_INDEX_WIDTH - 1 do
        begin
          LWest := LCol - 180;
          if LDownloaded and FDownloadedIndex.Has(LSouth, LWest) then
            LColor := DOWNLOADED_COLOR
          else if LAvailable and FTileIndex.Has(LSouth, LWest) then
            LColor := AVAILABLE_COLOR
          else
            LColor := TAlphaColors.Null;
          LData.SetPixel(LCol, LRow, LColor);
        end;
      end;
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

  // Horizontally the map wraps, so there is no edge to stop at
  if LContentWidth > 0 then
  begin
    if FAutoFit and (LContentWidth <= Width) then
      FOrigin.X := (Width - LContentWidth) / 2
    else if FDragMode <> mdSelect then
      // Shift by whole map widths, which shows exactly the same picture,
      // to keep the numbers small
      FOrigin.X := FOrigin.X - Floor(FOrigin.X / LContentWidth) * LContentWidth;
  end;

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

procedure TWorldMapView.ClearSelectionMask;
begin
  FHasSelectionMask := False;
  FSelectionName := '';
  FSelectionMask.Clear;
  FreeAndNil(FSelectionOverlay);
end;

function TWorldMapView.GetSelectionMask: TTileIndex;
begin
  if FHasSelectionMask then
    Result := FSelectionMask
  else
    Result := nil;
end;

procedure TWorldMapView.SelectTiles(ATiles: TTileIndex; const AName: string);
var
  LData: TBitmapData;
  LRow, LCol: Integer;
begin
  ClearSelectionMask;
  if (ATiles = nil) or ATiles.IsEmpty then
  begin
    ClearSelection;
    Exit;
  end;
  FSelectionMask.Assign(ATiles);
  FHasSelectionMask := True;
  FSelectionName := AName;
  FSelection := FSelectionMask.BoundingRect;

  FSelectionOverlay := TBitmap.Create(TILE_INDEX_WIDTH, TILE_INDEX_HEIGHT);
  if FSelectionOverlay.Map(TMapAccess.Write, LData) then
  try
    // Row 0 is the northernmost row of tiles, as in RebuildTileOverlay
    for LRow := 0 to TILE_INDEX_HEIGHT - 1 do
      for LCol := 0 to TILE_INDEX_WIDTH - 1 do
        if FSelectionMask.Has(89 - LRow, LCol - 180) then
          LData.SetPixel(LCol, LRow, SELECTION_COLOR)
        else
          LData.SetPixel(LCol, LRow, TAlphaColors.Null);
  finally
    FSelectionOverlay.Unmap(LData);
  end;

  Repaint;
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

procedure TWorldMapView.ClearSelection;
begin
  ClearSelectionMask;
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

procedure TWorldMapView.ScreenToGeoRaw(const APoint: TPointF; out ALat, ALon: Double);
begin
  if (FMap = nil) or (FScale <= 0) then
  begin
    ALat := 0;
    ALon := 0;
    Exit;
  end;
  ALon := (APoint.X - FOrigin.X) / FScale * 360 / MapWidth - 180;
  ALat := 90 - (APoint.Y - FOrigin.Y) / FScale * 180 / MapHeight;
end;

function TWorldMapView.ScreenToGeo(const APoint: TPointF; out ALat, ALon: Double): Boolean;
begin
  if (FMap = nil) or (FScale <= 0) then
  begin
    ALat := 0;
    ALon := 0;
    Exit(False);
  end;
  ScreenToGeoRaw(APoint, ALat, ALon);
  // Wrap into -180 <= ALon < 180
  ALon := ALon - Floor((ALon + 180) / 360) * 360;
  Result := InRange(ALat, -90, 90);
end;

procedure TWorldMapView.ScreenToGeoClamped(const APoint: TPointF; out ALat, ALon: Double);
begin
  ScreenToGeoRaw(APoint, ALat, ALon);
  // Stay just inside the poles so Floor never yields 90
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
    and the prime meridian (on every copy of the map) are drawn thicker and
    brighter.
    @param(ADegree The line's latitude or longitude.)
    @returns(Opacity for @code(DrawLine).) }
  function LineStyle(ADegree: Integer): Single;
  begin
    if NormalizeLon(ADegree) = 0 then
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
    LFrom := GeoToScreen(LDegree, AVisible.Left);
    LTo := GeoToScreen(LDegree, AVisible.Right);
    Canvas.DrawLine(LFrom, LTo, LineStyle(LDegree));
    Inc(LDegree, LStep);
  end;
end;

procedure TWorldMapView.PaintTileRect(const ATiles: TTileRect; AColor: TAlphaColor;
  AFillOpacity: Single; ALonShift: Integer);
var
  LRect: TRectF;
begin
  if ATiles.IsEmpty then
    Exit;
  LRect := TRectF.Create(GeoToScreen(ATiles.North, ATiles.West + ALonShift),
                         GeoToScreen(ATiles.South, ATiles.East + ALonShift));
  // Nothing to draw if this copy of the block is off screen
  if (LRect.Right < 0) or (LRect.Left > Width) then
    Exit;
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

procedure TWorldMapView.PaintMapCopy(ACopy: Integer; ANorth, ASouth, AWest, AEast: Double);
var
  LShift: TPointF;
  LClient, LSource, LDest: TRectF;
begin
  // This copy's image sits a whole number of map widths from FOrigin
  LShift := PointF(ACopy * MapWidth * FScale, 0);
  LClient := LocalRect;
  LSource := TRectF.Create((LClient.TopLeft - FOrigin - LShift) / FScale,
                           (LClient.BottomRight - FOrigin - LShift) / FScale);
  LSource.Intersect(TRectF.Create(0, 0, MapWidth, MapHeight));
  if LSource.IsEmpty then
    Exit;
  LDest := TRectF.Create(FOrigin + LShift + LSource.TopLeft * FScale,
                         FOrigin + LShift + LSource.BottomRight * FScale);
  Canvas.DrawBitmap(FMap, LSource, LDest, 1, False);

  // Tint tiles that have data or are downloaded
  if FTileOverlay <> nil then
    PaintTileBitmap(FTileOverlay, TILE_TINT_OPACITY, ACopy, ANorth, ASouth, AWest, AEast);
end;

procedure TWorldMapView.PaintTileBitmap(ABitmap: TBitmap; AOpacity: Single;
  ACopy: Integer; ANorth, ASouth, AWest, AEast: Double);
var
  LWest, LEast: Double;
begin
  // Bitmap pixels are whole degrees, so the source rectangle is this copy's
  // visible longitudes; drawn without smoothing so tiles stay square
  LWest := Max(AWest - ACopy * 360, -180);
  LEast := Min(AEast - ACopy * 360, 180);
  if LEast > LWest then
    Canvas.DrawBitmap(ABitmap,
      TRectF.Create(LWest + 180, 90 - ANorth, LEast + 180, 90 - ASouth),
      TRectF.Create(GeoToScreen(ANorth, LWest + ACopy * 360),
                    GeoToScreen(ASouth, LEast + ACopy * 360)),
      AOpacity, True);
end;

procedure TWorldMapView.PaintLayer(ALayer: TGeoLayer; AColor: TAlphaColor;
  AOpacity, AThickness: Single; ANorth, ASouth, AWest, AEast: Double);
var
  LPath: TPathData;
  LCopy, LFeature, LPart, LPoint, LLast: Integer;
  LShift: Double;
  LBounds: TRectF;
  LPoints: TArray<TPointF>;
  LScreen, LDrawn: TPointF;
begin
  if ALayer = nil then
    Exit;
  {$IFDEF SKIA}
  if FUseSkiaPaths and
     PaintLayerSkia(ALayer, AColor, AOpacity, AThickness, ANorth, ASouth, AWest, AEast) then
  begin
    FFrameSkiaLines := True;
    Exit;
  end;
  {$ENDIF}
  FFrameBuiltLines := True;
  LPath := TPathData.Create;
  try
    for LCopy := Floor((AWest + 180) / 360) to Floor((AEast + 180) / 360) do
    begin
      LShift := LCopy * 360;
      for LFeature := 0 to High(ALayer.Features) do
        for LPart := 0 to High(ALayer.Features[LFeature].Parts) do
        begin
          // Skip lines wholly off screen; Top is the smaller latitude
          LBounds := ALayer.Features[LFeature].Parts[LPart].Bounds;
          if (LBounds.Right + LShift < AWest) or (LBounds.Left + LShift > AEast) or
             (LBounds.Bottom < ASouth) or (LBounds.Top > ANorth) then
            Continue;
          LPoints := ALayer.Features[LFeature].Parts[LPart].Points;
          LLast := High(LPoints);
          LDrawn := GeoToScreen(LPoints[0].Y, LPoints[0].X + LShift);
          LPath.MoveTo(LDrawn);
          for LPoint := 1 to LLast do
          begin
            LScreen := GeoToScreen(LPoints[LPoint].Y, LPoints[LPoint].X + LShift);
            // Detail finer than a pixel cannot be seen, but the last point
            // is always drawn so lines meet
            if (LPoint = LLast) or (Abs(LScreen.X - LDrawn.X) >= MIN_SEGMENT_PIXELS) or
               (Abs(LScreen.Y - LDrawn.Y) >= MIN_SEGMENT_PIXELS) then
            begin
              LPath.LineTo(LScreen);
              LDrawn := LScreen;
            end;
          end;
        end;
    end;
    if LPath.Count = 0 then
      Exit;
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := AColor;
    Canvas.Stroke.Thickness := AThickness;
    Canvas.DrawPath(LPath, AOpacity);
  finally
    LPath.Free;
  end;
end;

{$IFDEF SKIA}
function TWorldMapView.LayerPieces(ALayer: TGeoLayer): TArray<TLinePiece>;
var
  LBuilders: array of ISkPathBuilder;
  LBounds: array of TRectF;
  LFeature, LPart, LPoint, LCell, LNext, LCount: Integer;
  LPoints: TArray<TPointF>;
  LAt: TPointF;

  { The square a point is in, counting west to east, then north to south.
    Points on the far edges count as inside.
    @param(APoint A point in path coordinates.)
    @returns(Its square's number.) }
  function CellOf(const APoint: TPointF): Integer;
  begin
    Result := EnsureRange(Floor(APoint.Y / LINE_PIECE_DEGREES), 0, LINE_PIECE_ROWS - 1) *
      LINE_PIECE_COLUMNS +
      EnsureRange(Floor(APoint.X / LINE_PIECE_DEGREES), 0, LINE_PIECE_COLUMNS - 1);
  end;

  { Adds a point to a square's bounds, starting its path if it has none.
    @param(ACell The square.)
    @param(APoint The point, in path coordinates.) }
  procedure Grow(ACell: Integer; const APoint: TPointF);
  begin
    if LBuilders[ACell] = nil then
    begin
      LBuilders[ACell] := TSkPathBuilder.Create;
      LBounds[ACell] := TRectF.Create(APoint, APoint);
    end
    else
    begin
      LBounds[ACell].Left := Min(LBounds[ACell].Left, APoint.X);
      LBounds[ACell].Right := Max(LBounds[ACell].Right, APoint.X);
      LBounds[ACell].Top := Min(LBounds[ACell].Top, APoint.Y);
      LBounds[ACell].Bottom := Max(LBounds[ACell].Bottom, APoint.Y);
    end;
  end;

begin
  if FLayerPaths.TryGetValue(ALayer, Result) then
    Exit;
  SetLength(LBuilders, LINE_PIECE_COLUMNS * LINE_PIECE_ROWS);
  SetLength(LBounds, LINE_PIECE_COLUMNS * LINE_PIECE_ROWS);
  for LFeature := 0 to High(ALayer.Features) do
    for LPart := 0 to High(ALayer.Features[LFeature].Parts) do
    begin
      LPoints := ALayer.Features[LFeature].Parts[LPart].Points;
      if Length(LPoints) = 0 then
        Continue;
      LAt := PointF(LPoints[0].X + 180, 90 - LPoints[0].Y);
      LCell := CellOf(LAt);
      Grow(LCell, LAt);
      LBuilders[LCell].MoveTo(LAt);
      for LPoint := 1 to High(LPoints) do
      begin
        LAt := PointF(LPoints[LPoint].X + 180, 90 - LPoints[LPoint].Y);
        // The segment belongs to the square it starts in, even if it ends
        // in another
        Grow(LCell, LAt);
        LBuilders[LCell].LineTo(LAt);
        LNext := CellOf(LAt);
        if LNext <> LCell then
        begin
          // Carry on in the new square from where the segment ended
          LCell := LNext;
          Grow(LCell, LAt);
          LBuilders[LCell].MoveTo(LAt);
        end;
      end;
    end;

  SetLength(Result, Length(LBuilders));
  LCount := 0;
  for LCell := 0 to High(LBuilders) do
    if LBuilders[LCell] <> nil then
    begin
      Result[LCount].Path := LBuilders[LCell].Detach;
      Result[LCount].Bounds := LBounds[LCell];
      Inc(LCount);
    end;
  SetLength(Result, LCount);
  FLayerPaths.Add(ALayer, Result);
end;

function TWorldMapView.PaintLayerSkia(ALayer: TGeoLayer; AColor: TAlphaColor;
  AOpacity, AThickness: Single; ANorth, ASouth, AWest, AEast: Double): Boolean;
var
  LCanvas: ISkCanvas;
  LPieces: TArray<TLinePiece>;
  LPaint: ISkPaint;
  LScaleX, LScaleY, LMargin: Single;
  LCopy, LPiece: Integer;
  LVisible: TRectF;
begin
  // Every Skia canvas FMX draws on, CPU or GPU, is a TSkCanvasCustom, and
  // its Skia canvas already holds this control's position and clipping
  if not (Canvas is TSkCanvasCustom) then
    Exit(False);
  LCanvas := TSkCanvasCustom(Canvas).Canvas;
  if LCanvas = nil then
    Exit(False);
  Result := True;
  LPieces := LayerPieces(ALayer);

  // Screen pixels per degree; the same both ways for a 2:1 map image
  LScaleX := MapWidth / 360 * FScale;
  LScaleY := MapHeight / 180 * FScale;
  LPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  LPaint.AntiAlias := True;
  LPaint.Color := AColor;
  LPaint.AlphaF := TAlphaColorRec(AColor).A / 255 * AOpacity;
  // The width is in the path's units, degrees, as the matrix scales it too
  LPaint.StrokeWidth := AThickness / LScaleX;

  // A line's width either side, so a line just off screen still shows its
  // edge
  LMargin := LPaint.StrokeWidth;

  for LCopy := Floor((AWest + 180) / 360) to Floor((AEast + 180) / 360) do
  begin
    // What is on screen of this copy, in the pieces' coordinates
    LVisible := TRectF.Create(AWest + 180 - LCopy * 360 - LMargin, 90 - ANorth - LMargin,
      AEast + 180 - LCopy * 360 + LMargin, 90 - ASouth + LMargin);
    LCanvas.Save;
    try
      // Degrees to pixels, then onto this copy of the map; the paths'
      // origin is the map's top-left corner, as for GeoToScreen
      LCanvas.Concat(TMatrix.CreateScaling(LScaleX, LScaleY) *
        TMatrix.CreateTranslation(FOrigin.X + LCopy * 360 * LScaleX, FOrigin.Y));
      for LPiece := 0 to High(LPieces) do
        // Compared by hand, as a straight east-west or north-south line
        // has bounds with no height or width
        if (LPieces[LPiece].Bounds.Right >= LVisible.Left) and
           (LPieces[LPiece].Bounds.Left <= LVisible.Right) and
           (LPieces[LPiece].Bounds.Bottom >= LVisible.Top) and
           (LPieces[LPiece].Bounds.Top <= LVisible.Bottom) then
          LCanvas.DrawPath(LPieces[LPiece].Path, LPaint);
    finally
      LCanvas.Restore;
    end;
  end;
end;
{$ENDIF}

procedure TWorldMapView.Paint;
var
  LStart, LEnd: Int64;
  LMs: Double;
begin
  FFrameLinesMs := 0;
  FFrameSkiaLines := False;
  FFrameBuiltLines := False;
  LStart := TStopwatch.GetTimeStamp;
  PaintMap;
  if not FMeasuring then
    Exit;
  LEnd := TStopwatch.GetTimeStamp;
  LMs := (LEnd - LStart) * 1000 / TStopwatch.Frequency;
  if FStats.Frames = 0 then
    FFirstFrameStamp := LStart;
  FLastFrameStamp := LEnd;
  Inc(FStats.Frames);
  FStats.AverageMs := FStats.AverageMs + LMs;
  FStats.LinesMs := FStats.LinesMs + FFrameLinesMs;
  FStats.WorstMs := Max(FStats.WorstMs, LMs);
  if FFrameBuiltLines or not FFrameSkiaLines then
    FStats.SkiaLines := False;
  FStats.CanvasName := Canvas.ClassName;
end;

procedure TWorldMapView.BeginMeasuring;
begin
  if FMeasuring or not Assigned(FOnPaintStats) then
    Exit;
  FMeasuring := True;
  FStats := Default(TMapPaintStats);
  FStats.SkiaLines := True;
end;

procedure TWorldMapView.EndMeasuring;
var
  LStats: TMapPaintStats;
begin
  FStatsTimer.Enabled := False;
  if not FMeasuring then
    Exit;
  FMeasuring := False;
  if FStats.Frames = 0 then
    Exit;
  LStats := FStats;
  LStats.Seconds := (FLastFrameStamp - FFirstFrameStamp) / TStopwatch.Frequency;
  LStats.AverageMs := LStats.AverageMs / LStats.Frames;
  LStats.LinesMs := LStats.LinesMs / LStats.Frames;
  if Assigned(FOnPaintStats) then
    FOnPaintStats(Self, LStats);
end;

procedure TWorldMapView.StatsTimerTick(Sender: TObject);
begin
  FStatsTimer.Enabled := False;
  // A drag that started during the zooming is reported when it ends
  if FDragMode = mdNone then
    EndMeasuring;
end;

procedure TWorldMapView.PaintMap;
var
  LClient: TRectF;
  LNorth, LWest, LSouth, LEast, LLat, LLon: Double;
  LCopy, LFirstCopy, LLastCopy: Integer;
  LTop, LBottom, LEdge: Single;
  LDetail: TGeoDetail;
  LLinesStart: Int64;
begin
  LClient := LocalRect;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := MAP_BACKGROUND;
  Canvas.FillRect(LClient, 0, 0, AllCorners, 1);

  if FMap = nil then
    Exit;

  // Visible area in degrees; longitudes are not wrapped
  ScreenToGeoRaw(LClient.TopLeft, LNorth, LWest);
  ScreenToGeoRaw(LClient.BottomRight, LSouth, LEast);
  LNorth := Min(LNorth, 90);
  LSouth := Max(LSouth, -90);
  if LNorth <= LSouth then
    Exit;

  // Draw every copy of the map that is at least partly on screen
  LFirstCopy := Floor((LWest + 180) / 360);
  LLastCopy := Floor((LEast + 180) / 360);
  for LCopy := LFirstCopy to LLastCopy do
    PaintMapCopy(LCopy, LNorth, LSouth, LWest, LEast);

  // Shade the areas ASTER GDEM does not cover, across the whole width
  Canvas.Fill.Color := TAlphaColors.Black;
  LTop := GeoToScreen(LNorth, 0).Y;
  LBottom := GeoToScreen(LSouth, 0).Y;
  if LNorth > GDEM_MAX_LAT then
  begin
    LEdge := GeoToScreen(GDEM_MAX_LAT, 0).Y;
    Canvas.FillRect(TRectF.Create(LClient.Left, LTop, LClient.Right, LEdge),
      0, 0, AllCorners, 0.45);
  end;
  if LSouth < GDEM_MIN_LAT then
  begin
    LEdge := GeoToScreen(GDEM_MIN_LAT, 0).Y;
    Canvas.FillRect(TRectF.Create(LClient.Left, LEdge, LClient.Right, LBottom),
      0, 0, AllCorners, 0.45);
  end;

  // Borders and coastlines, over the map and tints but under the grid
  if FVectors <> nil then
  begin
    LLinesStart := TStopwatch.GetTimeStamp;
    if ScreenPixelsPerDegree >= FINE_DETAIL_PIXELS_PER_DEGREE then
      LDetail := gdFine
    else
      LDetail := gdCoarse;
    if FShowCoastlines then
      PaintLayer(FVectors.Coastlines(LDetail), COAST_COLOR, COAST_OPACITY, 1,
        LNorth, LSouth, LWest, LEast);
    if FShowBorders then
      PaintLayer(FVectors.Borders(LDetail), BORDER_COLOR, BORDER_OPACITY, 1.25,
        LNorth, LSouth, LWest, LEast);
    FFrameLinesMs := (TStopwatch.GetTimeStamp - LLinesStart) * 1000 / TStopwatch.Frequency;
  end;

  PaintGrid(TRectF.Create(LWest, LNorth, LEast, LSouth));

  // Outline the tile under the pointer once tiles are big enough to see.
  // The unwrapped position keeps the outline on the copy being pointed at.
  if FMouseInside and (FDragMode = mdNone) and
     (ScreenPixelsPerDegree >= MIN_HOVER_TILE_SIZE) then
  begin
    ScreenToGeoRaw(FMousePos, LLat, LLon);
    if InRange(LLat, GDEM_MIN_LAT, GDEM_MAX_LAT) then
    begin
      Canvas.Stroke.Kind := TBrushKind.Solid;
      Canvas.Stroke.Color := HOVER_COLOR;
      Canvas.Stroke.Thickness := 1;
      Canvas.DrawRect(TRectF.Create(GeoToScreen(Floor(LLat) + 1, Floor(LLon)),
        GeoToScreen(Floor(LLat), Floor(LLon) + 1)), 0, 0, AllCorners, 0.8);
    end;
  end;

  // A selection of separate tiles shows those tiles, inside a thin outline
  // of the block holding them
  if FHasSelectionMask and (FSelectionOverlay <> nil) then
    for LCopy := LFirstCopy to LLastCopy do
      PaintTileBitmap(FSelectionOverlay, SELECTION_TINT_OPACITY, LCopy,
        LNorth, LSouth, LWest, LEast);

  // The selection is stored with West in -180..179 but may be up to 360
  // degrees wide, so it can show on the copies either side as well
  if not FSelection.IsEmpty then
    for LCopy := LFirstCopy - 1 to LLastCopy + 1 do
      if FHasSelectionMask then
        PaintTileRect(FSelection, SELECTION_COLOR, 0, LCopy * 360)
      else
        PaintTileRect(FSelection, SELECTION_COLOR, 0.25, LCopy * 360);
end;

procedure TWorldMapView.UpdateDragSelection;
var
  LLat, LLon: Double;
  LOld: TTileRect;
begin
  LOld := FSelection;
  ScreenToGeoClamped(FMousePos, LLat, LLon);
  FSelection := TTileRect.FromPoints(FAnchorLon, FAnchorLat, LLon, LLat);
  // Only when the tiles covered change, not on every pixel of movement
  if Assigned(FOnSelectionChanging) and
     ((FSelection.West <> LOld.West) or (FSelection.South <> LOld.South) or
      (FSelection.East <> LOld.East) or (FSelection.North <> LOld.North)) then
    FOnSelectionChanging(Self);
end;

function TWorldMapView.EdgeScrollStep: TPointF;

  { Speed along one axis. Positive when the pointer is before the start of
    the axis (left or top), negative when past its end.
    @param(APos Pointer position on the axis.)
    @param(ALength Length of the control along the axis.)
    @returns(Pixels to move the map by.) }
  function AxisStep(APos, ALength: Single): Single;
  var
    LDepth: Single;
  begin
    Result := 0;
    if APos < EDGE_SCROLL_MARGIN then
      LDepth := EDGE_SCROLL_MARGIN - APos
    else if APos > ALength - EDGE_SCROLL_MARGIN then
      LDepth := APos - (ALength - EDGE_SCROLL_MARGIN)
    else
      Exit;
    // Speed grows with how far into the band, or beyond the edge, it is
    Result := Min(EDGE_SCROLL_MAX_STEP, EDGE_SCROLL_MIN_STEP + LDepth / 2);
    if APos > ALength / 2 then
      Result := -Result;
  end;

begin
  Result := PointF(AxisStep(FMousePos.X, Width), AxisStep(FMousePos.Y, Height));
end;

procedure TWorldMapView.UpdateEdgeScroll;
var
  LStep: TPointF;
begin
  LStep := EdgeScrollStep;
  FScrollTimer.Enabled := (FDragMode = mdSelect) and ((LStep.X <> 0) or (LStep.Y <> 0));
end;

procedure TWorldMapView.ScrollTimerTick(Sender: TObject);
var
  LStep, LOldOrigin: TPointF;
begin
  if FDragMode <> mdSelect then
  begin
    FScrollTimer.Enabled := False;
    Exit;
  end;
  LStep := EdgeScrollStep;
  LOldOrigin := FOrigin;
  FAutoFit := False;
  FOrigin := FOrigin + LStep;
  ClampOrigin;
  // Keep ticking while the pointer stays at the edge, even once the map
  // can move no further, so scrolling resumes if the user zooms out
  if FOrigin <> LOldOrigin then
  begin
    UpdateDragSelection;
    DoHover(FMousePos);
    Repaint;
  end;
end;

procedure TWorldMapView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if FMap = nil then
    Exit;
  FMousePos := PointF(X, Y);
  BeginMeasuring;
  if (Button = TMouseButton.mbLeft) and not (ssShift in Shift) then
  begin
    FDragMode := mdSelect;
    ClearSelectionMask;
    ScreenToGeoClamped(FMousePos, FAnchorLat, FAnchorLon);
    FSelection := TTileRect.FromPoints(FAnchorLon, FAnchorLat, FAnchorLon, FAnchorLat);
    if Assigned(FOnSelectionChanging) then
      FOnSelectionChanging(Self);
  end
  else
  begin
    FDragMode := mdPan;
    FPanButton := Button;
    FDragStart := FMousePos;
    FDragOrigin := FOrigin;
  end;
  Repaint;
end;

procedure TWorldMapView.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  // During a drag the control keeps receiving moves after the pointer
  // leaves it, with positions outside its bounds
  FMousePos := PointF(X, Y);
  FMouseInside := True;
  case FDragMode of
    mdSelect:
      begin
        UpdateDragSelection;
        UpdateEdgeScroll;
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
  LWasSelecting, LRightClick: Boolean;
  LLat, LLon: Double;
begin
  inherited;
  LWasSelecting := FDragMode = mdSelect;
  // A right press and release that barely moved is a click, not a pan
  LRightClick := (FDragMode = mdPan) and (FPanButton = TMouseButton.mbRight) and
    (Button = TMouseButton.mbRight) and
    (PointF(X, Y).Distance(FDragStart) <= CLICK_SLOP);
  FDragMode := mdNone;
  FScrollTimer.Enabled := False;
  Repaint;
  EndMeasuring;
  if LWasSelecting and Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
  if LRightClick and Assigned(FOnRightClick) and ScreenToGeo(PointF(X, Y), LLat, LLon) then
    FOnRightClick(Self, LLat, LLon, Shift);
end;

procedure TWorldMapView.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  inherited;
  if FMap = nil then
    Exit;
  FAutoFit := False;
  // Time the frames until a second after the last notch, or until a drag
  // in progress ends
  BeginMeasuring;
  if FMeasuring and (FDragMode = mdNone) then
  begin
    FStatsTimer.Enabled := False;
    FStatsTimer.Enabled := True;
  end;
  // Zoom around the pointer, or the nearest point inside the control if a
  // drag has taken the pointer outside it
  SetScaleAt(FScale * Power(WHEEL_ZOOM_STEP, WheelDelta / 120),
    PointF(EnsureRange(FMousePos.X, 0, Width), EnsureRange(FMousePos.Y, 0, Height)));
  // The anchor is held in degrees, so the selection survives the zoom
  if FDragMode = mdSelect then
  begin
    UpdateDragSelection;
    Repaint;
  end;
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
