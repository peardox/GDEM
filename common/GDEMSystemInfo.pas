{ @abstract(The computer's memory and graphics processors, and how much of
  them this program uses.)

  @link(ReadMemoryInfo) gives the system memory, total and available now;
  @link(ReadProgramMemory) this program's own use; @link(ReadGpuInfo)
  every graphics processor with its memory; @link(DescribeSystem) all of
  it as lines for a log, and @link(DescribeMemoryUse) a single line of
  what is in use now, for measuring what a piece of work costs. How the
  figures are found, and how many are known, depends on the platform:

  @preformatted(
Windows   memory: GlobalMemoryStatusEx
          program: GetProcessMemoryInfo (working set and its peak)
          GPUs: DXGI, one entry for each adapter (Microsoft's software
          renderer left out): its name, PCI vendor, its own memory, the
          system memory it may share, and, from Windows 10 (DXGI 1.4),
          the budget Windows gives this program and how much it uses
macOS     memory: sysctl hw.memsize; available from the kernel's page
          counts (free, inactive and speculative pages)
          program: task_info (resident size and its peak)
          GPUs: Metal, one entry for each device: its name, whether its
          memory is unified with the CPU's (Apple silicon), the working
          set Metal recommends at most, and how much this program has
          allocated on it
Linux     memory: /proc/meminfo (MemTotal, MemAvailable)
          program: /proc/self/status (VmRSS, VmHWM)
          GPUs: /sys/class/drm, one entry for each card: its PCI vendor;
          for AMD, its own memory and how much is in use (by every
          program) from amdgpu's mem_info files; for NVIDIA, its name
          and memory from nvidia-smi where it is installed; Intel
          graphics share system memory
other     nothing: everything unknown
  )

  The memory manager's own count of what the program has allocated is
  known only if the program says how to read it, through
  @link(ProgramHeapReader): GDEMFetch sets it to FastMM5's usage summary
  on Windows. FastMM5 cannot give the system's memory, only the
  program's.

  Anything not known is @link(SIZE_UNKNOWN). Sizes are in bytes. All of it
  is read when asked, so the figures that change are current. Read from
  the main thread: on macOS, Metal's names come back autoreleased, and
  FMX's main loop drains them. On Linux with an NVIDIA card,
  @link(ReadGpuInfo) runs nvidia-smi, which can take a few tenths of a
  second.

  No FMX: any program can use it. }
unit GDEMSystemInfo;

interface

uses
  System.SysUtils;

const
  { A size the system did not give. }
  SIZE_UNKNOWN = -1;

  { PCI vendor number of NVIDIA. }
  VENDOR_NVIDIA = $10DE;
  { PCI vendor number of AMD. }
  VENDOR_AMD = $1002;
  { PCI vendor number of Intel. }
  VENDOR_INTEL = $8086;
  { PCI vendor number of Apple. }
  VENDOR_APPLE = $106B;

type
  { @abstract(The system memory.) }
  TMemoryInfo = record
    { All of it, in bytes; @link(SIZE_UNKNOWN) if not known. }
    Total: Int64;
    { What programs could have now without the system swapping, in bytes;
      @link(SIZE_UNKNOWN) if not known. }
    Available: Int64;

    { The memory as a line for the log.
      @returns(Such as @code(Memory: 63.6 GB, 41.2 GB available).) }
    function Describe: string;
  end;

  { @abstract(This program's use of the system memory.) }
  TProgramMemoryInfo = record
    { The program's memory held in RAM now (Windows' working set,
      resident size elsewhere), in bytes; @link(SIZE_UNKNOWN) if not
      known. }
    Resident: Int64;
    { The most @link(Resident) has been since the program started, in
      bytes; @link(SIZE_UNKNOWN) if not known. }
    PeakResident: Int64;
    { What the memory manager says the program has allocated and not
      freed, in bytes, from @link(ProgramHeapReader);
      @link(SIZE_UNKNOWN) if that is not set. }
    Allocated: Int64;

    { The program's memory as a line for the log.
      @returns(Such as @code(This program: 812 MB in memory (peak 1.4 GB),
        640 MB allocated).) }
    function Describe: string;
  end;

  { @abstract(One graphics processor.) }
  TGpuInfo = record
    { Its name, such as @code(NVIDIA GeForce RTX 5090 Laptop GPU). }
    Name: string;
    { Its PCI vendor number, such as @link(VENDOR_NVIDIA); 0 if not
      known. }
    VendorId: Cardinal;
    { Its own memory (video memory), in bytes; 0 for one that has none and
      uses system memory; @link(SIZE_UNKNOWN) if not known. }
    DedicatedMemory: Int64;
    { System memory it may use as well, in bytes; @link(SIZE_UNKNOWN) if
      not known. }
    SharedMemory: Int64;
    { How much the system says this program may use on it now, in bytes:
      DXGI's budget on Windows, Metal's recommended working set on macOS;
      @link(SIZE_UNKNOWN) if not known. }
    Budget: Int64;
    { How much of its memory is in use now, in bytes: by this program on
      Windows and macOS, by every program on Linux; @link(SIZE_UNKNOWN)
      if not known. }
    Used: Int64;
    { @true if @link(Used) counts this program alone, @false if every
      program's use. }
    UsedByThisProgram: Boolean;
    { @true if it shares one memory with the processor, as on Apple
      silicon. }
    UnifiedMemory: Boolean;

    { The vendor's name.
      @returns(@code(NVIDIA), @code(AMD), @code(Intel), @code(Apple), or
        an empty string for another or none.) }
    function VendorName: string;

    { The processor as a line for the log.
      @param(ANumber Its number in the list, from 1.)
      @returns(Such as @code(GPU 1: NVIDIA GeForce RTX 5090 Laptop GPU,
        23.6 GB own memory, 31.8 GB shared; this program may use 22.9 GB,
        this program uses 412 MB).) }
    function Describe(ANumber: Integer): string;
  end;

  { @abstract(Reads the memory manager's count of the bytes the program
    has allocated.)
    @returns(The bytes allocated and not freed.) }
  TProgramHeapReader = reference to function: Int64;

var
  { How to read the memory manager's count of allocated bytes for
    @link(TProgramMemoryInfo.Allocated); nil (the default) leaves it
    unknown. A program using FastMM5 sets it to return
    @code(FastMM_GetUsageSummary.AllocatedBytes). }
  ProgramHeapReader: TProgramHeapReader;

{ Reads the system memory.
  @returns(Total and available; each @link(SIZE_UNKNOWN) where the system
    does not say.) }
function ReadMemoryInfo: TMemoryInfo;

{ Reads this program's use of memory.
  @returns(Its memory now and at its peak, and what is allocated; each
    @link(SIZE_UNKNOWN) where not known.) }
function ReadProgramMemory: TProgramMemoryInfo;

{ Reads every graphics processor.
  @returns(The processors, in the system's order; empty if none can be
    found or the platform is not one this unit knows.) }
function ReadGpuInfo: TArray<TGpuInfo>;

{ Formats a size for the log.
  @param(ABytes The size; @link(SIZE_UNKNOWN) for unknown.)
  @returns(Such as @code(24.0 GB) or @code(512 MB), in units of 1,024;
    @code(unknown) for @link(SIZE_UNKNOWN).) }
function FormatMemorySize(ABytes: Int64): string;

{ The memory, this program's use of it and every graphics processor, as
  lines for a log. Never raises: anything that cannot be read is given as
  unknown.
  @returns(The lines: the memory, the program, then one for each
    processor, or a line saying none was found.) }
function DescribeSystem: TArray<string>;

{ What is in use now, in one line, for logging after a piece of work to
  see what it cost. Never raises.
  @returns(Such as @code(this program 812 MB in memory (peak 1.4 GB),
    640 MB allocated; system 41.2 GB available; GPU 1 412 MB used by this
    program).) }
function DescribeMemoryUse: string;

implementation

uses
  {$IF defined(MSWINDOWS)}
  Winapi.Windows,
  {$ENDIF}
  System.Classes, System.Math, System.Generics.Collections;

function FormatMemorySize(ABytes: Int64): string;
const
  MB = 1024 * 1024;
  GB = 1024 * MB;
begin
  if ABytes < 0 then
    Result := 'unknown'
  else if ABytes >= GB then
    Result := FormatFloat('0.0', ABytes / GB, TFormatSettings.Invariant) + ' GB'
  else
    Result := FormatFloat('0', ABytes / MB, TFormatSettings.Invariant) + ' MB';
end;

{ TMemoryInfo }

function TMemoryInfo.Describe: string;
begin
  Result := 'Memory: ' + FormatMemorySize(Total);
  if Available >= 0 then
    Result := Result + ', ' + FormatMemorySize(Available) + ' available';
end;

{ TProgramMemoryInfo }

function TProgramMemoryInfo.Describe: string;
begin
  Result := 'This program: ' + FormatMemorySize(Resident) + ' in memory';
  if PeakResident >= 0 then
    Result := Result + ' (peak ' + FormatMemorySize(PeakResident) + ')';
  if Allocated >= 0 then
    Result := Result + ', ' + FormatMemorySize(Allocated) + ' allocated';
end;

{ TGpuInfo }

function TGpuInfo.VendorName: string;
begin
  case VendorId of
    VENDOR_NVIDIA: Result := 'NVIDIA';
    VENDOR_AMD: Result := 'AMD';
    VENDOR_INTEL: Result := 'Intel';
    VENDOR_APPLE: Result := 'Apple';
  else
    Result := '';
  end;
end;

function TGpuInfo.Describe(ANumber: Integer): string;
var
  LParts: TArray<string>;
begin
  Result := Format('GPU %d: %s', [ANumber, Name]);
  LParts := nil;
  if UnifiedMemory then
    LParts := LParts + ['unified memory']
  else if DedicatedMemory > 0 then
    LParts := LParts + [FormatMemorySize(DedicatedMemory) + ' own memory']
  else if DedicatedMemory = 0 then
    LParts := LParts + ['no memory of its own'];
  if SharedMemory > 0 then
    LParts := LParts + [FormatMemorySize(SharedMemory) + ' shared'];
  if Length(LParts) > 0 then
    Result := Result + ', ' + string.Join(', ', LParts);
  LParts := nil;
  if Budget >= 0 then
    LParts := LParts + ['this program may use ' + FormatMemorySize(Budget)];
  if Used >= 0 then
  begin
    if UsedByThisProgram then
      LParts := LParts + ['this program uses ' + FormatMemorySize(Used)]
    else
      LParts := LParts + [FormatMemorySize(Used) + ' in use'];
  end;
  if Length(LParts) > 0 then
    Result := Result + '; ' + string.Join(', ', LParts);
end;

{ A GPU with every size unknown.
  @param(AName Its name.)
  @param(AVendor Its PCI vendor number, or 0.)
  @returns(The record.) }
function NewGpu(const AName: string; AVendor: Cardinal): TGpuInfo;
begin
  Result := Default(TGpuInfo);
  Result.Name := AName;
  Result.VendorId := AVendor;
  Result.DedicatedMemory := SIZE_UNKNOWN;
  Result.SharedMemory := SIZE_UNKNOWN;
  Result.Budget := SIZE_UNKNOWN;
  Result.Used := SIZE_UNKNOWN;
end;

{ A program memory record with every size unknown, and
  @link(TProgramMemoryInfo.Allocated) read from @link(ProgramHeapReader)
  if it is set.
  @returns(The record.) }
function NewProgramMemory: TProgramMemoryInfo;
begin
  Result.Resident := SIZE_UNKNOWN;
  Result.PeakResident := SIZE_UNKNOWN;
  Result.Allocated := SIZE_UNKNOWN;
  if Assigned(ProgramHeapReader) then
    try
      Result.Allocated := ProgramHeapReader();
    except
      Result.Allocated := SIZE_UNKNOWN;
    end;
end;

{$IF defined(MSWINDOWS)}

// DXGI, declared here rather than taken from Winapi.DXGI, so this unit
// depends only on the interfaces' published layout. Each interface lists
// its own methods in Microsoft's order, so the vtable lines up; only
// those called have exact parameters, and the methods after the last one
// called are left out.

type
  { DXGI_ADAPTER_DESC1. }
  TDxgiAdapterDesc1 = record
    { The adapter's name. }
    Description: array[0..127] of WideChar;
    { PCI vendor number. }
    VendorId: Cardinal;
    { PCI device number. }
    DeviceId: Cardinal;
    { PCI subsystem number. }
    SubSysId: Cardinal;
    { PCI revision. }
    Revision: Cardinal;
    { Video memory not shared with the CPU, in bytes. }
    DedicatedVideoMemory: NativeUInt;
    { System memory set aside for it alone, in bytes. }
    DedicatedSystemMemory: NativeUInt;
    { System memory it may share, in bytes. }
    SharedSystemMemory: NativeUInt;
    { Its locally unique identifier: low part. }
    AdapterLuidLow: Cardinal;
    { Its locally unique identifier: high part. }
    AdapterLuidHigh: Integer;
    { DXGI_ADAPTER_FLAG values. }
    Flags: Cardinal;
  end;

  { DXGI_QUERY_VIDEO_MEMORY_INFO. }
  TDxgiQueryVideoMemoryInfo = record
    { What the program may use without stalling, in bytes. }
    Budget: UInt64;
    { What the program uses now, in bytes. }
    CurrentUsage: UInt64;
    { What it could reserve, in bytes. }
    AvailableForReservation: UInt64;
    { What it has reserved, in bytes. }
    CurrentReservation: UInt64;
  end;

  { IDXGIObject. }
  IDxgiObject = interface(IUnknown)
    ['{AEC22FB8-76F3-4639-9BE0-28EB43A67A2E}']
    { SetPrivateData; not used. @returns(The result.) }
    function SetPrivateData(const AName: TGUID; ASize: Cardinal; AData: Pointer): HResult; stdcall;
    { SetPrivateDataInterface; not used. @returns(The result.) }
    function SetPrivateDataInterface(const AName: TGUID; const AObject: IUnknown): HResult; stdcall;
    { GetPrivateData; not used. @returns(The result.) }
    function GetPrivateData(const AName: TGUID; var ASize: Cardinal; AData: Pointer): HResult; stdcall;
    { GetParent; not used. @returns(The result.) }
    function GetParent(const AId: TGUID; out AParent): HResult; stdcall;
  end;

  { IDXGIAdapter. }
  IDxgiAdapter = interface(IDxgiObject)
    ['{2411E7E1-12AC-4CCF-BD14-9798E8534DC0}']
    { EnumOutputs; not used. @returns(The result.) }
    function EnumOutputs(AOutput: Cardinal; out AResult: IUnknown): HResult; stdcall;
    { GetDesc; not used. @returns(The result.) }
    function GetDesc(ADesc: Pointer): HResult; stdcall;
    { CheckInterfaceSupport; not used. @returns(The result.) }
    function CheckInterfaceSupport(const AId: TGUID; out AVersion: Int64): HResult; stdcall;
  end;

  { IDXGIAdapter1. }
  IDxgiAdapter1 = interface(IDxgiAdapter)
    ['{29038F61-3839-4626-91FD-086879011A05}']
    { Describes the adapter.
      @param(ADesc Receives the description.)
      @returns(S_OK on success.) }
    function GetDesc1(out ADesc: TDxgiAdapterDesc1): HResult; stdcall;
  end;

  { IDXGIAdapter2. }
  IDxgiAdapter2 = interface(IDxgiAdapter1)
    ['{0AA1AE0A-FA0E-4B84-8644-E05FF8E5ACB5}']
    { GetDesc2; not used. @returns(The result.) }
    function GetDesc2(ADesc: Pointer): HResult; stdcall;
  end;

  { IDXGIAdapter3 (DXGI 1.4, Windows 10). }
  IDxgiAdapter3 = interface(IDxgiAdapter2)
    ['{645967A4-1392-4310-A798-8053CE3E93FD}']
    { RegisterHardwareContentProtectionTeardownStatusEvent; not used.
      @returns(The result.) }
    function RegisterHardwareContentProtectionTeardownStatusEvent(AEvent: THandle;
      out ACookie: Cardinal): HResult; stdcall;
    { UnregisterHardwareContentProtectionTeardownStatus; not used.
      @param(ACookie From the registration.) }
    procedure UnregisterHardwareContentProtectionTeardownStatus(ACookie: Cardinal); stdcall;
    { The program's video memory budget and use.
      @param(ANode The adapter's node, 0 for a single GPU.)
      @param(AGroup 0 for the adapter's own memory, 1 for shared.)
      @param(AInfo Receives the figures.)
      @returns(S_OK on success.) }
    function QueryVideoMemoryInfo(ANode: Cardinal; AGroup: Integer;
      out AInfo: TDxgiQueryVideoMemoryInfo): HResult; stdcall;
  end;

  { IDXGIFactory. }
  IDxgiFactory = interface(IDxgiObject)
    ['{7B7166EC-21C7-44AE-B21A-C9AE321AE369}']
    { EnumAdapters; not used. @returns(The result.) }
    function EnumAdapters(AAdapter: Cardinal; out AResult: IDxgiAdapter): HResult; stdcall;
    { MakeWindowAssociation; not used. @returns(The result.) }
    function MakeWindowAssociation(AWindow: THandle; AFlags: Cardinal): HResult; stdcall;
    { GetWindowAssociation; not used. @returns(The result.) }
    function GetWindowAssociation(out AWindow: THandle): HResult; stdcall;
    { CreateSwapChain; not used. @returns(The result.) }
    function CreateSwapChain(const ADevice: IUnknown; ADesc: Pointer;
      out ASwapChain: IUnknown): HResult; stdcall;
    { CreateSoftwareAdapter; not used. @returns(The result.) }
    function CreateSoftwareAdapter(AModule: THandle; out AAdapter: IDxgiAdapter): HResult; stdcall;
  end;

  { IDXGIFactory1. }
  IDxgiFactory1 = interface(IDxgiFactory)
    ['{770AAE78-F26F-4DBA-A829-253C83D1B387}']
    { An adapter by number.
      @param(AAdapter From 0.)
      @param(AResult Receives it.)
      @returns(S_OK, or DXGI_ERROR_NOT_FOUND past the last.) }
    function EnumAdapters1(AAdapter: Cardinal; out AResult: IDxgiAdapter1): HResult; stdcall;
    { IsCurrent; not used. @returns(The result.) }
    function IsCurrent: BOOL; stdcall;
  end;

  { PROCESS_MEMORY_COUNTERS. }
  TProcessMemoryCounters = record
    { The record's size in bytes. }
    cb: Cardinal;
    { Page faults. }
    PageFaultCount: Cardinal;
    { The largest working set so far, in bytes. }
    PeakWorkingSetSize: NativeUInt;
    { The working set now, in bytes. }
    WorkingSetSize: NativeUInt;
    { Paged pool peak; not used. }
    QuotaPeakPagedPoolUsage: NativeUInt;
    { Paged pool; not used. }
    QuotaPagedPoolUsage: NativeUInt;
    { Non-paged pool peak; not used. }
    QuotaPeakNonPagedPoolUsage: NativeUInt;
    { Non-paged pool; not used. }
    QuotaNonPagedPoolUsage: NativeUInt;
    { Committed private memory; not used. }
    PagefileUsage: NativeUInt;
    { Its peak; not used. }
    PeakPagefileUsage: NativeUInt;
  end;

const
  { DXGI_ADAPTER_FLAG_SOFTWARE: Microsoft's software renderer. }
  DXGI_ADAPTER_FLAG_SOFTWARE = 2;
  { DXGI_MEMORY_SEGMENT_GROUP_LOCAL: the adapter's own memory, or for one
    with none, what it uses as its own. }
  DXGI_MEMORY_SEGMENT_GROUP_LOCAL = 0;

{ Makes a DXGI 1.1 factory.
  @param(AId The interface wanted.)
  @param(AFactory Receives it.)
  @returns(S_OK on success.) }
function CreateDXGIFactory1(const AId: TGUID; out AFactory): HResult; stdcall;
  external 'dxgi.dll' name 'CreateDXGIFactory1';

{ A process's memory counters (kernel32's copy of psapi's function, from
  Windows 7).
  @param(AProcess The process.)
  @param(ACounters Receives the counters.)
  @param(ASize The record's size.)
  @returns(Non-zero on success.) }
function K32GetProcessMemoryInfo(AProcess: THandle; var ACounters: TProcessMemoryCounters;
  ASize: Cardinal): BOOL; stdcall; external kernel32 name 'K32GetProcessMemoryInfo';

function ReadMemoryInfo: TMemoryInfo;
var
  LStatus: TMemoryStatusEx;
begin
  Result.Total := SIZE_UNKNOWN;
  Result.Available := SIZE_UNKNOWN;
  FillChar(LStatus, SizeOf(LStatus), 0);
  LStatus.dwLength := SizeOf(LStatus);
  if GlobalMemoryStatusEx(LStatus) then
  begin
    Result.Total := Int64(LStatus.ullTotalPhys);
    Result.Available := Int64(LStatus.ullAvailPhys);
  end;
end;

function ReadProgramMemory: TProgramMemoryInfo;
var
  LCounters: TProcessMemoryCounters;
begin
  Result := NewProgramMemory;
  FillChar(LCounters, SizeOf(LCounters), 0);
  LCounters.cb := SizeOf(LCounters);
  if K32GetProcessMemoryInfo(GetCurrentProcess, LCounters, SizeOf(LCounters)) then
  begin
    Result.Resident := Int64(LCounters.WorkingSetSize);
    Result.PeakResident := Int64(LCounters.PeakWorkingSetSize);
  end;
end;

function ReadGpuInfo: TArray<TGpuInfo>;
var
  LFactory: IDxgiFactory1;
  LAdapter: IDxgiAdapter1;
  LAdapter3: IDxgiAdapter3;
  LDesc: TDxgiAdapterDesc1;
  LMemory: TDxgiQueryVideoMemoryInfo;
  LIndex: Cardinal;
  LGpu: TGpuInfo;
begin
  Result := nil;
  if Failed(CreateDXGIFactory1(IDxgiFactory1, LFactory)) then
    Exit;
  LIndex := 0;
  // Ends at DXGI_ERROR_NOT_FOUND, or any other failure
  while Succeeded(LFactory.EnumAdapters1(LIndex, LAdapter)) do
  begin
    Inc(LIndex);
    FillChar(LDesc, SizeOf(LDesc), 0);
    if Failed(LAdapter.GetDesc1(LDesc)) or
       ((LDesc.Flags and DXGI_ADAPTER_FLAG_SOFTWARE) <> 0) then
      Continue;
    LGpu := NewGpu(Trim(string(PWideChar(@LDesc.Description[0]))), LDesc.VendorId);
    LGpu.DedicatedMemory := Int64(LDesc.DedicatedVideoMemory);
    LGpu.SharedMemory := Int64(LDesc.SharedSystemMemory);
    LGpu.UsedByThisProgram := True;
    // The budget and use, from Windows 10
    if Supports(LAdapter, IDxgiAdapter3, LAdapter3) and
       Succeeded(LAdapter3.QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, LMemory)) then
    begin
      LGpu.Budget := Int64(LMemory.Budget);
      LGpu.Used := Int64(LMemory.CurrentUsage);
    end;
    LAdapter3 := nil;
    Result := Result + [LGpu];
  end;
end;

{$ELSEIF defined(MACOS) and not defined(IOS)}

const
  { The C library, for sysctlbyname and the Mach calls. }
  LIBC = '/usr/lib/libc.dylib';
  { The Objective-C runtime. }
  LIBOBJC = '/usr/lib/libobjc.A.dylib';
  { The Metal framework. }
  METAL = '/System/Library/Frameworks/Metal.framework/Metal';
  { host_statistics64's flavour for TVmStatistics64. }
  HOST_VM_INFO64 = 4;
  { task_info's flavour for TMachTaskBasicInfo. }
  MACH_TASK_BASIC_INFO = 20;

type
  { vm_statistics64: page counts, as vm_stat shows them. Only a few
    fields are read, but the whole is declared so the kernel's write
    fits. }
  TVmStatistics64 = record
    { Free pages. }
    FreeCount: Cardinal;
    { Active pages. }
    ActiveCount: Cardinal;
    { Inactive pages, which can be taken back at once. }
    InactiveCount: Cardinal;
    { Wired pages. }
    WireCount: Cardinal;
    { Counters not used here: zero fills, reactivations, page-ins,
      page-outs, faults, copy-on-write faults, lookups, hits, purges. }
    Counters: array[0..8] of UInt64;
    { Purgeable pages. }
    PurgeableCount: Cardinal;
    { Speculative pages, free in all but name. }
    SpeculativeCount: Cardinal;
    { Counters not used here: decompressions, compressions, swap-ins,
      swap-outs. }
    MoreCounters: array[0..3] of UInt64;
    { Counts not used here: compressor, throttled, external and internal
      pages. }
    PageCounts: array[0..3] of Cardinal;
    { Pages held compressed; not used here. }
    UncompressedInCompressor: UInt64;
  end;

  { mach_task_basic_info. }
  TMachTaskBasicInfo = record
    { Virtual size, in bytes; not used. }
    VirtualSize: UInt64;
    { Resident size, in bytes. }
    ResidentSize: UInt64;
    { The largest resident size so far, in bytes. }
    ResidentSizeMax: UInt64;
    { User time, seconds and microseconds; not used. }
    UserTime: array[0..1] of Integer;
    { System time, seconds and microseconds; not used. }
    SystemTime: array[0..1] of Integer;
    { Scheduling policy; not used. }
    Policy: Integer;
    { Suspend count; not used. }
    SuspendCount: Integer;
  end;

{ Reads a system value by name.
  @returns(0 on success.) }
function sysctlbyname(AName: MarshaledAString; AOld: Pointer; AOldLength: PNativeUInt;
  ANew: Pointer; ANewLength: NativeUInt): Integer; cdecl; external LIBC name 'sysctlbyname';

{ This task's port to the host.
  @returns(The port.) }
function mach_host_self: Cardinal; cdecl; external LIBC name 'mach_host_self';

{ This task's own port.
  @returns(The port.) }
function mach_task_self: Cardinal; cdecl; external LIBC name 'mach_task_self';

{ The host's statistics.
  @returns(0 on success.) }
function host_statistics64(AHost: Cardinal; AFlavor: Integer; AInfo: Pointer;
  var ACount: Cardinal): Integer; cdecl; external LIBC name 'host_statistics64';

{ A task's information.
  @returns(0 on success.) }
function task_info(ATask: Cardinal; AFlavor: Integer; AInfo: Pointer;
  var ACount: Cardinal): Integer; cdecl; external LIBC name 'task_info';

{ Every Metal device, retained.
  @returns(An NSArray, to be released.) }
function MTLCopyAllDevices: Pointer; cdecl; external METAL name 'MTLCopyAllDevices';

{ A selector by name. @returns(The selector.) }
function sel_registerName(AName: MarshaledAString): Pointer; cdecl;
  external LIBOBJC name 'sel_registerName';

// objc_msgSend, declared once for each return and argument type used, as
// arm64 requires (see the README's rule)

{ A message returning an object or pointer. @returns(The result.) }
function MsgSendPointer(AReceiver, ASelector: Pointer): Pointer; cdecl;
  external LIBOBJC name 'objc_msgSend';

{ A message with an index, returning an object. @returns(The result.) }
function MsgSendAtIndex(AReceiver, ASelector: Pointer; AIndex: NativeUInt): Pointer; cdecl;
  external LIBOBJC name 'objc_msgSend';

{ A message returning NSUInteger. @returns(The result.) }
function MsgSendUInteger(AReceiver, ASelector: Pointer): NativeUInt; cdecl;
  external LIBOBJC name 'objc_msgSend';

{ A message returning uint64_t. @returns(The result.) }
function MsgSendUInt64(AReceiver, ASelector: Pointer): UInt64; cdecl;
  external LIBOBJC name 'objc_msgSend';

{ A message returning BOOL, one byte. @returns(The result.) }
function MsgSendBool(AReceiver, ASelector: Pointer): Byte; cdecl;
  external LIBOBJC name 'objc_msgSend';

{ A whole-number system value.
  @param(AName Its name, such as @code(hw.memsize).)
  @returns(The value, or @link(SIZE_UNKNOWN).) }
function SysctlInt64(const AName: string): Int64;
var
  LValue: Int64;
  LLength: NativeUInt;
  LName: UTF8String;
begin
  LValue := 0;
  LLength := SizeOf(LValue);
  LName := UTF8String(AName);
  if sysctlbyname(MarshaledAString(LName), @LValue, @LLength, nil, 0) <> 0 then
    Exit(SIZE_UNKNOWN);
  // A value narrower than eight bytes fills the low ones
  if LLength = 4 then
    LValue := LValue and $FFFFFFFF;
  Result := LValue;
end;

function ReadMemoryInfo: TMemoryInfo;
var
  LStats: TVmStatistics64;
  LCount: Cardinal;
  LPage: Int64;
begin
  Result.Total := SysctlInt64('hw.memsize');
  Result.Available := SIZE_UNKNOWN;
  LPage := SysctlInt64('hw.pagesize');
  FillChar(LStats, SizeOf(LStats), 0);
  LCount := SizeOf(LStats) div SizeOf(Integer);
  if (LPage > 0) and
     (host_statistics64(mach_host_self, HOST_VM_INFO64, @LStats, LCount) = 0) then
    // What can be had without swapping: free, inactive and speculative
    // pages
    Result.Available := (Int64(LStats.FreeCount) + LStats.InactiveCount +
      LStats.SpeculativeCount) * LPage;
end;

function ReadProgramMemory: TProgramMemoryInfo;
var
  LInfo: TMachTaskBasicInfo;
  LCount: Cardinal;
begin
  Result := NewProgramMemory;
  FillChar(LInfo, SizeOf(LInfo), 0);
  LCount := SizeOf(LInfo) div SizeOf(Integer);
  if task_info(mach_task_self, MACH_TASK_BASIC_INFO, @LInfo, LCount) = 0 then
  begin
    Result.Resident := Int64(LInfo.ResidentSize);
    Result.PeakResident := Int64(LInfo.ResidentSizeMax);
  end;
end;

function ReadGpuInfo: TArray<TGpuInfo>;
var
  LDevices, LDevice, LName: Pointer;
  LIndex, LCount: NativeUInt;
  LGpu: TGpuInfo;
  LText: string;
begin
  Result := nil;
  LDevices := MTLCopyAllDevices;
  if LDevices = nil then
    Exit;
  try
    LCount := MsgSendUInteger(LDevices, sel_registerName('count'));
    if LCount = 0 then
      Exit;
    for LIndex := 0 to LCount - 1 do
    begin
      LDevice := MsgSendAtIndex(LDevices, sel_registerName('objectAtIndex:'), LIndex);
      if LDevice = nil then
        Continue;
      LName := MsgSendPointer(LDevice, sel_registerName('name'));
      if LName <> nil then
        LText := UTF8ToString(MarshaledAString(MsgSendPointer(LName,
          sel_registerName('UTF8String'))))
      else
        LText := 'Metal device';
      LGpu := NewGpu(LText, 0);
      // Metal gives no PCI vendor, but the name says whose it is
      if LText.StartsWith('Apple') then
        LGpu.VendorId := VENDOR_APPLE
      else if LText.StartsWith('AMD') then
        LGpu.VendorId := VENDOR_AMD
      else if LText.StartsWith('Intel') then
        LGpu.VendorId := VENDOR_INTEL
      else if LText.StartsWith('NVIDIA') then
        LGpu.VendorId := VENDOR_NVIDIA;
      LGpu.UnifiedMemory := MsgSendBool(LDevice, sel_registerName('hasUnifiedMemory')) <> 0;
      if LGpu.UnifiedMemory then
        LGpu.DedicatedMemory := 0;
      LGpu.Budget := Int64(MsgSendUInt64(LDevice,
        sel_registerName('recommendedMaxWorkingSetSize')));
      LGpu.Used := Int64(MsgSendUInteger(LDevice, sel_registerName('currentAllocatedSize')));
      LGpu.UsedByThisProgram := True;
      Result := Result + [LGpu];
    end;
  finally
    MsgSendPointer(LDevices, sel_registerName('release'));
  end;
end;

{$ELSEIF defined(LINUX) and not defined(ANDROID)}

const
  { The C library, for popen. }
  LIBC = 'libc.so.6';
  { Where the kernel lists the graphics cards. }
  DRM_FOLDER = '/sys/class/drm';
  { Asks nvidia-smi for each NVIDIA GPU's name and memory, in MiB, one per
    line, with nothing on standard error if it is not installed. }
  NVIDIA_SMI = 'nvidia-smi --query-gpu=name,memory.total,memory.used ' +
    '--format=csv,noheader,nounits 2>/dev/null';

{ Runs a command and opens its output. @returns(The stream, or nil.) }
function popen(ACommand, AMode: MarshaledAString): Pointer; cdecl;
  external LIBC name 'popen';

{ Closes a stream from popen. @returns(The command's status.) }
function pclose(AStream: Pointer): Integer; cdecl; external LIBC name 'pclose';

{ Reads a line. @returns(The buffer, or nil at the end.) }
function fgets(ABuffer: MarshaledAString; ASize: Integer; AStream: Pointer): MarshaledAString;
  cdecl; external LIBC name 'fgets';

{ Reads a whole file as text, a block at a time until the end, since files
  in /proc and /sys report no true size.
  @param(AFileName The file.)
  @returns(Its text, or an empty string if it cannot be read.) }
function ReadTextFile(const AFileName: string): string;
var
  LFile: TFileStream;
  LText: TBytesStream;
  LBuffer: array[0..4095] of Byte;
  LRead: Integer;
begin
  Result := '';
  try
    LText := TBytesStream.Create;
    try
      LFile := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
      try
        repeat
          LRead := LFile.Read(LBuffer, SizeOf(LBuffer));
          if LRead > 0 then
            LText.WriteBuffer(LBuffer, LRead);
        until LRead <= 0;
      finally
        LFile.Free;
      end;
      Result := TEncoding.UTF8.GetString(LText.Bytes, 0, LText.Size);
    finally
      LText.Free;
    end;
  except
    Result := '';
  end;
end;

{ Reads a whole number written in a file, decimal or hexadecimal.
  @param(AFileName The file.)
  @returns(The number, or @link(SIZE_UNKNOWN).) }
function ReadNumberFile(const AFileName: string): Int64;
var
  LText: string;
begin
  LText := ReadTextFile(AFileName).Trim;
  if LText.StartsWith('0x', True) then
    LText := '$' + LText.Substring(2);
  if not TryStrToInt64(LText, Result) then
    Result := SIZE_UNKNOWN;
end;

{ Reads sizes in kB from a file of lines such as
  @code(MemTotal:  65843776 kB).
  @param(AFileName The file.)
  @param(ANames The names wanted.)
  @returns(The sizes in bytes, in the order of @code(ANames);
    @link(SIZE_UNKNOWN) for any not found.) }
function ReadKilobyteLines(const AFileName: string; const ANames: array of string): TArray<Int64>;
var
  LLine: string;
  LParts: TArray<string>;
  LValue: Int64;
  I: Integer;
begin
  SetLength(Result, Length(ANames));
  for I := 0 to High(Result) do
    Result[I] := SIZE_UNKNOWN;
  for LLine in ReadTextFile(AFileName).Split([#10]) do
  begin
    LParts := LLine.Split([' ', ':', #9], TStringSplitOptions.ExcludeEmpty);
    if (Length(LParts) < 2) or not TryStrToInt64(LParts[1], LValue) then
      Continue;
    for I := 0 to High(ANames) do
      if LParts[0] = ANames[I] then
        Result[I] := LValue * 1024;
  end;
end;

function ReadMemoryInfo: TMemoryInfo;
var
  LSizes: TArray<Int64>;
begin
  LSizes := ReadKilobyteLines('/proc/meminfo', ['MemTotal', 'MemAvailable']);
  Result.Total := LSizes[0];
  Result.Available := LSizes[1];
end;

function ReadProgramMemory: TProgramMemoryInfo;
var
  LSizes: TArray<Int64>;
begin
  Result := NewProgramMemory;
  LSizes := ReadKilobyteLines('/proc/self/status', ['VmRSS', 'VmHWM']);
  Result.Resident := LSizes[0];
  Result.PeakResident := LSizes[1];
end;

{ NVIDIA's GPUs as nvidia-smi describes them.
  @returns(One for each GPU; empty if nvidia-smi is not installed.) }
function ReadNvidiaSmi: TArray<TGpuInfo>;
var
  LCommand, LMode: UTF8String;
  LStream: Pointer;
  LBuffer: array[0..511] of AnsiChar;
  LParts: TArray<string>;
  LTotal, LUsed: Int64;
  LGpu: TGpuInfo;
begin
  Result := nil;
  LCommand := UTF8String(NVIDIA_SMI);
  LMode := 'r';
  LStream := popen(MarshaledAString(LCommand), MarshaledAString(LMode));
  if LStream = nil then
    Exit;
  try
    while fgets(@LBuffer[0], SizeOf(LBuffer), LStream) <> nil do
    begin
      // Such as "NVIDIA GeForce RTX 3080, 10240, 512"
      LParts := UTF8ToString(MarshaledAString(@LBuffer[0])).Trim.Split([',']);
      if (Length(LParts) < 3) or not TryStrToInt64(LParts[1].Trim, LTotal) or
         not TryStrToInt64(LParts[2].Trim, LUsed) then
        Continue;
      LGpu := NewGpu(LParts[0].Trim, VENDOR_NVIDIA);
      LGpu.DedicatedMemory := LTotal * 1024 * 1024;
      LGpu.Used := LUsed * 1024 * 1024;
      Result := Result + [LGpu];
    end;
  finally
    pclose(LStream);
  end;
end;

function ReadGpuInfo: TArray<TGpuInfo>;
var
  LSearch: TSearchRec;
  LCards: TArray<string>;
  LCard, LDevice: string;
  LVendor, LDeviceId, LShared: Int64;
  LGpu: TGpuInfo;
  LNvidia: TArray<TGpuInfo>;
  LNvidiaRead: Boolean;
begin
  Result := nil;
  LCards := nil;
  // card0, card1, ...; their connectors, such as card0-HDMI-A-1, are left
  // out
  if FindFirst(DRM_FOLDER + '/card*', faAnyFile, LSearch) = 0 then
  try
    repeat
      if not LSearch.Name.Contains('-') then
        LCards := LCards + [LSearch.Name];
    until FindNext(LSearch) <> 0;
  finally
    FindClose(LSearch);
  end;
  TArray.Sort<string>(LCards);

  LNvidia := nil;
  LNvidiaRead := False;
  for LCard in LCards do
  begin
    LDevice := DRM_FOLDER + '/' + LCard + '/device/';
    LVendor := ReadNumberFile(LDevice + 'vendor');
    LDeviceId := ReadNumberFile(LDevice + 'device');
    if LVendor = VENDOR_NVIDIA then
    begin
      // nvidia-smi lists them all at once, with their names and memory
      if not LNvidiaRead then
      begin
        LNvidiaRead := True;
        LNvidia := ReadNvidiaSmi;
        Result := Result + LNvidia;
      end;
      if Length(LNvidia) > 0 then
        Continue;
    end;
    LGpu := NewGpu('', Cardinal(Max(LVendor, 0)));
    if LGpu.VendorName <> '' then
      LGpu.Name := Format('%s GPU (device %.4x)', [LGpu.VendorName, Max(LDeviceId, 0)])
    else
      LGpu.Name := Format('GPU %s (vendor %.4x, device %.4x)',
        [LCard, Max(LVendor, 0), Max(LDeviceId, 0)]);
    if LVendor = VENDOR_AMD then
    begin
      LGpu.DedicatedMemory := ReadNumberFile(LDevice + 'mem_info_vram_total');
      LGpu.Used := ReadNumberFile(LDevice + 'mem_info_vram_used');
      LShared := ReadNumberFile(LDevice + 'mem_info_gtt_total');
      if LShared > 0 then
        LGpu.SharedMemory := LShared;
    end
    else if LVendor = VENDOR_INTEL then
      // Intel graphics have none of their own
      LGpu.DedicatedMemory := 0;
    Result := Result + [LGpu];
  end;
end;

{$ELSE}

function ReadMemoryInfo: TMemoryInfo;
begin
  Result.Total := SIZE_UNKNOWN;
  Result.Available := SIZE_UNKNOWN;
end;

function ReadProgramMemory: TProgramMemoryInfo;
begin
  Result := NewProgramMemory;
end;

function ReadGpuInfo: TArray<TGpuInfo>;
begin
  Result := nil;
end;

{$ENDIF}

function DescribeSystem: TArray<string>;
var
  LGpus: TArray<TGpuInfo>;
  I: Integer;
begin
  Result := nil;
  try
    Result := Result + [ReadMemoryInfo.Describe];
  except
    on E: Exception do
      Result := Result + ['Memory: could not be read (' + E.Message + ')'];
  end;
  try
    Result := Result + [ReadProgramMemory.Describe];
  except
    on E: Exception do
      Result := Result + ['This program: could not be read (' + E.Message + ')'];
  end;
  try
    LGpus := ReadGpuInfo;
    if Length(LGpus) = 0 then
      Result := Result + ['GPU: none found']
    else
      for I := 0 to High(LGpus) do
        Result := Result + [LGpus[I].Describe(I + 1)];
  except
    on E: Exception do
      Result := Result + ['GPU: could not be read (' + E.Message + ')'];
  end;
end;

function DescribeMemoryUse: string;
var
  LProgram: TProgramMemoryInfo;
  LMemory: TMemoryInfo;
  LGpus: TArray<TGpuInfo>;
  I: Integer;
begin
  try
    LProgram := ReadProgramMemory;
    Result := 'this program ' + FormatMemorySize(LProgram.Resident) + ' in memory';
    if LProgram.PeakResident >= 0 then
      Result := Result + ' (peak ' + FormatMemorySize(LProgram.PeakResident) + ')';
    if LProgram.Allocated >= 0 then
      Result := Result + ', ' + FormatMemorySize(LProgram.Allocated) + ' allocated';
    LMemory := ReadMemoryInfo;
    if LMemory.Available >= 0 then
      Result := Result + '; system ' + FormatMemorySize(LMemory.Available) + ' available';
    LGpus := ReadGpuInfo;
    for I := 0 to High(LGpus) do
      if LGpus[I].Used >= 0 then
      begin
        if LGpus[I].UsedByThisProgram then
          Result := Result + Format('; GPU %d %s used by this program',
            [I + 1, FormatMemorySize(LGpus[I].Used)])
        else
          Result := Result + Format('; GPU %d %s used by all programs',
            [I + 1, FormatMemorySize(LGpus[I].Used)]);
      end;
  except
    on E: Exception do
      Result := 'memory use could not be read (' + E.Message + ')';
  end;
end;

end.
