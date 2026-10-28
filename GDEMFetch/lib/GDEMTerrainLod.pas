{ @abstract(Decides which patches of the surface to draw, from where the
  camera is: fine ones near it, coarser further away, over a window of
  tiles that follows it; and has them made on worker threads.)

  @link(TTerrainLod) keeps a tree of patches (@link(TTerrainNode)) for each
  tile within @link(TERRAIN_WINDOW_KM) of the point the camera looks at
  (@link(TTerrainRoot)): the tile as one patch, split 3 by 3, then in
  quarters, as @code(GDEMTerrain) describes. A patch is split when the
  camera is nearer to it than @link(TTerrainLod.Range) times its size, so
  each step away halves the detail, and the number of patches drawn stays
  much the same wherever the camera is. A split patch is put back together
  only once the camera is @link(SPLIT_HYSTERESIS) times further than that,
  so patches do not flicker between two depths at the boundary.

  Patches are made by @code(BuildTerrainPatch) on the run-time library's
  thread pool, at most one per processor at a time, those in view first,
  coarse before fine, near before far. Until its finer patches are ready, a
  patch goes on being drawn; until a patch is ready, the finer ones it
  replaces go on being drawn: so the view never has holes, and sharpens as
  the work is done. Results come back through a queue
  (@link(ITerrainResults)) that outlives the tree, so a result for a patch
  no longer wanted is simply dropped.

  The tree knows nothing of the 3D library: the view makes a mesh for each
  patch made (@link(TTerrainLod.TakeBuilt), @link(TTerrainLod.Attach)),
  and is told when to show, hide and free it
  (@link(TTerrainLod.OnShowMesh), @link(TTerrainLod.OnReleaseMesh)). Every
  method is for the main thread.

  No FMX. }
unit GDEMTerrainLod;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math.Vectors,
  System.Generics.Collections, System.Generics.Defaults,
  GDEMTerrain;

const
  { Tiles are drawn whose nearest point is no further than this from the
    point the camera looks at, in kilometres: one and a half tiles north
    and south, so 3 tiles high, and as many as that takes east and west. }
  TERRAIN_WINDOW_KM = 170;

  { A tile is dropped once it is this many times @link(TERRAIN_WINDOW_KM)
    away, so moving back and forth over a boundary does not reload it. }
  WINDOW_KEEP = 1.25;

  { When the point the camera looks at is this far from the point
    positions are measured from, kilometres, everything is measured again
    from where it is, so up stays up and numbers stay small. }
  TERRAIN_REBASE_KM = 150;

  { A patch is put back together once the camera is this many times
    further than the distance that split it. }
  SPLIT_HYSTERESIS = 1.15;

  { No more patches than this are kept: a limit for safety, far above
    what a view needs (about 1,100 at the High distance detail). }
  TERRAIN_MAX_NODES = 6000;

type
  { @abstract(What the view knows about a tile, to draw it.) }
  TTerrainTileInfo = record
    { What it holds. }
    Kind: TTerrainTileKind;
    { Its @code(_dem.tif), for land. }
    DemFile: string;
  end;

  { @abstract(Says what a tile holds.)
    @param(ASouth Latitude of its south edge, -90 to 89.)
    @param(AWest Longitude of its west edge, -180 to 179.)
    @returns(What it holds, and its file.) }
  TTerrainTileLookup = reference to function(ASouth, AWest: Integer): TTerrainTileInfo;

  { @abstract(Where the camera is and where it looks, in the frame's
    kilometres.) }
  TTerrainEye = record
    { The camera's position. }
    Position: TPoint3D;
    { The way it looks, a unit vector. }
    Forward: TPoint3D;
    { Its right, a unit vector. }
    Right: TPoint3D;
    { Its up, a unit vector. }
    Up: TPoint3D;
    { The tangent of half the view's width, as an angle. }
    TanX: Single;
    { The tangent of half the view's height, as an angle. }
    TanY: Single;
    { The point it looks at; the window of tiles centres on it. }
    Target: TPoint3D;
  end;

  { @abstract(Where a patch is in being made.) }
  TTerrainNodeState = (
    { Not wanted yet. }
    nsEmpty,
    { Wanted, waiting for a worker. }
    nsWaiting,
    { Being made. }
    nsBuilding,
    { Made, with a mesh. }
    nsReady,
    { Could not be made; drawn as nothing. }
    nsFailed);

  { A tile in the window; declared below. }
  TTerrainRoot = class;

  { @abstract(One patch in a tile's tree.) }
  TTerrainNode = class
  public
    { A number unique to the patch, for matching results. }
    Id: Int64;
    { The tile. }
    Root: TTerrainRoot;
    { The patch this is part of; @nil for the tile's own. }
    Parent: TTerrainNode;
    { Its depth, 0 to @code(TERRAIN_MAX_DEPTH). }
    Depth: Integer;
    { Its column in the tile at that depth, 0 at the west. }
    X: Integer;
    { Its row, 0 at the north. }
    Y: Integer;
    { Its finer patches, when split; empty otherwise. }
    Children: TArray<TTerrainNode>;
    { Where it is in being made. }
    State: TTerrainNodeState;
    { The view's mesh for it, once ready. }
    Mesh: TObject;
    { The smallest corner of its box: estimated, then the patch's own. }
    BoxMin: TPoint3D;
    { The largest corner of its box. }
    BoxMax: TPoint3D;
    { The lowest height in it, metres: the parent's until made. }
    MinHeight: Single;
    { The highest height in it, metres. }
    MaxHeight: Single;
    { @true while it is split into finer patches. }
    Split: Boolean;
    { @true while its mesh is shown. }
    Visible: Boolean;
    { @true if its box was in view at the last look. }
    InView: Boolean;
    { The update that last kept it on show. }
    Kept: Cardinal;
    { The update that last wanted it made. }
    Wanted: Cardinal;
    { Its distance from the camera at the last look, kilometres. }
    Distance: Double;
    { Its place in the queue: lower is sooner. }
    Priority: Double;
  end;

  { @abstract(A tile in the window, and its tree.) }
  TTerrainRoot = class
  public
    { The latitude of its south edge. }
    South: Integer;
    { The longitude of its west edge, -180 to 179. }
    West: Integer;
    { Its heights. }
    Tile: ITerrainTile;
    { Its own patch, the top of its tree. }
    Node: TTerrainNode;
    { The deepest its tree may go: 0 for sea and missing tiles, which are
      flat. }
    MaxDepth: Integer;
  end;

  { @abstract(A patch made by a worker, or why it could not be.) }
  TTerrainBuildResult = record
    { The patch's @link(TTerrainNode.Id). }
    Id: Int64;
    { The tree's generation it was made for. }
    Generation: Integer;
    { The patch. }
    Patch: TTerrainPatch;
    { Why it could not be made; empty if it was. }
    Error: string;
    { How long it took, milliseconds. }
    Milliseconds: Double;
  end;

  { @abstract(The queue workers put patches on and the main thread takes
    them from.) }
  ITerrainResults = interface
    ['{9E7C3A51-0B2D-4F8E-8C61-5D4A2E9B7F10}']
    { Adds a result; any thread.
      @param(AResult The result.) }
    procedure Add(const AResult: TTerrainBuildResult);

    { Takes the oldest result.
      @param(AResult The result.)
      @returns(@false if there is none.) }
    function Take(out AResult: TTerrainBuildResult): Boolean;
  end;

  { @abstract(Shows or hides a patch's mesh.)
    @param(AMesh The mesh.)
    @param(AVisible @true to show it.) }
  TTerrainShowEvent = procedure(AMesh: TObject; AVisible: Boolean) of object;

  { @abstract(Frees a patch's mesh.)
    @param(AMesh The mesh.) }
  TTerrainReleaseEvent = procedure(AMesh: TObject) of object;

  { @abstract(Says whether a patch's mesh is ready to take over from the
    patches it replaces: for the view, whether its imagery has arrived.)
    @param(AMesh The mesh.)
    @returns(@true if it may be shown in place of others.) }
  TTerrainMeshReadyEvent = function(AMesh: TObject): Boolean of object;

  { @abstract(Reports something for the log.)
    @param(AText The line.) }
  TTerrainLogEvent = procedure(const AText: string) of object;

  { @abstract(The trees of patches for the tiles round the camera.) }
  TTerrainLod = class
  private
    { Says what each tile holds. }
    FLookup: TTerrainTileLookup;
    { Backing field for @link(Frame). }
    FFrame: TTerrainFrame;
    { Backing field for @link(Started). }
    FStarted: Boolean;
    { The tiles in the window, by west (X) and south (Y). }
    FRoots: TDictionary<TPoint, TTerrainRoot>;
    { Every patch, by @link(TTerrainNode.Id). }
    FNodes: TDictionary<Int64, TTerrainNode>;
    { The patches on show. }
    FShown: TList<TTerrainNode>;
    { The patches to show, gathered while looking. }
    FKeep: TList<TTerrainNode>;
    { The patches waiting for a worker. }
    FWaiting: TList<TTerrainNode>;
    { Orders @link(FWaiting) by priority. }
    FComparer: IComparer<TTerrainNode>;
    { Where workers put what they make. }
    FResults: ITerrainResults;
    { The last @link(TTerrainNode.Id) given. }
    FNextId: Int64;
    { Changed whenever patches already asked for would no longer fit (a
      new frame or height stretch), so their results are dropped. }
    FGeneration: Integer;
    { Counts updates. }
    FStamp: Cardinal;
    { Patches given to workers whose results have not been taken. }
    FInFlight: Integer;
    { The most patches given to workers at once. }
    FMaxInFlight: Integer;
    { Backing field for @link(MaxDepth). }
    FMaxDepth: Integer;
    { Backing field for @link(Range). }
    FRange: Double;
    { Backing field for @link(Exaggeration). }
    FExaggeration: Single;
    { The camera at the last update. }
    FEye: TTerrainEye;
    { Backing field for @link(BuiltCount). }
    FBuiltCount: Integer;
    { Backing field for @link(BuildMilliseconds). }
    FBuildMilliseconds: Double;
    { Backing field for @link(FailedCount). }
    FFailedCount: Integer;
    { Backing field for @link(OnShowMesh). }
    FOnShowMesh: TTerrainShowEvent;
    { Backing field for @link(OnReleaseMesh). }
    FOnReleaseMesh: TTerrainReleaseEvent;
    { Backing field for @link(OnMeshReady). }
    FOnMeshReady: TTerrainMeshReadyEvent;
    { Backing field for @link(OnLog). }
    FOnLog: TTerrainLogEvent;

    { The key of a tile in @link(FRoots).
      @param(ASouth Latitude of its south edge.)
      @param(AWest Longitude of its west edge, any.)
      @returns(The key, the longitude brought into -180 to 179.) }
    function TileKey(ASouth, AWest: Integer): TPoint;

    { Makes a patch and records it.
      @param(ARoot Its tile.)
      @param(AParent Its parent, or @nil.)
      @param(ADepth Its depth.)
      @param(AX Its column.)
      @param(AY Its row.)
      @returns(The patch.) }
    function NewNode(ARoot: TTerrainRoot; AParent: TTerrainNode; ADepth, AX, AY: Integer): TTerrainNode;

    { Estimates a patch's box before it is made, from its corners and
      middle and its heights so far. }
    procedure EstimateBox(ANode: TTerrainNode);

    { Frees a patch and its finer ones, with their meshes.
      @param(ANode The patch.) }
    procedure FreeNode(ANode: TTerrainNode);

    { Frees a patch's finer ones.
      @param(ANode The patch.) }
    procedure FreeChildren(ANode: TTerrainNode);

    { Makes a patch's finer ones, if it has none.
      @param(ANode The patch.) }
    procedure MakeChildren(ANode: TTerrainNode);

    { @true if a patch's finer ones are all made (or could not be).
      @param(ANode The patch.)
      @returns(@true if every child is ready or failed.) }
    function ChildrenReady(ANode: TTerrainNode): Boolean;

    { @true if a patch may take over from others: it could not be made, or
      it is made and @link(OnMeshReady) agrees.
      @param(ANode The patch.)
      @returns(@true if ready.) }
    function NodeReady(ANode: TTerrainNode): Boolean;

    { Gives a tile's tree a fresh top patch.
      @param(ARoot The tile.) }
    procedure ResetRoot(ARoot: TTerrainRoot);

    { Adds a tile to the window, if it is not there.
      @param(ASouth Latitude of its south edge.)
      @param(AWest Longitude of its west edge.) }
    procedure EnsureRoot(ASouth, AWest: Integer);

    { Frees a tile's tree and drops it from the window.
      @param(ARoot The tile.) }
    procedure FreeRoot(ARoot: TTerrainRoot);

    { Frees every tile. }
    procedure FreeRoots;

    { Brings the window up to date round a point.
      @param(ATarget The point the camera looks at.) }
    procedure UpdateWindow(const ATarget: TPoint3D);

    { Decides what to show of a patch, and what to make.
      @param(ANode The patch.) }
    procedure Visit(ANode: TTerrainNode);

    { Puts a patch on the list to show.
      @param(ANode The patch.) }
    procedure Keep(ANode: TTerrainNode);

    { Asks for a patch to be made, if it is not being.
      @param(ANode The patch.) }
    procedure Want(ANode: TTerrainNode);

    { Gives waiting patches to workers while there is room. }
    procedure LaunchWaiting;

    { Gives a patch to a worker.
      @param(ANode The patch.) }
    procedure Launch(ANode: TTerrainNode);

    { Shows or hides a patch's mesh.
      @param(ANode The patch.)
      @param(AVisible @true to show it.) }
    procedure SetShown(ANode: TTerrainNode; AVisible: Boolean);

    { Writer for @link(MaxDepth).
      @param(AValue 0 to @code(TERRAIN_MAX_DEPTH).) }
    procedure SetMaxDepth(AValue: Integer);

    { Writer for @link(Exaggeration): every patch is made again.
      @param(AValue Times true scale, at least 0.1.) }
    procedure SetExaggeration(AValue: Single);

    { Reader for @link(ShownCount). @returns(The patches on show.) }
    function GetShownCount: Integer;

    { Reader for @link(NodeCount). @returns(The patches kept.) }
    function GetNodeCount: Integer;

    { Reader for @link(TileCount). @returns(The tiles in the window.) }
    function GetTileCount: Integer;

    { Reader for @link(LandTileCount). @returns(The tiles with heights.) }
    function GetLandTileCount: Integer;
  public
    { An empty tree; nothing is drawn until @link(Start).
      @param(ALookup Says what each tile holds; called on the main
        thread.) }
    constructor Create(const ALookup: TTerrainTileLookup);

    { Frees every patch, with its mesh. Workers still running finish into
      a queue nothing reads. }
    destructor Destroy; override;

    { Starts again, measuring from the middle of a tile.
      @param(ASouth Latitude of its south edge.)
      @param(AWest Longitude of its west edge.) }
    procedure Start(ASouth, AWest: Integer);

    { Looks again from the camera: shows, hides and frees meshes, and
      gives workers what is wanted next.
      @param(AEye The camera.) }
    procedure Update(const AEye: TTerrainEye);

    { Takes the next patch made, for the view to make a mesh of; results
      no longer wanted are dropped, and failures recorded.
      @param(ANode The patch.)
      @param(APatch What was made.)
      @returns(@false when there are no more for now.) }
    function TakeBuilt(out ANode: TTerrainNode; out APatch: TTerrainPatch): Boolean;

    { Gives a patch its mesh; it is shown at the next update.
      @param(ANode The patch, from @link(TakeBuilt).)
      @param(AMesh The mesh.)
      @param(APatch What was made, for its box.) }
    procedure Attach(ANode: TTerrainNode; AMesh: TObject; const APatch: TTerrainPatch);

    { Records that a patch could not be made, so it is drawn as nothing.
      @param(ANode The patch.)
      @param(AWhy Why, for the log.) }
    procedure MarkFailed(ANode: TTerrainNode; const AWhy: string);

    { @true while patches are waiting or being made.
      @returns(@true if busy.) }
    function Busy: Boolean;

    { The height of the surface under a point, from the finest heights
      read so far, without reading any.
      @param(AX Kilometres east.)
      @param(AZ Kilometres north.)
      @param(AY The surface's Y there (negative above sea level).)
      @returns(@false if the tile there has none read yet.) }
    function SurfaceY(AX, AZ: Double; out AY: Single): Boolean;

    { The ground's true height at a place (not stretched), from the finest
      heights read so far, without reading any. Sea and tiles not
      downloaded are 0, as they are drawn.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @param(AMetres The height above sea level, metres.)
      @returns(@false if the tile there is not in the window yet, or has
        no heights read yet.) }
    function GroundHeight(ALatitude, ALongitude: Double; out AMetres: Double): Boolean;

    { @true if a point is far enough from the frame's point to start
      again from it (see @link(TERRAIN_REBASE_KM)).
      @param(AX Kilometres east.)
      @param(AZ Kilometres north.)
      @returns(@true if so.) }
    function NeedsRebase(AX, AZ: Double): Boolean;

    { Positions are measured from this point: the middle of the tile
      @link(Start) was given, at sea level. }
    property Frame: TTerrainFrame read FFrame;

    { @true once @link(Start) has been called. }
    property Started: Boolean read FStarted;

    { The deepest any land tile's tree goes: see
      @code(TerrainMaxDepth). }
    property MaxDepth: Integer read FMaxDepth write SetMaxDepth;

    { A patch is split when the camera is nearer than this many times its
      size. }
    property Range: Double read FRange write FRange;

    { Times to stretch heights; 1 is true scale. }
    property Exaggeration: Single read FExaggeration write SetExaggeration;

    { Patches on show. }
    property ShownCount: Integer read GetShownCount;

    { Patches kept, shown or not. }
    property NodeCount: Integer read GetNodeCount;

    { Tiles in the window. }
    property TileCount: Integer read GetTileCount;

    { Tiles in the window with heights. }
    property LandTileCount: Integer read GetLandTileCount;

    { Patches made since @link(ResetCounts). }
    property BuiltCount: Integer read FBuiltCount;

    { Workers' milliseconds making them, added up. }
    property BuildMilliseconds: Double read FBuildMilliseconds;

    { Patches that could not be made since @link(ResetCounts). }
    property FailedCount: Integer read FFailedCount;

    { Workers used at once. }
    property MaxInFlight: Integer read FMaxInFlight;

    { Shows or hides a mesh. }
    property OnShowMesh: TTerrainShowEvent read FOnShowMesh write FOnShowMesh;

    { Frees a mesh. }
    property OnReleaseMesh: TTerrainReleaseEvent read FOnReleaseMesh write FOnReleaseMesh;

    { Says whether a made mesh may take over from the patches it replaces;
      unset, every made mesh may. A patch split stays on show until its
      finer ones are ready by this, and finer ones stay until the patch
      put back together is. }
    property OnMeshReady: TTerrainMeshReadyEvent read FOnMeshReady write FOnMeshReady;

    { Reports problems. }
    property OnLog: TTerrainLogEvent read FOnLog write FOnLog;

    { Sets @link(BuiltCount), @link(BuildMilliseconds) and
      @link(FailedCount) back to 0. }
    procedure ResetCounts;
  end;

implementation

uses
  System.Math, System.Threading, System.Diagnostics,
  GDEMTiles;

type
  { The queue of results, locked for each use. }
  TTerrainResults = class(TInterfacedObject, ITerrainResults)
  private
    { Held while the queue is used. }
    FLock: TObject;
    { The results, oldest first. }
    FItems: TQueue<TTerrainBuildResult>;
  public
    { An empty queue. }
    constructor Create;
    { Frees the queue. }
    destructor Destroy; override;
    { See @link(ITerrainResults.Add).
      @param(AResult The result.) }
    procedure Add(const AResult: TTerrainBuildResult);
    { See @link(ITerrainResults.Take).
      @param(AResult The result.)
      @returns(@false if there is none.) }
    function Take(out AResult: TTerrainBuildResult): Boolean;
  end;

{ TTerrainResults }

constructor TTerrainResults.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FItems := TQueue<TTerrainBuildResult>.Create;
end;

destructor TTerrainResults.Destroy;
begin
  FItems.Free;
  FLock.Free;
  inherited;
end;

procedure TTerrainResults.Add(const AResult: TTerrainBuildResult);
begin
  TMonitor.Enter(FLock);
  try
    FItems.Enqueue(AResult);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TTerrainResults.Take(out AResult: TTerrainBuildResult): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FItems.Count > 0;
    if Result then
      AResult := FItems.Dequeue;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ Work for a worker: makes one patch and queues it. The values are copied
  here, so each worker has its own.
  @param(ATiles The patch's tile and neighbours.)
  @param(ADepth Its depth.)
  @param(AX Its column.)
  @param(AY Its row.)
  @param(AFrame The frame.)
  @param(AExaggeration The height stretch.)
  @param(AId The patch's number.)
  @param(AGeneration The tree's generation.)
  @param(AResults Where to put it.)
  @returns(The work.) }
function MakeBuildTask(const ATiles: TTerrainNeighbours; ADepth, AX, AY: Integer;
  const AFrame: TTerrainFrame; AExaggeration: Single; AId: Int64; AGeneration: Integer;
  const AResults: ITerrainResults): TProc;
var
  LTiles: TTerrainNeighbours;
  LDepth, LX, LY, LGeneration: Integer;
  LFrame: TTerrainFrame;
  LExaggeration: Single;
  LId: Int64;
  LResults: ITerrainResults;
begin
  LTiles := ATiles;
  LDepth := ADepth;
  LX := AX;
  LY := AY;
  LFrame := AFrame;
  LExaggeration := AExaggeration;
  LId := AId;
  LGeneration := AGeneration;
  LResults := AResults;
  Result :=
    procedure
    var
      LResult: TTerrainBuildResult;
      LWatch: TStopwatch;
    begin
      LResult.Id := LId;
      LResult.Generation := LGeneration;
      LResult.Error := '';
      LWatch := TStopwatch.StartNew;
      try
        LResult.Patch := BuildTerrainPatch(LTiles, LDepth, LX, LY, LFrame, LExaggeration);
      except
        on E: Exception do
          LResult.Error := E.ClassName + ': ' + E.Message;
      end;
      LResult.Milliseconds := LWatch.Elapsed.TotalMilliseconds;
      LResults.Add(LResult);
    end;
end;

{ The distance from a point to a box.
  @param(APoint The point.)
  @param(AMin The box's smallest corner.)
  @param(AMax Its largest corner.)
  @returns(0 inside the box.) }
function BoxDistance(const APoint, AMin, AMax: TPoint3D): Double;
var
  LX, LY, LZ: Double;
begin
  LX := Max(Max(AMin.X - APoint.X, 0), APoint.X - AMax.X);
  LY := Max(Max(AMin.Y - APoint.Y, 0), APoint.Y - AMax.Y);
  LZ := Max(Max(AMin.Z - APoint.Z, 0), APoint.Z - AMax.Z);
  Result := Sqrt(LX * LX + LY * LY + LZ * LZ);
end;

{ Whether any of a box may be in view: @false only when all its corners
  are beyond the same side of the view.
  @param(AEye The camera.)
  @param(AMin The box's smallest corner.)
  @param(AMax Its largest corner.)
  @returns(@true if it may be seen.) }
function BoxInView(const AEye: TTerrainEye; const AMin, AMax: TPoint3D): Boolean;
var
  I: Integer;
  LCorner, LOffset: TPoint3D;
  LX, LY, LZ: Single;
  LBehind, LLeft, LRight, LBelow, LAbove: Boolean;
begin
  LBehind := True;
  LLeft := True;
  LRight := True;
  LBelow := True;
  LAbove := True;
  for I := 0 to 7 do
  begin
    LCorner := AMin;
    if Odd(I) then
      LCorner.X := AMax.X;
    if Odd(I shr 1) then
      LCorner.Y := AMax.Y;
    if Odd(I shr 2) then
      LCorner.Z := AMax.Z;
    LOffset := LCorner - AEye.Position;
    LZ := LOffset.DotProduct(AEye.Forward);
    LX := LOffset.DotProduct(AEye.Right);
    LY := LOffset.DotProduct(AEye.Up);
    LBehind := LBehind and (LZ <= 0);
    LLeft := LLeft and (LX < -LZ * AEye.TanX);
    LRight := LRight and (LX > LZ * AEye.TanX);
    LBelow := LBelow and (LY < -LZ * AEye.TanY);
    LAbove := LAbove and (LY > LZ * AEye.TanY);
  end;
  Result := not (LBehind or LLeft or LRight or LBelow or LAbove);
end;

{ The distance from a place to the nearest point of a tile, on the ground.
  @param(ALatitude The place's latitude.)
  @param(ALongitude Its longitude.)
  @param(ASouth The tile's south edge.)
  @param(AWest Its west edge.)
  @returns(Kilometres; 0 inside the tile.) }
function TileDistanceKm(ALatitude, ALongitude: Double; ASouth, AWest: Integer): Double;
var
  LDLat, LDLon: Double;
begin
  LDLat := Max(Max(ASouth - ALatitude, 0), ALatitude - (ASouth + 1));
  // The short way round to the tile's middle, less half its width
  LDLon := ALongitude - (AWest + 0.5);
  LDLon := LDLon - 360 * Round(LDLon / 360);
  LDLon := Max(Abs(LDLon) - 0.5, 0);
  Result := KM_PER_DEGREE * Sqrt(Sqr(LDLat) +
    Sqr(LDLon * Cos(DegToRad(EnsureRange(ALatitude, -89.9, 89.9)))));
end;

{ TTerrainLod }

constructor TTerrainLod.Create(const ALookup: TTerrainTileLookup);
begin
  inherited Create;
  FLookup := ALookup;
  FRoots := TDictionary<TPoint, TTerrainRoot>.Create;
  FNodes := TDictionary<Int64, TTerrainNode>.Create;
  FShown := TList<TTerrainNode>.Create;
  FKeep := TList<TTerrainNode>.Create;
  FWaiting := TList<TTerrainNode>.Create;
  FComparer := TComparer<TTerrainNode>.Construct(
    function(const ALeft, ARight: TTerrainNode): Integer
    begin
      Result := CompareValue(ALeft.Priority, ARight.Priority);
    end);
  FResults := TTerrainResults.Create;
  FMaxInFlight := Max(2, TThread.ProcessorCount);
  FMaxDepth := TERRAIN_MAX_DEPTH;
  FRange := DEFAULT_TERRAIN_RANGE / 10;
  FExaggeration := DEFAULT_TERRAIN_HEIGHTS;
end;

destructor TTerrainLod.Destroy;
begin
  FreeRoots;
  FWaiting.Free;
  FKeep.Free;
  FShown.Free;
  FNodes.Free;
  FRoots.Free;
  FResults := nil;
  inherited;
end;

function TTerrainLod.TileKey(ASouth, AWest: Integer): TPoint;
begin
  Result.X := ((AWest + 180) mod 360 + 360) mod 360 - 180;
  Result.Y := ASouth;
end;

function TTerrainLod.NewNode(ARoot: TTerrainRoot; AParent: TTerrainNode;
  ADepth, AX, AY: Integer): TTerrainNode;
begin
  Inc(FNextId);
  Result := TTerrainNode.Create;
  Result.Id := FNextId;
  Result.Root := ARoot;
  Result.Parent := AParent;
  Result.Depth := ADepth;
  Result.X := AX;
  Result.Y := AY;
  Result.State := nsEmpty;
  if AParent <> nil then
  begin
    Result.MinHeight := AParent.MinHeight;
    Result.MaxHeight := AParent.MaxHeight;
  end
  else if ARoot.Tile.Kind = tkLand then
  begin
    // Unknown until made: enough for most land
    Result.MinHeight := 0;
    Result.MaxHeight := 2000;
  end
  else
  begin
    Result.MinHeight := 0;
    Result.MaxHeight := 0;
  end;
  FNodes.Add(Result.Id, Result);
  EstimateBox(Result);
end;

procedure TTerrainLod.EstimateBox(ANode: TTerrainNode);
var
  LSize, LNorth, LSouth, LWest, LEast, LMidLat, LMidLon: Double;
  LLow, LHigh: Double;
  LPoints: array[0..9] of TPoint3D;
  I: Integer;
begin
  LSize := NODE_ARCSEC[ANode.Depth] / TILE_ARCSEC;
  LNorth := ANode.Root.South + 1 - ANode.Y * LSize;
  LSouth := LNorth - LSize;
  LWest := ANode.Root.West + ANode.X * LSize;
  LEast := LWest + LSize;
  LMidLat := (LNorth + LSouth) / 2;
  LMidLon := (LWest + LEast) / 2;
  LLow := ANode.MinHeight * FExaggeration / 1000;
  LHigh := ANode.MaxHeight * FExaggeration / 1000;
  // The corners and the middle, which the curve of the Earth lifts above
  // them, at the lowest and highest heights
  LPoints[0] := FFrame.ToLocal(LNorth, LWest, LLow);
  LPoints[1] := FFrame.ToLocal(LNorth, LEast, LLow);
  LPoints[2] := FFrame.ToLocal(LSouth, LWest, LLow);
  LPoints[3] := FFrame.ToLocal(LSouth, LEast, LLow);
  LPoints[4] := FFrame.ToLocal(LMidLat, LMidLon, LLow);
  LPoints[5] := FFrame.ToLocal(LNorth, LWest, LHigh);
  LPoints[6] := FFrame.ToLocal(LNorth, LEast, LHigh);
  LPoints[7] := FFrame.ToLocal(LSouth, LWest, LHigh);
  LPoints[8] := FFrame.ToLocal(LSouth, LEast, LHigh);
  LPoints[9] := FFrame.ToLocal(LMidLat, LMidLon, LHigh);
  ANode.BoxMin := LPoints[0];
  ANode.BoxMax := LPoints[0];
  for I := 1 to High(LPoints) do
  begin
    ANode.BoxMin.X := Min(ANode.BoxMin.X, LPoints[I].X);
    ANode.BoxMin.Y := Min(ANode.BoxMin.Y, LPoints[I].Y);
    ANode.BoxMin.Z := Min(ANode.BoxMin.Z, LPoints[I].Z);
    ANode.BoxMax.X := Max(ANode.BoxMax.X, LPoints[I].X);
    ANode.BoxMax.Y := Max(ANode.BoxMax.Y, LPoints[I].Y);
    ANode.BoxMax.Z := Max(ANode.BoxMax.Z, LPoints[I].Z);
  end;
end;

procedure TTerrainLod.FreeChildren(ANode: TTerrainNode);
var
  LChild: TTerrainNode;
begin
  for LChild in ANode.Children do
    FreeNode(LChild);
  ANode.Children := nil;
  ANode.Split := False;
end;

procedure TTerrainLod.FreeNode(ANode: TTerrainNode);
begin
  FreeChildren(ANode);
  if ANode.Mesh <> nil then
  begin
    if Assigned(FOnReleaseMesh) then
      FOnReleaseMesh(ANode.Mesh);
    ANode.Mesh := nil;
  end;
  if ANode.Visible then
    FShown.Remove(ANode);
  if ANode.Kept = FStamp then
    FKeep.Remove(ANode);
  if ANode.State = nsWaiting then
    FWaiting.Remove(ANode);
  FNodes.Remove(ANode.Id);
  ANode.Free;
end;

procedure TTerrainLod.MakeChildren(ANode: TTerrainNode);
var
  LAcross, LA, LB: Integer;
begin
  if ANode.Children <> nil then
    Exit;
  // The tile in ninths, then quarters
  if ANode.Depth = 0 then
    LAcross := 3
  else
    LAcross := 2;
  SetLength(ANode.Children, LAcross * LAcross);
  for LB := 0 to LAcross - 1 do
    for LA := 0 to LAcross - 1 do
      ANode.Children[LB * LAcross + LA] := NewNode(ANode.Root, ANode, ANode.Depth + 1,
        ANode.X * LAcross + LA, ANode.Y * LAcross + LB);
end;

function TTerrainLod.ChildrenReady(ANode: TTerrainNode): Boolean;
var
  LChild: TTerrainNode;
begin
  Result := ANode.Children <> nil;
  for LChild in ANode.Children do
    if not NodeReady(LChild) then
      Exit(False);
end;

function TTerrainLod.NodeReady(ANode: TTerrainNode): Boolean;
begin
  Result := (ANode.State = nsFailed) or ((ANode.State = nsReady) and
    ((ANode.Mesh = nil) or not Assigned(FOnMeshReady) or FOnMeshReady(ANode.Mesh)));
end;

procedure TTerrainLod.ResetRoot(ARoot: TTerrainRoot);
begin
  if ARoot.Node <> nil then
    FreeNode(ARoot.Node);
  ARoot.Node := NewNode(ARoot, nil, 0, 0, 0);
end;

procedure TTerrainLod.EnsureRoot(ASouth, AWest: Integer);
var
  LKey: TPoint;
  LRoot: TTerrainRoot;
  LInfo: TTerrainTileInfo;
begin
  LKey := TileKey(ASouth, AWest);
  if FRoots.ContainsKey(LKey) then
    Exit;
  LInfo := FLookup(LKey.Y, LKey.X);
  LRoot := TTerrainRoot.Create;
  LRoot.South := LKey.Y;
  LRoot.West := LKey.X;
  LRoot.Tile := TTerrainTile.Create(LKey.Y, LKey.X, LInfo.Kind, LInfo.DemFile);
  if LInfo.Kind = tkLand then
    LRoot.MaxDepth := FMaxDepth
  else
    LRoot.MaxDepth := 0;
  FRoots.Add(LKey, LRoot);
  ResetRoot(LRoot);
end;

procedure TTerrainLod.FreeRoot(ARoot: TTerrainRoot);
begin
  FRoots.Remove(TileKey(ARoot.South, ARoot.West));
  if ARoot.Node <> nil then
    FreeNode(ARoot.Node);
  ARoot.Node := nil;
  ARoot.Tile := nil;
  ARoot.Free;
end;

procedure TTerrainLod.FreeRoots;
var
  LRoots: TArray<TTerrainRoot>;
  LRoot: TTerrainRoot;
begin
  LRoots := FRoots.Values.ToArray;
  for LRoot in LRoots do
    FreeRoot(LRoot);
  FShown.Clear;
  FWaiting.Clear;
end;

procedure TTerrainLod.UpdateWindow(const ATarget: TPoint3D);
var
  LLatitude, LLongitude, LReach, LReachLon: Double;
  LSouth, LWest: Integer;
  LRoots: TArray<TTerrainRoot>;
  LRoot: TTerrainRoot;
begin
  FFrame.ToGeo(ATarget.X, ATarget.Z, LLatitude, LLongitude);
  LReach := TERRAIN_WINDOW_KM / KM_PER_DEGREE;
  for LSouth := Floor(LLatitude - LReach) to Floor(LLatitude + LReach) do
  begin
    if not InRange(LSouth, -90, 89) then
      Continue;
    LReachLon := Min(LReach / Max(Cos(DegToRad(LSouth + 0.5)), 0.02), 179);
    for LWest := Floor(LLongitude - LReachLon) to Floor(LLongitude + LReachLon) do
      if TileDistanceKm(LLatitude, LLongitude, LSouth, LWest) <= TERRAIN_WINDOW_KM then
        EnsureRoot(LSouth, LWest);
  end;
  LRoots := FRoots.Values.ToArray;
  for LRoot in LRoots do
    if TileDistanceKm(LLatitude, LLongitude, LRoot.South, LRoot.West) >
       TERRAIN_WINDOW_KM * WINDOW_KEEP then
      FreeRoot(LRoot);
end;

procedure TTerrainLod.Start(ASouth, AWest: Integer);
begin
  FreeRoots;
  Inc(FGeneration);
  FFrame := TTerrainFrame.Create(ASouth + 0.5, TileKey(ASouth, AWest).X + 0.5);
  FStarted := True;
end;

procedure TTerrainLod.Keep(ANode: TTerrainNode);
begin
  ANode.Kept := FStamp;
  FKeep.Add(ANode);
end;

procedure TTerrainLod.Want(ANode: TTerrainNode);
begin
  ANode.Wanted := FStamp;
  ANode.Distance := BoxDistance(FEye.Position, ANode.BoxMin, ANode.BoxMax);
  ANode.InView := BoxInView(FEye, ANode.BoxMin, ANode.BoxMax);
  if ANode.State <> nsEmpty then
    Exit;
  ANode.State := nsWaiting;
  FWaiting.Add(ANode);
end;

procedure TTerrainLod.Visit(ANode: TTerrainNode);
var
  LLimit: Double;
  LSplit: Boolean;
  LChild: TTerrainNode;
begin
  ANode.Distance := BoxDistance(FEye.Position, ANode.BoxMin, ANode.BoxMax);
  ANode.InView := BoxInView(FEye, ANode.BoxMin, ANode.BoxMax);
  LLimit := FRange * NodeSizeKm(ANode.Depth);
  if ANode.Split then
    LLimit := LLimit * SPLIT_HYSTERESIS;
  LSplit := (ANode.Depth < ANode.Root.MaxDepth) and (ANode.Distance < LLimit) and
    ((ANode.Children <> nil) or (FNodes.Count < TERRAIN_MAX_NODES));
  if LSplit then
  begin
    ANode.Split := True;
    MakeChildren(ANode);
    if ChildrenReady(ANode) then
    begin
      for LChild in ANode.Children do
        Visit(LChild);
      Exit;
    end;
    // This patch stays on show until all its finer ones are made
    for LChild in ANode.Children do
      Want(LChild);
  end;

  if ANode.State in [nsReady, nsFailed] then
  begin
    // Being put back together, but not ready to take over (its imagery has
    // not come): the finer patches stay until it is
    if not LSplit and not NodeReady(ANode) and ChildrenReady(ANode) then
    begin
      for LChild in ANode.Children do
        Visit(LChild);
      Exit;
    end;
    if ANode.State = nsReady then
      Keep(ANode);
    if not LSplit then
      FreeChildren(ANode);
  end
  else
  begin
    Want(ANode);
    // Being put back together: the finer patches stay until it is made
    if not LSplit and ChildrenReady(ANode) then
      for LChild in ANode.Children do
        Visit(LChild);
  end;
end;

procedure TTerrainLod.SetShown(ANode: TTerrainNode; AVisible: Boolean);
begin
  ANode.Visible := AVisible;
  if (ANode.Mesh <> nil) and Assigned(FOnShowMesh) then
    FOnShowMesh(ANode.Mesh, AVisible);
end;

procedure TTerrainLod.Update(const AEye: TTerrainEye);
var
  LRoots: TArray<TTerrainRoot>;
  LRoot: TTerrainRoot;
  LNode: TTerrainNode;
  I: Integer;
begin
  if not FStarted then
    Exit;
  FEye := AEye;
  Inc(FStamp);
  UpdateWindow(AEye.Target);

  FKeep.Clear;
  LRoots := FRoots.Values.ToArray;
  for LRoot in LRoots do
    Visit(LRoot.Node);

  // Hide what is no longer kept, then show what is newly kept
  for LNode in FShown do
    if LNode.Kept <> FStamp then
      SetShown(LNode, False);
  for LNode in FKeep do
    if not LNode.Visible then
      SetShown(LNode, True);
  FShown.Clear;
  FShown.AddRange(FKeep);

  // Forget what is no longer wanted; the rest in order
  for I := FWaiting.Count - 1 downto 0 do
  begin
    LNode := FWaiting[I];
    if LNode.Wanted <> FStamp then
    begin
      LNode.State := nsEmpty;
      FWaiting.Delete(I);
    end
    else
    begin
      // In view first, then coarse before fine, then near before far
      LNode.Priority := LNode.Depth * 1E6 + LNode.Distance;
      if not LNode.InView then
        LNode.Priority := LNode.Priority + 1E12;
    end;
  end;
  FWaiting.Sort(FComparer);
  LaunchWaiting;
end;

procedure TTerrainLod.LaunchWaiting;
var
  LNode: TTerrainNode;
begin
  while (FInFlight < FMaxInFlight) and (FWaiting.Count > 0) do
  begin
    LNode := FWaiting[0];
    FWaiting.Delete(0);
    LNode.State := nsBuilding;
    Launch(LNode);
  end;
end;

procedure TTerrainLod.Launch(ANode: TTerrainNode);
var
  LTiles: TTerrainNeighbours;
  LRow, LColumn: Integer;
  LRoot: TTerrainRoot;
begin
  for LRow := -1 to 1 do
    for LColumn := -1 to 1 do
    begin
      // Row -1 is the tile to the north
      if FRoots.TryGetValue(TileKey(ANode.Root.South - LRow, ANode.Root.West + LColumn), LRoot) then
        LTiles[(LRow + 1) * 3 + LColumn + 1] := LRoot.Tile
      else
        LTiles[(LRow + 1) * 3 + LColumn + 1] := nil;
    end;
  LTiles[4] := ANode.Root.Tile;
  Inc(FInFlight);
  TTask.Run(MakeBuildTask(LTiles, ANode.Depth, ANode.X, ANode.Y, FFrame, FExaggeration,
    ANode.Id, FGeneration, FResults));
end;

function TTerrainLod.TakeBuilt(out ANode: TTerrainNode; out APatch: TTerrainPatch): Boolean;
var
  LResult: TTerrainBuildResult;
begin
  ANode := nil;
  while FResults.Take(LResult) do
  begin
    Dec(FInFlight);
    if (LResult.Generation <> FGeneration) or not FNodes.TryGetValue(LResult.Id, ANode) or
       (ANode.State <> nsBuilding) then
    begin
      ANode := nil;
      Continue;
    end;
    if LResult.Error <> '' then
    begin
      MarkFailed(ANode, LResult.Error);
      ANode := nil;
      Continue;
    end;
    Inc(FBuiltCount);
    FBuildMilliseconds := FBuildMilliseconds + LResult.Milliseconds;
    APatch := LResult.Patch;
    Exit(True);
  end;
  LaunchWaiting;
  Result := False;
end;

procedure TTerrainLod.Attach(ANode: TTerrainNode; AMesh: TObject; const APatch: TTerrainPatch);
begin
  ANode.Mesh := AMesh;
  ANode.State := nsReady;
  ANode.Visible := False;
  ANode.BoxMin := APatch.BoxMin;
  ANode.BoxMax := APatch.BoxMax;
  ANode.MinHeight := APatch.MinHeight;
  ANode.MaxHeight := APatch.MaxHeight;
end;

procedure TTerrainLod.MarkFailed(ANode: TTerrainNode; const AWhy: string);
begin
  ANode.State := nsFailed;
  Inc(FFailedCount);
  if (FFailedCount = 1) and Assigned(FOnLog) then
    FOnLog(Format('WARNING: a 3D patch of %s could not be made (%s); it is left out',
      [TileName(ANode.Root.South, ANode.Root.West), AWhy.TrimRight(['.'])]));
end;

function TTerrainLod.Busy: Boolean;
begin
  Result := (FInFlight > 0) or (FWaiting.Count > 0);
end;

function TTerrainLod.SurfaceY(AX, AZ: Double; out AY: Single): Boolean;
var
  LLatitude, LLongitude, LHeight: Double;
begin
  AY := 0;
  Result := False;
  if not FStarted then
    Exit;
  FFrame.ToGeo(AX, AZ, LLatitude, LLongitude);
  if not GroundHeight(LLatitude, LLongitude, LHeight) then
    Exit;
  AY := FFrame.ToLocal(LLatitude, LLongitude, LHeight * FExaggeration / 1000).Y;
  Result := True;
end;

function TTerrainLod.GroundHeight(ALatitude, ALongitude: Double; out AMetres: Double): Boolean;
var
  LRoot: TTerrainRoot;
  LLevel: TTerrainLevel;
begin
  AMetres := 0;
  Result := False;
  if not FStarted then
    Exit;
  if not FRoots.TryGetValue(TileKey(Floor(ALatitude), Floor(ALongitude)), LRoot) then
    Exit;
  if LRoot.Tile.Kind <> tkLand then
    AMetres := 0
  else if LRoot.Tile.TryFinestHeights(LLevel) then
    AMetres := LLevel.Sample((ALongitude - Floor(ALongitude)) * TILE_ARCSEC,
      (Floor(ALatitude) + 1 - ALatitude) * TILE_ARCSEC)
  else
    Exit;
  Result := True;
end;

function TTerrainLod.NeedsRebase(AX, AZ: Double): Boolean;
begin
  Result := FStarted and (Sqr(AX) + Sqr(AZ) > Sqr(TERRAIN_REBASE_KM));
end;

procedure TTerrainLod.SetMaxDepth(AValue: Integer);
var
  LRoot: TTerrainRoot;
begin
  FMaxDepth := EnsureRange(AValue, 0, TERRAIN_MAX_DEPTH);
  for LRoot in FRoots.Values do
    if LRoot.Tile.Kind = tkLand then
      LRoot.MaxDepth := FMaxDepth;
end;

procedure TTerrainLod.SetExaggeration(AValue: Single);
var
  LRoots: TArray<TTerrainRoot>;
  LRoot: TTerrainRoot;
begin
  AValue := Max(AValue, 0.1);
  if SameValue(AValue, FExaggeration) then
    Exit;
  FExaggeration := AValue;
  // Every patch again; the tiles' heights are kept
  Inc(FGeneration);
  LRoots := FRoots.Values.ToArray;
  for LRoot in LRoots do
    ResetRoot(LRoot);
end;

function TTerrainLod.GetShownCount: Integer;
begin
  Result := FShown.Count;
end;

function TTerrainLod.GetNodeCount: Integer;
begin
  Result := FNodes.Count;
end;

function TTerrainLod.GetTileCount: Integer;
begin
  Result := FRoots.Count;
end;

function TTerrainLod.GetLandTileCount: Integer;
var
  LRoot: TTerrainRoot;
begin
  Result := 0;
  for LRoot in FRoots.Values do
    if LRoot.Tile.Kind = tkLand then
      Inc(Result);
end;

procedure TTerrainLod.ResetCounts;
begin
  FBuiltCount := 0;
  FBuildMilliseconds := 0;
  FFailedCount := 0;
end;

end.
