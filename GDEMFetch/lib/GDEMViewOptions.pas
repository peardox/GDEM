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

  Written with Neon: every public property of @link(TViewOptions) is saved,
  so a new choice only needs a new property. The file is written to a
  temporary file first and renamed over the old one.

  No FMX: any program can use it. }
unit GDEMViewOptions;

interface

uses
  System.SysUtils;

const
  { The view choices file, in the settings folder. }
  VIEW_OPTIONS_FILE_NAME = 'view.json';

type
  { @abstract(Raised when the view choices cannot be read or written.) }
  EViewOptionsError = class(Exception);

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
  end;

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
