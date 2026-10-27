{ @abstract(Finds the tile set GDEMFetch draws as its high-resolution
  map.)

  The tile set is a folder made by TileMaker, holding a
  @code(tileset.json) (see @code(GDEMTileSet)). It is looked for, in this
  order:
  @orderedList(
    @item(the folder chosen in Settings, if one is; then only that one;)
    @item(a folder named @link(MAP_TILES_FOLDER_NAME) beside the program;)
    @item(on macOS, that folder in the app bundle's @code(Resources);)
    @item(@code(maps/tiles) beside the program or in any of the folders
      above it, up to @link(MAX_SEARCH_LEVELS) levels: this finds the
      repository's own tile set when the program runs from a build folder
      such as @code(GDEMFetch/Win64/Debug).)
  )
  The first folder with a @code(tileset.json) is used. }
unit GDEMMapTiles;

interface

uses
  System.SysUtils;

const
  { The name of a tile set folder beside the program. }
  MAP_TILES_FOLDER_NAME = 'tiles';

  { The repository's folder of maps, holding @link(MAP_TILES_FOLDER_NAME). }
  REPOSITORY_MAPS_FOLDER = 'maps';

  { How many folders above the program are searched for
    @code(maps/tiles). }
  MAX_SEARCH_LEVELS = 6;

{ The folders where a tile set is looked for, in order.
  @param(AConfigured The folder chosen in Settings, or empty to search.)
  @returns(The folders, which need not exist: just AConfigured if it is
    set, otherwise the places listed in this unit's description.) }
function MapTilesCandidates(const AConfigured: string): TArray<string>;

{ Finds the tile set to draw.
  @param(AConfigured The folder chosen in Settings, or empty to search.)
  @returns(The first of @link(MapTilesCandidates) that holds a
    @code(tileset.json), or an empty string if none does.) }
function FindMapTiles(const AConfigured: string): string;

implementation

uses
  System.IOUtils,
  GDEMTileSet;

function MapTilesCandidates(const AConfigured: string): TArray<string>;
var
  LProgramFolder, LFolder, LParent: string;
  LLevel: Integer;
begin
  if AConfigured.Trim <> '' then
  begin
    // Assigned, not passed to Exit, where [...] would be read as a set
    Result := [AConfigured.Trim];
    Exit;
  end;

  LProgramFolder := ExtractFileDir(ParamStr(0));
  Result := [TPath.Combine(LProgramFolder, MAP_TILES_FOLDER_NAME)];
  {$IF defined(MACOS) and not defined(IOS)}
  // Inside an app bundle the program is in Contents/MacOS, and files that
  // go with it in Contents/Resources
  Result := Result + [TPath.Combine(TPath.Combine(ExtractFileDir(LProgramFolder),
    'Resources'), MAP_TILES_FOLDER_NAME)];
  {$ENDIF}

  // The repository's maps/tiles, from a build folder inside it
  LFolder := LProgramFolder;
  for LLevel := 0 to MAX_SEARCH_LEVELS do
  begin
    Result := Result + [TPath.Combine(TPath.Combine(LFolder, REPOSITORY_MAPS_FOLDER),
      MAP_TILES_FOLDER_NAME)];
    LParent := ExtractFileDir(LFolder);
    if (LParent = '') or (LParent = LFolder) then
      Break;
    LFolder := LParent;
  end;
end;

function FindMapTiles(const AConfigured: string): string;
var
  LFolder: string;
begin
  for LFolder in MapTilesCandidates(AConfigured) do
    if TFile.Exists(TPath.Combine(LFolder, TILESET_FILE_NAME)) then
      Exit(LFolder);
  Result := '';
end;

end.
