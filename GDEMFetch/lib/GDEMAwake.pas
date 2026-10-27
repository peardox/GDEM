{ @abstract(Keeps the computer from going to sleep while a job runs.)

  A batch of downloads or an import can run for hours, often while nobody
  is using the computer, and most computers go to sleep after a while
  without keyboard or mouse use. @link(TKeepAwake) asks the operating
  system not to, for as long as a job is running:
  @unorderedList(
    @item(Windows: @code(SetThreadExecutionState) with
      @code(ES_SYSTEM_REQUIRED).)
    @item(macOS: an @code(NSProcessInfo) activity with
      @code(NSActivityUserInitiated), which also stops App Nap slowing the
      program down while its window is hidden.)
    @item(Linux: @code(systemd-inhibit), where it is installed. It holds
      the lock while a small shell loop runs, and the loop ends when the
      job does or when the program exits, so a lock is never left behind.)
    @item(Android and iOS: nothing.)
  )
  Only sleep is prevented: the screen may still turn off. Each request is
  given up automatically if the program ends, even if it crashes.

  If the system refuses or the means is missing, nothing happens and the job
  carries on; keeping awake is a convenience, never a reason to fail. }
unit GDEMAwake;

interface

type
  { @abstract(Asks the operating system not to sleep while jobs run.)

    Calls nest: the computer is kept awake from the first
    @link(Acquire) until the matching last @link(Release). Call both from
    the main thread. }
  TKeepAwake = class
  private
    { Outstanding @link(Acquire) calls. }
    class var FCount: Integer;
    {$IF defined(MACOS) and not defined(IOS)}
    { The NSProcessInfo activity, retained; @nil when there is none. }
    class var FActivity: Pointer;
    {$ENDIF}
    {$IF defined(LINUX) and not defined(ANDROID)}
    { File whose presence keeps the systemd-inhibit loop running; empty
      when there is none. }
    class var FFlagFile: string;
    {$ENDIF}

    { Makes the platform request.
      @param(AReason Why, shown by some systems to the user.) }
    class procedure Start(const AReason: string); static;

    { Withdraws the platform request. }
    class procedure Stop; static;
  public
    { Keeps the computer awake until the matching @link(Release).
      @param(AReason Why, such as @code(Downloading tiles); shown by some
        systems, for example in macOS's Activity Monitor.) }
    class procedure Acquire(const AReason: string); static;

    { Ends one @link(Acquire). When the last one ends the computer may
      sleep again. Extra calls are ignored. }
    class procedure Release; static;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  {$IF defined(LINUX) and not defined(ANDROID)}
  Posix.Stdlib, Posix.Unistd, System.IOUtils,
  {$ENDIF}
  System.SysUtils;

{$IF defined(MACOS) and not defined(IOS)}
const
  { The Objective-C runtime library. }
  libobjc = '/usr/lib/libobjc.A.dylib';

  { @code(NSActivityUserInitiated): work the user asked for, which keeps
    the system from idle sleep and the program out of App Nap. The display
    may still sleep. }
  NSActivityUserInitiated: UInt64 = $00FFFFFF;

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
  @param(AReceiver The object or class.)
  @param(ASelector The method.)
  @returns(The method's result.) }
function MsgSend0(AReceiver, ASelector: Pointer): Pointer; cdecl;
  external libobjc name 'objc_msgSend';

{ @code(objc_msgSend) with one pointer argument.
  @param(AReceiver The object or class.)
  @param(ASelector The method.)
  @param(AArg The argument.)
  @returns(The method's result.) }
function MsgSend1(AReceiver, ASelector, AArg: Pointer): Pointer; cdecl;
  external libobjc name 'objc_msgSend';

{ @code(objc_msgSend) for @code(beginActivityWithOptions:reason:).
  @param(AReceiver The process info object.)
  @param(ASelector The method.)
  @param(AOptions The activity options.)
  @param(AReason An NSString.)
  @returns(The activity object.) }
function MsgSendBegin(AReceiver, ASelector: Pointer; AOptions: UInt64;
  AReason: Pointer): Pointer; cdecl;
  external libobjc name 'objc_msgSend';

{ Makes an autoreleased NSString.
  @param(AText The text.)
  @returns(The NSString.) }
function NSStringOf(const AText: string): Pointer;
begin
  Result := MsgSend1(objc_getClass('NSString'), sel_registerName('stringWithUTF8String:'),
    MarshaledAString(UTF8String(AText)));
end;
{$ENDIF}

{ TKeepAwake }

class procedure TKeepAwake.Acquire(const AReason: string);
begin
  Inc(FCount);
  if FCount = 1 then
    try
      Start(AReason);
    except
      // Keeping awake is a convenience; the job carries on regardless
    end;
end;

class procedure TKeepAwake.Release;
begin
  if FCount = 0 then
    Exit;
  Dec(FCount);
  if FCount = 0 then
    try
      Stop;
    except
      // Nothing useful to do; the request ends with the program anyway
    end;
end;

class procedure TKeepAwake.Start(const AReason: string);
{$IF defined(MACOS) and not defined(IOS)}
var
  LInfo: Pointer;
{$ENDIF}
{$IF defined(LINUX) and not defined(ANDROID)}
var
  LCommand: string;
{$ENDIF}
begin
  {$IF defined(MSWINDOWS)}
  // Lasts until changed, but only while this (the main) thread lives
  SetThreadExecutionState(ES_CONTINUOUS or ES_SYSTEM_REQUIRED);
  {$ELSEIF defined(MACOS) and not defined(IOS)}
  LInfo := MsgSend0(objc_getClass('NSProcessInfo'), sel_registerName('processInfo'));
  if LInfo = nil then
    Exit;
  FActivity := MsgSendBegin(LInfo, sel_registerName('beginActivityWithOptions:reason:'),
    NSActivityUserInitiated, NSStringOf(AReason));
  // Keep it past the current autorelease pool, until endActivity
  if FActivity <> nil then
    MsgSend0(FActivity, sel_registerName('retain'));
  {$ELSEIF defined(LINUX) and not defined(ANDROID)}
  FFlagFile := TPath.Combine(TPath.GetTempPath,
    Format('gdemfetch-awake-%d', [getpid]));
  TFile.WriteAllText(FFlagFile, AReason);
  // The loop holds the lock while the flag file exists and this program
  // is still running; checked every 5 seconds. Runs in the background, and
  // does nothing if systemd-inhibit is not installed.
  LCommand := Format('systemd-inhibit --what=sleep:idle --who=GDEMFetch ' +
    '--why="%s" --mode=block sh -c ''while [ -e "%s" ] && kill -0 %d 2>/dev/null; ' +
    'do sleep 5; done'' >/dev/null 2>&1 &',
    [AReason.Replace('"', '').Replace('''', ''), FFlagFile, getpid]);
  _system(MarshaledAString(UTF8String(LCommand)));
  {$ENDIF}
end;

class procedure TKeepAwake.Stop;
begin
  {$IF defined(MSWINDOWS)}
  SetThreadExecutionState(ES_CONTINUOUS);
  {$ELSEIF defined(MACOS) and not defined(IOS)}
  if FActivity = nil then
    Exit;
  MsgSend1(MsgSend0(objc_getClass('NSProcessInfo'), sel_registerName('processInfo')),
    sel_registerName('endActivity:'), FActivity);
  MsgSend0(FActivity, sel_registerName('release'));
  FActivity := nil;
  {$ELSEIF defined(LINUX) and not defined(ANDROID)}
  // The loop sees the flag gone and ends, and systemd-inhibit with it
  if (FFlagFile <> '') and TFile.Exists(FFlagFile) then
    TFile.Delete(FFlagFile);
  FFlagFile := '';
  {$ENDIF}
end;

end.
