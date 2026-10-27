{ @abstract(Chooses how GDEMFetch draws: with Skia, on the GPU or the CPU.)

  GDEMFetch draws with Skia, which comes with Delphi. Skia can draw on the
  CPU or on the GPU, and which it uses has to be decided before
  @code(Application.Initialize), so @link(ConfigureDrawing) is called first
  thing in @code(GDEMFetch.dpr). It reads @link(TGDEMSettings.Drawing) from
  the settings file, so a change in File > Settings takes effect the next
  time the program starts.

  What each choice means on each platform, from Skia's own canvas code
  (@code(FMX.Skia.Canvas)):
  @unorderedList(
    @item(Windows: the GPU through Vulkan when FMX's
      @code(GlobalUseVulkan) is on and the driver supports Vulkan 1.1,
      otherwise OpenGL, otherwise the CPU after all. The CPU choice sets
      @code(GlobalUseSkiaRasterWhenAvailable), which is Skia's default.)
    @item(macOS: the GPU through Metal (@code(GlobalUseMetal)), or the CPU.)
    @item(Linux: Skia has only the CPU there, so the setting is not offered
      (see @link(GPU_DRAWING_AVAILABLE)).)
  )

  On Windows, @link(ConfigureDrawing) also applies
  @link(TGDEMSettings.GpuPreference), Windows' choice between a
  power-saving and a high-performance graphics processor (see
  @link(GDEMGpuPreference)). Windows keeps that for each program file, so
  a build at a new path would otherwise start without it.

  Measured on Windows on 27 October 2026 while panning the map: about 14
  to 21 frames a second on the CPU, 34 to 125 on the GPU (Vulkan), so the
  GPU is the default. }
unit GDEMDrawing;

interface

type
  {$SCOPEDENUMS ON}
  { @abstract(Where Skia draws.) }
  TDrawingMode = (
    { On the graphics card: much faster, and the default. }
    GPU,
    { On the processor: slower, but avoids graphics driver problems. }
    CPU);
  {$SCOPEDENUMS OFF}

const
  { How each mode is stored in the settings file. }
  DRAWING_MODE_KEYS: array[TDrawingMode] of string = ('GPU', 'CPU');

  { How each mode is shown in File > Settings. }
  DRAWING_MODE_CAPTIONS: array[TDrawingMode] of string = ('GPU (faster)', 'CPU');

  { The mode used when the settings file has none, or one this version
    does not know. }
  DEFAULT_DRAWING_MODE = TDrawingMode.GPU;

{$IF defined(MSWINDOWS) or (defined(MACOS) and not defined(IOS))}
  { @true where Skia can draw on the GPU, so the choice is worth offering:
    Windows and macOS. }
  GPU_DRAWING_AVAILABLE = True;
{$ELSE}
  { @true where Skia can draw on the GPU, so the choice is worth offering:
    Windows and macOS. }
  GPU_DRAWING_AVAILABLE = False;
{$ENDIF}

{ Turns a stored drawing mode back into a mode.
  @param(AKey A key from @link(DRAWING_MODE_KEYS), in any case.)
  @returns(The matching mode, or @link(DEFAULT_DRAWING_MODE) if AKey is not
    one of them.) }
function DrawingModeFromKey(const AKey: string): TDrawingMode;

{ Turns Skia on and tells it where to draw, from the settings file, and on
  Windows makes Windows' graphics processor preference for this program
  match @link(TGDEMSettings.GpuPreference) when that is power saving or
  high performance. (A setting of let Windows decide leaves the registry
  alone, so a choice made in Windows' own Settings stands.) Call it before
  @code(Application.Initialize). Settings that cannot be read give the
  defaults; the main window reports any problem with them later, as
  usual. }
procedure ConfigureDrawing;

{ Describes how the program is drawing, for the Debug tab.
  @returns(Such as "Drawing with Skia: asked for the GPU, using
    TVkCanvas; Windows graphics processor: High performance".) }
function DescribeDrawing: string;

implementation

uses
  System.SysUtils, FMX.Types, FMX.Graphics, FMX.Skia,
  GDEMSettings, GDEMGpuPreference;

var
  { The mode @link(ConfigureDrawing) asked Skia for. }
  StartupMode: TDrawingMode = DEFAULT_DRAWING_MODE;
  { Windows' preference when the program started, before any change. }
  StartupGpuPreference: TGpuPreference = TGpuPreference.Automatic;
  { @true if @link(StartupGpuPreference) could be read. }
  StartupGpuPreferenceRead: Boolean;
  { The preference @link(ConfigureDrawing) wrote, because the settings
    asked for a different one; @code(Automatic) when nothing was
    written. }
  WrittenGpuPreference: TGpuPreference = TGpuPreference.Automatic;
  { @true if writing @link(WrittenGpuPreference) failed. }
  GpuPreferenceWriteFailed: Boolean;

function DrawingModeFromKey(const AKey: string): TDrawingMode;
var
  LMode: TDrawingMode;
begin
  for LMode := Low(TDrawingMode) to High(TDrawingMode) do
    if SameText(AKey.Trim, DRAWING_MODE_KEYS[LMode]) then
      Exit(LMode);
  Result := DEFAULT_DRAWING_MODE;
end;

procedure ConfigureDrawing;
var
  LSettings: TGDEMSettings;
  LWanted: TGpuPreference;
begin
  StartupMode := DEFAULT_DRAWING_MODE;
  LWanted := DEFAULT_GPU_PREFERENCE;
  LSettings := TGDEMSettings.Create;
  try
    try
      if LSettings.Load then
      begin
        StartupMode := DrawingModeFromKey(LSettings.Drawing);
        LWanted := GpuPreferenceFromKey(LSettings.GpuPreference);
      end;
    except
      // Unreadable settings are reported once the main window is up
    end;
  finally
    LSettings.Free;
  end;

  // Windows reads its preference as the program starts, so one written now
  // may only count from the next start; DescribeDrawing says which
  StartupGpuPreferenceRead := ReadGpuPreference(StartupGpuPreference);
  if StartupGpuPreferenceRead and (LWanted <> TGpuPreference.Automatic) and
     (LWanted <> StartupGpuPreference) then
  begin
    WrittenGpuPreference := LWanted;
    GpuPreferenceWriteFailed := not WriteGpuPreference(LWanted);
  end;
  if not GPU_DRAWING_AVAILABLE then
    StartupMode := TDrawingMode.CPU;

  GlobalUseSkia := True;
  {$IF defined(MSWINDOWS)}
  // True puts Skia's CPU canvas ahead of its GPU ones
  GlobalUseSkiaRasterWhenAvailable := StartupMode = TDrawingMode.CPU;
  {$ELSEIF defined(MACOS) and not defined(IOS)}
  GlobalUseMetal := StartupMode = TDrawingMode.GPU;
  {$ENDIF}
end;

function DescribeDrawing: string;
var
  LCanvas: string;
begin
  if TCanvasManager.DefaultCanvas <> nil then
    LCanvas := TCanvasManager.DefaultCanvas.ClassName
  else
    LCanvas := 'an unknown canvas';
  Result := Format('Drawing with Skia: asked for the %s, using %s',
    [DRAWING_MODE_KEYS[StartupMode], LCanvas]);
  if (StartupMode = TDrawingMode.GPU) and SameText(LCanvas, 'TSkRasterCanvas') then
    Result := Result + ' (no usable GPU, so the CPU)';
  if StartupGpuPreferenceRead then
  begin
    Result := Result + '; Windows graphics processor: ' +
      GPU_PREFERENCE_CAPTIONS[StartupGpuPreference];
    if WrittenGpuPreference <> TGpuPreference.Automatic then
      if GpuPreferenceWriteFailed then
        Result := Result + Format(' (could not change it to %s as Settings asks)',
          [GPU_PREFERENCE_CAPTIONS[WrittenGpuPreference]])
      else
        Result := Result + Format(' (changed to %s, as Settings asks, from the next start)',
          [GPU_PREFERENCE_CAPTIONS[WrittenGpuPreference]]);
  end;
end;

end.
