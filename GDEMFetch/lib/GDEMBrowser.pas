{ @abstract(Opens web pages in the user's default browser.)

  FMX has no cross-platform call for this, so each platform uses its own
  mechanism:
  @unorderedList(
    @item(Windows: @code(ShellExecute))
    @item(macOS: the @code(open) command)
    @item(Linux: the @code(xdg-open) command)
    @item(Android: an @code(ACTION_VIEW) intent)
  )
  On other platforms, including iOS, @link(OpenURL) returns @false so the
  caller can show the address instead. }
unit GDEMBrowser;

interface

{ Opens a web address in the user's default browser.

  Only @code(http://) and @code(https://) addresses are accepted, so this
  can never be used to launch a local program or file.

  @param(AURL The address to open.)
  @returns(@true if the request was handed to the system; @false if the
    address was rejected, the platform is not supported, or the system
    reported a failure.) }
function OpenURL(const AURL: string): Boolean;

implementation

uses
  System.SysUtils
  {$IF defined(MSWINDOWS)}
  , Winapi.Windows, Winapi.ShellAPI
  {$ELSEIF defined(ANDROID)}
  , Androidapi.JNI.GraphicsContentViewText, Androidapi.JNI.Net,
  Androidapi.JNI.JavaTypes, Androidapi.Helpers
  {$ELSEIF defined(MACOS) and not defined(IOS)}
  , Posix.Stdlib
  {$ELSEIF defined(LINUX)}
  , Posix.Stdlib
  {$ENDIF}
  ;

{ Checks that an address is a web address.
  @param(AURL The address to check.)
  @returns(@true for @code(http://) and @code(https://) addresses.) }
function IsWebURL(const AURL: string): Boolean;
begin
  Result := AURL.StartsWith('https://', True) or AURL.StartsWith('http://', True);
end;

{$IF (defined(MACOS) and not defined(IOS)) or (defined(LINUX) and not defined(ANDROID))}
{ Wraps text in single quotes for a POSIX shell, escaping any single quotes
  inside it, so it is passed as exactly one argument.
  @param(AText Text to quote.)
  @returns(The quoted text.) }
function ShellQuote(const AText: string): string;
begin
  Result := '''' + AText.Replace('''', '''\''''', [rfReplaceAll]) + '''';
end;

{ Runs a shell command without waiting for any GUI program it starts.
  @param(ACommand The command line.)
  @returns(@true if the shell reported success.) }
function RunShell(const ACommand: string): Boolean;
begin
  Result := _system(PAnsiChar(UTF8String(ACommand))) = 0;
end;
{$ENDIF}

function OpenURL(const AURL: string): Boolean;
{$IF defined(ANDROID)}
var
  LIntent: JIntent;
{$ENDIF}
begin
  Result := False;
  if not IsWebURL(AURL) then
    Exit;
  try
    {$IF defined(MSWINDOWS)}
    Result := ShellExecute(0, 'open', PChar(AURL), nil, nil, SW_SHOWNORMAL) > 32;
    {$ELSEIF defined(ANDROID)}
    LIntent := TJIntent.JavaClass.init(TJIntent.JavaClass.ACTION_VIEW,
      TJnet_Uri.JavaClass.parse(StringToJString(AURL)));
    TAndroidHelper.Activity.startActivity(LIntent);
    Result := True;
    {$ELSEIF defined(IOS)}
    Result := False;
    {$ELSEIF defined(MACOS)}
    Result := RunShell('open ' + ShellQuote(AURL));
    {$ELSEIF defined(LINUX)}
    // xdg-open can wait on the browser, so run it in the background
    Result := RunShell('xdg-open ' + ShellQuote(AURL) + ' >/dev/null 2>&1 &');
    {$ENDIF}
  except
    Result := False;
  end;
end;

end.
