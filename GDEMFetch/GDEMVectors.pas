{ @abstract(Country borders, coastlines and country outlines for the world
  map.)

  The data comes from Natural Earth (@url(https://www.naturalearthdata.com)),
  which is in the public domain, at two levels of detail: 1:110m for the
  whole world and 1:50m for closer views. @code(tools/build_vectors.py)
  converts its GeoJSON files into the compact file
  @code(maps/world_vectors.bin), which is linked into the program as the
  @link(WORLD_VECTORS_RESOURCE) RCDATA resource, so nothing is deployed and
  no JSON is read at start-up.

  The file holds five layers (see @link(TWorldVectors)):
  @unorderedList(
    @item(@code(borders110) and @code(borders50): land borders between
      countries, as lines, so a shared border is drawn once and coasts are
      not drawn as borders;)
    @item(@code(coast110) and @code(coast50): coastlines, as lines;)
    @item(@code(countries50): each country's outline, as closed rings, with
      its name, used to name the country under the mouse pointer.)
  )

  File format, all numbers little-endian:
  @preformatted(
'GDVC'                magic
UInt16 version        1
UInt16 layer count
for each layer:
  UInt8  kind         1 = lines, 2 = areas (closed rings)
  UInt8  name length, then the name in ASCII
  UInt32 feature count
  for each feature:
    UInt16 name length, then the name in UTF-8 (empty for lines)
    UInt32 part count
    for each part (a line, or a ring of an area):
      UInt32 point count
      Int32 lon, Int32 lat of the first point, in thousandths of a degree
      for each further point:
        Int16 dlon, Int16 dlat, the change from the previous point; or
        Int16 -32768 then Int32 lon, Int32 lat of the point itself
  )

  Natural Earth splits everything at the 180 degree meridian, so no line or
  ring crosses it. Borders are shown as they are on the ground, which is
  Natural Earth's default for disputed areas.

  This unit has no FMX dependency. }
unit GDEMVectors;

interface

uses
  System.SysUtils, System.Classes, System.Types,
  GDEMTiles, GDEMTileIndex;

const
  { Name of the RCDATA resource holding @code(maps/world_vectors.bin). }
  WORLD_VECTORS_RESOURCE = 'WORLDVECTORS';

  { First four bytes of the file. }
  VECTORS_MAGIC: array[0..3] of AnsiChar = ('G', 'D', 'V', 'C');

  { The file version this unit reads. }
  VECTORS_VERSION = 1;

  { Points are stored in these units per degree. }
  VECTORS_UNITS_PER_DEGREE = 1000;

type
  { @abstract(Raised when vector data cannot be read.) }
  EVectorError = class(Exception);

  { What a layer's parts are. }
  TGeoLayerKind = (
    { Open lines, such as coastlines. }
    gkLines,
    { Closed rings outlining areas, such as countries. A point is inside a
      feature when it is inside an odd number of its rings, so holes (a
      country within a country) work without being marked. }
    gkAreas
  );

  { @abstract(One line, or one ring of an area, with its bounds.) }
  TGeoPart = record
    { The points: X is longitude and Y latitude, in degrees. }
    Points: TArray<TPointF>;
    { Bounds of @link(Points): Left is west, Right east, Top south and
      Bottom north (Top is the smaller latitude). }
    Bounds: TRectF;
  end;

  { @abstract(A named group of parts, such as one country.) }
  TGeoFeature = record
    { The name, such as @code(France); empty for lines. }
    Name: string;
    { The lines or rings. }
    Parts: TArray<TGeoPart>;
    { Bounds of all its parts, laid out as in @link(TGeoPart.Bounds). }
    Bounds: TRectF;
  end;

  { @abstract(One layer of the vector data.) }
  TGeoLayer = class
  private
    { Backing field for @link(Kind). }
    FKind: TGeoLayerKind;
    { Backing field for @link(Name). }
    FName: string;
    { Backing field for @link(Features). }
    FFeatures: TArray<TGeoFeature>;
    { Backing field for @link(PointCount). }
    FPointCount: Integer;
  public
    { Reads one layer from a stream positioned at its start.
      @param(AReader Reader over the vector file.)
      @raises(EVectorError if the layer is malformed.) }
    constructor CreateFromReader(AReader: TBinaryReader);

    { Finds the feature an area layer has at a point.
      @param(ALat Latitude, in degrees.)
      @param(ALon Longitude, from -180 to 180.)
      @returns(The feature's index in @link(Features), or -1 if the point
        is in none, or this is a line layer.) }
    function FeatureAt(ALat, ALon: Double): Integer;

    { Adds every one-degree tile an area feature touches: each tile its
      outline passes through, even at a corner, and each tile whose centre
      lies inside it. So the tiles along a border or coast are included
      even when only a sliver of the country is in them, and an island
      smaller than a tile still gives its tile. Tiles outside ASTER GDEM
      coverage (@code(GDEM_MIN_LAT) to @code(GDEM_MAX_LAT)) are left out.
      Does nothing for a line layer.
      @param(AFeature The feature's index in @link(Features).)
      @param(ATiles Receives the tiles; tiles already in it are kept.) }
    procedure AddFeatureTiles(AFeature: Integer; ATiles: TTileIndex);

    { Whether the parts are lines or rings. }
    property Kind: TGeoLayerKind read FKind;

    { The layer's name in the file, such as @code(coast50). }
    property Name: string read FName;

    { The features. Line layers hold a single unnamed feature. }
    property Features: TArray<TGeoFeature> read FFeatures;

    { Total number of points, for the log. }
    property PointCount: Integer read FPointCount;
  end;

  { How much detail to draw. }
  TGeoDetail = (
    { 1:110m, for the whole world or most of it. }
    gdCoarse,
    { 1:50m, for closer views. }
    gdFine
  );

  { @abstract(The borders, coastlines and countries, loaded from the
    vector file.) }
  TWorldVectors = class
  private
    { The layers, owned. }
    FLayers: TArray<TGeoLayer>;

    { Finds a layer by name.
      @param(AName The layer's name in the file.)
      @returns(The layer, or @nil if the file has none of that name.) }
    function LayerNamed(const AName: string): TGeoLayer;
  public
    { Frees the layers. }
    destructor Destroy; override;

    { Reads the whole vector file, replacing anything loaded before.
      @param(AStream Stream positioned at the start of the file.)
      @raises(EVectorError if it is not a vector file this unit can read.) }
    procedure LoadFromStream(AStream: TStream);

    { Reads the vector file from the program's
      @link(WORLD_VECTORS_RESOURCE) resource.
      @raises(EResNotFound if the program has no such resource.)
      @raises(EVectorError if it cannot be read.) }
    procedure LoadFromResource;

    { The land borders at a level of detail.
      @param(ADetail Which level.)
      @returns(The layer, or @nil if none is loaded.) }
    function Borders(ADetail: TGeoDetail): TGeoLayer;

    { The coastlines at a level of detail.
      @param(ADetail Which level.)
      @returns(The layer, or @nil if none is loaded.) }
    function Coastlines(ADetail: TGeoDetail): TGeoLayer;

    { The countries, for naming places.
      @returns(The layer, or @nil if none is loaded.) }
    function Countries: TGeoLayer;

    { Names the country at a point.
      @param(ALat Latitude, in degrees.)
      @param(ALon Longitude, in degrees; wrapped into -180 to 180.)
      @returns(The country's name, or an empty string over the sea or when
        nothing is loaded.) }
    function CountryAt(ALat, ALon: Double): string;

    { Finds the country at a point, for @link(AddCountryTiles).
      @param(ALat Latitude, in degrees.)
      @param(ALon Longitude, in degrees; wrapped into -180 to 180.)
      @returns(The country's index in @link(Countries), or -1 over the sea
        or when nothing is loaded.) }
    function CountryIndexAt(ALat, ALon: Double): Integer;

    { Adds every tile a country touches; see
      @link(TGeoLayer.AddFeatureTiles).
      @param(ACountry The country's index, from @link(CountryIndexAt).)
      @param(ATiles Receives the tiles.) }
    procedure AddCountryTiles(ACountry: Integer; ATiles: TTileIndex);

    { A country's name.
      @param(ACountry The country's index, from @link(CountryIndexAt).)
      @returns(The name, or an empty string if there is no such country.) }
    function CountryName(ACountry: Integer): string;

    { Describes what is loaded, for the log.
      @returns(Such as "5 layers, 187,892 points".) }
    function Describe: string;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  // RT_RCDATA; other platforms have it in System.Types
  Winapi.Windows,
  {$ENDIF}
  System.Math, System.Generics.Collections;

const
  { Marks a point stored whole rather than as a change. }
  ESCAPE_DELTA = -32768;

  { Layer names in the file. }
  LAYER_BORDERS: array[TGeoDetail] of string = ('borders110', 'borders50');
  { Layer names in the file. }
  LAYER_COASTS: array[TGeoDetail] of string = ('coast110', 'coast50');
  { Layer name in the file. }
  LAYER_COUNTRIES = 'countries50';

{ Grows a bounds rectangle to take in a point.
  @param(ABounds The bounds; Top is the smaller latitude.)
  @param(APoint The point, X longitude and Y latitude.) }
procedure GrowBounds(var ABounds: TRectF; const APoint: TPointF);
begin
  ABounds.Left := Min(ABounds.Left, APoint.X);
  ABounds.Right := Max(ABounds.Right, APoint.X);
  ABounds.Top := Min(ABounds.Top, APoint.Y);
  ABounds.Bottom := Max(ABounds.Bottom, APoint.Y);
end;

{ An empty bounds rectangle, ready for @link(GrowBounds).
  @returns(Bounds that any point will replace.) }
function EmptyBounds: TRectF;
begin
  Result := TRectF.Create(MaxSingle, MaxSingle, -MaxSingle, -MaxSingle);
end;

{ Checks whether a point lies inside a ring, by counting how many of the
  ring's edges a line running east from the point crosses.
  @param(APoints The ring's points; the last joins back to the first.)
  @param(ALon The point's longitude.)
  @param(ALat The point's latitude.)
  @returns(@true if it is inside.) }
function InRing(const APoints: TArray<TPointF>; ALon, ALat: Single): Boolean;
var
  LIndex, LPrev: Integer;
  LA, LB: TPointF;
begin
  Result := False;
  LPrev := High(APoints);
  for LIndex := 0 to High(APoints) do
  begin
    LA := APoints[LIndex];
    LB := APoints[LPrev];
    if ((LA.Y > ALat) <> (LB.Y > ALat)) and
       (ALon < (LB.X - LA.X) * (ALat - LA.Y) / (LB.Y - LA.Y) + LA.X) then
      Result := not Result;
    LPrev := LIndex;
  end;
end;

{ Reads a string stored as a length then bytes.
  @param(AReader The reader.)
  @param(ALength The number of bytes.)
  @param(AEncoding How the bytes are encoded.)
  @returns(The string.) }
function ReadText(AReader: TBinaryReader; ALength: Integer; AEncoding: TEncoding): string;
begin
  if ALength = 0 then
    Exit('');
  Result := AEncoding.GetString(AReader.ReadBytes(ALength));
end;

{ TGeoLayer }

constructor TGeoLayer.CreateFromReader(AReader: TBinaryReader);
var
  LKind, LFeature, LPart, LPoint, LFeatureCount, LPartCount, LPointCount: Integer;
  LX, LY: Integer;
  LDX, LDY: SmallInt;
  LParts: TArray<TGeoPart>;
  LPoints: TArray<TPointF>;
  LBounds: TRectF;
begin
  inherited Create;
  LKind := AReader.ReadByte;
  case LKind of
    1: FKind := gkLines;
    2: FKind := gkAreas;
  else
    raise EVectorError.CreateFmt('Unknown layer kind %d', [LKind]);
  end;
  FName := ReadText(AReader, AReader.ReadByte, TEncoding.ASCII);

  LFeatureCount := AReader.ReadInt32;
  SetLength(FFeatures, LFeatureCount);
  for LFeature := 0 to LFeatureCount - 1 do
  begin
    FFeatures[LFeature].Name := ReadText(AReader, AReader.ReadUInt16, TEncoding.UTF8);
    FFeatures[LFeature].Bounds := EmptyBounds;
    LPartCount := AReader.ReadInt32;
    SetLength(LParts, LPartCount);
    for LPart := 0 to LPartCount - 1 do
    begin
      LPointCount := AReader.ReadInt32;
      if LPointCount < 1 then
        raise EVectorError.CreateFmt('Empty part in layer %s', [FName]);
      SetLength(LPoints, LPointCount);
      LBounds := EmptyBounds;
      LX := AReader.ReadInt32;
      LY := AReader.ReadInt32;
      for LPoint := 0 to LPointCount - 1 do
      begin
        if LPoint > 0 then
        begin
          LDX := AReader.ReadInt16;
          if LDX = ESCAPE_DELTA then
          begin
            LX := AReader.ReadInt32;
            LY := AReader.ReadInt32;
          end
          else
          begin
            LDY := AReader.ReadInt16;
            Inc(LX, LDX);
            Inc(LY, LDY);
          end;
        end;
        LPoints[LPoint] := PointF(LX / VECTORS_UNITS_PER_DEGREE,
          LY / VECTORS_UNITS_PER_DEGREE);
        GrowBounds(LBounds, LPoints[LPoint]);
      end;
      LParts[LPart].Points := LPoints;
      LParts[LPart].Bounds := LBounds;
      // Each part needs its own array, not a reference to the next one's
      LPoints := nil;
      GrowBounds(FFeatures[LFeature].Bounds, LBounds.TopLeft);
      GrowBounds(FFeatures[LFeature].Bounds, LBounds.BottomRight);
      Inc(FPointCount, LPointCount);
    end;
    FFeatures[LFeature].Parts := LParts;
    LParts := nil;
  end;
end;

{ Checks whether a point lies within a bounds rectangle, edges included.
  @param(ABounds The bounds; Top is the smaller latitude.)
  @param(ALon The point's longitude.)
  @param(ALat The point's latitude.)
  @returns(@true if it is within them.) }
function InBounds(const ABounds: TRectF; ALon, ALat: Double): Boolean;
begin
  Result := InRange(ALon, ABounds.Left, ABounds.Right) and
    InRange(ALat, ABounds.Top, ABounds.Bottom);
end;

function TGeoLayer.FeatureAt(ALat, ALon: Double): Integer;
var
  LFeature, LPart: Integer;
  LInside: Boolean;
begin
  Result := -1;
  if FKind <> gkAreas then
    Exit;
  for LFeature := 0 to High(FFeatures) do
  begin
    // Most countries are ruled out by their bounds alone
    if not InBounds(FFeatures[LFeature].Bounds, ALon, ALat) then
      Continue;
    // Inside an odd number of rings means inside the country
    LInside := False;
    for LPart := 0 to High(FFeatures[LFeature].Parts) do
      if InBounds(FFeatures[LFeature].Parts[LPart].Bounds, ALon, ALat) and
         InRing(FFeatures[LFeature].Parts[LPart].Points, ALon, ALat) then
        LInside := not LInside;
    if LInside then
      Exit(LFeature);
  end;
end;

{ The tile row or column holding a coordinate. A coordinate on the far
  edge of the world (longitude 180, latitude 90) belongs to the last tile
  rather than one beyond it.
  @param(AValue Longitude or latitude, in degrees.)
  @param(ALast The last row or column: 179 for longitude, 89 for latitude.)
  @returns(The row or column: the tile's southern or western edge.) }
function CellOf(AValue: Double; ALast: Integer): Integer;
begin
  Result := Min(Floor(AValue), ALast);
end;

procedure TGeoLayer.AddFeatureTiles(AFeature: Integer; ATiles: TTileIndex);
var
  LFeature: TGeoFeature;
  LPart, LIndex, LCount, LRow, LCol, LPair: Integer;
  LCrossings: TList<Single>;
  LA, LB: TPointF;
  LMiddle: Single;

  { Adds one tile, if ASTER GDEM covers its latitude.
    @param(ARow The tile's southern edge.)
    @param(ACol The tile's western edge.) }
  procedure AddTile(ARow, ACol: Integer);
  begin
    if InRange(ARow, GDEM_MIN_LAT, GDEM_MAX_LAT - 1) then
      ATiles.Add(ARow, ACol);
  end;

  { Adds every tile a straight edge passes through, walking the grid from
    one tile to the next along it (Amanatides and Woo's method).
    @param(AFrom Where the edge starts, X longitude and Y latitude.)
    @param(ATo Where it ends.) }
  procedure TraceEdge(const AFrom, ATo: TPointF);
  var
    LX, LY, LEndX, LEndY, LStepX, LStepY, LSteps: Integer;
    LDX, LDY, LMaxX, LMaxY, LDeltaX, LDeltaY: Double;
  begin
    LX := CellOf(AFrom.X, 179);
    LY := CellOf(AFrom.Y, 89);
    LEndX := CellOf(ATo.X, 179);
    LEndY := CellOf(ATo.Y, 89);
    AddTile(LY, LX);
    LDX := ATo.X - AFrom.X;
    LDY := ATo.Y - AFrom.Y;
    LStepX := Sign(LDX);
    LStepY := Sign(LDY);
    // How far along the edge (0 to 1) the next column and row lines are
    if LStepX <> 0 then
    begin
      LDeltaX := 1 / Abs(LDX);
      if LStepX > 0 then
        LMaxX := (LX + 1 - AFrom.X) / LDX
      else
        LMaxX := (LX - AFrom.X) / LDX;
    end
    else
    begin
      LDeltaX := MaxDouble;
      LMaxX := MaxDouble;
    end;
    if LStepY <> 0 then
    begin
      LDeltaY := 1 / Abs(LDY);
      if LStepY > 0 then
        LMaxY := (LY + 1 - AFrom.Y) / LDY
      else
        LMaxY := (LY - AFrom.Y) / LDY;
    end
    else
    begin
      LDeltaY := MaxDouble;
      LMaxY := MaxDouble;
    end;

    // Bounded, so rounding can never make it run on
    LSteps := Abs(LEndX - LX) + Abs(LEndY - LY);
    while (LSteps > 0) and ((LX <> LEndX) or (LY <> LEndY)) do
    begin
      if LMaxX < LMaxY then
      begin
        Inc(LX, LStepX);
        LMaxX := LMaxX + LDeltaX;
        Dec(LSteps);
      end
      else if LMaxY < LMaxX then
      begin
        Inc(LY, LStepY);
        LMaxY := LMaxY + LDeltaY;
        Dec(LSteps);
      end
      else
      begin
        // Exactly through a corner: the tiles either side only touch the
        // edge at a point, but take them too so nothing is missed
        AddTile(LY, LX + LStepX);
        AddTile(LY + LStepY, LX);
        Inc(LX, LStepX);
        Inc(LY, LStepY);
        LMaxX := LMaxX + LDeltaX;
        LMaxY := LMaxY + LDeltaY;
        Dec(LSteps, 2);
      end;
      AddTile(LY, LX);
    end;
    AddTile(LEndY, LEndX);
  end;

begin
  if (FKind <> gkAreas) or not InRange(AFeature, 0, High(FFeatures)) then
    Exit;
  LFeature := FFeatures[AFeature];

  // 1. The tiles the outline passes through
  for LPart := 0 to High(LFeature.Parts) do
  begin
    LCount := Length(LFeature.Parts[LPart].Points);
    for LIndex := 0 to LCount - 1 do
      TraceEdge(LFeature.Parts[LPart].Points[LIndex],
        LFeature.Parts[LPart].Points[(LIndex + 1) mod LCount]);
  end;

  // 2. The tiles whose centres are inside: for each row, find where the
  // outline crosses the row's middle, and fill between pairs of crossings
  LCrossings := TList<Single>.Create;
  try
    for LRow := CellOf(LFeature.Bounds.Top, 89) to CellOf(LFeature.Bounds.Bottom, 89) do
    begin
      LMiddle := LRow + 0.5;
      LCrossings.Clear;
      for LPart := 0 to High(LFeature.Parts) do
      begin
        LCount := Length(LFeature.Parts[LPart].Points);
        for LIndex := 0 to LCount - 1 do
        begin
          LA := LFeature.Parts[LPart].Points[LIndex];
          LB := LFeature.Parts[LPart].Points[(LIndex + 1) mod LCount];
          if (LA.Y > LMiddle) <> (LB.Y > LMiddle) then
            LCrossings.Add(LA.X + (LMiddle - LA.Y) * (LB.X - LA.X) / (LB.Y - LA.Y));
        end;
      end;
      LCrossings.Sort;
      LPair := 0;
      while LPair + 1 < LCrossings.Count do
      begin
        for LCol := Ceil(LCrossings[LPair] - 0.5) to Floor(LCrossings[LPair + 1] - 0.5) do
          AddTile(LRow, LCol);
        Inc(LPair, 2);
      end;
    end;
  finally
    LCrossings.Free;
  end;
end;

{ TWorldVectors }

destructor TWorldVectors.Destroy;
var
  LLayer: TGeoLayer;
begin
  for LLayer in FLayers do
    LLayer.Free;
  inherited;
end;

procedure TWorldVectors.LoadFromStream(AStream: TStream);
var
  LReader: TBinaryReader;
  LMagic: TBytes;
  LVersion, LCount, LIndex: Integer;
  LLayer: TGeoLayer;
  LLayers: TArray<TGeoLayer>;
begin
  LLayers := nil;
  // The reader must not free the caller's stream
  LReader := TBinaryReader.Create(AStream, TEncoding.ASCII, False);
  try
    try
      LMagic := LReader.ReadBytes(4);
      if (Length(LMagic) <> 4) or (LMagic[0] <> Ord(VECTORS_MAGIC[0])) or
         (LMagic[1] <> Ord(VECTORS_MAGIC[1])) or (LMagic[2] <> Ord(VECTORS_MAGIC[2])) or
         (LMagic[3] <> Ord(VECTORS_MAGIC[3])) then
        raise EVectorError.Create('Not a GDEM vector file');
      LVersion := LReader.ReadUInt16;
      if LVersion <> VECTORS_VERSION then
        raise EVectorError.CreateFmt('Vector file version %d is not supported', [LVersion]);
      LCount := LReader.ReadUInt16;
      for LIndex := 1 to LCount do
      begin
        LLayer := TGeoLayer.CreateFromReader(LReader);
        LLayers := LLayers + [LLayer];
      end;
    except
      on E: EVectorError do
      begin
        for LLayer in LLayers do
          LLayer.Free;
        raise;
      end;
      on E: Exception do
      begin
        for LLayer in LLayers do
          LLayer.Free;
        // A short read is the usual cause: the file is cut off
        raise EVectorError.Create('Could not read the vector file: ' + E.Message);
      end;
    end;
  finally
    LReader.Free;
  end;

  for LLayer in FLayers do
    LLayer.Free;
  FLayers := LLayers;
end;

procedure TWorldVectors.LoadFromResource;
var
  LStream: TResourceStream;
begin
  LStream := TResourceStream.Create(HInstance, WORLD_VECTORS_RESOURCE, RT_RCDATA);
  try
    LoadFromStream(LStream);
  finally
    LStream.Free;
  end;
end;

function TWorldVectors.LayerNamed(const AName: string): TGeoLayer;
var
  LLayer: TGeoLayer;
begin
  for LLayer in FLayers do
    if SameText(LLayer.Name, AName) then
      Exit(LLayer);
  Result := nil;
end;

function TWorldVectors.Borders(ADetail: TGeoDetail): TGeoLayer;
begin
  Result := LayerNamed(LAYER_BORDERS[ADetail]);
end;

function TWorldVectors.Coastlines(ADetail: TGeoDetail): TGeoLayer;
begin
  Result := LayerNamed(LAYER_COASTS[ADetail]);
end;

function TWorldVectors.Countries: TGeoLayer;
begin
  Result := LayerNamed(LAYER_COUNTRIES);
end;

function TWorldVectors.CountryAt(ALat, ALon: Double): string;
begin
  Result := CountryName(CountryIndexAt(ALat, ALon));
end;

function TWorldVectors.CountryIndexAt(ALat, ALon: Double): Integer;
var
  LLayer: TGeoLayer;
begin
  LLayer := Countries;
  if LLayer = nil then
    Exit(-1);
  ALon := ALon - Floor((ALon + 180) / 360) * 360;
  Result := LLayer.FeatureAt(ALat, ALon);
end;

procedure TWorldVectors.AddCountryTiles(ACountry: Integer; ATiles: TTileIndex);
var
  LLayer: TGeoLayer;
begin
  LLayer := Countries;
  if LLayer <> nil then
    LLayer.AddFeatureTiles(ACountry, ATiles);
end;

function TWorldVectors.CountryName(ACountry: Integer): string;
var
  LLayer: TGeoLayer;
begin
  LLayer := Countries;
  if (LLayer = nil) or not InRange(ACountry, 0, High(LLayer.Features)) then
    Exit('');
  Result := LLayer.Features[ACountry].Name;
end;

function TWorldVectors.Describe: string;
var
  LLayer: TGeoLayer;
  LPoints: Integer;
begin
  LPoints := 0;
  for LLayer in FLayers do
    Inc(LPoints, LLayer.PointCount);
  Result := Format('%d layers, %.0n points', [Length(FLayers), LPoints * 1.0]);
end;

end.
