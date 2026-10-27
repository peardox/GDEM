{ @abstract(Colours the windows' title bars to go with the application's FMX
  style, where the operating system allows it.)

  @link(SetTitleBarSpec) stores how title bars should look and applies it at
  once to every form on screen; forms shown later get it as they are shown.
  @link(TitleBarSpecFromStyle) works out a spec from the FMX style in use,
  taking the colour of its form background.

  @table(
    @rowHead(@cell(System) @cell(What can be changed))
    @row(@cell(Windows 11) @cell(Caption, caption text and border colours
      (DWM).))
    @row(@cell(Windows 10) @cell(Dark or light title bar only (DWM immersive
      dark mode, build 17763 on).))
    @row(@cell(macOS 10.14 on) @cell(Dark or light appearance for the whole
      application (@code(NSApp.appearance)).))
    @row(@cell(Linux) @cell(Nothing: the window manager draws the title
      bar.))
    @row(@cell(Android, iOS) @cell(Nothing: there is no title bar.))
  )

  Where only dark or light is possible, a caption colour darker than mid
  grey gives dark. Calls on a system without the feature are ignored.

  Ported from Sprite3D's @code(Sprite3DTitleBar). The unit knows nothing of
  any particular application. Call it on the main thread only. }
unit GDEMTitleBar;

// Delphi also defines MACOS for iOS; this names the desktop system only
{$IF DEFINED(MACOS) and not DEFINED(IOS)}
  {$DEFINE GDEM_DESKTOP_MACOS}
{$ENDIF}

interface

uses
  System.UITypes, FMX.Forms;

type
  { @abstract(How title bars should look.) }
  TGDEMTitleBarSpec = record
    { @true to leave title bars as the system draws them; the colours are
      then ignored. }
    UseSystem: Boolean;
    { The caption's background colour; its brightness also picks dark or
      light where colours are not possible. }
    Caption: TAlphaColor;
    { The caption text's colour. }
    Text: TAlphaColor;
    { The window border's colour, or @code(TAlphaColors.Null) for the
      system's. }
    Border: TAlphaColor;

    { A spec that leaves title bars to the system.
      @returns(The spec, with @link(UseSystem) @true.) }
    class function System: TGDEMTitleBarSpec; static;

    { A spec with ACaption behind the caption, text in black or white,
      whichever reads better, and ABorder round the window.
      @param(ACaption The caption's background colour.)
      @param(ABorder The border's colour; @code(TAlphaColors.Null) for the
        system's.)
      @returns(The spec.) }
    class function Coloured(const ACaption: TAlphaColor;
      const ABorder: TAlphaColor = TAlphaColors.Null): TGDEMTitleBarSpec; static;

    { Checks whether the caption colour is darker than mid grey.
      @returns(@true if a dark title bar suits the caption colour.) }
    function IsDark: Boolean;
  end;

{ The colour of the form background in the FMX style in use.

  Reads the @code(backgroundstyle) resource that every FMX style draws
  behind a form; for a gradient, its first colour.
  @param(AColour Receives the colour found; unchanged if none is.)
  @returns(@true if the style has a background with a colour.) }
function StyleBackgroundColour(var AColour: TAlphaColor): Boolean;

{ A title bar spec to go with the FMX style in use. The caption takes the
  style's form background colour, as @link(StyleBackgroundColour) reads it,
  or AFallback if the style has none.
  @param(AFallback The caption colour to use if the style's cannot be
    read.)
  @param(ABorder The border colour, often the style's accent;
    @code(TAlphaColors.Null) for the system's.)
  @returns(The spec.) }
function TitleBarSpecFromStyle(const AFallback: TAlphaColor;
  const ABorder: TAlphaColor = TAlphaColors.Null): TGDEMTitleBarSpec;

{ Makes ASpec the look of every title bar, now and for forms shown later.
  @param(ASpec How title bars should look.) }
procedure SetTitleBarSpec(const ASpec: TGDEMTitleBarSpec);

{ Gives one form's title bar the current spec. @link(SetTitleBarSpec)
  already does this for every form; call it only for a form whose window
  has been made again. A form whose window does not exist yet is skipped.
  @param(AForm The form.) }
procedure ApplyTitleBar(const AForm: TCommonCustomForm);

implementation

uses
  System.Classes, System.Messaging, FMX.Types, FMX.Graphics, FMX.Objects, FMX.Styles
  {$IF DEFINED(MSWINDOWS)}
  , Winapi.Windows, FMX.Platform.Win
  {$ENDIF}
  ;

var
  { The spec applied to every title bar. }
  GSpec: TGDEMTitleBarSpec;
  { @true once subscribed to forms being shown. }
  GSubscribed: Boolean;
  { The subscription to @code(TFormBeforeShownMessage). }
  GSubscriptionId: Integer;

{ TGDEMTitleBarSpec }

class function TGDEMTitleBarSpec.System: TGDEMTitleBarSpec;
begin
  Result.UseSystem := True;
  Result.Caption := TAlphaColors.White;
  Result.Text := TAlphaColors.Black;
  Result.Border := TAlphaColors.Null;
end;

class function TGDEMTitleBarSpec.Coloured(const ACaption,
  ABorder: TAlphaColor): TGDEMTitleBarSpec;
begin
  Result.UseSystem := False;
  Result.Caption := ACaption or TAlphaColors.Black;   // opaque
  Result.Border := ABorder;
  if Result.IsDark then
    Result.Text := TAlphaColors.White
  else
    Result.Text := TAlphaColors.Black;
end;

function TGDEMTitleBarSpec.IsDark: Boolean;
var
  LColour: TAlphaColorRec;
begin
  LColour.Color := Caption;
  // Perceived brightness, ITU-R BT.601 weights, on 0..255
  Result := (0.299 * LColour.R + 0.587 * LColour.G + 0.114 * LColour.B) < 128;
end;

function StyleBackgroundColour(var AColour: TAlphaColor): Boolean;
var
  LStyle, LResource: TFmxObject;
  LBrush: TBrush;
begin
  Result := False;
  LStyle := TStyleManager.ActiveStyle(nil);
  if LStyle = nil then
    Exit;
  LResource := LStyle.FindStyleResource('backgroundstyle');
  if not (LResource is TShape) then
    Exit;
  LBrush := TShape(LResource).Fill;
  case LBrush.Kind of
    TBrushKind.Solid:
      begin
        AColour := LBrush.Color;
        Result := True;
      end;
    TBrushKind.Gradient:
      if LBrush.Gradient.Points.Count > 0 then
      begin
        AColour := LBrush.Gradient.Points[0].Color;
        Result := True;
      end;
  end;
end;

function TitleBarSpecFromStyle(const AFallback, ABorder: TAlphaColor): TGDEMTitleBarSpec;
var
  LColour: TAlphaColor;
begin
  LColour := AFallback;
  StyleBackgroundColour(LColour);
  Result := TGDEMTitleBarSpec.Coloured(LColour, ABorder);
end;

{$IF DEFINED(MSWINDOWS)}
{ ---------------------------------------------------------------- Windows }

const
  { Immersive dark mode, Windows 10 1809 to 1909. }
  DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;
  { Immersive dark mode, Windows 10 2004 on. }
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
  { Window border colour, Windows 11 on. }
  DWMWA_BORDER_COLOR = 34;
  { Caption colour, Windows 11 on. }
  DWMWA_CAPTION_COLOR = 35;
  { Caption text colour, Windows 11 on. }
  DWMWA_TEXT_COLOR = 36;
  { Puts back the system's colour. }
  DWMWA_COLOR_DEFAULT = $FFFFFFFF;

{ The DWM call that sets a window attribute.
  @param(AWnd The window.)
  @param(AAttribute Which attribute.)
  @param(AValue Pointer to the value.)
  @param(ASize Size of the value.)
  @returns(@code(S_OK) on success.) }
function DwmSetWindowAttribute(AWnd: HWND; AAttribute: DWORD; AValue: Pointer;
  ASize: DWORD): HRESULT; stdcall; external 'dwmapi.dll' name 'DwmSetWindowAttribute';

{ Converts a colour for Windows: a @code(TAlphaColor) is @code($AARRGGBB),
  a @code(COLORREF) is @code($00BBGGRR).
  @param(AColour The colour.)
  @returns(The @code(COLORREF).) }
function ToColorRef(const AColour: TAlphaColor): DWORD;
var
  LColour: TAlphaColorRec;
begin
  LColour.Color := AColour;
  Result := DWORD(LColour.R) or (DWORD(LColour.G) shl 8) or (DWORD(LColour.B) shl 16);
end;

{ Sets a 32-bit DWM attribute, ignoring failure where the attribute is
  unknown, as on older versions of Windows.
  @param(AWnd The window.)
  @param(AAttribute Which attribute.)
  @param(AValue The value.) }
procedure SetDword(const AWnd: HWND; const AAttribute, AValue: DWORD);
var
  LValue: DWORD;
begin
  LValue := AValue;
  DwmSetWindowAttribute(AWnd, AAttribute, @LValue, SizeOf(LValue));
end;

{ Gives one window the current spec.
  @param(AWnd The window.) }
procedure ApplyToWindow(const AWnd: HWND);
var
  LDark: BOOL;
begin
  if AWnd = 0 then
    Exit;
  LDark := not GSpec.UseSystem and GSpec.IsDark;
  if DwmSetWindowAttribute(AWnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @LDark, SizeOf(LDark)) <> S_OK then
    DwmSetWindowAttribute(AWnd, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, @LDark, SizeOf(LDark));
  if GSpec.UseSystem then
  begin
    SetDword(AWnd, DWMWA_CAPTION_COLOR, DWMWA_COLOR_DEFAULT);
    SetDword(AWnd, DWMWA_TEXT_COLOR, DWMWA_COLOR_DEFAULT);
    SetDword(AWnd, DWMWA_BORDER_COLOR, DWMWA_COLOR_DEFAULT);
  end
  else
  begin
    SetDword(AWnd, DWMWA_CAPTION_COLOR, ToColorRef(GSpec.Caption));
    SetDword(AWnd, DWMWA_TEXT_COLOR, ToColorRef(GSpec.Text));
    if GSpec.Border = TAlphaColors.Null then
      SetDword(AWnd, DWMWA_BORDER_COLOR, DWMWA_COLOR_DEFAULT)
    else
      SetDword(AWnd, DWMWA_BORDER_COLOR, ToColorRef(GSpec.Border));
  end;
end;

procedure ApplyTitleBar(const AForm: TCommonCustomForm);
begin
  if (AForm = nil) or (AForm.Handle = nil) then
    Exit;
  ApplyToWindow(FormToHWND(AForm));
end;

{ Nothing to do on Windows: each window carries its own attributes; see
  @link(ApplyTitleBar). }
procedure ApplyToApplication;
begin
end;

{$ELSEIF DEFINED(GDEM_DESKTOP_MACOS)}
{ ------------------------------------------------------------------ macOS }

const
  { The Objective-C runtime library. }
  libobjc = '/usr/lib/libobjc.A.dylib';

{ Looks up an Objective-C class.
  @param(AName The class name.)
  @returns(The class, or @nil.) }
function objc_getClass(AName: MarshaledAString): Pointer; cdecl;
  external libobjc name 'objc_getClass';

{ Looks up an Objective-C selector.
  @param(AName The selector name.)
  @returns(The selector.) }
function sel_registerName(AName: MarshaledAString): Pointer; cdecl;
  external libobjc name 'sel_registerName';

{ @code(objc_msgSend) with no arguments, typed as arm64 requires.
  @param(AObject The receiver.)
  @param(ASelector The message.)
  @returns(The result.) }
function MsgSend0(AObject, ASelector: Pointer): Pointer; cdecl;
  external libobjc name 'objc_msgSend';

{ @code(objc_msgSend) with one pointer argument.
  @param(AObject The receiver.)
  @param(ASelector The message.)
  @param(AArg The argument.)
  @returns(The result.) }
function MsgSend1(AObject, ASelector, AArg: Pointer): Pointer; cdecl;
  external libobjc name 'objc_msgSend';

{ @code(objc_msgSend) with one pointer argument and a @code(BOOL) result.
  @param(AObject The receiver.)
  @param(ASelector The message.)
  @param(AArg The argument.)
  @returns(The result, 0 for NO.) }
function MsgSendBool1(AObject, ASelector, AArg: Pointer): Byte; cdecl;
  external libobjc name 'objc_msgSend';

{ Makes an @code(NSString).
  @param(AText The text.)
  @returns(The autoreleased string.) }
function NSStringOf(const AText: UTF8String): Pointer;
begin
  Result := MsgSend1(objc_getClass('NSString'), sel_registerName('stringWithUTF8String:'),
    PAnsiChar(AText));
end;

{ Sets the appearance of the whole application, so every window's title
  bar follows it, those not yet made included. }
procedure ApplyToApplication;
var
  LApp, LSetSel, LAppearance: Pointer;
begin
  LApp := MsgSend0(objc_getClass('NSApplication'), sel_registerName('sharedApplication'));
  LSetSel := sel_registerName('setAppearance:');
  if (LApp = nil) or
     (MsgSendBool1(LApp, sel_registerName('respondsToSelector:'), LSetSel) = 0) then
    Exit;   // before macOS 10.14
  if GSpec.UseSystem then
    LAppearance := nil   // follow the system's light or dark setting
  else if GSpec.IsDark then
    LAppearance := MsgSend1(objc_getClass('NSAppearance'),
      sel_registerName('appearanceNamed:'), NSStringOf('NSAppearanceNameDarkAqua'))
  else
    LAppearance := MsgSend1(objc_getClass('NSAppearance'),
      sel_registerName('appearanceNamed:'), NSStringOf('NSAppearanceNameAqua'));
  MsgSend1(LApp, LSetSel, LAppearance);
end;

procedure ApplyTitleBar(const AForm: TCommonCustomForm);
begin
  // The application's appearance covers every window
end;

{$ELSE}
{ --------------------------------------------- Linux, Android and iOS }

{ Nothing to do: the window manager, or no title bar at all. }
procedure ApplyToApplication;
begin
end;

procedure ApplyTitleBar(const AForm: TCommonCustomForm);
begin
end;

{$ENDIF}

{ Gives a form being shown the current spec.
  @param(Sender Who sent the message.)
  @param(M The message.) }
procedure FormShown(const Sender: TObject; const M: TMessage);
begin
  if M is TFormBeforeShownMessage then
    ApplyTitleBar(TFormBeforeShownMessage(M).Value)
  else if Sender is TCommonCustomForm then
    ApplyTitleBar(TCommonCustomForm(Sender));
end;

procedure SetTitleBarSpec(const ASpec: TGDEMTitleBarSpec);
var
  LIndex: Integer;
begin
  GSpec := ASpec;
  if not GSubscribed then
  begin
    // Forms shown from now on; the message comes once the window exists
    GSubscriptionId := TMessageManager.DefaultManager.SubscribeToMessage(
      TFormBeforeShownMessage, FormShown);
    GSubscribed := True;
  end;
  ApplyToApplication;
  for LIndex := 0 to Screen.FormCount - 1 do
    ApplyTitleBar(Screen.Forms[LIndex]);
end;

initialization
  GSpec := TGDEMTitleBarSpec.System;

finalization
  if GSubscribed then
    TMessageManager.DefaultManager.Unsubscribe(TFormBeforeShownMessage, GSubscriptionId);

end.
