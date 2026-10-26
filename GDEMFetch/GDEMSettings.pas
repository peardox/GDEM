{ @abstract(Persistent application settings for GDEM.)

  Settings are stored as @code(settings.json) in a per-user folder chosen to
  suit each operating system:
  @unorderedList(
    @item(Windows: @code(%APPDATA%\GDEM))
    @item(macOS: @code(~/Library/Application Support/GDEM))
    @item(Linux: @code($XDG_CONFIG_HOME/GDEM), or @code(~/.config/GDEM)
      when @code(XDG_CONFIG_HOME) is not set)
    @item(Android and iOS: a @code(GDEM) folder in the app's private
      documents folder)
  )

  The file is written and read with the Neon JSON library
  (@url(https://github.com/paolo-rossi/delphi-neon)). Every public property
  of @link(TGDEMSettings) is saved, so new settings only need a new
  property.

  The bearer token is a credential, so on macOS, Linux and other POSIX
  systems the file is made readable and writable by its owner only. On
  Windows the per-user AppData folder already restricts access to the
  current user. }
unit GDEMSettings;

interface

uses
  System.SysUtils;

const
  { Name of the per-user folder settings are kept in. }
  SETTINGS_FOLDER_NAME = 'GDEM';

  { Name of the settings file inside @link(SETTINGS_FOLDER_NAME). }
  SETTINGS_FILE_NAME = 'settings.json';

  { Default for @link(TGDEMSettings.MinFreeSpaceMB): keep 2 GB free. }
  DEFAULT_MIN_FREE_SPACE_MB = 2048;

type
  { @abstract(Raised when settings cannot be read or written.) }
  ESettingsError = class(Exception);

  { @abstract(The user's saved settings.)

    Create one, call @link(Load), and check its result to find out whether
    settings already existed. Change properties and call @link(Save) to
    write them back.

    Only public properties are saved. Methods and private fields are not. }
  TGDEMSettings = class
  private
    { Backing field for @link(BearerToken). }
    FBearerToken: string;
    { Backing field for @link(DataFolder). }
    FDataFolder: string;
    { Backing field for @link(DataFolderUsed). }
    FDataFolderUsed: Boolean;
    { Backing field for @link(MinFreeSpaceMB). }
    FMinFreeSpaceMB: Integer;

    { Writer for @link(DataFolder); trims spaces and any trailing path
      separator. It has no other side effects, because Neon may set
      properties in any order when loading.
      @param(AValue The folder.) }
    procedure SetDataFolder(const AValue: string);

    { Writer for @link(BearerToken); stores the cleaned-up token.
      @param(AValue The token as entered.) }
    procedure SetBearerToken(const AValue: string);
  public
    { Creates settings with default values, which are kept for any
      setting missing from the file when it is loaded. }
    constructor Create;

    { Default folder for downloaded tiles: an @code(ASTGTM) folder in the
      user's documents folder.
      @returns(Full path of the folder.) }
    class function DefaultDataFolder: string; static;

    { Folder settings are stored in for the current user and platform.
      The folder is not created by this call.
      @returns(Full path of the folder.) }
    class function SettingsFolder: string; static;

    { Full path of the settings file.
      @returns(@link(SettingsFolder) combined with
        @link(SETTINGS_FILE_NAME).) }
    class function SettingsFileName: string; static;

    { Checks whether a settings file has been saved before.
      @returns(@true if the settings file exists.) }
    class function Exists: Boolean; static;

    { Removes every character a pasted token should not contain: spaces,
      tabs and line breaks anywhere, and a leading @code(Bearer) word.
      @param(AToken The token as pasted by the user.)
      @returns(The token ready to send in an @code(Authorization) header.) }
    class function CleanToken(const AToken: string): string; static;

    { Reads the settings file into this object.
      @returns(@true if the file existed and was read; @false if there is
        no settings file yet, in which case the properties are unchanged.)
      @raises(ESettingsError if the file exists but cannot be read or is
        not valid settings JSON.) }
    function Load: Boolean;

    { Writes this object to the settings file, creating the folder if
      needed. The file is written to a temporary name first and then
      renamed, so an interrupted save cannot leave a half-written file.
      @raises(ESettingsError if the file cannot be written.) }
    procedure Save;

    { Earthdata Login bearer token, used to download files from NASA
      Earthdata Cloud. Generated at @url(https://urs.earthdata.nasa.gov).
      Whitespace and a leading @code(Bearer) word are removed when it is
      set; see @link(CleanToken). Empty when no token has been entered. }
    property BearerToken: string read FBearerToken write SetBearerToken;

    { Folder downloaded tiles are kept in; see @link(TGDEMStore). May be
      on a removable drive. Defaults to @link(DefaultDataFolder). When
      changing it, also set @link(DataFolderUsed) to match the new
      folder. }
    property DataFolder: string read FDataFolder write SetDataFolder;

    { @true once the program has set up @link(DataFolder). If the folder
      is then missing, it is taken to be on a drive that is not connected,
      and the user is asked to connect it rather than it being created
      again somewhere unexpected. }
    property DataFolderUsed: Boolean read FDataFolderUsed write FDataFolderUsed;

    { Free space, in megabytes, that downloads must leave on the drive
      holding @link(DataFolder). A batch of downloads stops before going
      below it. Defaults to @link(DEFAULT_MIN_FREE_SPACE_MB). }
    property MinFreeSpaceMB: Integer read FMinFreeSpaceMB write FMinFreeSpaceMB;
  end;

implementation

uses
  System.IOUtils, System.Character,
  {$IFDEF POSIX}
  Posix.SysStat,
  {$ENDIF}
  Neon.Core.Persistence, Neon.Core.Persistence.JSON;

{ Returns the Neon configuration used for both reading and writing, so the
  two always agree on member names.
  @returns(Camel-case member names, pretty-printed, raising exceptions on
    bad data.) }
function SettingsNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Camel
    .SetPrettyPrint(True)
    .SetRaiseExceptions(True);
end;

{ TGDEMSettings }

constructor TGDEMSettings.Create;
begin
  inherited Create;
  FDataFolder := DefaultDataFolder;
  FMinFreeSpaceMB := DEFAULT_MIN_FREE_SPACE_MB;
end;

class function TGDEMSettings.DefaultDataFolder: string;
begin
  Result := TPath.Combine(TPath.GetDocumentsPath, 'ASTGTM');
end;

procedure TGDEMSettings.SetDataFolder(const AValue: string);
begin
  FDataFolder := ExcludeTrailingPathDelimiter(Trim(AValue));
end;

procedure TGDEMSettings.SetBearerToken(const AValue: string);
begin
  FBearerToken := CleanToken(AValue);
end;

class function TGDEMSettings.SettingsFolder: string;
{$IF defined(LINUX) and not defined(ANDROID)}
var
  LConfigHome: string;
{$ENDIF}
begin
  {$IF defined(MSWINDOWS)}
  // TPath.GetHomePath is %APPDATA% (the roaming profile) on Windows
  Result := TPath.Combine(TPath.GetHomePath, SETTINGS_FOLDER_NAME);
  {$ELSEIF defined(ANDROID) or defined(IOS)}
  // Mobile apps may only write inside their own sandbox
  Result := TPath.Combine(TPath.GetDocumentsPath, SETTINGS_FOLDER_NAME);
  {$ELSEIF defined(MACOS)}
  Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetHomePath,
    'Library'), 'Application Support'), SETTINGS_FOLDER_NAME);
  {$ELSEIF defined(LINUX)}
  // XDG Base Directory specification
  LConfigHome := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if LConfigHome = '' then
    LConfigHome := TPath.Combine(TPath.GetHomePath, '.config');
  Result := TPath.Combine(LConfigHome, SETTINGS_FOLDER_NAME);
  {$ELSE}
  Result := TPath.Combine(TPath.GetHomePath, SETTINGS_FOLDER_NAME);
  {$ENDIF}
end;

class function TGDEMSettings.SettingsFileName: string;
begin
  Result := TPath.Combine(SettingsFolder, SETTINGS_FILE_NAME);
end;

class function TGDEMSettings.Exists: Boolean;
begin
  Result := TFile.Exists(SettingsFileName);
end;

class function TGDEMSettings.CleanToken(const AToken: string): string;
var
  LBuilder: TStringBuilder;
  LText: string;
  LChar: Char;
begin
  // Drop a leading "Bearer " copied along with the token from a header
  LText := AToken.Trim;
  if (Length(LText) > 6) and LText.StartsWith('Bearer', True) and
     LText.Chars[6].IsWhiteSpace then
    LText := LText.Substring(6);

  // Tokens never contain whitespace, but pasting can introduce line breaks
  LBuilder := TStringBuilder.Create(Length(LText));
  try
    for LChar in LText do
      if not LChar.IsWhiteSpace then
        LBuilder.Append(LChar);
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TGDEMSettings.Load: Boolean;
var
  LFileName, LJSON: string;
begin
  LFileName := SettingsFileName;
  if not TFile.Exists(LFileName) then
    Exit(False);
  try
    LJSON := TEncoding.UTF8.GetString(TFile.ReadAllBytes(LFileName));
    TNeon.JSONToObject(Self, LJSON, SettingsNeonConfig);
  except
    on E: Exception do
      raise ESettingsError.CreateFmt('Could not read settings from %s: %s',
        [LFileName, E.Message]);
  end;
  Result := True;
end;

procedure TGDEMSettings.Save;
var
  LFileName, LTempName, LJSON: string;
begin
  LFileName := SettingsFileName;
  LTempName := LFileName + '.tmp';
  try
    ForceDirectories(SettingsFolder);
    LJSON := TNeon.ObjectToJSONString(Self, SettingsNeonConfig);
    TFile.WriteAllBytes(LTempName, TEncoding.UTF8.GetBytes(LJSON));
    {$IFDEF POSIX}
    // Owner read/write only: the file holds a credential
    chmod(PAnsiChar(UTF8String(LTempName)), S_IRUSR or S_IWUSR);
    {$ENDIF}
    if TFile.Exists(LFileName) then
      TFile.Delete(LFileName);
    TFile.Move(LTempName, LFileName);
  except
    on E: Exception do
    begin
      if TFile.Exists(LTempName) then
        TFile.Delete(LTempName);
      raise ESettingsError.CreateFmt('Could not save settings to %s: %s',
        [LFileName, E.Message]);
    end;
  end;
end;

end.
