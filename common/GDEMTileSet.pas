{ @abstract(Describes a tile set: an image cut into square tiles at several
  levels of detail, and saved as @link(TILESET_FILE_NAME).)

  TileMaker writes a tile set and GDEMFetch reads one. On disk it is a
  folder holding @link(TILESET_FILE_NAME), which this unit reads and
  writes, and one folder per level, named after the level's size (such as
  @code(10800x5400)), holding that level's tiles:

  @preformatted(
<tile set>/
  tileset.json
  10800x5400/
    r000_c000.jpg   top-left tile
    r000_c001.jpg   the next one east
    ...
  5400x2700/
  ...
  )

  Level 0 is the full image; each later level is half the size of the one
  before. Every level is cut into tiles of the same size, which divides it
  exactly, so a level of W x H pixels has W / tile size columns and
  H / tile size rows. Tile names are @code(r) and the row, @code(_c) and the
  column, each three digits, counted from 0 at the top left (see
  @link(TTileSet.TileFileName)).

  @link(TTileSet.Bounds) says what the image covers, in degrees for a map;
  an image of the whole world in the equirectangular projection runs from
  180 west to 180 east and 90 north to 90 south. The file is written last,
  so a folder without it is an unfinished tile set.

  This unit uses only the run-time library and Neon, so any program can
  use it. }
unit GDEMTileSet;

interface

uses
  System.SysUtils, System.Types,
  Neon.Core.Attributes;

const
  { Name of the file describing a tile set, in the tile set's folder. }
  TILESET_FILE_NAME = 'tileset.json';

  { The version of the description this unit writes and reads. }
  TILESET_FORMAT = 1;

  { The projection of a map covering @link(TTileSet.Bounds) with pixels
    equally spaced in longitude and latitude. }
  PROJECTION_EQUIRECTANGULAR = 'equirectangular';

type
  { @abstract(Raised when a tile set cannot be read or written.) }
  ETileSetError = class(Exception);

  { @abstract(What a tile set covers, in the units of its projection:
    degrees for a map.) }
  TTileSetBounds = record
    { Western edge: the left of the image. }
    [NeonProperty('west')]
    West: Double;
    { Northern edge: the top of the image. }
    [NeonProperty('north')]
    North: Double;
    { Eastern edge: the right of the image. }
    [NeonProperty('east')]
    East: Double;
    { Southern edge: the bottom of the image. }
    [NeonProperty('south')]
    South: Double;

    { The whole world: 180 west to 180 east, 90 north to 90 south.
      @returns(The bounds.) }
    class function World: TTileSetBounds; static;

    { Whether the bounds go all the way round, so the left and right edges
      of the image meet.
      @returns(@true if they span 360 degrees east to west.) }
    function WrapsEastWest: Boolean;
  end;

  { @abstract(One level of detail.) }
  TTileSetLevel = record
    { Width of the whole level, in pixels. }
    [NeonProperty('width')]
    Width: Integer;
    { Height of the whole level, in pixels. }
    [NeonProperty('height')]
    Height: Integer;
    { Tiles across: @link(Width) divided by the tile size. }
    [NeonProperty('columns')]
    Columns: Integer;
    { Tiles down: @link(Height) divided by the tile size. }
    [NeonProperty('rows')]
    Rows: Integer;
    { The level's folder, inside the tile set's folder. }
    [NeonProperty('folder')]
    Folder: string;
  end;

  { @abstract(A tile set's description, as kept in
    @link(TILESET_FILE_NAME).) }
  TTileSet = record
    { Version of the description; see @link(TILESET_FORMAT). }
    [NeonProperty('format')]
    Format: Integer;
    { A name for the tile set, such as the source image's name. }
    [NeonProperty('name')]
    Name: string;
    { File name of the image it was made from, without its folder. }
    [NeonProperty('source')]
    Source: string;
    { Width of the source image, in pixels: level 0's width. }
    [NeonProperty('sourceWidth')]
    SourceWidth: Integer;
    { Height of the source image, in pixels: level 0's height. }
    [NeonProperty('sourceHeight')]
    SourceHeight: Integer;
    { Width and height of every tile, in pixels. }
    [NeonProperty('tileSize')]
    TileSize: Integer;
    { The tiles' file type, as their extension without the full stop:
      @code(jpg), @code(webp) or @code(png). }
    [NeonProperty('imageFormat')]
    ImageFormat: string;
    { Quality the tiles were encoded at, from 1 to 100; ignored for
      @code(png). }
    [NeonProperty('quality')]
    Quality: Integer;
    { How the smaller levels were made from the full image, such as
      @code(lanczos3, linear light). }
    [NeonProperty('resampling')]
    Resampling: string;
    { The projection, such as @link(PROJECTION_EQUIRECTANGULAR); empty for
      an image that is not a map. }
    [NeonProperty('projection')]
    Projection: string;
    { What the image covers. }
    [NeonProperty('bounds')]
    Bounds: TTileSetBounds;
    { The levels, full size first, each half the size of the one before. }
    [NeonProperty('levels')]
    Levels: TArray<TTileSetLevel>;
    { The program that made it. }
    [NeonProperty('generator')]
    Generator: string;
    { When it was made, in UTC, as ISO 8601. }
    [NeonProperty('created')]
    Created: string;

    { The name of a level's folder: its width and height, such as
      @code(10800x5400).
      @param(AWidth The level's width.)
      @param(AHeight The level's height.)
      @returns(The folder name.) }
    class function LevelFolderName(AWidth, AHeight: Integer): string; static;

    { A tile's file, relative to the tile set's folder, such as
      @code(10800x5400/r003_c017.jpg), with the platform's path separator.
      @param(ALevel The level, 0 for the full image.)
      @param(ARow The row, 0 at the top.)
      @param(AColumn The column, 0 at the left.)
      @returns(The relative path.) }
    function TileFileName(ALevel, ARow, AColumn: Integer): string;

    { The level to draw at a scale: the smallest one still at least as
      detailed as the screen, so nothing is drawn from fewer pixels than it
      covers. Past level 0's detail, level 0.
      @param(AScreenPixelsPerUnit Screen pixels per unit of
        @link(Bounds) across, such as pixels per degree of longitude.)
      @returns(The level, 0 for the full image; -1 if there are none.) }
    function LevelFor(AScreenPixelsPerUnit: Double): Integer;

    { Pixels per unit of @link(Bounds) across a level, such as pixels per
      degree of longitude.
      @param(ALevel The level.)
      @returns(The pixels per unit; 0 if the bounds have no width.) }
    function PixelsPerUnit(ALevel: Integer): Double;

    { Checks the description makes sense: a known format, a tile size, and
      levels that the tile size cuts exactly, each half the last.
      @raises(ETileSetError saying what is wrong.) }
    procedure Validate;

    { Reads a tile set's description.
      @param(AFolder The tile set's folder, holding
        @link(TILESET_FILE_NAME).)
      @returns(The description, checked with @link(Validate).)
      @raises(ETileSetError if it is missing, unreadable or does not make
        sense.) }
    class function Load(const AFolder: string): TTileSet; static;

    { Writes the description into a tile set's folder, under a temporary
      name first and then renamed, so a reader never sees half a file.
      @param(AFolder The tile set's folder.)
      @raises(ETileSetError if it cannot be written.) }
    procedure Save(const AFolder: string);
  end;

implementation

uses
  System.IOUtils, System.Math, System.Rtti,
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON;

{ The Neon configuration for reading and writing a tile set: names exactly
  as in the [NeonProperty] attributes, laid out readably, and exceptions
  raised rather than logged, so a bad file is reported.
  @returns(The configuration.) }
function TileSetNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Create
    .SetMemberCase(TNeonCase.Unchanged)
    .SetPrettyPrint(True)
    .SetRaiseExceptions(True);
end;

{ TTileSetBounds }

class function TTileSetBounds.World: TTileSetBounds;
begin
  Result.West := -180;
  Result.North := 90;
  Result.East := 180;
  Result.South := -90;
end;

function TTileSetBounds.WrapsEastWest: Boolean;
begin
  Result := SameValue(Abs(East - West), 360, 1e-9);
end;

{ TTileSet }

class function TTileSet.LevelFolderName(AWidth, AHeight: Integer): string;
begin
  Result := System.SysUtils.Format('%dx%d', [AWidth, AHeight]);
end;

function TTileSet.TileFileName(ALevel, ARow, AColumn: Integer): string;
begin
  Result := TPath.Combine(Levels[ALevel].Folder,
    System.SysUtils.Format('r%.3d_c%.3d.%s', [ARow, AColumn, ImageFormat]));
end;

function TTileSet.PixelsPerUnit(ALevel: Integer): Double;
var
  LSpan: Double;
begin
  LSpan := Abs(Bounds.East - Bounds.West);
  if (LSpan = 0) or not InRange(ALevel, 0, High(Levels)) then
    Exit(0);
  Result := Levels[ALevel].Width / LSpan;
end;

function TTileSet.LevelFor(AScreenPixelsPerUnit: Double): Integer;
var
  LLevel: Integer;
begin
  if Length(Levels) = 0 then
    Exit(-1);
  // From the smallest level up, the first with enough detail
  for LLevel := High(Levels) downto 0 do
    if PixelsPerUnit(LLevel) >= AScreenPixelsPerUnit then
      Exit(LLevel);
  Result := 0;
end;

procedure TTileSet.Validate;
var
  LLevel: Integer;
begin
  if Format <> TILESET_FORMAT then
    raise ETileSetError.CreateFmt('Tile set format %d is not supported; this program ' +
      'reads format %d.', [Format, TILESET_FORMAT]);
  if TileSize < 1 then
    raise ETileSetError.Create('The tile set has no tile size.');
  if Length(Levels) = 0 then
    raise ETileSetError.Create('The tile set has no levels.');
  if (ImageFormat = '') or (ImageFormat.IndexOfAny(['/', '\', '.']) >= 0) then
    raise ETileSetError.CreateFmt('The tile set''s image format "%s" is not valid.',
      [ImageFormat]);
  for LLevel := 0 to High(Levels) do
  begin
    if (Levels[LLevel].Columns * TileSize <> Levels[LLevel].Width) or
       (Levels[LLevel].Rows * TileSize <> Levels[LLevel].Height) then
      raise ETileSetError.CreateFmt('Level %d (%d x %d) is not %d x %d tiles of %d pixels.',
        [LLevel, Levels[LLevel].Width, Levels[LLevel].Height, Levels[LLevel].Columns,
         Levels[LLevel].Rows, TileSize]);
    if (LLevel > 0) and ((Levels[LLevel].Width * 2 <> Levels[LLevel - 1].Width) or
       (Levels[LLevel].Height * 2 <> Levels[LLevel - 1].Height)) then
      raise ETileSetError.CreateFmt('Level %d is not half the size of level %d.',
        [LLevel, LLevel - 1]);
    // A folder name could otherwise lead outside the tile set
    if (Levels[LLevel].Folder = '') or (Levels[LLevel].Folder.IndexOfAny(['/', '\']) >= 0) or
       (Levels[LLevel].Folder = '..') or (Levels[LLevel].Folder = '.') then
      raise ETileSetError.CreateFmt('Level %d''s folder "%s" is not valid.',
        [LLevel, Levels[LLevel].Folder]);
  end;
end;

class function TTileSet.Load(const AFolder: string): TTileSet;
var
  LFileName: string;
begin
  LFileName := TPath.Combine(AFolder, TILESET_FILE_NAME);
  if not TFile.Exists(LFileName) then
    raise ETileSetError.CreateFmt('%s has no %s, so it is not a finished tile set.',
      [AFolder, TILESET_FILE_NAME]);
  try
    Result := TNeon.JSONToValue<TTileSet>(
      TEncoding.UTF8.GetString(TFile.ReadAllBytes(LFileName)), TileSetNeonConfig);
  except
    on E: Exception do
      raise ETileSetError.CreateFmt('Could not read %s: %s', [LFileName, E.Message]);
  end;
  Result.Validate;
end;

procedure TTileSet.Save(const AFolder: string);
var
  LFileName, LTempName, LJSON: string;
begin
  LFileName := TPath.Combine(AFolder, TILESET_FILE_NAME);
  LTempName := LFileName + '.tmp';
  try
    LJSON := TNeon.ValueToJSONString(TValue.From<TTileSet>(Self), TileSetNeonConfig);
    TFile.WriteAllBytes(LTempName, TEncoding.UTF8.GetBytes(LJSON));
    if TFile.Exists(LFileName) then
      TFile.Delete(LFileName);
    TFile.Move(LTempName, LFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise ETileSetError.CreateFmt('Could not write %s: %s', [LFileName, E.Message]);
    end;
  end;
end;

end.
