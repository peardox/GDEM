{ @abstract(The 1 by 1 degree tile grid that ASTER GDEM V3 is published on.)

  Every tile is named after the latitude and longitude of its south-west
  corner: tile @code(N50W002) covers latitudes 50 to 51 north and
  longitudes 2 to 1 west. The whole grid is 360 by 180 tiles, but ASTER
  GDEM only covers latitudes 83 south to 83 north, and only tiles that
  contain land exist.

  This unit is pure arithmetic with no FMX or network dependencies. }
unit GDEMTiles;

interface

uses
  System.SysUtils, System.Types;

const
  { Southern limit of ASTER GDEM coverage, in degrees. }
  GDEM_MIN_LAT = -83;
  { Northern limit of ASTER GDEM coverage, in degrees. }
  GDEM_MAX_LAT = 83;
  { Western edge of the tile grid, in degrees. }
  GDEM_MIN_LON = -180;
  { Eastern edge of the tile grid, in degrees. }
  GDEM_MAX_LON = 180;

  { The degree sign, written as a character code because Delphi reads
    source files without a byte order mark as ANSI. }
  DEGREE_SIGN = #$00B0;

type
  { @abstract(A rectangular block of whole tiles.)

    Edges are whole degrees. @link(West) and @link(South) are the
    south-west corner of the first tile; @link(East) and @link(North) are
    the far edges, so a single tile has @code(East = West + 1) and
    @code(North = South + 1). }
  TTileRect = record
    { Western edge, from -180 to 179. }
    West: Integer;
    { Southern edge, from @link(GDEM_MIN_LAT) to 82. }
    South: Integer;
    { Eastern edge, from -179 to 180. Always greater than @link(West). }
    East: Integer;
    { Northern edge, from -82 to @link(GDEM_MAX_LAT). Always greater than
      @link(South). }
    North: Integer;

    { Builds the smallest block of tiles that contains two points, clipped
      to the area ASTER GDEM covers. The points may be given in any order.
      @param(ALon1 Longitude of the first point, in degrees.)
      @param(ALat1 Latitude of the first point, in degrees.)
      @param(ALon2 Longitude of the second point, in degrees.)
      @param(ALat2 Latitude of the second point, in degrees.)
      @returns(The block of tiles.) }
    class function FromPoints(ALon1, ALat1, ALon2, ALat2: Double): TTileRect; static;

    { An empty block, used to mean "nothing selected".
      @returns(A block with no tiles.) }
    class function Empty: TTileRect; static;

    { Checks whether the block holds any tiles.
      @returns(@true if there are no tiles.) }
    function IsEmpty: Boolean;

    { Number of tiles across.
      @returns(@code(East - West).) }
    function Width: Integer;

    { Number of tiles down.
      @returns(@code(North - South).) }
    function Height: Integer;

    { Total number of tiles.
      @returns(@code(Width * Height), or 0 when empty.) }
    function Count: Integer;

    { Names every tile in the block, north-west first, row by row.
      @returns(Tile names such as @code(N50W002).) }
    function TileNames: TArray<string>;

    { A short description for display, such as
      @code(N50W002 to N52E001 (3 x 3 = 9 tiles)).
      @returns(The description, or @code(Nothing selected).) }
    function Describe: string;
  end;

{ Names the tile whose south-west corner is at the given whole degrees.
  @param(ASouth Latitude of the tile's southern edge.)
  @param(AWest Longitude of the tile's western edge.)
  @returns(The tile name, for example @code(N50W002) for 50, -2.) }
function TileName(ASouth, AWest: Integer): string;

{ Reads the corner of a tile from its name. Accepts a bare name such as
  @code(N50W002) or one embedded in a longer name such as
  @code(ASTGTMV003_N50W002) or @code(ASTGTMV003_N50W002_dem.tif). Letter
  case does not matter.
  @param(AName The name to read.)
  @param(ASouth Receives the latitude of the tile's southern edge.)
  @param(AWest Receives the longitude of the tile's western edge.)
  @returns(@true if a valid tile name was found.) }
function TryParseTileName(const AName: string; out ASouth, AWest: Integer): Boolean;

{ Names the tile that contains a point.
  @param(ALat Latitude in degrees.)
  @param(ALon Longitude in degrees.)
  @returns(The name of the tile containing the point.) }
function TileNameAt(ALat, ALon: Double): string;

{ Formats a latitude for display, such as @code(50.6750) followed by a
  degree sign and @code(N).
  @param(ALat Latitude in degrees.)
  @returns(The formatted latitude.) }
function FormatLat(ALat: Double): string;

{ Formats a longitude for display, such as @code(1.3000) followed by a
  degree sign and @code(W).
  @param(ALon Longitude in degrees.)
  @returns(The formatted longitude.) }
function FormatLon(ALon: Double): string;

implementation

uses
  System.Math, System.RegularExpressions;

function TileName(ASouth, AWest: Integer): string;
const
  NS: array[Boolean] of Char = ('S', 'N');
  EW: array[Boolean] of Char = ('W', 'E');
begin
  Result := Format('%s%.2d%s%.3d',
    [NS[ASouth >= 0], Abs(ASouth), EW[AWest >= 0], Abs(AWest)]);
end;

function TryParseTileName(const AName: string; out ASouth, AWest: Integer): Boolean;
var
  LMatch: TMatch;
begin
  ASouth := 0;
  AWest := 0;
  // The name must not be part of a longer run of letters and digits
  LMatch := TRegEx.Match(AName,
    '(?:^|[^A-Z0-9])([NS])(\d{2})([EW])(\d{3})(?:$|[^A-Z0-9])', [roIgnoreCase]);
  if not LMatch.Success then
    Exit(False);
  ASouth := StrToInt(LMatch.Groups[2].Value);
  AWest := StrToInt(LMatch.Groups[4].Value);
  if SameText(LMatch.Groups[1].Value, 'S') then
    ASouth := -ASouth;
  if SameText(LMatch.Groups[3].Value, 'W') then
    AWest := -AWest;
  Result := InRange(ASouth, -90, 89) and InRange(AWest, GDEM_MIN_LON, GDEM_MAX_LON - 1);
end;

function TileNameAt(ALat, ALon: Double): string;
begin
  Result := TileName(Floor(ALat), Floor(ALon));
end;

function FormatLat(ALat: Double): string;
const
  NS: array[Boolean] of Char = ('S', 'N');
begin
  Result := FormatFloat('0.0000', Abs(ALat)) + DEGREE_SIGN + NS[ALat >= 0];
end;

function FormatLon(ALon: Double): string;
const
  EW: array[Boolean] of Char = ('W', 'E');
begin
  Result := FormatFloat('0.0000', Abs(ALon)) + DEGREE_SIGN + EW[ALon >= 0];
end;

{ TTileRect }

class function TTileRect.Empty: TTileRect;
begin
  Result.West := 0;
  Result.South := 0;
  Result.East := 0;
  Result.North := 0;
end;

class function TTileRect.FromPoints(ALon1, ALat1, ALon2, ALat2: Double): TTileRect;
begin
  Result.West := Floor(Min(ALon1, ALon2));
  Result.East := Floor(Max(ALon1, ALon2)) + 1;
  Result.South := Floor(Min(ALat1, ALat2));
  Result.North := Floor(Max(ALat1, ALat2)) + 1;

  Result.West := EnsureRange(Result.West, GDEM_MIN_LON, GDEM_MAX_LON - 1);
  Result.East := EnsureRange(Result.East, Result.West + 1, GDEM_MAX_LON);
  Result.South := EnsureRange(Result.South, GDEM_MIN_LAT, GDEM_MAX_LAT - 1);
  Result.North := EnsureRange(Result.North, Result.South + 1, GDEM_MAX_LAT);
end;

function TTileRect.IsEmpty: Boolean;
begin
  Result := (East <= West) or (North <= South);
end;

function TTileRect.Width: Integer;
begin
  Result := Max(0, East - West);
end;

function TTileRect.Height: Integer;
begin
  Result := Max(0, North - South);
end;

function TTileRect.Count: Integer;
begin
  Result := Width * Height;
end;

function TTileRect.TileNames: TArray<string>;
var
  LLat, LLon, LIndex: Integer;
begin
  SetLength(Result, Count);
  LIndex := 0;
  for LLat := North - 1 downto South do
    for LLon := West to East - 1 do
    begin
      Result[LIndex] := TileName(LLat, LLon);
      Inc(LIndex);
    end;
end;

function TTileRect.Describe: string;
begin
  if IsEmpty then
    Result := 'Nothing selected'
  else if Count = 1 then
    Result := TileName(South, West) + ' (1 tile)'
  else
    Result := Format('%s to %s (%d x %d = %d tiles)',
      [TileName(North - 1, West), TileName(South, East - 1),
       Width, Height, Count]);
end;

end.
