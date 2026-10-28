{ @abstract(The pieces of the 3D surface: where the ground lies on the
  globe, the heights of each tile at each detail, and the patches of mesh
  made from them.)

  The surface is drawn as square patches of @link(PATCH_CELLS) cells a
  side, whatever their size on the ground: a patch is a whole tile seen
  from far away, or a 75 arc-second square (about 2.3 km) close up. A
  tile's patches form a tree (see @code(GDEMTerrainLod)): the tile at
  depth 0, split 3 by 3 at depth 1 and then in quarters down to depth
  @link(TERRAIN_MAX_DEPTH), each depth halving the distance between
  samples (@link(NODE_ARCSEC)). An ASTER GDEM file holds the full 3601 x
  3601 image and overviews of 1801, 901, 451 and 226 among others, so each
  depth reads the coarsest image fine enough for it
  (@link(TTerrainTile.Heights)): a patch far away costs a small read.
  Samples are taken where the file's georeference puts them (each image's
  pixels cover the tile's area, as GDAL makes them), blended between the
  four nearest.

  Positions are laid out on a sphere of @link(EARTH_RADIUS_KM), seen from a
  point on its surface (@link(TTerrainFrame)): kilometres east (X), down
  (Y, so heights are negative Y, as FMX's up is -Y) and north (Z) of it.
  So the ground falls away with distance as the Earth's does (0.8 km one
  tile away), and a degree of longitude shrinks with the latitude, so
  tiles of different latitudes fit together.

  Each patch has a skirt: its edges copied a little lower and joined to
  them, so where a fine patch meets a coarser one no gap shows between
  them. All patches share one list of triangles
  (@link(TerrainPatchIndices)), wound clockwise as seen from above with
  north up the screen, as the first 3D view showed Gorilla3D wants;
  @link(TERRAIN_FLIP_WINDING) reverses it.

  Colours come from the height (@link(HeightColour): blue water, greens,
  yellows and browns, grey rock, white above 4,500 m) and are shaded by a
  sun in the north-west, 45 degrees up, so the relief shows even under a
  material that ignores lighting.

  Patches are made on worker threads (@link(BuildTerrainPatch) touches
  nothing shared but the tiles, which lock while reading). No FMX: TPoint3D
  and TAlphaColor come from the run-time library. }
unit GDEMTerrain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math.Vectors;

const
  { The height ASTER GDEM gives a void, where no elevation is known. }
  TERRAIN_VOID = -9999;

  { The details offered: the most samples across a tile used close to the
    camera. Each allows patches down to the depth whose samples are that
    close together (see @link(TerrainMaxDepth)): 226 stops at depth 1, 3601
    (every sample) goes to depth 5. Far away, every detail draws the same
    coarse patches. }
  TERRAIN_DETAILS: array[0..4] of Integer = (226, 451, 901, 1801, 3601);

  { Names for @link(TERRAIN_DETAILS), as offered. }
  TERRAIN_DETAIL_NAMES: array[0..4] of string = ('Coarse', 'Medium', 'Fine', 'Very fine',
    'Full');

  { The detail used unless another is chosen. }
  DEFAULT_TERRAIN_DETAIL = 3601;

  { The height stretches offered, times true scale. }
  TERRAIN_HEIGHTS: array[0..4] of Integer = (1, 2, 3, 5, 10);

  { The height stretch used unless another is chosen. }
  DEFAULT_TERRAIN_HEIGHTS = 2;

  { The distance details offered, in tenths: a patch is split into finer
    ones when the camera is nearer than this many times its size. Higher
    keeps more detail further away and draws more triangles. }
  TERRAIN_RANGES: array[0..2] of Integer = (15, 20, 30);

  { Names for @link(TERRAIN_RANGES), as offered. }
  TERRAIN_RANGE_NAMES: array[0..2] of string = ('Low', 'Medium', 'High');

  { The distance detail used unless another is chosen. }
  DEFAULT_TERRAIN_RANGE = 20;

  { The Earth's mean radius, in kilometres. }
  EARTH_RADIUS_KM = 6371.0088;

  { Kilometres in a degree of latitude on that sphere. }
  KM_PER_DEGREE = 2 * Pi * EARTH_RADIUS_KM / 360;

  { Kilometres in an arc-second of latitude. }
  KM_PER_ARCSEC = KM_PER_DEGREE / 3600;

  { Arc-seconds across a tile: one degree. }
  TILE_ARCSEC = 3600;

  { Cells along each side of a patch. 75 divides the 3,600 arc-seconds of
    a tile into 48 patches of 75 at full detail, and gives every depth a
    whole number of arc-seconds between samples. }
  PATCH_CELLS = 75;

  { Samples along each side of a patch. }
  PATCH_SIDE = PATCH_CELLS + 1;

  { Vertices of a patch's surface, before its skirt. }
  PATCH_GRID_VERTICES = PATCH_SIDE * PATCH_SIDE;

  { Vertices of a patch with its skirt: 6,080. }
  PATCH_VERTICES = PATCH_GRID_VERTICES + 4 * PATCH_SIDE;

  { Triangles of a patch with its skirt, which is drawn from both sides:
    12,450. }
  PATCH_TRIANGLES = PATCH_CELLS * PATCH_CELLS * 2 + 4 * PATCH_CELLS * 4;

  { The deepest a tile's tree goes: patches of 75 arc-seconds, every
    sample of the full image. }
  TERRAIN_MAX_DEPTH = 5;

  { Arc-seconds across a patch at each depth: the tile, its ninths, then
    halves of those. Divided by @link(PATCH_CELLS): 48, 16, 8, 4, 2 and 1
    arc-seconds between samples. }
  NODE_ARCSEC: array[0..TERRAIN_MAX_DEPTH] of Integer = (3600, 1200, 600, 300, 150, 75);

  { @true to wind triangles the other way, should the 3D library cull
    the surface seen from above. }
  TERRAIN_FLIP_WINDING = False;

type
  { @abstract(Raised when a tile cannot be read as terrain.) }
  ETerrainError = class(Exception);

  { @abstract(A point on the globe to draw from, and the conversion of
    places to kilometres east, down and north of it.)

    The point is at sea level. Local positions are those of a sphere, so
    the surface curves away from it. }
  TTerrainFrame = record
  private
    { Backing field for @link(Latitude). }
    FLatitude: Double;
    { Backing field for @link(Longitude). }
    FLongitude: Double;
    { The sine of the latitude. }
    FSinLat: Double;
    { The cosine of the latitude. }
    FCosLat: Double;
    { The sine of the longitude. }
    FSinLon: Double;
    { The cosine of the longitude. }
    FCosLon: Double;
    { The point's position from the Earth's centre, kilometres: towards
      latitude 0, longitude 0. }
    FOriginX: Double;
    { The same, towards latitude 0, longitude 90 east. }
    FOriginY: Double;
    { The same, towards the north pole. }
    FOriginZ: Double;

    { Turns a direction measured from the Earth's centre into one measured
      in the frame.
      @param(AX Towards latitude 0, longitude 0.)
      @param(AY Towards latitude 0, longitude 90 east.)
      @param(AZ Towards the north pole.)
      @returns(The same direction east (X), down (Y) and north (Z).) }
    function FromGlobe(AX, AY, AZ: Double): TPoint3D;
  public
    { A frame at a point.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @returns(The frame.) }
    class function Create(ALatitude, ALongitude: Double): TTerrainFrame; static;

    { Where a place lies from the point.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @param(AHeightKm Height above sea level, kilometres (already
        stretched, if heights are stretched).)
      @returns(Kilometres east (X), down (Y) and north (Z).) }
    function ToLocal(ALatitude, ALongitude, AHeightKm: Double): TPoint3D;

    { The place on the ground (at sea level) under a local position.
      @param(AX Kilometres east.)
      @param(AZ Kilometres north.)
      @param(ALatitude Its latitude, degrees.)
      @param(ALongitude Its longitude, degrees, -180 to 180.) }
    procedure ToGeo(AX, AZ: Double; out ALatitude, ALongitude: Double);

    { Where a local position is on the globe, height included: the exact
      inverse of @link(ToLocal).
      @param(APoint Kilometres east (X), down (Y) and north (Z).)
      @param(ALatitude Its latitude, degrees.)
      @param(ALongitude Its longitude, degrees, -180 to 180.)
      @param(AHeightKm Its height above sea level, kilometres (stretched,
        if heights are stretched).) }
    procedure ToGeoHeight(const APoint: TPoint3D; out ALatitude, ALongitude, AHeightKm: Double);

    { The ways east and north along the ground at a place, as local
      directions. Away from the frame's point they turn from the frame's
      own X and Z, as the meridians close together towards the poles.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @param(AEast The way east, one unit long.)
      @param(ANorth The way north, one unit long.) }
    procedure Directions(ALatitude, ALongitude: Double; out AEast, ANorth: TPoint3D);

    { The point's latitude, degrees. }
    property Latitude: Double read FLatitude;

    { The point's longitude, degrees. }
    property Longitude: Double read FLongitude;
  end;

  { @abstract(What a tile holds.) }
  TTerrainTileKind = (
    { Heights, downloaded: drawn as land. }
    tkLand,
    { No tile exists here: open sea, drawn flat at sea level. }
    tkSea,
    { A tile exists but is not downloaded: drawn flat and grey. }
    tkMissing);

  { @abstract(One image of a tile's heights.) }
  TTerrainLevel = record
    { Samples across (and down) this image; 0 for none. }
    Width: Integer;
    { Samples across the tile's full image, 3601 for ASTER GDEM. }
    FullWidth: Integer;
    { Heights in metres, row by row from the north-west; voids filled. }
    Heights: TArray<SmallInt>;

    { The height at a place in the tile, blended between the four nearest
      samples.
      @param(AX Arc-seconds east of the tile's west edge, 0 to 3600.)
      @param(AY Arc-seconds south of its north edge, 0 to 3600.)
      @returns(Metres; 0 if the image is empty.) }
    function Sample(AX, AY: Double): Single;
  end;

  { @abstract(A tile's heights, read when first needed.) }
  ITerrainTile = interface
    ['{6C1F2B7E-3D9A-4E55-9A0C-2F8B7D41C6A3}']
    { Reader for @link(South). @returns(The latitude of the south edge.) }
    function GetSouth: Integer;
    { Reader for @link(West). @returns(The longitude of the west edge.) }
    function GetWest: Integer;
    { Reader for @link(Kind). @returns(What the tile holds.) }
    function GetKind: TTerrainTileKind;

    { The coarsest image whose samples are no further apart than asked,
      read and its voids filled the first time it is wanted, then kept.
      Waits while another thread reads the same tile.
      @param(AStride Arc-seconds between the samples wanted.)
      @returns(The image; empty (width 0) for a tile that is not land.)
      @raises(EGeoTiffError if the file cannot be read.) }
    function Heights(AStride: Integer): TTerrainLevel;

    { The finest image read so far, without waiting or reading.
      @param(ALevel The image.)
      @returns(@false if none is read yet, or another thread is reading
        the tile.) }
    function TryFinestHeights(out ALevel: TTerrainLevel): Boolean;

    { The latitude of the tile's south edge. }
    property South: Integer read GetSouth;
    { The longitude of the tile's west edge, -180 to 179. }
    property West: Integer read GetWest;
    { What the tile holds. }
    property Kind: TTerrainTileKind read GetKind;
  end;

  { @abstract(A tile's heights, read from its @code(_dem.tif).) }
  TTerrainTile = class(TInterfacedObject, ITerrainTile)
  private
    { Backing field for @link(ITerrainTile.South). }
    FSouth: Integer;
    { Backing field for @link(ITerrainTile.West). }
    FWest: Integer;
    { Backing field for @link(ITerrainTile.Kind). }
    FKind: TTerrainTileKind;
    { The tile's @code(_dem.tif), for land. }
    FDemFile: string;
    { Held while reading, and while looking at @link(FLevels). }
    FLock: TObject;
    { The width of each image in the file, largest first as in the file;
      empty until the file is first opened. }
    FWidths: TArray<Integer>;
    { The images read so far, by their place in the file. }
    FLevels: TArray<TTerrainLevel>;

    { The image to read for a spacing of samples.
      @param(AStride Arc-seconds between samples wanted.)
      @returns(Its place in the file.) }
    function ChooseImage(AStride: Integer): Integer;
  public
    { A tile; nothing is read yet.
      @param(ASouth Latitude of its south edge.)
      @param(AWest Longitude of its west edge.)
      @param(AKind What it holds.)
      @param(ADemFile Its @code(_dem.tif), for land.) }
    constructor Create(ASouth, AWest: Integer; AKind: TTerrainTileKind; const ADemFile: string);

    { Frees the images. }
    destructor Destroy; override;

    { See @link(ITerrainTile.South). @returns(The latitude.) }
    function GetSouth: Integer;
    { See @link(ITerrainTile.West). @returns(The longitude.) }
    function GetWest: Integer;
    { See @link(ITerrainTile.Kind). @returns(The kind.) }
    function GetKind: TTerrainTileKind;
    { See @link(ITerrainTile.Heights).
      @param(AStride Arc-seconds between the samples wanted.)
      @returns(The image.) }
    function Heights(AStride: Integer): TTerrainLevel;
    { See @link(ITerrainTile.TryFinestHeights).
      @param(ALevel The image.)
      @returns(@true if there was one.) }
    function TryFinestHeights(out ALevel: TTerrainLevel): Boolean;
  end;

  { @abstract(A tile and its eight neighbours, for patches at its edges,
    whose normals look one sample beyond.)

    Index 4 is the tile itself; index (row + 1) * 3 + (column + 1) holds
    the neighbour that many tiles north (row -1) or south (row 1), and west
    (column -1) or east (column 1). A neighbour may be @nil. }
  TTerrainNeighbours = array[0..8] of ITerrainTile;

  { @abstract(One patch of the surface, ready to become a mesh.) }
  TTerrainPatch = record
    { Vertex positions, kilometres from the frame's point:
      @link(PATCH_GRID_VERTICES) of the surface, row by row from the
      north-west, then the skirt along the north, south, west and east
      edges, @link(PATCH_SIDE) each. }
    Positions: TArray<TPoint3D>;
    { Unit normals, pointing up (towards -Y). }
    Normals: TArray<TPoint3D>;
    { Vertex colours, shaded. }
    Colours: TArray<TAlphaColor>;
    { The smallest corner of the box holding every vertex. }
    BoxMin: TPoint3D;
    { The largest corner of that box. }
    BoxMax: TPoint3D;
    { The lowest height of the surface, metres. }
    MinHeight: Single;
    { The highest height of the surface, metres. }
    MaxHeight: Single;
    { Samples across the tile's image the heights came from; 0 for flat
      sea or a missing tile. }
    ImageWidth: Integer;
  end;

{ The deepest depth a detail allows.
  @param(ADetail Samples across a tile, from @link(TERRAIN_DETAILS).)
  @returns(0 to @link(TERRAIN_MAX_DEPTH).) }
function TerrainMaxDepth(ADetail: Integer): Integer;

{ Patches across a tile at a depth.
  @param(ADepth The depth.)
  @returns(1, 3, 6, 12, 24 or 48.) }
function NodesAcross(ADepth: Integer): Integer;

{ The size of a patch at a depth, north to south.
  @param(ADepth The depth.)
  @returns(Kilometres.) }
function NodeSizeKm(ADepth: Integer): Double;

{ Makes one patch, reading the heights it needs.
  @param(ATiles The patch's tile and its neighbours.)
  @param(ADepth Its depth, 0 to @link(TERRAIN_MAX_DEPTH).)
  @param(AX Its column in the tile at that depth, 0 at the west.)
  @param(AY Its row, 0 at the north.)
  @param(AFrame Where positions are measured from.)
  @param(AExaggeration How many times to stretch heights; 1 is true
    scale.)
  @returns(The patch.)
  @raises(EGeoTiffError if a tile cannot be read.) }
function BuildTerrainPatch(const ATiles: TTerrainNeighbours; ADepth, AX, AY: Integer;
  const AFrame: TTerrainFrame; AExaggeration: Single): TTerrainPatch;

{ The triangles every patch is drawn with: three vertex indices each, for
  the vertices of @link(TTerrainPatch.Positions).
  @returns(3 x @link(PATCH_TRIANGLES) indices.) }
function TerrainPatchIndices: TArray<Integer>;

{ The colour for a height, before shading.
  @param(AMetres The height; 0 or below is water, as ASTER GDEM marks the
    sea and lakes at sea level.)
  @returns(The colour.) }
function HeightColour(AMetres: Single): TAlphaColor;

implementation

uses
  System.Math,
  GDEMGeoTiff;

type
  { A point of the colour scale: a height and its colour. }
  THeightStop = record
    { The height, in metres. }
    Metres: Single;
    { Red, 0 to 255. }
    R: Byte;
    { Green, 0 to 255. }
    G: Byte;
    { Blue, 0 to 255. }
    B: Byte;
  end;

const
  { The colour scale from sea level up, colours between stops blended. }
  HEIGHT_STOPS: array[0..7] of THeightStop = (
    (Metres: 0;    R: 70;  G: 120; B: 60),
    (Metres: 200;  R: 110; G: 160; B: 80),
    (Metres: 500;  R: 200; G: 195; B: 115),
    (Metres: 1000; R: 175; G: 135; B: 80),
    (Metres: 2000; R: 135; G: 110; B: 95),
    (Metres: 3000; R: 165; G: 160; B: 155),
    (Metres: 4500; R: 250; G: 250; B: 250),
    (Metres: 9000; R: 255; G: 255; B: 255));

  { The colour of water. }
  WATER_COLOUR: TAlphaColor = $FF2E6FAD;

  { The colour of a tile that exists but is not downloaded. }
  MISSING_COLOUR: TAlphaColor = $FF6A6F78;

  { The share of a colour kept in full shadow. }
  SHADE_AMBIENT = 0.35;

  { Most passes made filling voids from their neighbours; what is left
    after that becomes sea level. }
  MAX_VOID_PASSES = 64;

  { How far a skirt hangs below its edge, in cells of the patch's own
    size, times the height stretch: deep enough to meet a neighbour two
    depths coarser on a steep slope. }
  SKIRT_CELLS = 1.6;

  { The least a skirt hangs, kilometres. }
  SKIRT_MIN_KM = 0.02;

  { The most a skirt hangs, kilometres. }
  SKIRT_MAX_KM = 10.0;

var
  { The shared triangles, made once at start-up. }
  GPatchIndices: TArray<Integer>;

function HeightColour(AMetres: Single): TAlphaColor;
var
  I: Integer;
  LT: Single;
  LRec: TAlphaColorRec;
begin
  if AMetres <= 0 then
    Exit(WATER_COLOUR);
  I := 0;
  while (I < High(HEIGHT_STOPS) - 1) and (AMetres > HEIGHT_STOPS[I + 1].Metres) do
    Inc(I);
  LT := (AMetres - HEIGHT_STOPS[I].Metres) /
    (HEIGHT_STOPS[I + 1].Metres - HEIGHT_STOPS[I].Metres);
  if LT > 1 then
    LT := 1;
  LRec.A := 255;
  LRec.R := Round(HEIGHT_STOPS[I].R + (HEIGHT_STOPS[I + 1].R - HEIGHT_STOPS[I].R) * LT);
  LRec.G := Round(HEIGHT_STOPS[I].G + (HEIGHT_STOPS[I + 1].G - HEIGHT_STOPS[I].G) * LT);
  LRec.B := Round(HEIGHT_STOPS[I].B + (HEIGHT_STOPS[I + 1].B - HEIGHT_STOPS[I].B) * LT);
  Result := LRec.Color;
end;

{ A colour shaded by the light falling on it.
  @param(AColour The colour.)
  @param(AShade 0 to 1.)
  @returns(The colour darkened.) }
function Shaded(AColour: TAlphaColor; AShade: Single): TAlphaColor;
var
  LRec: TAlphaColorRec;
begin
  LRec.Color := AColour;
  LRec.R := Round(LRec.R * AShade);
  LRec.G := Round(LRec.G * AShade);
  LRec.B := Round(LRec.B * AShade);
  Result := LRec.Color;
end;

function TerrainMaxDepth(ADetail: Integer): Integer;
var
  LStride: Double;
  LDepth: Integer;
begin
  LStride := TILE_ARCSEC / Max(ADetail - 1, 1);
  for LDepth := TERRAIN_MAX_DEPTH downto 0 do
    if NODE_ARCSEC[LDepth] / PATCH_CELLS >= LStride - 1E-6 then
      Exit(LDepth);
  Result := 0;
end;

function NodesAcross(ADepth: Integer): Integer;
begin
  Result := TILE_ARCSEC div NODE_ARCSEC[ADepth];
end;

function NodeSizeKm(ADepth: Integer): Double;
begin
  Result := NODE_ARCSEC[ADepth] * KM_PER_ARCSEC;
end;

{ TTerrainFrame }

class function TTerrainFrame.Create(ALatitude, ALongitude: Double): TTerrainFrame;
begin
  Result.FLatitude := ALatitude;
  Result.FLongitude := ALongitude;
  SinCos(DegToRad(ALatitude), Result.FSinLat, Result.FCosLat);
  SinCos(DegToRad(ALongitude), Result.FSinLon, Result.FCosLon);
  Result.FOriginX := EARTH_RADIUS_KM * Result.FCosLat * Result.FCosLon;
  Result.FOriginY := EARTH_RADIUS_KM * Result.FCosLat * Result.FSinLon;
  Result.FOriginZ := EARTH_RADIUS_KM * Result.FSinLat;
end;

function TTerrainFrame.ToLocal(ALatitude, ALongitude, AHeightKm: Double): TPoint3D;
var
  LSinLat, LCosLat, LSinLon, LCosLon, LRadius, LX, LY, LZ: Double;
begin
  SinCos(DegToRad(ALatitude), LSinLat, LCosLat);
  SinCos(DegToRad(ALongitude), LSinLon, LCosLon);
  LRadius := EARTH_RADIUS_KM + AHeightKm;
  // From the Earth's centre, less the frame's point
  LX := LRadius * LCosLat * LCosLon - FOriginX;
  LY := LRadius * LCosLat * LSinLon - FOriginY;
  LZ := LRadius * LSinLat - FOriginZ;
  // East, then down (up is -Y), then north
  Result.X := -FSinLon * LX + FCosLon * LY;
  Result.Y := -(FCosLat * FCosLon * LX + FCosLat * FSinLon * LY + FSinLat * LZ);
  Result.Z := -FSinLat * FCosLon * LX - FSinLat * FSinLon * LY + FCosLat * LZ;
end;

procedure TTerrainFrame.ToGeo(AX, AZ: Double; out ALatitude, ALongitude: Double);
var
  LUp, LX, LY, LZ: Double;
begin
  // The point at that distance east and north whose height brings it to
  // the surface of the sphere
  LUp := Sqrt(Max(Sqr(EARTH_RADIUS_KM) - Sqr(AX) - Sqr(AZ), 0)) - EARTH_RADIUS_KM;
  LX := FOriginX - FSinLon * AX - FSinLat * FCosLon * AZ + FCosLat * FCosLon * LUp;
  LY := FOriginY + FCosLon * AX - FSinLat * FSinLon * AZ + FCosLat * FSinLon * LUp;
  LZ := FOriginZ + FCosLat * AZ + FSinLat * LUp;
  ALatitude := RadToDeg(ArcTan2(LZ, Sqrt(Sqr(LX) + Sqr(LY))));
  ALongitude := RadToDeg(ArcTan2(LY, LX));
end;

procedure TTerrainFrame.ToGeoHeight(const APoint: TPoint3D; out ALatitude, ALongitude,
  AHeightKm: Double);
var
  LUp, LX, LY, LZ: Double;
begin
  // As ToGeo, but with the point's own height: up is -Y
  LUp := -APoint.Y;
  LX := FOriginX - FSinLon * APoint.X - FSinLat * FCosLon * APoint.Z + FCosLat * FCosLon * LUp;
  LY := FOriginY + FCosLon * APoint.X - FSinLat * FSinLon * APoint.Z + FCosLat * FSinLon * LUp;
  LZ := FOriginZ + FCosLat * APoint.Z + FSinLat * LUp;
  ALatitude := RadToDeg(ArcTan2(LZ, Sqrt(Sqr(LX) + Sqr(LY))));
  ALongitude := RadToDeg(ArcTan2(LY, LX));
  AHeightKm := Sqrt(Sqr(LX) + Sqr(LY) + Sqr(LZ)) - EARTH_RADIUS_KM;
end;

function TTerrainFrame.FromGlobe(AX, AY, AZ: Double): TPoint3D;
begin
  // The rotation of ToLocal, without the move to the frame's point
  Result.X := -FSinLon * AX + FCosLon * AY;
  Result.Y := -(FCosLat * FCosLon * AX + FCosLat * FSinLon * AY + FSinLat * AZ);
  Result.Z := -FSinLat * FCosLon * AX - FSinLat * FSinLon * AY + FCosLat * AZ;
end;

procedure TTerrainFrame.Directions(ALatitude, ALongitude: Double; out AEast, ANorth: TPoint3D);
var
  LSinLat, LCosLat, LSinLon, LCosLon: Double;
begin
  SinCos(DegToRad(ALatitude), LSinLat, LCosLat);
  SinCos(DegToRad(ALongitude), LSinLon, LCosLon);
  AEast := FromGlobe(-LSinLon, LCosLon, 0);
  ANorth := FromGlobe(-LSinLat * LCosLon, -LSinLat * LSinLon, LCosLat);
end;

{ TTerrainLevel }

function TTerrainLevel.Sample(AX, AY: Double): Single;
var
  LScale, LFX, LFY, LTX, LTY: Double;
  LX0, LY0, LIndex: Integer;
begin
  if Width < 2 then
    Exit(0);
  // Arc-seconds to the full image's samples, then to this image's: each
  // image's pixels share out the same area (pixel is area)
  LScale := (FullWidth - 1) / TILE_ARCSEC;
  LFX := (AX * LScale + 0.5) * Width / FullWidth - 0.5;
  LFY := (AY * LScale + 0.5) * Width / FullWidth - 0.5;
  LFX := EnsureRange(LFX, 0, Width - 1);
  LFY := EnsureRange(LFY, 0, Width - 1);
  LX0 := Min(Trunc(LFX), Width - 2);
  LY0 := Min(Trunc(LFY), Width - 2);
  LTX := LFX - LX0;
  LTY := LFY - LY0;
  LIndex := LY0 * Width + LX0;
  Result :=
    (Heights[LIndex] * (1 - LTX) + Heights[LIndex + 1] * LTX) * (1 - LTY) +
    (Heights[LIndex + Width] * (1 - LTX) + Heights[LIndex + Width + 1] * LTX) * LTY;
end;

{ Fills voids with the mean of their known neighbours, pass after pass, so
  a hole closes in from its edges; anything still unknown becomes 0.
  @param(AHeights The heights, row by row.)
  @param(AWidth Samples across, and down.) }
procedure FillVoids(var AHeights: TArray<SmallInt>; AWidth: Integer);
var
  LKnown, LNext: TArray<Boolean>;
  LLeft, LPass, LRow, LColumn, LDX, LDY, LCount, LIndex, LOther: Integer;
  LSum: Integer;
begin
  SetLength(LKnown, Length(AHeights));
  LLeft := 0;
  for LIndex := 0 to High(AHeights) do
  begin
    LKnown[LIndex] := AHeights[LIndex] <> TERRAIN_VOID;
    if not LKnown[LIndex] then
      Inc(LLeft);
  end;
  LPass := 0;
  while (LLeft > 0) and (LPass < MAX_VOID_PASSES) do
  begin
    LNext := Copy(LKnown);
    for LRow := 0 to AWidth - 1 do
      for LColumn := 0 to AWidth - 1 do
      begin
        LIndex := LRow * AWidth + LColumn;
        if LKnown[LIndex] then
          Continue;
        LSum := 0;
        LCount := 0;
        for LDY := -1 to 1 do
          for LDX := -1 to 1 do
            if InRange(LColumn + LDX, 0, AWidth - 1) and InRange(LRow + LDY, 0, AWidth - 1) then
            begin
              LOther := (LRow + LDY) * AWidth + LColumn + LDX;
              if LKnown[LOther] then
              begin
                Inc(LSum, AHeights[LOther]);
                Inc(LCount);
              end;
            end;
        if LCount > 0 then
        begin
          AHeights[LIndex] := Round(LSum / LCount);
          LNext[LIndex] := True;
          Dec(LLeft);
        end;
      end;
    LKnown := LNext;
    Inc(LPass);
  end;
  if LLeft > 0 then
    for LIndex := 0 to High(LKnown) do
      if not LKnown[LIndex] then
        AHeights[LIndex] := 0;
end;

{ TTerrainTile }

constructor TTerrainTile.Create(ASouth, AWest: Integer; AKind: TTerrainTileKind;
  const ADemFile: string);
begin
  inherited Create;
  FSouth := ASouth;
  FWest := AWest;
  FKind := AKind;
  FDemFile := ADemFile;
  FLock := TObject.Create;
end;

destructor TTerrainTile.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TTerrainTile.GetSouth: Integer;
begin
  Result := FSouth;
end;

function TTerrainTile.GetWest: Integer;
begin
  Result := FWest;
end;

function TTerrainTile.GetKind: TTerrainTileKind;
begin
  Result := FKind;
end;

function TTerrainTile.ChooseImage(AStride: Integer): Integer;
var
  I: Integer;
  LSpacing: Double;
begin
  // The full image, unless a smaller one is fine enough: the smaller the
  // better
  Result := 0;
  for I := 1 to High(FWidths) do
    if FWidths[I] >= 2 then
    begin
      // Arc-seconds between this image's samples
      LSpacing := TILE_ARCSEC * FWidths[0] / ((FWidths[0] - 1) * FWidths[I]);
      if (LSpacing <= AStride * (1 + 1E-6)) and (FWidths[I] < FWidths[Result]) then
        Result := I;
    end;
end;

function TTerrainTile.Heights(AStride: Integer): TTerrainLevel;
var
  LTiff: TGeoTiff;
  I, LImage: Integer;
begin
  Result := Default(TTerrainLevel);
  if FKind <> tkLand then
    Exit;
  TMonitor.Enter(FLock);
  try
    LTiff := nil;
    try
      if FWidths = nil then
      begin
        LTiff := TGeoTiff.Create(FDemFile);
        SetLength(FWidths, LTiff.ImageCount);
        for I := 0 to LTiff.ImageCount - 1 do
          FWidths[I] := LTiff.Images[I].Width;
        SetLength(FLevels, LTiff.ImageCount);
        if (Length(FWidths) = 0) or (FWidths[0] < 2) then
          raise ETerrainError.CreateFmt('%s holds no heights', [ExtractFileName(FDemFile)]);
      end;
      LImage := ChooseImage(AStride);
      if FLevels[LImage].Heights = nil then
      begin
        if LTiff = nil then
          LTiff := TGeoTiff.Create(FDemFile);
        FLevels[LImage].Width := FWidths[LImage];
        FLevels[LImage].FullWidth := FWidths[0];
        FLevels[LImage].Heights := LTiff.ReadInt16(LImage);
        if Length(FLevels[LImage].Heights) <> Sqr(FWidths[LImage]) then
        begin
          FLevels[LImage].Heights := nil;
          raise ETerrainError.CreateFmt('%s: image %d is not square',
            [ExtractFileName(FDemFile), LImage]);
        end;
        FillVoids(FLevels[LImage].Heights, FWidths[LImage]);
      end;
      Result := FLevels[LImage];
    finally
      LTiff.Free;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TTerrainTile.TryFinestHeights(out ALevel: TTerrainLevel): Boolean;
var
  I: Integer;
begin
  ALevel := Default(TTerrainLevel);
  Result := False;
  if (FKind <> tkLand) or not TMonitor.TryEnter(FLock) then
    Exit;
  try
    for I := 0 to High(FLevels) do
      if (FLevels[I].Heights <> nil) and (FLevels[I].Width > ALevel.Width) then
      begin
        ALevel := FLevels[I];
        Result := True;
      end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ Patches }

function BuildTerrainPatch(const ATiles: TTerrainNeighbours; ADepth, AX, AY: Integer;
  const AFrame: TTerrainFrame; AExaggeration: Single): TTerrainPatch;
const
  // Samples along a side with the ring beyond the edges, for normals
  GRID = PATCH_SIDE + 2;
var
  LLevels: array[0..8] of TTerrainLevel;
  LTried: array[0..8] of Boolean;
  LSize, LStride, LRow, LColumn, LIndex, LEdge, K: Integer;
  LNorth, LWest: Integer;
  LSinLat, LCosLat, LSinLon, LCosLon: array[0..GRID - 1] of Double;
  LHeights: array of Single;
  LGrid: array of TPoint3D;
  LRadius, LEX, LEY, LEZ, LSkirt, LShade: Double;
  LEast, LAhead, LNormal, LSun, LPoint: TPoint3D;
  LDot: Single;
  LFlat: Boolean;
  LFlatColour: TAlphaColor;
  LBoxMin, LBoxMax: TPoint3D;

  { The height at a sample, in this tile or, one sample beyond its edges,
    in a neighbour; the tile's own edge where there is no neighbour.
    @param(AGX Arc-seconds east of the tile's west edge.)
    @param(AGY Arc-seconds south of its north edge.)
    @returns(Metres.) }
  function HeightAt(AGX, AGY: Integer): Single;
  var
    LTileX, LTileY, LSlot: Integer;
  begin
    LTileX := 0;
    LTileY := 0;
    if AGX < 0 then
    begin
      LTileX := -1;
      Inc(AGX, TILE_ARCSEC);
    end
    else if AGX > TILE_ARCSEC then
    begin
      LTileX := 1;
      Dec(AGX, TILE_ARCSEC);
    end;
    if AGY < 0 then
    begin
      LTileY := -1;
      Inc(AGY, TILE_ARCSEC);
    end
    else if AGY > TILE_ARCSEC then
    begin
      LTileY := 1;
      Dec(AGY, TILE_ARCSEC);
    end;
    LSlot := (LTileY + 1) * 3 + LTileX + 1;
    if (LSlot <> 4) and ((ATiles[LSlot] = nil) or (ATiles[LSlot].Kind <> tkLand)) then
    begin
      // No heights beyond this edge: repeat the edge
      LSlot := 4;
      AGX := EnsureRange(AGX + LTileX * TILE_ARCSEC, 0, TILE_ARCSEC);
      AGY := EnsureRange(AGY + LTileY * TILE_ARCSEC, 0, TILE_ARCSEC);
    end;
    if (ATiles[LSlot] = nil) or (ATiles[LSlot].Kind <> tkLand) then
      Exit(0);
    if not LTried[LSlot] then
    begin
      LLevels[LSlot] := ATiles[LSlot].Heights(LStride);
      LTried[LSlot] := True;
    end;
    Result := LLevels[LSlot].Sample(AGX, AGY);
  end;

  { Updates the patch's box with a position.
    @param(APoint The position.) }
  procedure Grow(const APoint: TPoint3D);
  begin
    LBoxMin.X := Min(LBoxMin.X, APoint.X);
    LBoxMin.Y := Min(LBoxMin.Y, APoint.Y);
    LBoxMin.Z := Min(LBoxMin.Z, APoint.Z);
    LBoxMax.X := Max(LBoxMax.X, APoint.X);
    LBoxMax.Y := Max(LBoxMax.Y, APoint.Y);
    LBoxMax.Z := Max(LBoxMax.Z, APoint.Z);
  end;

  { The surface vertex on an edge.
    @param(AEdge 0 north, 1 south, 2 west, 3 east.)
    @param(AStep 0 to @link(PATCH_CELLS), west to east or north to
      south.)
    @returns(Its index.) }
  function EdgeVertex(AEdge, AStep: Integer): Integer;
  begin
    case AEdge of
      0: Result := AStep;
      1: Result := PATCH_CELLS * PATCH_SIDE + AStep;
      2: Result := AStep * PATCH_SIDE;
    else
      Result := AStep * PATCH_SIDE + PATCH_CELLS;
    end;
  end;

begin
  Result := Default(TTerrainPatch);
  if (ATiles[4] = nil) or not InRange(ADepth, 0, TERRAIN_MAX_DEPTH) then
    raise ETerrainError.Create('A patch was asked for with no tile');
  for K := 0 to 8 do
    LTried[K] := False;
  LSize := NODE_ARCSEC[ADepth];
  LStride := LSize div PATCH_CELLS;
  LNorth := ATiles[4].South + 1;
  LWest := ATiles[4].West;
  LFlat := ATiles[4].Kind <> tkLand;
  if ATiles[4].Kind = tkSea then
    LFlatColour := WATER_COLOUR
  else
    LFlatColour := MISSING_COLOUR;

  // Each row's latitude and each column's longitude, with the ring beyond
  for K := 0 to GRID - 1 do
  begin
    SinCos(DegToRad(LNorth - (AY * LSize + (K - 1) * LStride) / TILE_ARCSEC),
      LSinLat[K], LCosLat[K]);
    SinCos(DegToRad(LWest + (AX * LSize + (K - 1) * LStride) / TILE_ARCSEC),
      LSinLon[K], LCosLon[K]);
  end;

  // Heights and positions of every sample, ring included
  SetLength(LHeights, GRID * GRID);
  SetLength(LGrid, GRID * GRID);
  for LRow := 0 to GRID - 1 do
    for LColumn := 0 to GRID - 1 do
    begin
      LIndex := LRow * GRID + LColumn;
      if LFlat then
        LHeights[LIndex] := 0
      else
        LHeights[LIndex] := HeightAt(AX * LSize + (LColumn - 1) * LStride,
          AY * LSize + (LRow - 1) * LStride);
      // As TTerrainFrame.ToLocal, with the sines and cosines worked out
      // once a row and a column
      LRadius := EARTH_RADIUS_KM + LHeights[LIndex] * AExaggeration / 1000;
      LEX := LRadius * LCosLat[LRow] * LCosLon[LColumn] - AFrame.FOriginX;
      LEY := LRadius * LCosLat[LRow] * LSinLon[LColumn] - AFrame.FOriginY;
      LEZ := LRadius * LSinLat[LRow] - AFrame.FOriginZ;
      LGrid[LIndex].X := -AFrame.FSinLon * LEX + AFrame.FCosLon * LEY;
      LGrid[LIndex].Y := -(AFrame.FCosLat * AFrame.FCosLon * LEX +
        AFrame.FCosLat * AFrame.FSinLon * LEY + AFrame.FSinLat * LEZ);
      LGrid[LIndex].Z := -AFrame.FSinLat * AFrame.FCosLon * LEX -
        AFrame.FSinLat * AFrame.FSinLon * LEY + AFrame.FCosLat * LEZ;
    end;

  if not LFlat and LTried[4] then
    Result.ImageWidth := LLevels[4].Width;
  SetLength(Result.Positions, PATCH_VERTICES);
  SetLength(Result.Normals, PATCH_VERTICES);
  SetLength(Result.Colours, PATCH_VERTICES);
  LBoxMin := Point3D(MaxSingle, MaxSingle, MaxSingle);
  LBoxMax := Point3D(-MaxSingle, -MaxSingle, -MaxSingle);
  Result.MinHeight := MaxSingle;
  Result.MaxHeight := -MaxSingle;
  // Towards the sun, in the north-west, 45 degrees up: up is -Y, north +Z
  LSun := Point3D(-1, -Sqrt(2), 1) * 0.5;

  // The surface: normals across the neighbouring samples
  K := 0;
  for LRow := 1 to PATCH_SIDE do
    for LColumn := 1 to PATCH_SIDE do
    begin
      LIndex := LRow * GRID + LColumn;
      LEast := LGrid[LIndex + 1] - LGrid[LIndex - 1];
      LAhead := LGrid[LIndex - GRID] - LGrid[LIndex + GRID];
      LNormal := LEast.CrossProduct(LAhead).Normalize;
      if LNormal.Y > 0 then
        LNormal := LNormal * -1;
      Result.Positions[K] := LGrid[LIndex];
      Result.Normals[K] := LNormal;
      LDot := LNormal.DotProduct(LSun);
      if LDot < 0 then
        LDot := 0;
      LShade := SHADE_AMBIENT + (1 - SHADE_AMBIENT) * LDot;
      if LFlat then
        Result.Colours[K] := Shaded(LFlatColour, LShade)
      else
        Result.Colours[K] := Shaded(HeightColour(LHeights[LIndex]), LShade);
      Result.MinHeight := Min(Result.MinHeight, LHeights[LIndex]);
      Result.MaxHeight := Max(Result.MaxHeight, LHeights[LIndex]);
      Grow(LGrid[LIndex]);
      Inc(K);
    end;

  // The skirt: each edge again, lower down
  LSkirt := EnsureRange(SKIRT_CELLS * LStride * KM_PER_ARCSEC * AExaggeration + SKIRT_MIN_KM,
    SKIRT_MIN_KM, SKIRT_MAX_KM);
  for LEdge := 0 to 3 do
    for LColumn := 0 to PATCH_CELLS do
    begin
      LIndex := EdgeVertex(LEdge, LColumn);
      LPoint := Result.Positions[LIndex];
      LPoint.Y := LPoint.Y + LSkirt;
      Result.Positions[K] := LPoint;
      Result.Normals[K] := Result.Normals[LIndex];
      Result.Colours[K] := Result.Colours[LIndex];
      Grow(LPoint);
      Inc(K);
    end;
  Result.BoxMin := LBoxMin;
  Result.BoxMax := LBoxMax;
end;

{ Makes the shared triangles. }
procedure MakePatchIndices;
var
  LRow, LColumn, LEdge, LStep, K: Integer;
  LNW, LNE, LSW, LSE, LE0, LE1, LS0, LS1: Integer;

  { Adds a triangle.
    @param(A First vertex.)
    @param(B Second vertex.)
    @param(C Third vertex.) }
  procedure Add(A, B, C: Integer);
  begin
    GPatchIndices[K] := A;
    GPatchIndices[K + 1] := B;
    GPatchIndices[K + 2] := C;
    Inc(K, 3);
  end;

  { The surface vertex on an edge; as in BuildTerrainPatch.
    @param(AEdge 0 north, 1 south, 2 west, 3 east.)
    @param(AStep 0 to PATCH_CELLS.)
    @returns(Its index.) }
  function EdgeVertex(AEdge, AStep: Integer): Integer;
  begin
    case AEdge of
      0: Result := AStep;
      1: Result := PATCH_CELLS * PATCH_SIDE + AStep;
      2: Result := AStep * PATCH_SIDE;
    else
      Result := AStep * PATCH_SIDE + PATCH_CELLS;
    end;
  end;

begin
  SetLength(GPatchIndices, PATCH_TRIANGLES * 3);
  K := 0;
  // Two triangles a cell, clockwise seen from above with north up the
  // screen: north-west, north-east, south-east; north-west, south-east,
  // south-west
  for LRow := 0 to PATCH_CELLS - 1 do
    for LColumn := 0 to PATCH_CELLS - 1 do
    begin
      LNW := LRow * PATCH_SIDE + LColumn;
      LNE := LNW + 1;
      LSW := LNW + PATCH_SIDE;
      LSE := LSW + 1;
      if TERRAIN_FLIP_WINDING then
      begin
        Add(LNW, LSE, LNE);
        Add(LNW, LSW, LSE);
      end
      else
      begin
        Add(LNW, LNE, LSE);
        Add(LNW, LSE, LSW);
      end;
    end;
  // The skirts, wound both ways, so they show from either side
  for LEdge := 0 to 3 do
    for LStep := 0 to PATCH_CELLS - 1 do
    begin
      LE0 := EdgeVertex(LEdge, LStep);
      LE1 := EdgeVertex(LEdge, LStep + 1);
      LS0 := PATCH_GRID_VERTICES + LEdge * PATCH_SIDE + LStep;
      LS1 := LS0 + 1;
      Add(LE0, LE1, LS1);
      Add(LE0, LS1, LS0);
      Add(LE0, LS1, LE1);
      Add(LE0, LS0, LS1);
    end;
end;

function TerrainPatchIndices: TArray<Integer>;
begin
  Result := GPatchIndices;
end;

initialization
  MakePatchIndices;

end.
