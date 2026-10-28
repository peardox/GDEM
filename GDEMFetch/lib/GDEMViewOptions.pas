{ @abstract(Remembers what the View menu shows on the map, between runs.)

  The choices are kept in @link(VIEW_OPTIONS_FILE_NAME) in the settings
  folder (see @code(TGDEMSettings.SettingsFolder)), apart from
  @code(settings.json): that file's presence tells the program it has been
  set up before, so writing view choices into it on a first run would skip
  the first-run Settings dialog.

  The layers that cost the most to draw without a GPU (country borders,
  coastlines, town and city names and the high-resolution map) start off;
  the tile tints, which are what the map is for and cost one bitmap
  stretch, and the user's own markers start on. A choice missing from the
  file, such as one added in a later version, keeps its default.

  The 3D tab's detail, height stretch and distance detail, and the Map
  tab's Click for 3D switch, are kept here too.

  Those defaults suit drawing on the CPU or a low-powered graphics
  processor. The first time the user changes how GDEMFetch draws to
  something faster, @link(SuggestedViewLayers) says which layers to turn
  on for it, and @link(TViewOptions.DrawingSuggestionMade) records that
  this has been done, so it is done once only. @link(VIEW_LAYERS_BY_COST)
  lists the layers from the most demanding to the least, for telling the
  user which to turn off first if the map is slow.

  Written with Neon: every public property of @link(TViewOptions) is saved,
  so a new choice only needs a new property. The file is written to a
  temporary file first and renamed over the old one.

  No FMX: any program can use it. }
unit GDEMViewOptions;

interface

uses
  System.SysUtils,
  GDEMGpuPreference;

const
  { The view choices file, in the settings folder. }
  VIEW_OPTIONS_FILE_NAME = 'view.json';

type
  { @abstract(Raised when the view choices cannot be read or written.) }
  EViewOptionsError = class(Exception);

  { @abstract(One of the things the View menu can show on the map.) }
  TViewLayer = (
    { Coastlines. }
    vlCoastlines,
    { Country borders. }
    vlBorders,
    { Town and city names. }
    vlPlaces,
    { The high-resolution map. }
    vlMapTiles,
    { The tint of tiles that have data. }
    vlAvailableTiles,
    { The tint of downloaded tiles. }
    vlDownloadedTiles,
    { The user's markers. }
    vlMarkers);

  { @abstract(A set of @link(TViewLayer) values.) }
  TViewLayers = set of TViewLayer;

const
  { Every layer. }
  ALL_VIEW_LAYERS = [Low(TViewLayer)..High(TViewLayer)];

  { The layers from the most demanding to draw to the least, when drawing
    on the GPU: the 1:50m coastline (about 60,000 points zoomed in), then
    the borders, then up to 250 town names placed and drawn each frame,
    then the high-resolution map (tiles decoded as they come into view,
    cheap to draw on a GPU), then the two tints (one bitmap stretch each),
    then the markers. Estimated from the timings of the lines and of
    filling pixels, not measured for every layer; on the CPU the
    high-resolution map and the tints, which fill the window, would come
    higher. }
  VIEW_LAYERS_BY_COST: array[0..6] of TViewLayer = (vlCoastlines, vlBorders,
    vlPlaces, vlMapTiles, vlAvailableTiles, vlDownloadedTiles, vlMarkers);

type
  { @abstract(What the View menu shows on the map.)

    Only public properties are saved. }
  TViewOptions = class
  private
    { Backing field for @link(ShowAvailableTiles). }
    FShowAvailableTiles: Boolean;
    { Backing field for @link(ShowDownloadedTiles). }
    FShowDownloadedTiles: Boolean;
    { Backing field for @link(ShowBorders). }
    FShowBorders: Boolean;
    { Backing field for @link(ShowCoastlines). }
    FShowCoastlines: Boolean;
    { Backing field for @link(ShowMapTiles). }
    FShowMapTiles: Boolean;
    { Backing field for @link(ShowPlaces). }
    FShowPlaces: Boolean;
    { Backing field for @link(ShowMarkers). }
    FShowMarkers: Boolean;
    { Backing field for @link(DrawingSuggestionMade). }
    FDrawingSuggestionMade: Boolean;
    { Backing field for @link(TerrainDetail). }
    FTerrainDetail: Integer;
    { Backing field for @link(TerrainHeights). }
    FTerrainHeights: Integer;
    { Backing field for @link(ClickShows3D). }
    FClickShows3D: Boolean;
    { Backing field for @link(TerrainRange). }
    FTerrainRange: Integer;
    { Backing field for @link(TerrainRealistic). }
    FTerrainRealistic: Boolean;
    { Backing field for @link(TerrainControlsCollapsed). }
    FTerrainControlsCollapsed: Boolean;
    { Backing field for @link(TerrainLabels). }
    FTerrainLabels: Boolean;
    { Backing field for @link(TerrainAutopilot). }
    FTerrainAutopilot: Boolean;
  public
    { Sets the defaults: tile tints and markers on, the other layers
      off. }
    constructor Create;

    { The file the choices are kept in.
      @returns(@link(VIEW_OPTIONS_FILE_NAME) in the settings folder.) }
    class function FileName: string; static;

    { Reads the file, if there is one. Choices it does not mention keep
      their values.
      @returns(@true if the file was there and read.)
      @raises(EViewOptionsError if it is there but cannot be read.) }
    function Load: Boolean;

    { Writes the file.
      @raises(EViewOptionsError if it cannot be written.) }
    procedure Save;

    { Tiles that have data are tinted cyan. On by default. }
    property ShowAvailableTiles: Boolean read FShowAvailableTiles write FShowAvailableTiles;

    { Downloaded tiles are tinted green. On by default. }
    property ShowDownloadedTiles: Boolean read FShowDownloadedTiles write FShowDownloadedTiles;

    { Country borders are drawn. Off by default. }
    property ShowBorders: Boolean read FShowBorders write FShowBorders;

    { Coastlines are drawn. Off by default. }
    property ShowCoastlines: Boolean read FShowCoastlines write FShowCoastlines;

    { The high-resolution map is drawn, when there is a tile set. Off by
      default. }
    property ShowMapTiles: Boolean read FShowMapTiles write FShowMapTiles;

    { Towns and cities are labelled. Off by default. }
    property ShowPlaces: Boolean read FShowPlaces write FShowPlaces;

    { The user's markers are drawn. On by default. }
    property ShowMarkers: Boolean read FShowMarkers write FShowMarkers;

    { @true once layers have been turned on to suit a faster way of
      drawing (see @link(SuggestedViewLayers)), so it happens only the
      first time. @false by default. }
    property DrawingSuggestionMade: Boolean read FDrawingSuggestionMade
      write FDrawingSuggestionMade;

    { The 3D tab's detail: the most samples across a tile near the camera
      (see @code(TERRAIN_DETAILS) in @code(GDEMTerrain)). 3601 (Full) by
      default. }
    property TerrainDetail: Integer read FTerrainDetail write FTerrainDetail;

    { The 3D tab's height stretch, times true scale. 2 by default. }
    property TerrainHeights: Integer read FTerrainHeights write FTerrainHeights;

    { No longer used: the Map tab's switch, now Launch Mode, starts on
      every time. Kept so older files read as before. }
    property ClickShows3D: Boolean read FClickShows3D write FClickShows3D;

    { The 3D tab's distance detail, in tenths (see @code(TERRAIN_RANGES)
      in @code(GDEMTerrain)): a patch is split when the camera is nearer
      than this many tenths of its size. 20 (Medium) by default. }
    property TerrainRange: Integer read FTerrainRange write FTerrainRange;

    { The 3D tab's Realistic switch: @true to draw satellite imagery
      instead of height colours. @false by default. }
    property TerrainRealistic: Boolean read FTerrainRealistic write FTerrainRealistic;

    { The 3D view's controls panel: @true if collapsed to its title.
      @false (open) by default. }
    property TerrainControlsCollapsed: Boolean read FTerrainControlsCollapsed
      write FTerrainControlsCollapsed;

    { The 3D tab's Labels switch: @true to show the names of places on
      poles over the ground. @true by default. }
    property TerrainLabels: Boolean read FTerrainLabels write FTerrainLabels;

    { The 3D tab's Autopilot box: @true to keep the flight clear of the
      ground. @false by default. }
    property TerrainAutopilot: Boolean read FTerrainAutopilot write FTerrainAutopilot;
  end;

{ The layers to turn on the first time the user chooses how GDEMFetch
  draws, for that choice:
  @unorderedList(
    @item(on the CPU: none, since the defaults suit it;)
    @item(on the GPU on Windows with the High performance graphics
      processor: every layer;)
    @item(on the GPU on Windows otherwise (Let Windows decide, or Power
      saving, usually the graphics built into the processor): borders,
      coastlines and the high-resolution map, but not town and city names;)
    @item(on the GPU on macOS (Metal): every layer;)
    @item(elsewhere (Linux draws only on the CPU): none.)
  )
  @param(AOnGpu @true if drawing on the GPU was chosen.)
  @param(AGpuPreference Windows' graphics processor choice; ignored
    elsewhere.)
  @returns(The layers; empty if nothing should change.) }
function SuggestedViewLayers(AOnGpu: Boolean; AGpuPreference: TGpuPreference): TViewLayers;

implementation

uses
  System.IOUtils,
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON,
  GDEMSettings;

{ The Neon configuration for both reading and writing, so the two agree on
  member names.
  @returns(Camel-case member names, laid out readably, exceptions raised
    on bad data.) }
function ViewNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Camel
    .SetPrettyPrint(True)
    .SetRaiseExceptions(True);
end;

function SuggestedViewLayers(AOnGpu: Boolean; AGpuPreference: TGpuPreference): TViewLayers;
begin
  Result := [];
  if not AOnGpu then
    Exit;
  {$IF defined(MSWINDOWS)}
  if AGpuPreference = TGpuPreference.HighPerformance then
    Result := ALL_VIEW_LAYERS
  else
    Result := [vlBorders, vlCoastlines, vlMapTiles];
  {$ELSEIF defined(MACOS) and not defined(IOS)}
  Result := ALL_VIEW_LAYERS;
  {$ENDIF}
end;

{ TViewOptions }

constructor TViewOptions.Create;
begin
  inherited Create;
  FShowAvailableTiles := True;
  FShowDownloadedTiles := True;
  FShowBorders := False;
  FShowCoastlines := False;
  FShowMapTiles := False;
  FShowPlaces := False;
  FShowMarkers := True;
  // Written out, as GDEMTerrain's defaults, so this unit stays small
  FTerrainDetail := 3601;
  FTerrainHeights := 2;
  FTerrainRange := 20;
  FTerrainLabels := True;
end;

class function TViewOptions.FileName: string;
begin
  Result := TPath.Combine(TGDEMSettings.SettingsFolder, VIEW_OPTIONS_FILE_NAME);
end;

function TViewOptions.Load: Boolean;
var
  LFileName: string;
begin
  LFileName := FileName;
  if not TFile.Exists(LFileName) then
    Exit(False);
  try
    TNeon.JSONToObject(Self, TEncoding.UTF8.GetString(TFile.ReadAllBytes(LFileName)),
      ViewNeonConfig);
  except
    on E: Exception do
      raise EViewOptionsError.CreateFmt('Could not read %s: %s', [LFileName, E.Message]);
  end;
  Result := True;
end;

procedure TViewOptions.Save;
var
  LFileName, LTempName, LJSON: string;
begin
  LFileName := FileName;
  LTempName := LFileName + '.tmp';
  try
    ForceDirectories(TGDEMSettings.SettingsFolder);
    LJSON := TNeon.ObjectToJSONString(Self, ViewNeonConfig);
    TFile.WriteAllBytes(LTempName, TEncoding.UTF8.GetBytes(LJSON));
    if TFile.Exists(LFileName) then
      TFile.Delete(LFileName);
    TFile.Move(LTempName, LFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise EViewOptionsError.CreateFmt('Could not write %s: %s', [LFileName, E.Message]);
    end;
  end;
end;

end.
