{ @abstract(The themes GDEM programs can be shown in.)

  @link(TGDEMTheme) lists them: FMX's own platform look (@code(Default)),
  and four of the FMX styles that come with RAD Studio: @code(Dark),
  @code(AquaGraphite), @code(RubyGraphite) and @code(GoldenGraphite). The
  choice is kept in the settings by its key (@link(ThemeKey)), so a name the
  program does not know, perhaps from a later version, simply means
  @code(Default).

  @link(ApplyTheme) gives the whole application the theme, title bars
  included (see @link(GDEMTitleBar)). Each style is looked for first as an
  RCDATA resource called @code(GDEM<Key>Style), such as
  @code(GDEMDarkStyle), which @code(styles/GDEMThemes.rc) links into every
  build, then, should that be missing, as a file:
  @orderedList(
    @item(in a @code(styles) folder beside the program;)
    @item(beside the program;)
    @item(in the repository's @code(styles) folder, when run from the IDE;)
    @item(in a @code(styles) folder in the settings folder;)
    @item(on Windows, in RAD Studio's @code(Redist\styles\Fmx) folder, when
      the @code(BDS) environment variable is set, as it is when run from
      the IDE.)
  )

  Modelled on Sprite3D's themes, so both projects look and behave alike.
  Call on the main thread only. }
unit GDEMThemes;

interface

uses
  System.SysUtils, System.UITypes;

type
  { The themes available. }
  TGDEMTheme = (
    { FMX's own platform look, with the system's title bars. }
    thDefault,
    { RAD Studio's Dark style. }
    thDark,
    { RAD Studio's Aqua Graphite style. }
    thAquaGraphite,
    { RAD Studio's Ruby Graphite style. }
    thRubyGraphite,
    { RAD Studio's Golden Graphite style. }
    thGoldenGraphite
  );

{ The key a theme is stored under in the settings, which is also its style's
  file name without @code(.style).
  @param(ATheme The theme.)
  @returns(For example @code(AquaGraphite).) }
function ThemeKey(ATheme: TGDEMTheme): string;

{ The name to show the user for a theme.
  @param(ATheme The theme.)
  @returns(For example @code(Aqua Graphite).) }
function ThemeCaption(ATheme: TGDEMTheme): string;

{ Finds the theme stored under a key. Matching ignores case.
  @param(AKey The key from the settings.)
  @returns(The theme, or @code(thDefault) for an empty or unknown key.) }
function ThemeFromKey(const AKey: string): TGDEMTheme;

{ Gives the whole application, title bars included, the look ATheme names.
  @code(thDefault) puts back FMX's own platform style and the system's
  title bars.
  @param(ATheme The look to use.)
  @param(AError On failure, why, including where the style was looked
    for.)
  @returns(@true if the look is now in use; @false leaves the current one,
    title bars included.) }
function ApplyTheme(ATheme: TGDEMTheme; out AError: string): Boolean;

implementation

uses
  System.IOUtils,
  GDEMStyles, GDEMTitleBar, GDEMSettings;

type
  { What the program knows about each theme. }
  TThemeInfo = record
    { Stored in the settings; also the style's file name. }
    Key: string;
    { Shown to the user. }
    Caption: string;
    { Caption colour if the style's background cannot be read. }
    Fallback: TAlphaColor;
    { Window border colour; @code(TAlphaColors.Null) for the system's. }
    Accent: TAlphaColor;
  end;

const
  { Prefix of the RCDATA resource names in @code(styles/GDEMThemes.rc). }
  STYLE_RESOURCE_PREFIX = 'GDEM';
  { Suffix of the RCDATA resource names in @code(styles/GDEMThemes.rc). }
  STYLE_RESOURCE_SUFFIX = 'Style';

  { Every theme's details, in the order of @link(TGDEMTheme). }
  THEMES: array[TGDEMTheme] of TThemeInfo = (
    (Key: 'Default';        Caption: 'Default';         Fallback: TAlphaColors.White; Accent: TAlphaColors.Null),
    (Key: 'Dark';           Caption: 'Dark';            Fallback: $FF2B2B2B;          Accent: TAlphaColors.Null),
    (Key: 'AquaGraphite';   Caption: 'Aqua Graphite';   Fallback: $FF3A3A3A;          Accent: $FF2A9FD6),
    (Key: 'RubyGraphite';   Caption: 'Ruby Graphite';   Fallback: $FF3A3A3A;          Accent: $FFC0262C),
    (Key: 'GoldenGraphite'; Caption: 'Golden Graphite'; Fallback: $FF3A3A3A;          Accent: $FFD4A017));

function ThemeKey(ATheme: TGDEMTheme): string;
begin
  Result := THEMES[ATheme].Key;
end;

function ThemeCaption(ATheme: TGDEMTheme): string;
begin
  Result := THEMES[ATheme].Caption;
end;

function ThemeFromKey(const AKey: string): TGDEMTheme;
var
  LTheme: TGDEMTheme;
begin
  for LTheme := Low(TGDEMTheme) to High(TGDEMTheme) do
    if SameText(AKey, THEMES[LTheme].Key) then
      Exit(LTheme);
  Result := thDefault;
end;

{ The folders to look in for a style file that is not linked in, in order.
  @returns(The folders; some may not exist.) }
function StyleFolders: TArray<string>;
var
  LExeDir: string;
  {$IFDEF MSWINDOWS}
  LBds: string;
  {$ENDIF}
begin
  LExeDir := ExtractFilePath(ParamStr(0));
  Result := [
    TPath.Combine(LExeDir, 'styles'),
    LExeDir,
    // GDEMFetch\<Platform>\<Config>\ when run from the IDE
    TPath.GetFullPath(TPath.Combine(LExeDir, '..' + PathDelim + '..' + PathDelim +
      '..' + PathDelim + 'styles')),
    TPath.Combine(TGDEMSettings.SettingsFolder, 'styles')];
  {$IFDEF MSWINDOWS}
  // Set by the IDE for programs it runs
  LBds := GetEnvironmentVariable('BDS');
  if LBds <> '' then
    Result := Result + [TPath.Combine(LBds, 'Redist\styles\Fmx')];
  {$ENDIF}
end;

function ApplyTheme(ATheme: TGDEMTheme; out AError: string): Boolean;
var
  LStyleName, LResourceName: string;
begin
  if ATheme = thDefault then
  begin
    LStyleName := '';
    LResourceName := '';
  end
  else
  begin
    LStyleName := THEMES[ATheme].Key;
    LResourceName := STYLE_RESOURCE_PREFIX + LStyleName + STYLE_RESOURCE_SUFFIX;
  end;

  Result := ApplyFmxStyle(LStyleName, LResourceName, StyleFolders, AError);
  if not Result then
    Exit;   // the old style is still in use; so are its title bars

  if ATheme = thDefault then
    SetTitleBarSpec(TGDEMTitleBarSpec.System)
  else
    SetTitleBarSpec(TitleBarSpecFromStyle(THEMES[ATheme].Fallback, THEMES[ATheme].Accent));
end;

end.
