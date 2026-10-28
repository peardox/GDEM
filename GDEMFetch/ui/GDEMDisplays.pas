{ @abstract(Which display a form is on, and that display's refresh rate.)

  The 3D view draws no more frames a second than the display it is on can
  show, and checks again when the window moves to another display. The
  way each system is asked is Sprite3D's (@code(DisplayData)), cut down
  to these two questions:

  @preformatted(
Windows  the monitor Windows puts most of the window on (MonitorFromWindow),
         and its current mode's frequency (EnumDisplaySettings)
macOS    FMX's display for the form; its refresh rate from CoreGraphics,
         the main display's for the primary, the others in the system's
         order
Linux    FMX's display for the form; refresh rate 0, unknown
  )

  A refresh rate of 0 means the system did not say (macOS does not for
  some built-in panels). For the main thread. }
unit GDEMDisplays;

interface

uses
  System.SysUtils, System.Types, FMX.Forms;

type
  { @abstract(The display a form is on.) }
  TFormDisplay = record
    { Names the display, to tell when the form has moved to another:
      Windows' device name, such as @code(\\.\DISPLAY1), elsewhere
      @code(Display) and its number. Empty if it cannot be told. }
    Name: string;
    { The display's refresh rate, hertz; 0 if the system does not say. }
    RefreshRate: Integer;
  end;

{ The display a form is on, and its refresh rate.
  @param(AForm The form; one without a window yet gives an empty name.)
  @param(AReadRate @false to leave the refresh rate 0 and only name the
    display, which is quicker: enough to tell whether the form has moved.)
  @returns(The display.) }
function DisplayOfForm(const AForm: TCommonCustomForm; AReadRate: Boolean): TFormDisplay;

implementation

uses
  {$IF DEFINED(MSWINDOWS)}
  Winapi.Windows, Winapi.MultiMon, FMX.Platform.Win;
  {$ELSE}
  System.Math;
  {$ENDIF}

{$IF DEFINED(MSWINDOWS)}

const
  { Asks @code(EnumDisplaySettings) for the mode in use. }
  ENUM_CURRENT_SETTINGS = DWORD(-1);

function DisplayOfForm(const AForm: TCommonCustomForm; AReadRate: Boolean): TFormDisplay;
var
  LWnd: HWND;
  LInfo: TMonitorInfoEx;
  LMode: TDevMode;
begin
  Result.Name := '';
  Result.RefreshRate := 0;
  if (AForm = nil) or (AForm.Handle = nil) then
    Exit;
  LWnd := WindowHandleToPlatform(AForm.Handle).Wnd;
  if LWnd = 0 then
    Exit;
  FillChar(LInfo, SizeOf(LInfo), 0);
  LInfo.cbSize := SizeOf(TMonitorInfoEx);
  if not GetMonitorInfo(MonitorFromWindow(LWnd, MONITOR_DEFAULTTONEAREST), @LInfo) then
    Exit;
  Result.Name := string(LInfo.szDevice);
  if not AReadRate then
    Exit;
  FillChar(LMode, SizeOf(LMode), 0);
  LMode.dmSize := SizeOf(TDevMode);
  // 0 and 1 both mean the hardware's default, which says nothing
  if EnumDisplaySettings(PChar(Result.Name), ENUM_CURRENT_SETTINGS, LMode) and
     (LMode.dmDisplayFrequency > 1) then
    Result.RefreshRate := LMode.dmDisplayFrequency;
end;

{$ELSE}

{$IF DEFINED(MACOS) and not DEFINED(IOS)}
const
  { CoreGraphics, declared here as Sprite3D does, so nothing depends on
    which of these a Delphi version translates. }
  CORE_GRAPHICS = '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics';

  { The most displays asked about. }
  MAX_DISPLAYS = 32;

{ CoreGraphics' main display.
  @returns(Its display id.) }
function CGMainDisplayID: UInt32; cdecl; external CORE_GRAPHICS name 'CGMainDisplayID';

{ CoreGraphics' active displays.
  @param(AMaxDisplays Room in the list.)
  @param(ADisplays The list.)
  @param(ACount How many were put in it.)
  @returns(0 on success.) }
function CGGetActiveDisplayList(AMaxDisplays: UInt32; ADisplays: PUInt32;
  ACount: PUInt32): Int32; cdecl; external CORE_GRAPHICS name 'CGGetActiveDisplayList';

{ A display's mode, to be released.
  @param(ADisplay The display id.)
  @returns(The mode, or nil.) }
function CGDisplayCopyDisplayMode(ADisplay: UInt32): Pointer; cdecl;
  external CORE_GRAPHICS name 'CGDisplayCopyDisplayMode';

{ A mode's refresh rate.
  @param(AMode The mode.)
  @returns(Hertz; 0 if not known.) }
function CGDisplayModeGetRefreshRate(AMode: Pointer): Double; cdecl;
  external CORE_GRAPHICS name 'CGDisplayModeGetRefreshRate';

{ Releases a mode.
  @param(AMode The mode.) }
procedure CGDisplayModeRelease(AMode: Pointer); cdecl;
  external CORE_GRAPHICS name 'CGDisplayModeRelease';

{ A CoreGraphics display's refresh rate.
  @param(ADisplay The display id.)
  @returns(Hertz; 0 if not known.) }
function CGRefreshRate(ADisplay: UInt32): Integer;
var
  LMode: Pointer;
begin
  Result := 0;
  LMode := CGDisplayCopyDisplayMode(ADisplay);
  if LMode = nil then
    Exit;
  try
    Result := Round(CGDisplayModeGetRefreshRate(LMode));
  finally
    CGDisplayModeRelease(LMode);
  end;
end;

{ The refresh rate of FMX's display at a place among the others.
  @param(APrimary @true for the primary display.)
  @param(AOthersBefore How many displays that are not primary come before
    it in FMX's list.)
  @returns(Hertz; 0 if not known.) }
function PlatformRefreshRate(APrimary: Boolean; AOthersBefore: Integer): Integer;
var
  LIds: array[0..MAX_DISPLAYS - 1] of UInt32;
  LCount: UInt32;
  LMain: UInt32;
  I, LSeen: Integer;
begin
  LMain := CGMainDisplayID;
  Result := CGRefreshRate(LMain);
  if APrimary then
    Exit;
  // The others in CoreGraphics' order, as Sprite3D matches them; a
  // display not found keeps the main display's rate
  LCount := 0;
  if CGGetActiveDisplayList(MAX_DISPLAYS, @LIds[0], @LCount) <> 0 then
    Exit;
  LSeen := 0;
  for I := 0 to Integer(LCount) - 1 do
    if LIds[I] <> LMain then
    begin
      if LSeen = AOthersBefore then
        Exit(CGRefreshRate(LIds[I]));
      Inc(LSeen);
    end;
end;
{$ELSE}

{ The refresh rate of a display, which this system does not say.
  @param(APrimary @true for the primary display.)
  @param(AOthersBefore How many displays that are not primary come before
    it.)
  @returns(0, unknown.) }
function PlatformRefreshRate(APrimary: Boolean; AOthersBefore: Integer): Integer;
begin
  Result := 0;
end;
{$ENDIF}

function DisplayOfForm(const AForm: TCommonCustomForm; AReadRate: Boolean): TFormDisplay;
var
  LIndex, I, LOthers: Integer;
begin
  Result.Name := '';
  Result.RefreshRate := 0;
  if (AForm = nil) or (Screen.DisplayCount = 0) then
    Exit;
  LIndex := Screen.DisplayFromForm(AForm).Index;
  if not InRange(LIndex, 0, Screen.DisplayCount - 1) then
    Exit;
  Result.Name := Format('Display %d', [LIndex + 1]);
  if not AReadRate then
    Exit;
  LOthers := 0;
  for I := 0 to LIndex - 1 do
    if not Screen.Displays[I].Primary then
      Inc(LOthers);
  Result.RefreshRate := PlatformRefreshRate(Screen.Displays[LIndex].Primary, LOthers);
end;

{$ENDIF}

end.
