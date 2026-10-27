{ @abstract(Turns an ASTER GDEM tile into a surface to draw in 3D: a grid of
  heights, and the triangles, normals and colours of the mesh made from
  it.)

  @link(LoadTerrainGrid) reads a tile's @code(_dem.tif) with
  @code(GDEMGeoTiff) at a chosen detail: the largest of its images (the
  full 3601 x 3601 or one of its overviews) no wider than asked for, so a
  coarse surface costs only a small read. Voids (-9999) are filled from
  their neighbours.

  @link(TerrainChunk) makes the mesh in pieces of at most
  @link(TERRAIN_CHUNK_CELLS) cells a side, so no piece has more than 58,081
  vertices: each fits 16-bit indices, whatever index format the 3D library
  uses, and a large grid is drawn as several pieces. Neighbouring pieces
  share their edge vertices, with the same normals and colours, so no seam
  shows.

  The mesh is in kilometres, centred on the tile, in FMX's axes: X east,
  Z north, and Y down, so heights are negative Y. Triangles are wound
  clockwise as seen from above with north at the top of the screen, which
  is counter-clockwise in the coordinates' own sense, as Gorilla3D's
  meshes want; @link(TERRAIN_FLIP_WINDING) reverses it.

  Colours come from the height (@link(HeightColour): blue water, greens,
  yellows and browns, grey rock, white above 4,500 m) and are shaded by a
  sun in the north-west, 45 degrees up, so the relief shows even under a
  material that ignores lighting.

  No FMX: TPoint3D and TAlphaColor come from the run-time library. }
unit GDEMTerrain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math.Vectors;

const
  { The height ASTER GDEM gives a void, where no elevation is known. }
  TERRAIN_VOID = -9999;

  { The most cells a mesh piece has along each side; 241 x 241 vertices,
    58,081, fit 16-bit indices. }
  TERRAIN_CHUNK_CELLS = 240;

  { Metres in a degree of latitude, and of longitude at the equator, on a
    sphere the size of the WGS 84 ellipsoid's equator: close enough for
    drawing. }
  METRES_PER_DEGREE = 111320.0;

  { @true to wind triangles the other way, should the 3D library cull
    the surface seen from above. }
  TERRAIN_FLIP_WINDING = False;

  { The details offered: the most samples across a tile. Each picks the
    largest of the tile's images no wider, so 226, 451, 901, 1801 and 3601
    samples for an ASTER GDEM tile: about 50,000, 200,000, 800,000, 3.2
    million and 13 million vertices. Very fine built in 649 ms on the
    owner's laptop (RTX 5090 Mobile); Full is four times as many. }
  TERRAIN_DETAILS: array[0..4] of Integer = (226, 451, 901, 1801, 3601);

  { Names for @link(TERRAIN_DETAILS), as offered. }
  TERRAIN_DETAIL_NAMES: array[0..4] of string = ('Coarse', 'Medium', 'Fine', 'Very fine',
    'Full');

  { The detail used unless another is chosen. }
  DEFAULT_TERRAIN_DETAIL = 451;

  { The height stretches offered, times true scale. }
  TERRAIN_HEIGHTS: array[0..4] of Integer = (1, 2, 3, 5, 10);

  { The height stretch used unless another is chosen. }
  DEFAULT_TERRAIN_HEIGHTS = 2;

type
  { @abstract(Raised when a tile cannot be read as terrain.) }
  ETerrainError = class(Exception);

  { @abstract(A tile's heights on a regular grid.) }
  TTerrainGrid = record
    { The tile's name, such as @code(N50W002). }
    Tile: string;
    { Samples across, west to east. }
    Columns: Integer;
    { Samples down, north to south. }
    Rows: Integer;
    { Heights in metres, row by row from the north-west; voids filled. }
    Heights: TArray<Single>;
    { How many samples were voids and have been filled. }
    Voids: Integer;
    { The lowest height, in metres. }
    MinHeight: Single;
    { The highest height, in metres. }
    MaxHeight: Single;
    { Metres between samples west to east, at the tile's middle latitude. }
    SpacingX: Double;
    { Metres between samples north to south. }
    SpacingZ: Double;
    { Which image of the file the heights came from: 0 for the full image,
      then the overviews. }
    ImageIndex: Integer;
    { How many images the file holds. }
    ImageCount: Integer;

    { A height.
      @param(AColumn The column, 0 at the west.)
      @param(ARow The row, 0 at the north.)
      @returns(The height in metres.) }
    function HeightAt(AColumn, ARow: Integer): Single; inline;

    { The tile's size west to east.
      @returns(Kilometres.) }
    function WidthKm: Double;

    { The tile's size north to south.
      @returns(Kilometres.) }
    function DepthKm: Double;
  end;

  { @abstract(One piece of the mesh.) }
  TTerrainChunk = record
    { Vertex positions, in kilometres. }
    Positions: TArray<TPoint3D>;
    { Unit normals, pointing up (towards -Y). }
    Normals: TArray<TPoint3D>;
    { Vertex colours, shaded. }
    Colours: TArray<TAlphaColor>;
    { Three vertex indices for each triangle. }
    Indices: TArray<Integer>;
  end;

{ Reads a tile's heights.
  @param(ADemFile The tile's @code(_dem.tif).)
  @param(ATile The tile's name, kept in the grid.)
  @param(AMaxSize The most samples across wanted: the largest image no
    wider than this is read (the smallest image if all are wider).)
  @returns(The grid.)
  @raises(ETerrainError if the file is not a GDEM tile.)
  @raises(EGeoTiffError if it cannot be decoded.) }
function LoadTerrainGrid(const ADemFile, ATile: string; AMaxSize: Integer): TTerrainGrid;

{ A grid with nothing in it.
  @returns(Every field zero or empty.) }
function EmptyTerrainGrid: TTerrainGrid;

{ How many pieces the mesh of a grid is made in.
  @param(AGrid The grid.)
  @returns(The number of pieces.) }
function TerrainChunkCount(const AGrid: TTerrainGrid): Integer;

{ Makes one piece of the mesh.
  @param(AGrid The grid.)
  @param(AIndex Which piece, from 0 to @link(TerrainChunkCount) - 1,
    west to east and then north to south.)
  @param(AExaggeration How many times to stretch heights; 1 is true
    scale.)
  @returns(The piece.) }
function TerrainChunk(const AGrid: TTerrainGrid; AIndex: Integer;
  AExaggeration: Single): TTerrainChunk;

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
    { Red, green and blue, 0 to 255. }
    R, G, B: Byte;
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

  { The share of a colour kept in full shadow. }
  SHADE_AMBIENT = 0.35;

  { Most passes made filling voids from their neighbours; what is left
    after that becomes sea level. }
  MAX_VOID_PASSES = 64;

function TTerrainGrid.HeightAt(AColumn, ARow: Integer): Single;
begin
  Result := Heights[ARow * Columns + AColumn];
end;

function TTerrainGrid.WidthKm: Double;
begin
  Result := (Columns - 1) * SpacingX / 1000;
end;

function TTerrainGrid.DepthKm: Double;
begin
  Result := (Rows - 1) * SpacingZ / 1000;
end;

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

{ Fills voids with the mean of their known neighbours, pass after pass, so
  a hole closes in from its edges; anything still unknown becomes 0.
  @param(AGrid The grid; its Voids is set.)
  @param(AKnown For each sample, @true if it is not a void.) }
procedure FillVoids(var AGrid: TTerrainGrid; var AKnown: TArray<Boolean>);
var
  LPass, LColumn, LRow, LDX, LDY, LCount, LIndex, LLeft: Integer;
  LSum: Double;
  LNext: TArray<Boolean>;
begin
  LLeft := AGrid.Voids;
  LPass := 0;
  while (LLeft > 0) and (LPass < MAX_VOID_PASSES) do
  begin
    LNext := Copy(AKnown);
    for LRow := 0 to AGrid.Rows - 1 do
      for LColumn := 0 to AGrid.Columns - 1 do
      begin
        LIndex := LRow * AGrid.Columns + LColumn;
        if AKnown[LIndex] then
          Continue;
        LSum := 0;
        LCount := 0;
        for LDY := -1 to 1 do
          for LDX := -1 to 1 do
            if InRange(LColumn + LDX, 0, AGrid.Columns - 1) and
               InRange(LRow + LDY, 0, AGrid.Rows - 1) and
               AKnown[(LRow + LDY) * AGrid.Columns + LColumn + LDX] then
            begin
              LSum := LSum + AGrid.Heights[(LRow + LDY) * AGrid.Columns + LColumn + LDX];
              Inc(LCount);
            end;
        if LCount > 0 then
        begin
          AGrid.Heights[LIndex] := LSum / LCount;
          LNext[LIndex] := True;
          Dec(LLeft);
        end;
      end;
    AKnown := LNext;
    Inc(LPass);
  end;
  if LLeft > 0 then
    for LIndex := 0 to High(AKnown) do
      if not AKnown[LIndex] then
        AGrid.Heights[LIndex] := 0;
end;

function LoadTerrainGrid(const ADemFile, ATile: string; AMaxSize: Integer): TTerrainGrid;
var
  LTiff: TGeoTiff;
  LImage: Integer;
  LGeo: TGeoTiffGeoreference;
  LSamples: TArray<SmallInt>;
  LKnown: TArray<Boolean>;
  I: Integer;
  LLatitude: Double;
  LValue: Single;
begin
  Result := Default(TTerrainGrid);
  Result.Tile := ATile;
  LTiff := TGeoTiff.Create(ADemFile);
  try
    // The largest image no wider than asked for; images come largest first
    LImage := LTiff.ImageCount - 1;
    for I := 0 to LTiff.ImageCount - 1 do
      if LTiff.Images[I].Width <= AMaxSize then
      begin
        LImage := I;
        Break;
      end;
    LGeo := LTiff.Georeference(LImage);
    if not LGeo.Valid then
      raise ETerrainError.CreateFmt('%s does not say where it lies', [ExtractFileName(ADemFile)]);
    LSamples := LTiff.ReadInt16(LImage);
    Result.ImageIndex := LImage;
    Result.ImageCount := LTiff.ImageCount;
    Result.Columns := LTiff.Images[LImage].Width;
    Result.Rows := LTiff.Images[LImage].Height;
  finally
    LTiff.Free;
  end;
  if (Result.Columns < 2) or (Result.Rows < 2) then
    raise ETerrainError.CreateFmt('%s is too small to draw', [ExtractFileName(ADemFile)]);

  // Degrees to metres; a degree of longitude shrinks with the latitude
  LLatitude := LGeo.CentreY((Result.Rows - 1) / 2);
  Result.SpacingX := LGeo.ScaleX * METRES_PER_DEGREE * Cos(DegToRad(LLatitude));
  Result.SpacingZ := LGeo.ScaleY * METRES_PER_DEGREE;

  SetLength(Result.Heights, Length(LSamples));
  SetLength(LKnown, Length(LSamples));
  Result.MinHeight := MaxSingle;
  Result.MaxHeight := -MaxSingle;
  for I := 0 to High(LSamples) do
  begin
    LKnown[I] := LSamples[I] <> TERRAIN_VOID;
    if LKnown[I] then
    begin
      LValue := LSamples[I];
      Result.Heights[I] := LValue;
      if LValue < Result.MinHeight then
        Result.MinHeight := LValue;
      if LValue > Result.MaxHeight then
        Result.MaxHeight := LValue;
    end
    else
      Inc(Result.Voids);
  end;
  if Result.Voids = Length(LSamples) then
  begin
    Result.MinHeight := 0;
    Result.MaxHeight := 0;
  end;
  if Result.Voids > 0 then
    FillVoids(Result, LKnown);
end;

function EmptyTerrainGrid: TTerrainGrid;
begin
  // Here rather than in GDEMTerrainView, where Gorilla.DefTypes declares an
  // enumeration value named Default that hides the Default intrinsic
  Result := Default(TTerrainGrid);
end;

{ The number of pieces along one side of the grid.
  @param(ASamples Samples along that side.)
  @returns(Pieces needed for the cells between them.) }
function ChunksAlong(ASamples: Integer): Integer;
begin
  Result := (ASamples - 1 + TERRAIN_CHUNK_CELLS - 1) div TERRAIN_CHUNK_CELLS;
end;

function TerrainChunkCount(const AGrid: TTerrainGrid): Integer;
begin
  Result := ChunksAlong(AGrid.Columns) * ChunksAlong(AGrid.Rows);
end;

function TerrainChunk(const AGrid: TTerrainGrid; AIndex: Integer;
  AExaggeration: Single): TTerrainChunk;
var
  LAcross, LColumn0, LRow0, LColumns, LRows, LColumn, LRow, LVertex, LIndex: Integer;
  LMidColumn, LMidRow, LScale, LGX, LGZ, LShade: Double;
  LDot: Single;
  LNormal, LSun: TPoint3D;
  LColour: TAlphaColorRec;
  LNW, LNE, LSW, LSE: Integer;

  { The change of height per metre west to east at a sample, from its
    neighbours (one-sided at the edges), already exaggerated. }
  function SlopeX(AColumn, ARow: Integer): Double;
  var
    LWest, LEast: Integer;
  begin
    LWest := Max(AColumn - 1, 0);
    LEast := Min(AColumn + 1, AGrid.Columns - 1);
    Result := (AGrid.HeightAt(LEast, ARow) - AGrid.HeightAt(LWest, ARow)) * AExaggeration /
      ((LEast - LWest) * AGrid.SpacingX);
  end;

  { The change of height per metre south to north at a sample. }
  function SlopeZ(AColumn, ARow: Integer): Double;
  var
    LNorth, LSouth: Integer;
  begin
    LNorth := Max(ARow - 1, 0);
    LSouth := Min(ARow + 1, AGrid.Rows - 1);
    Result := (AGrid.HeightAt(AColumn, LNorth) - AGrid.HeightAt(AColumn, LSouth)) *
      AExaggeration / ((LSouth - LNorth) * AGrid.SpacingZ);
  end;

begin
  Result := Default(TTerrainChunk);
  LAcross := ChunksAlong(AGrid.Columns);
  LColumn0 := (AIndex mod LAcross) * TERRAIN_CHUNK_CELLS;
  LRow0 := (AIndex div LAcross) * TERRAIN_CHUNK_CELLS;
  // Samples in this piece, sharing the edge ones with its neighbours
  LColumns := Min(TERRAIN_CHUNK_CELLS, AGrid.Columns - 1 - LColumn0) + 1;
  LRows := Min(TERRAIN_CHUNK_CELLS, AGrid.Rows - 1 - LRow0) + 1;
  if (LColumns < 2) or (LRows < 2) then
    Exit;

  LMidColumn := (AGrid.Columns - 1) / 2;
  LMidRow := (AGrid.Rows - 1) / 2;
  LScale := AExaggeration / 1000;
  // Towards the sun, in the north-west, 45 degrees up: up is -Y, north +Z
  LSun := Point3D(-1, -Sqrt(2), 1) * 0.5;

  SetLength(Result.Positions, LColumns * LRows);
  SetLength(Result.Normals, LColumns * LRows);
  SetLength(Result.Colours, LColumns * LRows);
  LVertex := 0;
  for LRow := LRow0 to LRow0 + LRows - 1 do
    for LColumn := LColumn0 to LColumn0 + LColumns - 1 do
    begin
      Result.Positions[LVertex] := Point3D(
        (LColumn - LMidColumn) * AGrid.SpacingX / 1000,
        -AGrid.HeightAt(LColumn, LRow) * LScale,
        (LMidRow - LRow) * AGrid.SpacingZ / 1000);
      // The surface's up-pointing normal, with up as -Y
      LGX := SlopeX(LColumn, LRow);
      LGZ := SlopeZ(LColumn, LRow);
      LNormal := Point3D(-LGX, -1, -LGZ).Normalize;
      Result.Normals[LVertex] := LNormal;
      LDot := LNormal.DotProduct(LSun);
      if LDot < 0 then
        LDot := 0;
      LShade := SHADE_AMBIENT + (1 - SHADE_AMBIENT) * LDot;
      LColour.Color := HeightColour(AGrid.HeightAt(LColumn, LRow));
      LColour.R := Round(LColour.R * LShade);
      LColour.G := Round(LColour.G * LShade);
      LColour.B := Round(LColour.B * LShade);
      Result.Colours[LVertex] := LColour.Color;
      Inc(LVertex);
    end;

  // Two triangles a cell, clockwise seen from above with north up the
  // screen: north-west, north-east, south-east; north-west, south-east,
  // south-west
  SetLength(Result.Indices, (LColumns - 1) * (LRows - 1) * 6);
  LIndex := 0;
  for LRow := 0 to LRows - 2 do
    for LColumn := 0 to LColumns - 2 do
    begin
      LNW := LRow * LColumns + LColumn;
      LNE := LNW + 1;
      LSW := LNW + LColumns;
      LSE := LSW + 1;
      Result.Indices[LIndex] := LNW;
      if TERRAIN_FLIP_WINDING then
      begin
        Result.Indices[LIndex + 1] := LSE;
        Result.Indices[LIndex + 2] := LNE;
        Result.Indices[LIndex + 4] := LSW;
        Result.Indices[LIndex + 5] := LSE;
      end
      else
      begin
        Result.Indices[LIndex + 1] := LNE;
        Result.Indices[LIndex + 2] := LSE;
        Result.Indices[LIndex + 4] := LSE;
        Result.Indices[LIndex + 5] := LSW;
      end;
      Result.Indices[LIndex + 3] := LNW;
      Inc(LIndex, 6);
    end;
end;

end.
