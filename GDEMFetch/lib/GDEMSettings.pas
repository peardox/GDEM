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

  { Default for @link(TGDEMSettings.MinFreePercent): keep 10% of the drive
    free. SSDs in particular need spare space to stay fast and last. }
  DEFAULT_RESERVE_PERCENT = 10;

  { The lowest @link(TGDEMSettings.MinFreePercent) allowed: some space is
    always kept free, so the drive never fills completely. }
  MIN_RESERVE_PERCENT = 1;

  { The highest @link(TGDEMSettings.MinFreePercent) allowed. }
  MAX_RESERVE_PERCENT = 50;

  { Default for @link(TGDEMSettings.ImportWorkers): one file at a time,
    which suits every kind of drive. }
  DEFAULT_IMPORT_WORKERS = 1;

  { Most files downloaded at once at any speed. NASA does not publish a
    limit, but cuts off or refuses downloads when it has had enough; the
    downloads then back off by themselves (see @code(TDownloadThrottle)). }
  MAX_DOWNLOAD_WORKERS = 16;

type
  {$SCOPEDENUMS ON}
  { @abstract(How hard downloads push NASA's servers.)

    Each speed sets how many files download at once to begin with
    (@link(DOWNLOAD_SPEED_START)) and the most they may climb to
    (@link(DOWNLOAD_SPEED_MAX)). Downloads climb towards the most while
    they go well and halve when NASA objects, the way TCP shares a network
    (additive increase, multiplicative decrease; see
    @code(TDownloadThrottle)). }
  TDownloadSpeed = (
    { Suits a slow or shared connection: starts at 1, at most 4. }
    Slow,
    { The default: starts at 2, at most 8. }
    Medium,
    { Suits a fast connection: starts at 4, at most 16. }
    Fast);
  {$SCOPEDENUMS OFF}

const
  { Files downloaded at once when a batch starts, for each speed. }
  DOWNLOAD_SPEED_START: array[TDownloadSpeed] of Integer = (1, 2, 4);

  { Most files downloaded at once, for each speed. None is above
    @link(MAX_DOWNLOAD_WORKERS). }
  DOWNLOAD_SPEED_MAX: array[TDownloadSpeed] of Integer = (4, 8, MAX_DOWNLOAD_WORKERS);

  { How each speed is stored in the settings file and shown to the user. }
  DOWNLOAD_SPEED_KEYS: array[TDownloadSpeed] of string = ('Slow', 'Medium', 'Fast');

  { Default for @link(TGDEMSettings.DownloadSpeed). }
  DEFAULT_DOWNLOAD_SPEED = TDownloadSpeed.Medium;

  { A token with fewer days than this left gets a warning. }
  TOKEN_WARN_DAYS = 7;

{ Reads when an Earthdata Login bearer token stops working. The token is a
  JSON Web Token: three parts separated by full stops, the middle one
  holding its claims, including @code(exp), the expiry time in seconds
  since 1970 (UTC). The token is not checked with NASA, only read.
  @param(AToken The token.)
  @param(AExpires Receives the expiry time, in local time.)
  @returns(@true if the token held an expiry time; @false if it is empty
    or not a token this can read.) }
function TokenExpiry(const AToken: string; out AExpires: TDateTime): Boolean;

{ Describes when a bearer token expires, for the user.
  @param(AToken The token.)
  @returns(Such as "Token expires 25 Dec 2026 20:13 (59 days left)",
    "Token expired on ...", "Token expiry not known", or an empty string
    if AToken is empty.) }
function DescribeTokenExpiry(const AToken: string): string;

{ Turns a stored download speed back into a speed.
  @param(AKey A key from @link(DOWNLOAD_SPEED_KEYS), in any case.)
  @returns(The matching speed, or @link(DEFAULT_DOWNLOAD_SPEED) if AKey
    is not one of them.) }
function DownloadSpeedFromKey(const AKey: string): TDownloadSpeed;

{ Tidies a folder path: removes surrounding spaces and any trailing path
  separator, except where the separator is part of a root. A drive root
  stays @code(F:\) (and a bare @code(F:) becomes @code(F:\)), because
  @code(F:) on its own means the current folder on drive F, not its root;
  the POSIX root stays @code(/).
  @param(APath The folder as typed or chosen.)
  @returns(The tidied folder, or an empty string if APath is blank.) }
function NormalizeFolder(const APath: string): string;

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
    { Backing field for @link(MinFreePercent). }
    FMinFreePercent: Integer;
    { Backing field for @link(Theme). }
    FTheme: string;
    { Backing field for @link(ImportWorkers). }
    FImportWorkers: Integer;
    { Backing field for @link(DownloadSpeed). }
    FDownloadSpeed: string;
    { Backing field for @link(Drawing). }
    FDrawing: string;
    { Backing field for @link(GpuPreference). }
    FGpuPreference: string;

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

    { How much of the drive holding @link(DataFolder) downloads, imports
      and moves must leave free, as a percentage of the drive's size, from
      @link(MIN_RESERVE_PERCENT) to @link(MAX_RESERVE_PERCENT); values
      outside that are kept to it when used. A batch stops before going
      below it. Defaults to @link(DEFAULT_RESERVE_PERCENT). Settings saved
      by older versions held a fixed size in megabytes
      (@code(minFreeSpaceMB)); that is ignored, so they start at the
      default. }
    property MinFreePercent: Integer read FMinFreePercent write FMinFreePercent;

    { The look of the program, stored by key: @code(Default), @code(Dark),
      @code(AquaGraphite), @code(RubyGraphite) or @code(GoldenGraphite).
      Kept as text so that a name this version does not know can never stop
      the settings loading; use @code(ThemeFromKey) in @code(GDEMThemes) to
      turn it into a theme. Defaults to @code(Default). }
    property Theme: string read FTheme write FTheme;

    { How many files an import copies at once. 1 suits a spinning hard
      disk, where copying several files at once makes the heads jump
      between them; on SSDs, a higher number (such as 4) can be several
      times faster, by hiding the time each file takes to open, flush,
      check and rename. Defaults to @link(DEFAULT_IMPORT_WORKERS). }
    property ImportWorkers: Integer read FImportWorkers write FImportWorkers;

    { How hard downloads push NASA's servers, stored by key:
      @code(Slow), @code(Medium) or @code(Fast); see @link(TDownloadSpeed).
      A single download often uses only part of a fast connection, because
      of the distance to NASA's servers in the USA, so several at once can
      be much faster. Kept as text so that a value this version does not
      know can never stop the settings loading; use
      @link(DownloadSpeedFromKey) to turn it into a speed. Defaults to
      @code(Medium). }
    property DownloadSpeed: string read FDownloadSpeed write FDownloadSpeed;

    { Where the program draws, stored by key: @code(GPU) or @code(CPU); see
      @code(TDrawingMode) in @code(GDEMDrawing). Read once at start-up, so a
      change takes effect the next time the program starts. Kept as text so
      that a value this version does not know can never stop the settings
      loading. Defaults to @code(GPU). }
    property Drawing: string read FDrawing write FDrawing;

    { Which graphics processor Windows starts the program on, stored by
      key: @code(Automatic) (let Windows decide), @code(PowerSaving) or
      @code(HighPerformance); see @code(TGpuPreference) in
      @code(GDEMGpuPreference). Windows keeps the real setting in the
      registry, for each program file; this copy lets a new build, at a new
      path, be given the same choice at start-up. Windows only. Kept as
      text so that a value this version does not know can never stop the
      settings loading. Defaults to @code(Automatic). }
    property GpuPreference: string read FGpuPreference write FGpuPreference;
  end;

implementation

uses
  System.IOUtils, System.Character, System.NetEncoding, System.DateUtils, System.Math,
  {$IFDEF POSIX}
  Posix.SysStat,
  {$ENDIF}
  Neon.Core.Persistence, Neon.Core.Persistence.JSON;

function NormalizeFolder(const APath: string): string;
begin
  Result := Trim(APath);
  if Result = '' then
    Exit;
  {$IFDEF MSWINDOWS}
  // A drive letter alone, or a drive root
  if (Length(Result) = 2) and (Result[2] = ':') then
    Exit(Result + PathDelim);
  if (Length(Result) = 3) and (Result[2] = ':') and IsPathDelimiter(Result, 3) then
    Exit;
  {$ENDIF}
  if Result = PathDelim then
    Exit;
  Result := ExcludeTrailingPathDelimiter(Result);
end;

type
  { The one claim read from a bearer token by @link(TokenExpiry). Other
    claims in the token are ignored. }
  TTokenClaims = class
  private
    { Backing field for @link(Exp). }
    FExp: Int64;
  public
    { Expiry time, in seconds since 1970 (UTC); 0 if the token has none. }
    property Exp: Int64 read FExp write FExp;
  end;

function TokenExpiry(const AToken: string; out AExpires: TDateTime): Boolean;
var
  LParts: TArray<string>;
  LPayload, LJSON: string;
  LClaims: TTokenClaims;
begin
  Result := False;
  AExpires := 0;
  LParts := AToken.Trim.Split(['.']);
  if Length(LParts) <> 3 then
    Exit;
  // Base64url: '-' and '_' for '+' and '/', and no padding
  LPayload := LParts[1].Replace('-', '+').Replace('_', '/');
  while Length(LPayload) mod 4 <> 0 do
    LPayload := LPayload + '=';
  LClaims := TTokenClaims.Create;
  try
    try
      LJSON := TEncoding.UTF8.GetString(TNetEncoding.Base64.DecodeStringToBytes(LPayload));
      TNeon.JSONToObject(LClaims, LJSON, TNeonConfiguration.Camel);
    except
      // Not a token this can read; the caller says the expiry is unknown
      Exit;
    end;
    if LClaims.Exp <= 0 then
      Exit;
    AExpires := UnixToDateTime(LClaims.Exp, False);
    Result := True;
  finally
    LClaims.Free;
  end;
end;

function DescribeTokenExpiry(const AToken: string): string;
var
  LExpires: TDateTime;
  LDays: Double;
begin
  if AToken.Trim = '' then
    Exit('');
  if not TokenExpiry(AToken, LExpires) then
    Exit('Token expiry not known');
  LDays := LExpires - Now;
  if LDays <= 0 then
    Result := 'Token expired on ' + FormatDateTime('d mmm yyyy hh:nn', LExpires)
  else if LDays < 1 then
    Result := Format('Token expires %s (in %d hours)',
      [FormatDateTime('d mmm yyyy hh:nn', LExpires), Max(1, Trunc(LDays * 24))])
  else
    Result := Format('Token expires %s (%d days left)',
      [FormatDateTime('d mmm yyyy hh:nn', LExpires), Trunc(LDays)]);
end;

function DownloadSpeedFromKey(const AKey: string): TDownloadSpeed;
var
  LSpeed: TDownloadSpeed;
begin
  for LSpeed := Low(TDownloadSpeed) to High(TDownloadSpeed) do
    if SameText(AKey.Trim, DOWNLOAD_SPEED_KEYS[LSpeed]) then
      Exit(LSpeed);
  Result := DEFAULT_DOWNLOAD_SPEED;
end;

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
  FMinFreePercent := DEFAULT_RESERVE_PERCENT;
  FTheme := 'Default';
  FImportWorkers := DEFAULT_IMPORT_WORKERS;
  FDownloadSpeed := DOWNLOAD_SPEED_KEYS[DEFAULT_DOWNLOAD_SPEED];
  // GDEMDrawing's default, written out so this unit needs no FMX
  FDrawing := 'GPU';
  FGpuPreference := 'Automatic';
end;

class function TGDEMSettings.DefaultDataFolder: string;
begin
  Result := TPath.Combine(TPath.GetDocumentsPath, 'ASTGTM');
end;

procedure TGDEMSettings.SetDataFolder(const AValue: string);
begin
  FDataFolder := NormalizeFolder(AValue);
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
