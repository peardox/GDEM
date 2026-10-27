{ @abstract(Windows' choice of graphics processor for this program, as
  Settings > System > Display > Graphics sets it.)

  On a computer with two graphics processors, such as a laptop with a
  power-saving one built into the processor and a high-performance one
  beside it, Windows keeps for each program file which to start it on: let
  Windows decide, power saving, or high performance. It is a string value
  named after the program's full path under
  @code(HKCU\Software\Microsoft\DirectX\UserGpuPreferences), such as
  @code(GpuPreference=2;). Windows reads it when the program starts, so a
  change takes effect at the next start.

  The value can hold other settings as well, separated by semicolons
  (Windows 11 adds @code(SwapEffectUpgradeEnable=1;) for its windowed games
  optimisation), so only the @code(GpuPreference) part is changed and the
  rest is kept.

  Ported from Sprite3D's @code(GpuPreference) unit
  (@url(https://github.com/peardox/Sprite3D)), which Sprite3D sets from its
  own Settings dialog.

  Only Windows has this; elsewhere @link(ReadGpuPreference) and
  @link(WriteGpuPreference) do nothing and return @false, so callers need
  no conditional compilation. Safe to call from any thread. }
unit GDEMGpuPreference;

interface

type
  {$SCOPEDENUMS ON}
  { @abstract(Which graphics processor Windows starts the program on.) }
  TGpuPreference = (
    { Let Windows decide: no @code(GpuPreference) is kept, and Windows
      usually picks the power-saving processor for a program like this. }
    Automatic,
    { The power-saving processor, usually the one built into the CPU;
      stored as 1. }
    PowerSaving,
    { The high-performance processor, usually the separate graphics card;
      stored as 2. }
    HighPerformance);
  {$SCOPEDENUMS OFF}

const
  { How each preference is stored in the settings file. }
  GPU_PREFERENCE_KEYS: array[TGpuPreference] of string =
    ('Automatic', 'PowerSaving', 'HighPerformance');

  { How each preference is shown in File > Settings, in Windows' own
    words. }
  GPU_PREFERENCE_CAPTIONS: array[TGpuPreference] of string =
    ('Let Windows decide', 'Power saving', 'High performance');

  { The preference used when the settings file has none, or one this
    version does not know: leave the choice to Windows, as for any other
    program. }
  DEFAULT_GPU_PREFERENCE = TGpuPreference.Automatic;

{$IF defined(MSWINDOWS)}
  { @true where the choice exists, so it is worth offering: Windows. }
  GPU_PREFERENCE_AVAILABLE = True;
{$ELSE}
  { @true where the choice exists, so it is worth offering: Windows. }
  GPU_PREFERENCE_AVAILABLE = False;
{$ENDIF}

{ Turns a stored preference back into a preference.
  @param(AKey A key from @link(GPU_PREFERENCE_KEYS), in any case.)
  @returns(The matching preference, or @link(DEFAULT_GPU_PREFERENCE) if
    AKey is not one of them.) }
function GpuPreferenceFromKey(const AKey: string): TGpuPreference;

{ Reads Windows' preference for the running program. Nothing is written.
  @param(APreference Receives the preference;
    @code(TGpuPreference.Automatic) if there is none, or it cannot be read,
    or the number in it is neither 1 nor 2.)
  @returns(@true if the registry could be read, whether or not it held a
    preference for this program; @false where there is no such registry or
    it could not be opened.) }
function ReadGpuPreference(out APreference: TGpuPreference): Boolean;

{ Sets Windows' preference for the running program, keeping any other
  settings in the same value. @code(TGpuPreference.Automatic) removes the
  preference, and the whole value if nothing else is left in it. Takes
  effect the next time the program starts.
  @param(APreference The preference.)
  @returns(@true if it was written or removed; @false where there is no
    such registry or it could not be written.) }
function WriteGpuPreference(APreference: TGpuPreference): Boolean;

implementation

uses
  System.SysUtils
  {$IF defined(MSWINDOWS)}
  , System.Win.Registry, Winapi.Windows
  {$ENDIF}
  ;

function GpuPreferenceFromKey(const AKey: string): TGpuPreference;
var
  LPreference: TGpuPreference;
begin
  for LPreference := Low(TGpuPreference) to High(TGpuPreference) do
    if SameText(AKey.Trim, GPU_PREFERENCE_KEYS[LPreference]) then
      Exit(LPreference);
  Result := DEFAULT_GPU_PREFERENCE;
end;

{$IF defined(MSWINDOWS)}
const
  { Where Windows keeps each program's graphics settings, under
    @code(HKEY_CURRENT_USER). }
  GPU_PREFERENCE_KEY = 'Software\Microsoft\DirectX\UserGpuPreferences';

  { The name of the setting inside a program's value. }
  GPU_PREFERENCE_NAME = 'GpuPreference';

{ The registry value's name for the running program: its full path, as
  Windows uses.
  @returns(The path of the executable.) }
function ProgramValueName: string;
begin
  Result := ParamStr(0);
end;

{ Splits a value such as @code(SwapEffectUpgradeEnable=1;GpuPreference=2;)
  into its settings, leaving out the @code(GpuPreference) one.
  @param(AData The value.)
  @param(AFound Receives the number given for @code(GpuPreference), or -1
    if there is none.)
  @returns(The other settings, each still in @code(Name=Value) form.) }
function OtherSettings(const AData: string; out AFound: Integer): TArray<string>;
var
  LPart, LName, LValue: string;
  LEquals: Integer;
begin
  AFound := -1;
  Result := nil;
  for LPart in AData.Split([';']) do
  begin
    if LPart.Trim = '' then
      Continue;
    LEquals := LPart.IndexOf('=');
    if LEquals < 0 then
      LName := LPart.Trim
    else
      LName := LPart.Substring(0, LEquals).Trim;
    if SameText(LName, GPU_PREFERENCE_NAME) then
    begin
      if LEquals >= 0 then
        LValue := LPart.Substring(LEquals + 1).Trim
      else
        LValue := '';
      AFound := StrToIntDef(LValue, 0);
    end
    else
      Result := Result + [LPart.Trim];
  end;
end;

function ReadGpuPreference(out APreference: TGpuPreference): Boolean;
var
  LRegistry: TRegistry;
  LFound: Integer;
begin
  APreference := TGpuPreference.Automatic;
  Result := False;
  LRegistry := TRegistry.Create(KEY_READ);
  try
    try
      LRegistry.RootKey := HKEY_CURRENT_USER;
      // No key at all is the same as no preferences anywhere
      if not LRegistry.KeyExists(GPU_PREFERENCE_KEY) then
        Exit(True);
      if not LRegistry.OpenKeyReadOnly(GPU_PREFERENCE_KEY) then
        Exit;
      try
        Result := True;
        if not LRegistry.ValueExists(ProgramValueName) then
          Exit;
        OtherSettings(LRegistry.ReadString(ProgramValueName), LFound);
        case LFound of
          1: APreference := TGpuPreference.PowerSaving;
          2: APreference := TGpuPreference.HighPerformance;
        end;
      finally
        LRegistry.CloseKey;
      end;
    except
      // A value of the wrong type, say: as good as no preference
      on E: ERegistryException do
        Result := False;
    end;
  finally
    LRegistry.Free;
  end;
end;

function WriteGpuPreference(APreference: TGpuPreference): Boolean;
var
  LRegistry: TRegistry;
  LOthers: TArray<string>;
  LFound: Integer;
  LData: string;
begin
  Result := False;
  LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      LRegistry.RootKey := HKEY_CURRENT_USER;
      if not LRegistry.OpenKey(GPU_PREFERENCE_KEY, APreference <> TGpuPreference.Automatic) then
        // Automatic with no key at all: nothing to remove
        Exit(APreference = TGpuPreference.Automatic);
      try
        LOthers := nil;
        if LRegistry.ValueExists(ProgramValueName) then
          LOthers := OtherSettings(LRegistry.ReadString(ProgramValueName), LFound);
        case APreference of
          TGpuPreference.PowerSaving:
            LOthers := LOthers + [GPU_PREFERENCE_NAME + '=1'];
          TGpuPreference.HighPerformance:
            LOthers := LOthers + [GPU_PREFERENCE_NAME + '=2'];
        end;
        if Length(LOthers) = 0 then
        begin
          if LRegistry.ValueExists(ProgramValueName) then
            LRegistry.DeleteValue(ProgramValueName);
        end
        else
        begin
          // Windows writes each setting followed by a semicolon
          LData := string.Join(';', LOthers) + ';';
          LRegistry.WriteString(ProgramValueName, LData);
        end;
        Result := True;
      finally
        LRegistry.CloseKey;
      end;
    except
      on E: ERegistryException do
        Result := False;
    end;
  finally
    LRegistry.Free;
  end;
end;
{$ELSE}
function ReadGpuPreference(out APreference: TGpuPreference): Boolean;
begin
  APreference := TGpuPreference.Automatic;
  Result := False;
end;

function WriteGpuPreference(APreference: TGpuPreference): Boolean;
begin
  Result := False;
end;
{$ENDIF}

end.
