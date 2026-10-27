{ @abstract(Opens the tile set GDEMFetch draws as its high-resolution
  map.)

  The tile set is made by TileMaker (see @code(GDEMTileSet)) as the
  repository's @code(maps/tiles), packed into one zip,
  @code(maps/tiles.zip), by @code(tools/pack_tiles.py), and linked into the
  program as the @link(MAP_TILES_RESOURCE) resource, so nothing has to be
  deployed on any platform. }
unit GDEMMapTiles;

interface

uses
  System.SysUtils,
  GDEMTileCache;

const
  { The RCDATA resource holding the tile set, packed as a zip. }
  MAP_TILES_RESOURCE = 'MAPTILES';

  { How the tile set's origin is described in the log. }
  BUILT_IN_MAP_TILES = 'built into the program';

{ Opens the tile set linked into the program.
  @param(ACapacity Most tiles to keep in memory, besides pinned ones.)
  @returns(The tile set, whose @code(Origin) is @link(BUILT_IN_MAP_TILES).)
  @raises(Exception if the resource is missing, as in a build without it,
    or does not hold a valid tile set.) }
function OpenBuiltInMapTiles(
  ACapacity: Integer = DEFAULT_TILE_CACHE_CAPACITY): TTileCache;

implementation

uses
  {$IFDEF MSWINDOWS}
  // RT_RCDATA; other platforms have it in System.Types
  Winapi.Windows,
  {$ENDIF}
  System.Classes, System.Types;

function OpenBuiltInMapTiles(ACapacity: Integer): TTileCache;
begin
  // The cache owns the stream from here on, and frees it if this raises
  Result := TTileCache.CreateFromPack(
    TResourceStream.Create(HInstance, MAP_TILES_RESOURCE, RT_RCDATA),
    BUILT_IN_MAP_TILES, ACapacity);
end;

end.
