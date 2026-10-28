{ @abstract(The 3D view: a Gorilla3D viewport showing the ground round a
  tile, fine near the camera and coarser further away, flown over with
  the keyboard and the mouse.)

  @link(TTerrainView) is a layout that fills the 3D tab. It holds:

  @preformatted(
TTerrainView                  takes the mouse and the keys
`-- TGorillaViewport          HitTest off, so the mouse reaches the layout
    |-- target (TDummy)       the point the camera looks at
    |-- terrain (TDummy)      holds the patches' meshes
    |   `-- TGorillaSingletonMesh, one per patch, all sharing one
    |       TGorillaVertexColorMaterialSource
    `-- TGorillaCamera        where the flight is; Target is the target
        `-- TGorillaLight     a point light where the camera is
TTerrainAltimeter, TTerrainFrameRate, TTerrainSpeedPanel (top left),
TTerrainCompass (top right) and TTerrainBanner (middle, for a crash), over
the viewport, letting the mouse through
  )

  Which patches to draw is decided by @code(TTerrainLod) (in
  @code(GDEMTerrainLod)), which has them made on worker threads; this view
  turns each one made into a mesh on the main thread, a few at a time
  (@link(UPLOAD_BUDGET_MS) each tick of a 15 ms timer), so the window keeps
  responding while the ground sharpens. The vertices are copied straight
  into FMX's vertex buffer where its layout can be found, and the one list
  of triangles every patch shares is copied in a single move.

  The camera is a flight (@code(TFlight), in @code(GDEMFlight)): it starts
  hovering, facing north, @link(TTerrainView.StartHeight) metres above the
  middle of the tile asked for, and looks ahead and a little down. Keys,
  held: Up and Down change the speed (never below a hover), Left and Right
  turn, Page Up and Page Down climb and descend, Q and A tilt the camera
  up and down; H stops to a hover; Space pauses and carries on; B asks
  for a bookmark (@link(TTerrainView.OnBookmark)); L turns the place
  names on and off; R starts again. The keys are listed in a panel at the
  bottom left, which collapses to its title.

  Named places (@link(TTerrainView.PlaceLabels): towns and cities,
  mountains, the user's markers) within @link(LABEL_RANGE_KM) are labelled
  on poles standing on the ground under them, the most important first,
  as many as fit. Their ground is projected onto the screen as the camera
  sees it: field of view @code(TERRAIN_FOV) up and down, wider across by
  the view's shape. Going below the
  ground is a crash, which stops the flight until R. Left-drag looks round
  (turns and tilts), the wheel climbs and descends, a double click starts
  again. Each tick moves the flight by the time gone, so its speed does not
  depend on the frame rate. Flying far from where positions are measured
  from measures everything again from there (@code(TERRAIN_REBASE_KM)), so
  the flight can go as far as there are tiles.

  With @link(TTerrainView.Realistic) on, each patch is drawn with
  satellite imagery instead of its height colours: a patch on show is
  drawn at once in its colours, its texture is asked of
  @link(TTerrainView.Imagery) (@code(GDEMImagery), which downloads and
  caches it in the background), and the texture replaces the colours when
  it arrives. A patch asks when it is shown, or earlier, while it waits to
  take over from others: the tree (@code(TTerrainLod.OnMeshReady)) keeps a
  patch on show until the finer patches replacing it have their imagery,
  and finer ones until the patch put back together has its, so imagery is
  never replaced by bare patches. A patch that waits longer than
  @link(IMAGERY_WAIT_MS) for its texture may take over all the same, so a
  slow connection does not hold the view back. A patch whose texture could
  not be made asks again a minute later (@link(IMAGERY_RETRY_MS)). Every patch carries texture
  coordinates, so turning Realistic on or off needs no patch made again. EOX's credit is drawn
  along the bottom while it is on.

  The view draws no more frames a second than the display the window is
  on refreshes at (@code(GDEMDisplays)), and checks four times a second
  whether the window has moved to another display.

  The instruments (@code(GDEMTerrainHud)) show the flight's height above
  the ground under it and above sea level, the ground's height there, its
  heading against true north, its speed and the camera's tilt, and the
  frames drawn a second. Heights are true heights: when heights are
  stretched for drawing, the flight is drawn that much higher too, so it
  stays the same height above the ground as drawn. }
unit GDEMTerrainView;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math.Vectors,
  System.Diagnostics, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Layouts, FMX.Types3D, FMX.Controls3D,
  FMX.Objects3D,
  Gorilla.Viewport, Gorilla.Camera, Gorilla.Light, Gorilla.Mesh, Gorilla.Material.VertexColor,
  Gorilla.Material.Default,
  GDEMTerrain, GDEMTerrainLod, GDEMTerrainHud, GDEMFlight, GDEMImagery;

const
  { The most milliseconds a timer tick spends turning patches into meshes;
    what is left waits for the next tick. }
  UPLOAD_BUDGET_MS = 12;

  { Places nearer the flight than this are labelled, kilometres. }
  LABEL_RANGE_KM = 100;

  { The list of places in reach is made again when the flight has moved
    this far, kilometres. }
  LABEL_REFRESH_KM = 10;

  { Milliseconds before a patch whose imagery could not be made asks for
    it again. }
  IMAGERY_RETRY_MS = 60000;

  { How often patches on show without imagery are looked for, to ask for
    it, milliseconds. }
  IMAGERY_SWEEP_MS = 5000;

  { The longest a patch waits for its imagery before it may take over
    from others without it, milliseconds. }
  IMAGERY_WAIT_MS = 2000;

  { How often the tree looks again while patches wait for imagery,
    milliseconds, so one whose wait runs out takes over. }
  IMAGERY_LOOK_MS = 100;

  { How often the imagery along the way ahead is looked for while
    flying, milliseconds. }
  IMAGERY_AHEAD_MS = 2000;

  { How far ahead imagery is fetched: the distance flown in this many
    seconds at the speed now, up to @link(IMAGERY_AHEAD_KM). }
  IMAGERY_AHEAD_SECONDS = 60;

  { The farthest ahead imagery is fetched, kilometres. }
  IMAGERY_AHEAD_KM = 30;

  { The most imagery tiles asked for ahead at each look. }
  IMAGERY_AHEAD_TILES = 24;

type
  { @abstract(Reports a line for the log.)
    @param(Sender The view.)
    @param(AText The line.) }
  TTerrainReportEvent = procedure(Sender: TObject; const AText: string) of object;

  { @abstract(Where the flight is and how it is going: all a bookmark needs
    to come back to it.) }
  TTerrainFlightState = record
    { Latitude, degrees. }
    Latitude: Double;
    { Longitude, degrees. }
    Longitude: Double;
    { True height above sea level, metres. }
    Altitude: Double;
    { The way the flight goes, degrees clockwise from true north. }
    Heading: Double;
    { Speed over the ground, metres a second. }
    Speed: Double;
    { The camera's tilt below the level, degrees. }
    Tilt: Double;
  end;

  { @abstract(A named place to label in the view.) }
  TTerrainPlaceLabel = record
    { The name to show. }
    Name: string;
    { Latitude, degrees. }
    Latitude: Double;
    { Longitude, degrees. }
    Longitude: Double;
    { What it is, which sets its colour. }
    Kind: TTerrainLabelKind;
    { How much it matters: lower first, so it wins a place on screen. }
    Rank: Single;
  end;

  { @abstract(A patch's mesh, with where the patch is, for its imagery.) }
  TTerrainPatchMesh = class(TGorillaSingletonMesh)
  public
    { The id its imagery is asked for under, unique to the mesh. }
    ImageryId: Int64;
    { The patch's north edge, degrees. }
    North: Double;
    { The patch's west edge, degrees. }
    West: Double;
    { The patch's size, degrees, north to south and west to east. }
    Size: Double;
    { Its textured material while it has one, owned by the mesh;
      @nil while it shows its height colours. }
    Imagery: TGorillaDefaultMaterialSource;
    { @true while its imagery is asked for and not yet arrived. }
    ImageryAsked: Boolean;
    { When its imagery was asked for (@code(TThread.GetTickCount64)). }
    ImageryAskedAt: UInt64;
    { When its imagery last could not be made (@code(TThread.GetTickCount64));
      0 if it has not failed. It is not asked for again until
      @link(IMAGERY_RETRY_MS) later. }
    ImageryFailedAt: UInt64;
  end;

  { @abstract(A Gorilla3D view of the ground round a tile, flown over.) }
  TTerrainView = class(TLayout)
  private
    { The Gorilla3D viewport, filling the layout. }
    FViewport: TGorillaViewport;
    { The camera. }
    FCamera: TGorillaCamera;
    { The point the camera looks at. }
    FCentre: TDummy;
    { The light, riding on the camera. }
    FLight: TGorillaLight;
    { Holds the patches' meshes. }
    FTerrain: TDummy;
    { The material every patch is drawn with: its vertex colours. }
    FMaterial: TGorillaVertexColorMaterialSource;
    { Decides which patches to draw; made by the first @link(ShowArea). }
    FLod: TTerrainLod;
    { Turns patches into meshes, moves the flight, and looks again, every
      15 ms. }
    FTimer: TTimer;
    { Backing field for @link(TileLookup). }
    FTileLookup: TTerrainTileLookup;
    { The shared triangles. }
    FIndices: TArray<Integer>;
    { The same as 16-bit numbers, for a 16-bit index buffer. }
    FIndices16: TArray<Word>;
    { The same as 32-bit numbers. }
    FIndices32: TArray<Cardinal>;
    { The latitude of the south edge of the tile asked for. }
    FAreaSouth: Integer;
    { The longitude of its west edge. }
    FAreaWest: Integer;
    { @true once a tile has been asked for. }
    FHasArea: Boolean;
    { Backing field for @link(Exaggeration). }
    FExaggeration: Single;
    { Backing field for @link(MaxDetail). }
    FMaxDetail: Integer;
    { Backing field for @link(Range). }
    FRange: Integer;
    { The flight: where the camera is and where it is going. }
    FFlight: TFlight;
    { The flight's controls held down on the keyboard. }
    FHeld: TFlightControls;
    { Times the gap between moves of the flight. }
    FFlightWatch: TStopwatch;
    { @true while the left button is held down on the view, looking round. }
    FDragging: Boolean;
    { Where the pointer was at the last move of the drag. }
    FDragLast: TPointF;
    { @true when the camera has moved since the tree last looked. }
    FCameraMoved: Boolean;
    { @true while patches were being made at the last tick. }
    FWasBusy: Boolean;
    { Times the work since it started. }
    FBusyWatch: TStopwatch;
    { Milliseconds spent turning patches into meshes since the work
      started. }
    FUploadMs: Double;
    { Patches turned into meshes since the work started. }
    FUploads: Integer;
    { @true if the last patch's vertices were copied straight into the
      buffer; @false if FMX's setters had to be used for some. }
    FDirectCopy: Boolean;
    { The nearest the view draws, kilometres, as last set: it follows the
      flight down, so the ground is not cut away when flying low. }
    FNearPlane: Single;
    { The camera's heights, over the top left of the viewport. }
    FAltimeter: TTerrainAltimeter;
    { The frames drawn a second, under @link(FAltimeter). }
    FFrameRate: TTerrainFrameRate;
    { The speed and the camera's tilt, under @link(FFrameRate). }
    FSpeedPanel: TTerrainSpeedPanel;
    { The compass, over the top right of the viewport. }
    FCompass: TTerrainCompass;
    { News across the middle of the view: a crash. }
    FBanner: TTerrainBanner;
    { Times the gap between readings of the frame rate and checks of the
      display. }
    FRateWatch: TStopwatch;
    { The display the window was on at the last check; empty before the
      first. }
    FDisplayName: string;
    { Backing field for @link(StartHeight). }
    FStartHeight: Integer;
    { Backing field for @link(Imagery). }
    FImagery: TImageryService;
    { Backing field for @link(Realistic). }
    FRealistic: Boolean;
    { Every patch mesh, by its imagery id, to match textures that arrive. }
    FMeshes: TDictionary<Int64, TTerrainPatchMesh>;
    { The next imagery id to give a mesh. }
    FNextImageryId: Int64;
    { The texture coordinates every patch shares. }
    FTexCoords: TArray<TPointF>;
    { @true once it has been logged that the meshes have no room for
      texture coordinates. }
    FNoTexCoordsLogged: Boolean;
    { EOX's credit, along the bottom while @link(Realistic) is on. }
    FCredit: TTerrainCredit;
    { Textures applied since the work started. }
    FTextures: Integer;
    { Milliseconds the workers took for them. }
    FTextureMs: Double;
    { Tiles downloaded for them. }
    FTilesDownloaded: Integer;
    { Textures that could not be made since the work started. }
    FTextureFailures: Integer;
    { Times the gap between looks for patches on show without imagery. }
    FImagerySweep: TStopwatch;
    { @true once the vertex buffer's layout has been logged. }
    FLayoutLogged: Boolean;
    { Times the gap between looks by the tree while patches wait for
      imagery. }
    FImageryLook: TStopwatch;
    { @true when a texture has been put on a mesh since the tree last
      looked. }
    FImageryArrived: Boolean;
    { Times the gap between looks for the imagery along the way ahead. }
    FImageryAhead: TStopwatch;
    { Backing field for @link(Paused). }
    FPaused: Boolean;
    { Says the view is paused, below the crash banner's place. }
    FPauseBanner: TTerrainBanner;
    { Hides the view while @link(Covered). }
    FCover: TTerrainCover;
    { The keys, bottom left, collapsible. }
    FControls: TTerrainControls;
    { Backing field for @link(OnBookmark). }
    FOnBookmark: TNotifyEvent;
    { Backing field for @link(OnControlsToggle). }
    FOnControlsToggle: TNotifyEvent;
    { @true while Space is held, so its repeats and its character do not
      pause and carry on again. }
    FSpaceDown: Boolean;
    { @true while B is held, for the same reason. }
    FBookmarkKeyDown: Boolean;
    { @true while L is held, for the same reason. }
    FLabelsKeyDown: Boolean;
    { @true from a bookmark key until @link(OnBookmark) has been called. }
    FBookmarkQueued: Boolean;
    { The place names, under the instruments. }
    FLabelLayer: TTerrainLabelLayer;
    { Backing field for @link(PlaceLabels). }
    FPlaceLabels: TArray<TTerrainPlaceLabel>;
    { The places within reach of the flight, as indexes into
      @link(FPlaceLabels), sorted most important first. }
    FNearLabels: TArray<Integer>;
    { Where the flight was when @link(FNearLabels) was made, latitude. }
    FNearLatitude: Double;
    { Where the flight was when @link(FNearLabels) was made, longitude. }
    FNearLongitude: Double;
    { @true while @link(FNearLabels) fits the labels given. }
    FNearValid: Boolean;
    { Backing field for @link(ShowLabels). }
    FShowLabels: Boolean;
    { Backing field for @link(OnLabelsToggle). }
    FOnLabelsToggle: TNotifyEvent;
    { Backing field for @link(OnFlightMoved). }
    FOnFlightMoved: TNotifyEvent;
    { Backing field for @link(OnCrash). }
    FOnCrash: TNotifyEvent;
    { Backing field for @link(OnRestart). }
    FOnRestart: TNotifyEvent;
    { Backing field for @link(OnSettled). }
    FOnSettled: TTerrainReportEvent;
    { Backing field for @link(OnLog). }
    FOnLog: TTerrainReportEvent;

    { Puts the camera where the flight is, looking along its heading and
      down by its tilt, and has the instruments show it. }
    procedure PlaceCamera;

    { The camera, for the tree.
      @returns(Its position, directions and view.) }
    function MakeEye: TTerrainEye;

    { The ground's true height at a place, for the flight: from the tree's
      heights, once there is a tree.
      @param(ALatitude Latitude, degrees.)
      @param(ALongitude Longitude, degrees.)
      @param(AMetres The height above sea level, metres.)
      @returns(@false if the ground there is not known yet.) }
    function FlightGround(ALatitude, ALongitude: Double; out AMetres: Double): Boolean;

    { Moves the flight on by the time since the last tick, turns made
      patches into meshes, measures again from a new point if the flight
      has gone far, and has the tree look again.
      @param(Sender The timer.) }
    procedure TimerTick(Sender: TObject);

    { Shows the crash banner and logs where it happened.
      @param(ASpeed The speed just before, metres a second.) }
    procedure ReportCrash(ASpeed: Double);

    { Gives the instruments the flight's heights, heading, speed and tilt;
      dashes while there is nothing to measure from. }
    procedure UpdateInstruments;

    { Puts the instruments in the corners of the view, and the banner in
      the middle. }
    procedure PlaceInstruments;

    { Reads the frame rate for its panel, and if the window has moved to
      another display, draws no faster than that display refreshes. }
    procedure CheckFrameRate;

    { Makes a patch's mesh, hidden, and asks for its imagery if
      @link(Realistic) is on.
      @param(APatch The patch.)
      @param(ANode Its node in the tree, for where it is.)
      @returns(The mesh.)
      @raises(ETerrainError if Gorilla3D gives it no mesh data.) }
    function MakeMesh(const APatch: TTerrainPatch; ANode: TTerrainNode): TObject;

    { Asks for a mesh's imagery, unless it has it, is waiting for it, or
      could not have it less than @link(IMAGERY_RETRY_MS) ago.
      @param(AMesh The mesh.) }
    procedure RequestImagery(AMesh: TTerrainPatchMesh);

    { Asks for the imagery of every patch on show that has none and is not
      waiting for it. }
    procedure SweepImagery;

    { Asks the imagery service to fetch, into its disk cache, the tiles
      under the way ahead at the detail the ground below the flight is
      drawn with, so they are there when the patches under them are made:
      up to @link(IMAGERY_AHEAD_TILES), nearest first, a line along the
      heading and one each side. }
    procedure PrefetchImagery;

    { For the tree: whether a mesh may take over from the patches it
      replaces. With @link(Realistic) on, only once its imagery has
      arrived, could not be made, or has been waited for
      @link(IMAGERY_WAIT_MS); asks for it if it has not been.
      @param(AMesh The mesh.)
      @returns(@true if it may.) }
    function MeshReady(AMesh: TObject): Boolean;

    { Puts a texture on its mesh, if the mesh is still there and
      @link(Realistic) still on.
      @param(AResult The texture.) }
    procedure ApplyImagery(const AResult: TImageryResult);

    { Puts a mesh back to its height colours, freeing its texture.
      @param(AMesh The mesh.) }
    procedure DropImagery(AMesh: TTerrainPatchMesh);

    { Writer for @link(Realistic): asks for every mesh's imagery, or puts
      every mesh back to its height colours.
      @param(AValue @true for imagery.) }
    procedure SetRealistic(AValue: Boolean);

    { Writer for @link(Imagery): forgets what the old service was asked,
      and asks the new one for every mesh's imagery if @link(Realistic) is
      on.
      @param(AValue The service, or @nil.) }
    procedure SetImagery(AValue: TImageryService);

    { Copies a patch's vertices into a vertex buffer, straight into its
      memory where the layout can be found, otherwise through FMX's
      setters.
      @param(ABuffer The buffer, already the right length.)
      @param(APatch The patch.)
      @returns(@true if every attribute was copied straight.) }
    function FillVertices(ABuffer: TVertexBuffer; const APatch: TTerrainPatch): Boolean;

    { Copies the shared triangles into an index buffer.
      @param(ABuffer The buffer.) }
    procedure FillIndices(ABuffer: TIndexBuffer);

    { Shows or hides a mesh, for the tree.
      @param(AMesh The mesh.)
      @param(AVisible @true to show it.) }
    procedure ShowMesh(AMesh: TObject; AVisible: Boolean);

    { Frees a mesh, for the tree.
      @param(AMesh The mesh.) }
    procedure ReleaseMesh(AMesh: TObject);

    { Passes the tree's problems to @link(OnLog).
      @param(AText The line.) }
    procedure LodLog(const AText: string);

    { Starts timing a round of work. }
    procedure BeginWork;

    { Measures everything again from the tile under the flight. }
    procedure Rebase;

    { Writer for @link(Exaggeration): every patch is made again, and the
      flight drawn as much higher.
      @param(AValue Times to stretch heights; at least 0.1.) }
    procedure SetExaggeration(AValue: Single);

    { Writer for @link(MaxDetail).
      @param(AValue Samples across a tile, from @code(TERRAIN_DETAILS).) }
    procedure SetMaxDetail(AValue: Integer);

    { Writer for @link(Range).
      @param(AValue Tenths, from @code(TERRAIN_RANGES).) }
    procedure SetRange(AValue: Integer);

    { Writer for @link(StartHeight).
      @param(AValue Metres; less than 0 is taken as 0.) }
    procedure SetStartHeight(AValue: Integer);

    { Writer for @link(Paused): stops or carries on the flight, and shows
      or hides the banner saying so.
      @param(AValue @true to pause.) }
    procedure SetPaused(AValue: Boolean);

    { Reader for @link(Covered). @returns(@true while covered.) }
    function GetCovered: Boolean;

    { Writer for @link(Covered).
      @param(AValue @true to cover the view.) }
    procedure SetCovered(AValue: Boolean);

    { A picture of the 3D drawing as it is now, for the cover.
      @returns(The picture, the caller's to free; @nil if none could be
        had, or it came out empty.) }
    function PictureOfView: TBitmap;

    { Shows on the speed panel whether the autopilot is on, and climbing. }
    procedure UpdateAutopilotText;

    { Reader for @link(GroundHug). @returns(@true if on.) }
    function GetGroundHug: Boolean;

    { Writer for @link(GroundHug).
      @param(AValue @true to hug the ground.) }
    procedure SetGroundHug(AValue: Boolean);

    { Reader for @link(Autopilot). @returns(@true if on.) }
    function GetAutopilot: Boolean;

    { Writer for @link(Autopilot).
      @param(AValue @true to turn it on.) }
    procedure SetAutopilot(AValue: Boolean);

    { Writer for @link(FlownKm).
      @param(AValue Kilometres.) }
    procedure SetFlownKm(AValue: Double);

    { Writer for @link(FlightSpeed).
      @param(AValue Metres a second.) }
    procedure SetFlightSpeed(AValue: Double);

    { Reader for @link(ControlsCollapsed). @returns(@true if collapsed.) }
    function GetControlsCollapsed: Boolean;

    { Writer for @link(ControlsCollapsed).
      @param(AValue @true to show only the panel's title.) }
    procedure SetControlsCollapsed(AValue: Boolean);

    { Moves the panel to the bottom again when it opens or closes, keeps
      the keyboard here, and tells @link(OnControlsToggle).
      @param(Sender The panel.) }
    procedure ControlsToggled(Sender: TObject);

    { Calls @link(OnBookmark) once the key's handling is over, and only
      once for a key that came both as a key and as a character. }
    procedure AskForBookmark;

    { Finds the places within @link(LABEL_RANGE_KM) of the flight again,
      most important first, when it has moved far enough. }
    procedure FindNearLabels;

    { Projects the places near the flight onto the screen and gives them
      to the label layer; nothing when @link(ShowLabels) is off. }
    procedure UpdateLabels;

    { Writer for @link(PlaceLabels).
      @param(AValue The places.) }
    procedure SetPlaceLabels(const AValue: TArray<TTerrainPlaceLabel>);

    { Writer for @link(ShowLabels).
      @param(AValue @true to label places.) }
    procedure SetShowLabels(AValue: Boolean);

    { Reader for @link(ShownPatches). @returns(Patches on show.) }
    function GetShownPatches: Integer;
  protected
    { Keeps the instruments in place when the view changes size. }
    procedure Resize; override;

    { Takes the keyboard and starts looking round with the left button.
      @param(Button The button.)
      @param(Shift The keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Turns and tilts while dragging: across turns, up and down tilts.
      @param(Shift The keys and buttons held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;

    { Stops looking round.
      @param(Button The button.)
      @param(Shift The keys held.)
      @param(X Horizontal position.)
      @param(Y Vertical position.) }
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;

    { Climbs (rolling away) or descends.
      @param(Shift The keys held.)
      @param(WheelDelta 120 a notch.)
      @param(Handled Set to @true.) }
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;

    { Starts the flight again. }
    procedure DblClick; override;

    { Holds a flight control down, or stops (Space) or starts again (R).
      @param(Key The key's code; set to 0 when used.)
      @param(KeyChar The character typed; set to #0 when used.)
      @param(Shift The keys held.) }
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;

    { Lets a flight control go.
      @param(Key The key's code; set to 0 when used.)
      @param(KeyChar The character typed; set to #0 when used.)
      @param(Shift The keys held.) }
    procedure KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;

    { Lets every flight control go when the keyboard goes elsewhere, since
      the keys' release would not arrive here. }
    procedure DoExit; override;
  public
    { Makes the viewport, camera, light, material, flight and
      instruments; nothing is shown yet.
      @param(AOwner The owner.) }
    constructor Create(AOwner: TComponent); override;

    { Stops the timer and frees every mesh and the flight. }
    destructor Destroy; override;

    { Shows the ground round a tile.
      @param(ASouth The latitude of the tile's south edge.)
      @param(AWest The longitude of its west edge.)
      @param(AResetView @true to start the flight again over the tile;
        @false to keep flying where it is.)
      @raises(ETerrainError if @link(TileLookup) is not set.) }
    procedure ShowArea(ASouth, AWest: Integer; AResetView: Boolean);

    { Starts the flight again: hovering, facing north,
      @link(StartHeight) above the middle of the tile asked for. }
    procedure ResetView;

    { Where the flight is and how it is going now.
      @returns(The state, for a bookmark.) }
    function FlightState: TTerrainFlightState;

    { Puts the flight exactly in a state, measuring the view again from
      there if it is far from where it is measured from now. Call after
      @link(ShowArea), with a tile near the state's place.
      @param(AState The state, from a bookmark.)
      @param(AAboveGround @true if the state's altitude is a height above
        the ground there, which the flight lifts to once that ground is
        known.) }
    procedure JumpTo(const AState: TTerrainFlightState; AAboveGround: Boolean = False);

    { Starts the flight again looking at a place: a little south of it,
      facing north, @link(StartHeight) above the ground there, tilted so
      the place is in the middle of the view. Call after @link(ShowArea).
      @param(ALatitude The place's latitude.)
      @param(ALongitude Its longitude.) }
    procedure StartLookingAt(ALatitude, ALongitude: Double);

    { Starts the flight again looking at a place from a heading, height
      and tilt, as a bookmark keeps them: back from it along the heading,
      facing it, tilted so it is in the middle of the view once the ground
      is known; hovering. Call after @link(ShowArea).
      @param(ALatitude The place's latitude.)
      @param(ALongitude Its longitude.)
      @param(AHeading The way to face, degrees from north.)
      @param(AHeight The height, metres.)
      @param(AAboveGround @true if above the ground; @false if above the
        sea.)
      @param(ATilt The camera's tilt below the level, degrees.) }
    procedure StartLookingAlong(ALatitude, ALongitude, AHeading, AHeight: Double;
      AAboveGround: Boolean; ATilt: Double);

    { Says a tile has been downloaded since it was drawn flat: its
      patches are made again from its heights.
      @param(ASouth The tile's south edge.)
      @param(AWest Its west edge.) }
    procedure TileDownloaded(ASouth, AWest: Integer);

    { @true once a tile has been shown and every patch wanted, and with
      @link(Realistic) on every texture, has been made.
      @returns(@true if settled.) }
    function Settled: Boolean;

    { How far the work since the last change has got, for a progress bar.
      @param(ADone Patches and textures made.)
      @param(ATotal Those made and those still to come.)
      @param(AText A line saying so.) }
    procedure WorkProgress(out ADone, ATotal: Integer; out AText: string);

    { Says what each tile holds; set before @link(ShowArea). Called on the
      main thread. }
    property TileLookup: TTerrainTileLookup read FTileLookup write FTileLookup;

    { Times to stretch heights; 1 is true scale. Setting it makes every
      patch again. }
    property Exaggeration: Single read FExaggeration write SetExaggeration;

    { The most samples across a tile used near the camera, from
      @code(TERRAIN_DETAILS). }
    property MaxDetail: Integer read FMaxDetail write SetMaxDetail;

    { The distance detail, in tenths, from @code(TERRAIN_RANGES). }
    property Range: Integer read FRange write SetRange;

    { How far above the ground the flight starts, metres; used from the
      next start. }
    property StartHeight: Integer read FStartHeight write SetStartHeight;

    { Makes the imagery for @link(Realistic); not owned. Set it to @nil
      before freeing it. }
    property Imagery: TImageryService read FImagery write SetImagery;

    { @true to draw satellite imagery from @link(Imagery) instead of
      height colours. }
    property Realistic: Boolean read FRealistic write SetRealistic;

    { @true once a tile has been shown. }
    property HasTerrain: Boolean read FHasArea;

    { Patches on show. }
    property ShownPatches: Integer read GetShownPatches;

    { Says what a round of work did, once every patch wanted has been
      made: patches, triangles, tiles and times. }
    property OnSettled: TTerrainReportEvent read FOnSettled write FOnSettled;

    { Reports problems, changes of frame, of display and crashes. }
    property OnLog: TTerrainReportEvent read FOnLog write FOnLog;

    { @true while the flight is paused: it does not move, the movement keys
      and the wheel do nothing, and looking round still works. }
    property Paused: Boolean read FPaused write SetPaused;

    { @true to hide the view behind a plain cover saying it is being got
      ready, while it goes on working underneath, so a new place and its
      imagery are not seen coming in. }
    property Covered: Boolean read GetCovered write SetCovered;

    { The flight's speed, metres a second; setting it changes it at once. }
    property FlightSpeed: Double write SetFlightSpeed;

    { How far the current flight has gone, kilometres, shown on the speed
      panel; less than 0 hides it. Set by whoever records the flight. }
    property FlownKm: Double write SetFlownKm;

    { @true while the controls panel shows only its title. }
    property ControlsCollapsed: Boolean read GetControlsCollapsed write SetControlsCollapsed;

    { Told when B is pressed, to make a bookmark; called after the key's
      handling, so it may open a modal dialog. }
    property OnBookmark: TNotifyEvent read FOnBookmark write FOnBookmark;

    { Told when the controls panel is opened or closed with the mouse, to
      remember it. }
    property OnControlsToggle: TNotifyEvent read FOnControlsToggle write FOnControlsToggle;

    { The named places to label: towns and cities, mountains, markers. }
    property PlaceLabels: TArray<TTerrainPlaceLabel> read FPlaceLabels write SetPlaceLabels;

    { @true to label the places near the flight. }
    property ShowLabels: Boolean read FShowLabels write SetShowLabels;

    { @true to keep the flight clear of the ground: at least
      @code(AUTOPILOT_CLEARANCE) (50 m) above it, climbing ahead of time
      for higher ground on the way. }
    property Autopilot: Boolean read GetAutopilot write SetAutopilot;

    { With @link(Autopilot) on, @true to hug the ground: 25 to 75 m above
      it, aiming at 50 m; the height keys and the wheel then do nothing. }
    property GroundHug: Boolean read GetGroundHug write SetGroundHug;

    { Told when L turns the place names on or off, to remember it. }
    property OnLabelsToggle: TNotifyEvent read FOnLabelsToggle write FOnLabelsToggle;

    { Told whenever the instruments are updated, as the flight moves or
      the ground under it sharpens; @link(FlightState) says where it is. }
    property OnFlightMoved: TNotifyEvent read FOnFlightMoved write FOnFlightMoved;

    { Told when the flight crashes into the ground; @link(FlightState) says
      where. }
    property OnCrash: TNotifyEvent read FOnCrash write FOnCrash;

    { Told when the user starts the flight again (R or a double-click),
      after it has been put back over the tile. }
    property OnRestart: TNotifyEvent read FOnRestart write FOnRestart;
  end;

implementation

uses
  // Gorilla.DefTypes declares enumeration values with common names (such as
  // Default), so it comes before System.Math, whose names then win; and
  // Default() is not used in this unit
  Gorilla.DefTypes,
  // For FMX's vertex and index buffer setters to be expanded inline
  System.RTLConsts,
  System.Math, System.TypInfo, System.Generics.Defaults, FMX.Forms, GDEMDisplays,
  GDEMTiles;

const
  { The viewport's background, a dark blue-grey that reads as sky. }
  TERRAIN_BACKGROUND = $FF1B2230;
  { The camera's field of view, in degrees. }
  TERRAIN_FOV = 45;
  { The nearest the view draws, kilometres: 50 m, when high up. }
  NEAR_PLANE_KM = 0.05;
  { The nearest the view draws when low down, kilometres: 5 m. }
  MIN_NEAR_PLANE_KM = 0.005;
  { The nearest the view draws is this share of the height above the
    ground, between @link(MIN_NEAR_PLANE_KM) and @link(NEAR_PLANE_KM), so
    the ground below is not cut away when flying low. }
  NEAR_PLANE_SHARE = 0.25;
  { The farthest the view draws, kilometres. }
  FAR_PLANE_KM = 3000;
  { How far ahead of the camera the point it looks at is, kilometres;
    typed, as @code(TPoint3D) multiplies by Single. }
  LOOK_AHEAD_KM: Single = 1;
  { Degrees turned for each pixel dragged across. }
  DRAG_TURN = 0.25;
  { Degrees tilted for each pixel dragged up or down. }
  DRAG_TILT = 0.2;
  { The view is treated as this much wider and taller than it is when
    deciding what is in view, so nothing at its edges is missed. }
  VIEW_MARGIN = 1.1;
  { Ticks of the timer, milliseconds. }
  TICK_MS = 15;
  { The instruments' distance from the view's edges, pixels. }
  HUD_MARGIN = 12;
  { The gap between instruments, pixels. }
  HUD_GAP = 6;
  { How often the frame rate is read and the display checked,
    milliseconds. }
  FPS_REFRESH_MS = 250;
  { The frames a second drawn when the display does not say how fast it
    refreshes, as on Linux. }
  DEFAULT_FRAME_RATE = 60;
  { Refresh rates below this are not believed. }
  MIN_FRAME_RATE = 24;
  { The credit line's height, pixels. }
  CREDIT_HEIGHT = 20;

{ The parts a vertex format holds, for the log.
  @param(AFormat The format.)
  @returns(Such as @code(Vertex Normal Color0 TexCoord0).) }
function VertexFormatText(const AFormat: TVertexFormats): string;
var
  LPart: TVertexFormat;
begin
  Result := '';
  for LPart := Low(TVertexFormat) to High(TVertexFormat) do
    if LPart in AFormat then
      Result := Result + ' ' + GetEnumName(TypeInfo(TVertexFormat), Ord(LPart));
  Result := Result.Trim;
end;

{ TTerrainView }

constructor TTerrainView.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited Create(AOwner);
  // The layout takes the mouse and the keys; the viewport lets them through
  HitTest := True;
  CanFocus := True;
  FExaggeration := DEFAULT_TERRAIN_HEIGHTS;
  FMaxDetail := DEFAULT_TERRAIN_DETAIL;
  FRange := DEFAULT_TERRAIN_RANGE;
  FStartHeight := DEFAULT_FLIGHT_START_HEIGHT;
  FFlight := TFlight.Create(FlightGround);
  FFlight.StartHeight := FStartHeight;
  FFlight.LookStretch := FExaggeration;
  FMeshes := TDictionary<Int64, TTerrainPatchMesh>.Create;
  FTexCoords := ImageryPatchTexCoords;

  FViewport := TGorillaViewport.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := TAlignLayout.Client;
  FViewport.HitTest := False;
  FViewport.UseFixedFrameRate := True;
  FViewport.FixedFrameRate := DEFAULT_FRAME_RATE;
  FViewport.VSync := False;
  FViewport.Color := TERRAIN_BACKGROUND;
  FViewport.UsingDesignCamera := False;
  // The scene is in kilometres: from 50 m to beyond the farthest tile
  FNearPlane := NEAR_PLANE_KM;
  FViewport.NearPlane := FNearPlane;
  FViewport.FarPlane := FAR_PLANE_KM;

  // The place names, made before the instruments so they are drawn under
  // them
  FLabelLayer := TTerrainLabelLayer.Create(Self);
  FLabelLayer.Parent := Self;
  FShowLabels := True;

  FCentre := TDummy.Create(Self);
  FCentre.Parent := FViewport;

  FTerrain := TDummy.Create(Self);
  FTerrain.Parent := FViewport;

  FCamera := TGorillaCamera.Create(Self);
  FCamera.Parent := FViewport;
  FCamera.FOV := TERRAIN_FOV;
  FCamera.Target := FCentre;
  FViewport.Camera := FCamera;

  // As in Sprite3D, the light rides on the camera, lighting whatever side
  // is in view
  FLight := TGorillaLight.Create(Self);
  FLight.Parent := FCamera;
  FLight.Position.Point := TPoint3D.Zero;
  FLight.LightType := TLightType.Point;

  // One material for every patch
  FMaterial := TGorillaVertexColorMaterialSource.Create(Self);
  FMaterial.Parent := FViewport;

  FIndices := TerrainPatchIndices;
  SetLength(FIndices16, Length(FIndices));
  SetLength(FIndices32, Length(FIndices));
  for I := 0 to High(FIndices) do
  begin
    FIndices16[I] := FIndices[I];
    FIndices32[I] := FIndices[I];
  end;

  // The instruments, made after the viewport so they are drawn over it
  FAltimeter := TTerrainAltimeter.Create(Self);
  FAltimeter.Parent := Self;
  FFrameRate := TTerrainFrameRate.Create(Self);
  FFrameRate.Parent := Self;
  FSpeedPanel := TTerrainSpeedPanel.Create(Self);
  FSpeedPanel.Parent := Self;
  FCompass := TTerrainCompass.Create(Self);
  FCompass.Parent := Self;
  FBanner := TTerrainBanner.Create(Self);
  FBanner.Parent := Self;
  FCredit := TTerrainCredit.Create(Self);
  FCredit.Parent := Self;
  FPauseBanner := TTerrainBanner.Create(Self);
  FPauseBanner.Parent := Self;
  FPauseBanner.Colour := BANNER_NOTE;
  FControls := TTerrainControls.Create(Self);
  FControls.Parent := Self;
  FControls.OnToggle := ControlsToggled;
  // Last, so it is over everything
  FCover := TTerrainCover.Create(Self);
  FCover.Parent := Self;
  FCover.Colour := TERRAIN_BACKGROUND;
  FCover.Text := 'Preparing for flight...';
  PlaceInstruments;
  FRateWatch := TStopwatch.StartNew;
  FFlightWatch := TStopwatch.StartNew;
  FImagerySweep := TStopwatch.StartNew;
  FImageryLook := TStopwatch.StartNew;
  FImageryAhead := TStopwatch.StartNew;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := TICK_MS;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
end;

destructor TTerrainView.Destroy;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  // The meshes go with the tree, before the material they use
  FImagery := nil;
  FreeAndNil(FLod);
  FreeAndNil(FMeshes);
  FreeAndNil(FFlight);
  inherited;
end;

function TTerrainView.FlightGround(ALatitude, ALongitude: Double; out AMetres: Double): Boolean;
begin
  AMetres := 0;
  Result := (FLod <> nil) and FLod.GroundHeight(ALatitude, ALongitude, AMetres);
end;

procedure TTerrainView.PlaceCamera;
var
  LPosition, LEast, LNorth, LUp, LAhead, LLook: TPoint3D;
  LSinHeading, LCosHeading, LSinTilt, LCosTilt, LGround: Double;
  LNear, LSH, LCH, LST, LCT: Single;
begin
  if (FLod = nil) or not FLod.Started then
  begin
    UpdateInstruments;
    Exit;
  end;
  // Heights are drawn stretched, so the flight is too, keeping its height
  // above the ground as drawn
  LPosition := FLod.Frame.ToLocal(FFlight.Latitude, FFlight.Longitude,
    FFlight.Altitude * FExaggeration / 1000);
  // Its own east, north and up, which turn from the frame's away from the
  // frame's point; east x north is up (-Y at the frame's point)
  FLod.Frame.Directions(FFlight.Latitude, FFlight.Longitude, LEast, LNorth);
  LUp := LEast.CrossProduct(LNorth);
  SinCos(DegToRad(FFlight.Heading), LSinHeading, LCosHeading);
  SinCos(DegToRad(FFlight.Tilt), LSinTilt, LCosTilt);
  // TPoint3D multiplies by Single
  LSH := LSinHeading;
  LCH := LCosHeading;
  LST := LSinTilt;
  LCT := LCosTilt;
  LAhead := LEast * LSH + LNorth * LCH;
  LLook := LAhead * LCT - LUp * LST;
  FCamera.Position.Point := LPosition;
  FCentre.Position.Point := LPosition + LLook * LOOK_AHEAD_KM;

  // The nearest the view draws follows the flight down, so low over the
  // ground it is not cut away; high up it stays at 50 m
  if FLod.GroundHeight(FFlight.Latitude, FFlight.Longitude, LGround) then
    LNear := EnsureRange(NEAR_PLANE_SHARE * (FFlight.Altitude - LGround) * FExaggeration / 1000,
      MIN_NEAR_PLANE_KM, NEAR_PLANE_KM)
  else
    LNear := NEAR_PLANE_KM;
  if Abs(LNear - FNearPlane) > 0.1 * FNearPlane then
  begin
    FNearPlane := LNear;
    FViewport.NearPlane := FNearPlane;
  end;

  FCameraMoved := True;
  UpdateInstruments;
  UpdateLabels;
end;

procedure TTerrainView.UpdateInstruments;
var
  LGround: Double;
begin
  if (FAltimeter = nil) or (FFrameRate = nil) or (FSpeedPanel = nil) or (FCompass = nil) then
    Exit;
  if (FLod = nil) or not FLod.Started then
  begin
    FAltimeter.AltitudeKnown := False;
    FAltimeter.Known := False;
    FCompass.Known := False;
    Exit;
  end;
  FAltimeter.Exaggeration := FExaggeration;
  FAltimeter.Altitude := FFlight.Altitude;
  FAltimeter.AltitudeKnown := True;
  if FLod.GroundHeight(FFlight.Latitude, FFlight.Longitude, LGround) then
  begin
    FAltimeter.Ground := LGround;
    FAltimeter.AboveGround := FFlight.Altitude - LGround;
    FAltimeter.Known := True;
  end
  else
    FAltimeter.Known := False;
  FCompass.Heading := FFlight.Heading;
  FCompass.Known := True;
  FSpeedPanel.Speed := FFlight.Speed;
  FSpeedPanel.Tilt := FFlight.Tilt;
  UpdateAutopilotText;
  if Assigned(FOnFlightMoved) then
    FOnFlightMoved(Self);
end;

procedure TTerrainView.PlaceInstruments;
var
  LTop: Single;
begin
  if (FAltimeter = nil) or (FFrameRate = nil) or (FSpeedPanel = nil) or (FCompass = nil) or
     (FBanner = nil) or (FCredit = nil) or (FPauseBanner = nil) or (FControls = nil) then
    Exit;
  LTop := HUD_MARGIN;
  FAltimeter.Position.Point := PointF(HUD_MARGIN, LTop);
  LTop := LTop + ALTIMETER_HEIGHT + HUD_GAP;
  FSpeedPanel.Position.Point := PointF(HUD_MARGIN, LTop);
  LTop := LTop + SPEED_PANEL_HEIGHT + HUD_GAP;
  FFrameRate.Position.Point := PointF(HUD_MARGIN, LTop);
  FCompass.Position.Point := PointF(Max(Width - HUD_MARGIN - COMPASS_SIZE,
    HUD_MARGIN + ALTIMETER_WIDTH + HUD_GAP), HUD_MARGIN);
  FBanner.Position.Point := PointF(Max((Width - BANNER_WIDTH) / 2, 0),
    Max(Height * 0.35 - BANNER_HEIGHT / 2, 0));
  FCredit.SetBounds(HUD_MARGIN, Max(Height - HUD_MARGIN - CREDIT_HEIGHT, 0),
    Max(Width - 2 * HUD_MARGIN, 0), CREDIT_HEIGHT);
  FPauseBanner.Position.Point := PointF(Max((Width - BANNER_WIDTH) / 2, 0),
    Max(Height * 0.35 + BANNER_HEIGHT / 2 + HUD_GAP, 0));
  if FLabelLayer <> nil then
    FLabelLayer.SetBounds(0, 0, Width, Height);
  if FCover <> nil then
    FCover.SetBounds(0, 0, Width, Height);
  // Kept to the bottom edge, whether open or collapsed
  FControls.Position.Point := PointF(HUD_MARGIN,
    Max(Height - HUD_MARGIN - FControls.PanelHeight, 0));
end;

procedure TTerrainView.Resize;
begin
  inherited;
  PlaceInstruments;
  // The view's shape has changed, so the labels' places on the screen and
  // the patches in view have too, even when hovering or paused, when the
  // camera does not move; the next tick looks again with the viewport at
  // its new size
  FCameraMoved := True;
  UpdateLabels;
end;

procedure TTerrainView.CheckFrameRate;
var
  LForm: TCommonCustomForm;
  LDisplay: TFormDisplay;
  LRate: Integer;
begin
  // Gorilla3D's own count: with a fixed frame rate, the frames drawn in
  // the last second
  FFrameRate.FramesPerSecond := FViewport.FPS;
  FFrameRate.Known := True;

  // Which display the window is on: naming it is quick, its refresh rate
  // is read only when it changes
  if (Root = nil) or not (Root.GetObject is TCommonCustomForm) then
    Exit;
  LForm := TCommonCustomForm(Root.GetObject);
  LDisplay := DisplayOfForm(LForm, False);
  if (LDisplay.Name = '') or (LDisplay.Name = FDisplayName) then
    Exit;
  FDisplayName := LDisplay.Name;
  LDisplay := DisplayOfForm(LForm, True);
  LRate := LDisplay.RefreshRate;
  if LRate >= MIN_FRAME_RATE then
    FViewport.FixedFrameRate := LRate
  else
    FViewport.FixedFrameRate := DEFAULT_FRAME_RATE;
  FFrameRate.Limit := Round(FViewport.FixedFrameRate);
  if Assigned(FOnLog) then
  begin
    if LRate >= MIN_FRAME_RATE then
      FOnLog(Self, Format('3D: the window is on %s, which refreshes at %d Hz, so the view is ' +
        'drawn at up to %d frames a second', [FDisplayName, LRate, LRate]))
    else
      FOnLog(Self, Format('3D: the window is on %s, which does not say how fast it refreshes, ' +
        'so the view is drawn at up to %d frames a second', [FDisplayName, DEFAULT_FRAME_RATE]));
  end;
end;

function TTerrainView.MakeEye: TTerrainEye;
var
  LHeight: Single;
begin
  Result.Position := FCamera.Position.Point;
  Result.Target := FCentre.Position.Point;
  Result.Forward := (Result.Target - Result.Position).Normalize;
  // Up is -Y
  Result.Right := Point3D(0, -1, 0).CrossProduct(Result.Forward).Normalize;
  Result.Up := Result.Forward.CrossProduct(Result.Right);
  LHeight := Max(FViewport.Height, 1);
  Result.TanY := Tan(DegToRad(TERRAIN_FOV / 2)) * VIEW_MARGIN;
  Result.TanX := Result.TanY * Max(FViewport.Width, 1) / LHeight;
end;

procedure TTerrainView.ResetView;
var
  LStart: TPoint3D;
begin
  FBanner.Visible := False;
  FHeld := [];
  if not FHasArea then
    Exit;
  FFlight.StartHeight := FStartHeight;
  FFlight.Start(FAreaSouth + 0.5, FAreaWest + 0.5);
  // Measured again from the tile asked for if the flight had gone far
  if FLod <> nil then
  begin
    LStart := FLod.Frame.ToLocal(FFlight.Latitude, FFlight.Longitude, 0);
    if FLod.NeedsRebase(LStart.X, LStart.Z) then
    begin
      FLod.Start(FAreaSouth, FAreaWest);
      BeginWork;
    end;
  end;
  PlaceCamera;
end;

procedure TTerrainView.BeginWork;
begin
  FBusyWatch := TStopwatch.StartNew;
  FUploadMs := 0;
  FUploads := 0;
  FTextures := 0;
  FTextureMs := 0;
  FTilesDownloaded := 0;
  FTextureFailures := 0;
  if FLod <> nil then
    FLod.ResetCounts;
  FWasBusy := True;
end;

procedure TTerrainView.ShowArea(ASouth, AWest: Integer; AResetView: Boolean);
begin
  if not Assigned(FTileLookup) then
    raise ETerrainError.Create('The 3D view was not told where to find tiles');
  if FLod = nil then
  begin
    FLod := TTerrainLod.Create(FTileLookup);
    FLod.OnShowMesh := ShowMesh;
    FLod.OnReleaseMesh := ReleaseMesh;
    FLod.OnMeshReady := MeshReady;
    FLod.OnLog := LodLog;
  end;
  FLod.MaxDepth := TerrainMaxDepth(FMaxDetail);
  FLod.Range := FRange / 10;
  FLod.Exaggeration := FExaggeration;
  FAreaSouth := ASouth;
  FAreaWest := AWest;
  if AResetView or not FHasArea then
  begin
    FLod.Start(ASouth, AWest);
    FHasArea := True;
    FFlight.StartHeight := FStartHeight;
    FFlight.Start(ASouth + 0.5, AWest + 0.5);
    FBanner.Visible := False;
  end
  else
    // Flying on from where it is, measured from the tile under it
    FLod.Start(Floor(FFlight.Latitude), Floor(FFlight.Longitude));
  FHeld := [];
  PlaceCamera;
  BeginWork;
  FLod.Update(MakeEye);
  FCameraMoved := False;
  FFlightWatch := TStopwatch.StartNew;
  FTimer.Enabled := True;
end;

procedure TTerrainView.Rebase;
begin
  FLod.Start(Floor(FFlight.Latitude), Floor(FFlight.Longitude));
  if Assigned(FOnLog) then
    FOnLog(Self, Format('3D: the flight went more than %d km, so the view is measured again ' +
      'from %.4f, %.4f', [TERRAIN_REBASE_KM, FFlight.Latitude, FFlight.Longitude]));
  BeginWork;
  PlaceCamera;
end;

procedure TTerrainView.ReportCrash(ASpeed: Double);
var
  LWhere: string;
begin
  FHeld := [];
  LWhere := Format('%.4f, %.4f', [FFlight.Latitude, FFlight.Longitude]);
  FBanner.ShowText('Crashed',
    Format('Into the ground at %s, %s km/h. Press R to start again.',
      [FormatHudHeight(FFlight.Altitude), FormatFloat('#,##0', ASpeed * 3.6)]));
  PlaceInstruments;
  if Assigned(FOnLog) then
    FOnLog(Self, Format('3D: crashed into the ground at %s (ground %s), heading %.0f, ' +
      '%s km/h', [LWhere, FormatHudHeight(FFlight.Altitude), FFlight.Heading,
       FormatFloat('#,##0', ASpeed * 3.6)]));
  if Assigned(FOnCrash) then
    FOnCrash(Self);
end;

procedure TTerrainView.TimerTick(Sender: TObject);
var
  LWatch: TStopwatch;
  LNode: TTerrainNode;
  LPatch: TTerrainPatch;
  LMesh: TObject;
  LChanged, LBusy, LWasCrashed: Boolean;
  LSeconds, LSpeed: Double;
  LReport, LCopy, LMessage: string;
  LImagery: TImageryResult;
begin
  if (FLod = nil) or not FLod.Started then
    Exit;
  try
    if FRateWatch.ElapsedMilliseconds >= FPS_REFRESH_MS then
    begin
      FRateWatch := TStopwatch.StartNew;
      CheckFrameRate;
    end;

    // The flight moves on by the time gone, whatever the frame rate
    LSeconds := FFlightWatch.Elapsed.TotalSeconds;
    FFlightWatch := TStopwatch.StartNew;
    LWasCrashed := FFlight.Crashed;
    LSpeed := FFlight.Speed;
    if not FPaused and FFlight.Step(FHeld, LSeconds) then
      PlaceCamera;
    // Also when hovering, when the camera does not move
    UpdateAutopilotText;
    if FFlight.Crashed and not LWasCrashed then
      ReportCrash(LSpeed);

    if FLod.NeedsRebase(FCamera.Position.X, FCamera.Position.Z) then
      Rebase;

    LChanged := FCameraMoved;
    LWatch := TStopwatch.StartNew;
    while (LWatch.ElapsedMilliseconds < UPLOAD_BUDGET_MS) and FLod.TakeBuilt(LNode, LPatch) do
    begin
      try
        LMesh := MakeMesh(LPatch, LNode);
        FLod.Attach(LNode, LMesh, LPatch);
        Inc(FUploads);
      except
        on E: Exception do
          FLod.MarkFailed(LNode, E.ClassName + ': ' + E.Message);
      end;
      LChanged := True;
    end;
    if LChanged then
      FUploadMs := FUploadMs + LWatch.Elapsed.TotalMilliseconds;

    // Textures that have arrived, in what is left of the budget
    if FImagery <> nil then
    begin
      while (LWatch.ElapsedMilliseconds < UPLOAD_BUDGET_MS) and FImagery.Take(LImagery) do
        ApplyImagery(LImagery);
      while FImagery.TakeMessage(LMessage) do
        if Assigned(FOnLog) then
          FOnLog(Self, LMessage);
      if FImagerySweep.ElapsedMilliseconds >= IMAGERY_SWEEP_MS then
      begin
        FImagerySweep := TStopwatch.StartNew;
        SweepImagery;
      end;
      if FImageryAhead.ElapsedMilliseconds >= IMAGERY_AHEAD_MS then
      begin
        FImageryAhead := TStopwatch.StartNew;
        PrefetchImagery;
      end;
    end;

    // Imagery that arrived (or failed) may let a patch take over; while
    // patches wait for it, the tree looks again now and then, so one whose
    // wait has run out takes over
    if FImageryArrived then
    begin
      FImageryArrived := False;
      LChanged := True;
    end
    else if FRealistic and (FImagery <> nil) and (FImagery.Pending > 0) and
       (FImageryLook.ElapsedMilliseconds >= IMAGERY_LOOK_MS) then
      LChanged := True;
    if LChanged then
      FImageryLook := TStopwatch.StartNew;

    if LChanged then
    begin
      FCameraMoved := False;
      FLod.Update(MakeEye);
      // Finer heights under the flight change its height above them, and
      // under the places their poles
      UpdateInstruments;
      UpdateLabels;
    end;

    // Settled once the patches and, with Realistic on, their imagery are
    // all made
    LBusy := FLod.Busy or (FRealistic and (FImagery <> nil) and (FImagery.Pending > 0));
    if LBusy and not FWasBusy then
      BeginWork
    else if not LBusy and FWasBusy then
    begin
      FWasBusy := False;
      if Assigned(FOnSettled) then
      begin
        if FDirectCopy then
          LCopy := 'copied straight'
        else
          LCopy := 'through FMX''s setters';
        LReport := Format('3D: settled in %d ms: %d patches on show (%s triangles) of %d kept, ' +
          'over %d tiles (%d with heights); %d made by up to %d workers, %.1f ms each; ' +
          '%d meshes in %.0f ms, %.2f ms each (vertices %s)',
          [FBusyWatch.ElapsedMilliseconds, FLod.ShownCount,
           FormatFloat('#,##0', Int64(FLod.ShownCount) * PATCH_TRIANGLES), FLod.NodeCount,
           FLod.TileCount, FLod.LandTileCount, FLod.BuiltCount, FLod.MaxInFlight,
           FLod.BuildMilliseconds / Max(FLod.BuiltCount, 1), FUploads, FUploadMs,
           FUploadMs / Max(FUploads, 1),
           LCopy]);
        if FLod.FailedCount > 0 then
          LReport := LReport + Format('; %d could not be made', [FLod.FailedCount]);
        if FRealistic and (FImagery <> nil) then
          LReport := LReport + Format('; imagery: %d textures, %.0f ms each, %d tiles ' +
            'downloaded, %d still to come, %d could not be made; %d fetched ahead; EOX pace ' +
            '%.1f tiles a second, %d refused so far', [FTextures,
             FTextureMs / Max(FTextures, 1), FTilesDownloaded, FImagery.Pending,
             FTextureFailures, FImagery.Prefetched, FImagery.Rate, FImagery.Refusals]);
        FOnSettled(Self, LReport);
      end;
    end;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      if Assigned(FOnLog) then
        FOnLog(Self, 'WARNING: the 3D view stopped (' + E.ClassName + ': ' +
          E.Message.TrimRight(['.']) + ')');
    end;
  end;
end;

function TTerrainView.FillVertices(ABuffer: TVertexBuffer; const APatch: TTerrainPatch): Boolean;
const
  // A colour no patch has, to find where FMX keeps a vertex's colour
  SENTINEL: TAlphaColor = $A1B2C3D4;
  // Texture coordinates no patch has, to find where FMX keeps them: FMX
  // gives no pointer to them, as for colours
  TEX_SENTINEL_U: Single = 0.3721;
  TEX_SENTINEL_V: Single = 0.8913;
var
  LBase, LVertex: PByte;
  LSize, LVertexOffset, LNormalOffset, LColourOffset, LColourFOffset, LTexOffset, I: Integer;
  LPointsDirect, LHasTex: Boolean;
  LMarkF, LColourF: TAlphaColorF;

  { @true if four floats at an offset are, within rounding, a float
    colour.
    @param(AOffset The offset.)
    @param(AColour The colour.)
    @returns(@true if they match.) }
  function IsColourF(AOffset: Integer; const AColour: TAlphaColorF): Boolean;
  begin
    Result := (Abs(PSingle(LBase + AOffset)^ - AColour.R) < 1E-5) and
      (Abs(PSingle(LBase + AOffset + 4)^ - AColour.G) < 1E-5) and
      (Abs(PSingle(LBase + AOffset + 8)^ - AColour.B) < 1E-5) and
      (Abs(PSingle(LBase + AOffset + 12)^ - AColour.A) < 1E-5);
  end;

  { @true if some bytes at an offset would overlap a position or normal.
    @param(AOffset The offset.)
    @param(ALength How many bytes.)
    @returns(@true if they overlap.) }
  function OverlapsPoints(AOffset, ALength: Integer): Boolean;
  begin
    Result :=
      ((AOffset + ALength > LVertexOffset) and (AOffset < LVertexOffset + SizeOf(TPoint3D))) or
      ((AOffset + ALength > LNormalOffset) and (AOffset < LNormalOffset + SizeOf(TPoint3D)));
  end;

  { @true if a colour at an offset would overlap a position or normal.
    @param(AOffset The offset.)
    @returns(@true if it overlaps.) }
  function Overlaps(AOffset: Integer): Boolean;
  begin
    Result := OverlapsPoints(AOffset, SizeOf(TAlphaColor));
  end;

begin
  LBase := PByte(ABuffer.Buffer);
  LSize := ABuffer.VertexSize;
  // Where the first vertex's position and normal are, from FMX's own
  // pointers; where its colour is, by setting it and looking for it
  LVertexOffset := Integer(PByte(ABuffer.VerticesPtr[0]) - LBase);
  LNormalOffset := Integer(PByte(ABuffer.NormalsPtr[0]) - LBase);
  LPointsDirect := (LBase <> nil) and InRange(LVertexOffset, 0, LSize - SizeOf(TPoint3D)) and
    InRange(LNormalOffset, 0, LSize - SizeOf(TPoint3D));
  LColourOffset := -1;
  LColourFOffset := -1;
  // Texture coordinates, for imagery, where the buffer has room for them
  LHasTex := TVertexFormat.TexCoord0 in ABuffer.Format;
  LTexOffset := -1;
  if LHasTex and LPointsDirect then
  begin
    ABuffer.TexCoord0[0] := PointF(TEX_SENTINEL_U, TEX_SENTINEL_V);
    for I := 0 to LSize - SizeOf(TPointF) do
      if (PSingle(LBase + I)^ = TEX_SENTINEL_U) and (PSingle(LBase + I + SizeOf(Single))^ =
         TEX_SENTINEL_V) and not OverlapsPoints(I, SizeOf(TPointF)) then
      begin
        LTexOffset := I;
        Break;
      end;
  end;
  if not LHasTex and not FNoTexCoordsLogged then
  begin
    FNoTexCoordsLogged := True;
    if Assigned(FOnLog) then
      FOnLog(Self, 'WARNING: the patches'' meshes have no texture coordinates, so Realistic ' +
        'cannot show imagery');
  end;
  if LPointsDirect then
  begin
    ABuffer.Color0[0] := SENTINEL;
    for I := 0 to LSize - SizeOf(TAlphaColor) do
      if (PCardinal(LBase + I)^ = SENTINEL) and not Overlaps(I) and
         ((LTexOffset < 0) or (I + SizeOf(TAlphaColor) <= LTexOffset) or
          (I >= LTexOffset + SizeOf(TPointF))) then
      begin
        LColourOffset := I;
        Break;
      end;
    // Gorilla3D's meshes keep colour as four floats (ColorF0), which FMX's
    // Color0 setter fills; looked for as floats when not found as a
    // 4-byte colour
    if LColourOffset < 0 then
    begin
      LMarkF := TAlphaColorF.Create(SENTINEL);
      I := 0;
      while I <= LSize - SizeOf(TAlphaColorF) do
      begin
        if IsColourF(I, LMarkF) and not OverlapsPoints(I, SizeOf(TAlphaColorF)) and
           ((LTexOffset < 0) or (I + SizeOf(TAlphaColorF) <= LTexOffset) or
            (I >= LTexOffset + SizeOf(TPointF))) then
        begin
          LColourFOffset := I;
          Break;
        end;
        Inc(I, SizeOf(Single));
      end;
    end;
  end;

  if not FLayoutLogged and Assigned(FOnLog) then
  begin
    FLayoutLogged := True;
    FOnLog(Self, Format('3D: vertex layout: %d bytes a vertex, format %s; position at %d, ' +
      'normal at %d, colour at %d (4 bytes) or %d (4 floats), texture at %d (-1 not found)',
      [LSize, VertexFormatText(ABuffer.Format), LVertexOffset, LNormalOffset, LColourOffset,
       LColourFOffset, LTexOffset]));
  end;
  if LPointsDirect then
    for I := 0 to High(APatch.Positions) do
    begin
      LVertex := LBase + I * LSize;
      PPoint3D(LVertex + LVertexOffset)^ := APatch.Positions[I];
      PPoint3D(LVertex + LNormalOffset)^ := APatch.Normals[I];
      if LColourOffset >= 0 then
        PAlphaColor(LVertex + LColourOffset)^ := APatch.Colours[I]
      else if LColourFOffset >= 0 then
      begin
        LColourF := TAlphaColorF.Create(APatch.Colours[I]);
        System.Move(LColourF, (LVertex + LColourFOffset)^, SizeOf(TAlphaColorF));
      end
      else
        ABuffer.Color0[I] := APatch.Colours[I];
      if LTexOffset >= 0 then
        PPointF(LVertex + LTexOffset)^ := FTexCoords[I]
      else if LHasTex then
        ABuffer.TexCoord0[I] := FTexCoords[I];
    end
  else
    for I := 0 to High(APatch.Positions) do
    begin
      ABuffer.Vertices[I] := APatch.Positions[I];
      ABuffer.Normals[I] := APatch.Normals[I];
      ABuffer.Color0[I] := APatch.Colours[I];
      if LHasTex then
        ABuffer.TexCoord0[I] := FTexCoords[I];
    end;
  Result := LPointsDirect and ((LColourOffset >= 0) or (LColourFOffset >= 0)) and
    (not LHasTex or (LTexOffset >= 0));
end;

procedure TTerrainView.FillIndices(ABuffer: TIndexBuffer);
var
  LBase: PByte;
  I, LCount: Integer;
begin
  LCount := Length(FIndices);
  ABuffer.Length := LCount;
  // Which size FMX gave the indices: 16 bits puts the second at byte 2
  ABuffer.Indices[0] := 1;
  ABuffer.Indices[1] := 2;
  LBase := PByte(ABuffer.Buffer);
  if (LBase <> nil) and (PWord(LBase + 2)^ = 2) then
    System.Move(FIndices16[0], LBase^, LCount * SizeOf(Word))
  else if (LBase <> nil) and (PCardinal(LBase + 4)^ = 2) then
    System.Move(FIndices32[0], LBase^, LCount * SizeOf(Cardinal))
  else
    for I := 0 to LCount - 1 do
      ABuffer.Indices[I] := FIndices[I];
end;

function TTerrainView.MakeMesh(const APatch: TTerrainPatch; ANode: TTerrainNode): TObject;
var
  LMesh: TTerrainPatchMesh;
  LData: TMeshData;
  LDef: TMeshDef;
begin
  LMesh := TTerrainPatchMesh.Create(nil);
  try
    // Where the patch is, for its imagery
    LMesh.Size := NODE_ARCSEC[ANode.Depth] / TILE_ARCSEC;
    LMesh.North := ANode.Root.South + 1 - ANode.Y * LMesh.Size;
    LMesh.West := ANode.Root.West + ANode.X * LMesh.Size;
    LMesh.Visible := False;
    LMesh.Parent := FTerrain;
    LData := LMesh.MeshData;
    if LData = nil then
      raise ETerrainError.Create('Gorilla3D gave a patch no mesh data to fill');
    LData.VertexBuffer.Length := Length(APatch.Positions);
    FDirectCopy := FillVertices(LData.VertexBuffer, APatch);
    FillIndices(LData.IndexBuffer);

    // Made static, the data goes to the GPU once and stays there; the mesh
    // frees its definition with it
    LDef := TMeshDef.Create(nil);
    LMesh.IsDefOwner := True;
    LMesh.Def := LDef;
    LDef.ApplyFromMeshData(LData);
    LDef.IsStatic := True;
    LData.Clear;
    LMesh.MaterialSource := FMaterial;
  except
    LMesh.Free;
    raise;
  end;
  Inc(FNextImageryId);
  LMesh.ImageryId := FNextImageryId;
  FMeshes.Add(LMesh.ImageryId, LMesh);
  // Made hidden: its imagery is asked for when the tree shows it
  Result := LMesh;
end;

procedure TTerrainView.ShowMesh(AMesh: TObject; AVisible: Boolean);
var
  LMesh: TTerrainPatchMesh;
begin
  TControl3D(AMesh).Visible := AVisible;
  if not (AMesh is TTerrainPatchMesh) then
    Exit;
  LMesh := TTerrainPatchMesh(AMesh);
  // A patch hidden keeps its texture, and its request, for when it is
  // shown again; it is cancelled only when the patch is freed
  if AVisible and FRealistic then
    RequestImagery(LMesh);
end;

function TTerrainView.MeshReady(AMesh: TObject): Boolean;
var
  LMesh: TTerrainPatchMesh;
begin
  Result := True;
  if not FRealistic or (FImagery = nil) or not (AMesh is TTerrainPatchMesh) then
    Exit;
  LMesh := TTerrainPatchMesh(AMesh);
  if (LMesh.Imagery <> nil) or (LMesh.ImageryFailedAt <> 0) then
    Exit;
  // Asked for now, while it waits to be shown
  RequestImagery(LMesh);
  Result := not LMesh.ImageryAsked or
    (TThread.GetTickCount64 - LMesh.ImageryAskedAt >= IMAGERY_WAIT_MS);
end;

procedure TTerrainView.ReleaseMesh(AMesh: TObject);
var
  LMesh: TTerrainPatchMesh;
begin
  if AMesh is TTerrainPatchMesh then
  begin
    LMesh := TTerrainPatchMesh(AMesh);
    if FMeshes <> nil then
      FMeshes.Remove(LMesh.ImageryId);
    if LMesh.ImageryAsked and (FImagery <> nil) then
      FImagery.Cancel(LMesh.ImageryId);
  end;
  // Its textured material, if any, goes with it
  AMesh.Free;
end;

procedure TTerrainView.RequestImagery(AMesh: TTerrainPatchMesh);
begin
  if (FImagery = nil) or (AMesh.Imagery <> nil) or AMesh.ImageryAsked then
    Exit;
  if (AMesh.ImageryFailedAt <> 0) and
     (TThread.GetTickCount64 - AMesh.ImageryFailedAt < IMAGERY_RETRY_MS) then
    Exit;
  AMesh.ImageryAsked := True;
  AMesh.ImageryAskedAt := TThread.GetTickCount64;
  FImagery.Request(AMesh.ImageryId, AMesh.North, AMesh.West, AMesh.Size);
end;

procedure TTerrainView.ApplyImagery(const AResult: TImageryResult);
var
  LMesh: TTerrainPatchMesh;
  LBitmap: TBitmap;
  LData: TBitmapData;
  LMaterial: TGorillaDefaultMaterialSource;
  X, Y: Integer;
begin
  if not FMeshes.TryGetValue(AResult.Id, LMesh) then
    Exit;
  LMesh.ImageryAsked := False;
  if not FRealistic then
    Exit;
  if Length(AResult.Pixels) <> IMAGERY_PIXELS * IMAGERY_PIXELS then
  begin
    // Its height colours stay, and it asks again later; the service has
    // logged why
    LMesh.ImageryFailedAt := TThread.GetTickCount64;
    if LMesh.ImageryFailedAt = 0 then
      LMesh.ImageryFailedAt := 1;
    FImageryArrived := True;
    Inc(FTextureFailures);
    Exit;
  end;
  LBitmap := TBitmap.Create(IMAGERY_PIXELS, IMAGERY_PIXELS);
  try
    if LBitmap.Map(TMapAccess.Write, LData) then
    try
      // TAlphaColor is BGRA in memory, so rows copy straight into a BGRA
      // bitmap; any other layout goes pixel by pixel
      if LData.PixelFormat = TPixelFormat.BGRA then
        for Y := 0 to IMAGERY_PIXELS - 1 do
          System.Move(AResult.Pixels[Y * IMAGERY_PIXELS], LData.GetScanline(Y)^,
            IMAGERY_PIXELS * SizeOf(TAlphaColor))
      else
        for Y := 0 to IMAGERY_PIXELS - 1 do
          for X := 0 to IMAGERY_PIXELS - 1 do
            LData.SetPixel(X, Y, AResult.Pixels[Y * IMAGERY_PIXELS + X]);
    finally
      LBitmap.Unmap(LData);
    end;
    // Its own material: Gorilla3D's materials take vertex colours or a
    // texture, not both. The imagery has the real light in it, so it is
    // drawn flat, unlit
    LMaterial := TGorillaDefaultMaterialSource.Create(LMesh);
    LMaterial.UseLighting := False;
    LMaterial.UseSpecular := False;
    LMaterial.UseTexturing := True;
    LMaterial.UseTexture0 := True;
    LMaterial.Texture.Assign(LBitmap);
    if LMesh.Imagery <> nil then
      LMesh.Imagery.Free;
    LMesh.Imagery := LMaterial;
    LMesh.MaterialSource := LMaterial;
  finally
    LBitmap.Free;
  end;
  FImageryArrived := True;
  Inc(FTextures);
  FTextureMs := FTextureMs + AResult.Milliseconds;
  Inc(FTilesDownloaded, AResult.Downloaded);
end;

procedure TTerrainView.DropImagery(AMesh: TTerrainPatchMesh);
begin
  AMesh.MaterialSource := FMaterial;
  FreeAndNil(AMesh.Imagery);
  AMesh.ImageryAsked := False;
  AMesh.ImageryFailedAt := 0;
end;

procedure TTerrainView.SweepImagery;
var
  LMesh: TTerrainPatchMesh;
begin
  if not FRealistic or (FImagery = nil) then
    Exit;
  for LMesh in FMeshes.Values do
    if LMesh.Visible then
      RequestImagery(LMesh);
end;

procedure TTerrainView.PrefetchImagery;
var
  LGround, LAbove, LAhead, LStep, LDistance, LTileKm, LLatitude, LLongitude, LSideLatitude,
    LSideLongitude: Double;
  LDepth, LZoom, LSide: Integer;
  LTiles: TArray<TImageryTileRef>;
begin
  if not FRealistic or (FImagery = nil) or FPaused or FFlight.Crashed or (FLod = nil) or
     not FLod.Started then
    Exit;
  // Hovering: the ground below is already asked for by its patches
  if FFlight.Speed < 1 then
  begin
    FImagery.ClearPrefetch;
    Exit;
  end;
  // The depth the tree draws straight below: the first it does not split,
  // the camera being no nearer than Range times its size (in the scene's
  // kilometres, stretched with the heights)
  if not FlightGround(FFlight.Latitude, FFlight.Longitude, LGround) then
    LGround := 0;
  LAbove := Max(FFlight.Altitude - LGround, 0) * FExaggeration / 1000;
  LDepth := 0;
  while (LDepth < FMaxDetail) and (LAbove < FLod.Range * NodeSizeKm(LDepth)) do
    Inc(LDepth);
  LZoom := ImageryZoomFor(NODE_ARCSEC[LDepth] / TILE_ARCSEC);
  // A tile's height north to south, and samples every half tile
  LTileKm := 180 / (1 shl LZoom) * KM_PER_DEGREE;
  LStep := LTileKm * 500;
  LAhead := Min(FFlight.Speed * IMAGERY_AHEAD_SECONDS, IMAGERY_AHEAD_KM * 1000);
  LTiles := nil;
  LDistance := LStep;
  while (LDistance <= LAhead) and (Length(LTiles) < IMAGERY_AHEAD_TILES) do
  begin
    DestinationPoint(FFlight.Latitude, FFlight.Longitude, FFlight.Heading, LDistance,
      LLatitude, LLongitude);
    LTiles := LTiles + [ImageryTileAt(LLatitude, LLongitude, LZoom)];
    // A tile to each side, as the view is wider than one tile
    for LSide := -1 to 1 do
      if LSide <> 0 then
      begin
        DestinationPoint(LLatitude, LLongitude, FFlight.Heading + 90 * LSide, LTileKm * 1000,
          LSideLatitude, LSideLongitude);
        LTiles := LTiles + [ImageryTileAt(LSideLatitude, LSideLongitude, LZoom)];
      end;
    LDistance := LDistance + LStep;
  end;
  // Samples half a tile apart find most tiles twice; the service leaves
  // out repeats and tiles it has
  FImagery.Prefetch(LTiles);
end;

procedure TTerrainView.TileDownloaded(ASouth, AWest: Integer);
begin
  if (FLod = nil) or not FLod.Started then
    Exit;
  if FLod.RefreshTile(ASouth, AWest) then
  begin
    LodLog(Format('3D: tile %s downloaded while flying; its ground is made again from its ' +
      'heights', [TileName(ASouth, AWest)]));
    // The next tick looks again and makes its patches
    FCameraMoved := True;
  end;
end;

procedure TTerrainView.SetRealistic(AValue: Boolean);
var
  LMesh: TTerrainPatchMesh;
begin
  if AValue = FRealistic then
    Exit;
  FRealistic := AValue;
  if FImagery <> nil then
  begin
    FImagery.CancelAll;
    FImagery.ClearPrefetch;
  end;
  for LMesh in FMeshes.Values do
  begin
    DropImagery(LMesh);
    if FRealistic and LMesh.Visible then
      RequestImagery(LMesh);
  end;
  FCredit.Visible := FRealistic and (FImagery <> nil);
  BeginWork;
end;

procedure TTerrainView.SetImagery(AValue: TImageryService);
var
  LMesh: TTerrainPatchMesh;
begin
  if AValue = FImagery then
    Exit;
  if FImagery <> nil then
    FImagery.CancelAll;
  FImagery := AValue;
  if FImagery <> nil then
    FCredit.Text := ImageryCredit(FImagery.Layer);
  if FMeshes <> nil then
    for LMesh in FMeshes.Values do
    begin
      LMesh.ImageryAsked := False;
      LMesh.ImageryFailedAt := 0;
      if FRealistic and LMesh.Visible then
        RequestImagery(LMesh);
    end;
  FCredit.Visible := FRealistic and (FImagery <> nil);
end;

procedure TTerrainView.LodLog(const AText: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, AText);
end;

procedure TTerrainView.SetExaggeration(AValue: Single);
begin
  AValue := Max(AValue, 0.1);
  if SameValue(AValue, FExaggeration) then
    Exit;
  FExaggeration := AValue;
  FFlight.LookStretch := AValue;
  if FLod <> nil then
  begin
    FLod.Exaggeration := AValue;
    BeginWork;
    PlaceCamera;
  end;
end;

procedure TTerrainView.SetStartHeight(AValue: Integer);
begin
  FStartHeight := Max(AValue, 0);
end;

procedure TTerrainView.SetMaxDetail(AValue: Integer);
begin
  FMaxDetail := AValue;
  if FLod <> nil then
  begin
    FLod.MaxDepth := TerrainMaxDepth(AValue);
    FCameraMoved := True;
  end;
end;

procedure TTerrainView.SetRange(AValue: Integer);
begin
  FRange := Max(AValue, 5);
  if FLod <> nil then
  begin
    FLod.Range := FRange / 10;
    FCameraMoved := True;
  end;
end;

function TTerrainView.GetShownPatches: Integer;
begin
  if FLod <> nil then
    Result := FLod.ShownCount
  else
    Result := 0;
end;

procedure TTerrainView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  // A click on the view gives it the keyboard, for flying
  SetFocus;
  if Button = TMouseButton.mbLeft then
  begin
    FDragging := True;
    FDragLast := PointF(X, Y);
  end;
end;

procedure TTerrainView.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if not FDragging then
    Exit;
  // As looking round with the head: dragging right turns right, dragging
  // down looks further down
  FFlight.Look((X - FDragLast.X) * DRAG_TURN, (Y - FDragLast.Y) * DRAG_TILT);
  FDragLast := PointF(X, Y);
  PlaceCamera;
end;

procedure TTerrainView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FDragging := False;
end;

procedure TTerrainView.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  inherited;
  if not FPaused then
  begin
    FFlight.Climb(WheelDelta / 120);
    PlaceCamera;
  end;
  Handled := True;
end;

procedure TTerrainView.DblClick;
begin
  inherited;
  FDragging := False;
  ResetView;
  if Assigned(FOnRestart) then
    FOnRestart(Self);
end;

{ Which flight control a key is.
  @param(AKey The key's code; 0 for a character typed.)
  @param(AKeyChar The character typed.)
  @param(AControl The control.)
  @returns(@false if the key is not a flight control.) }
function KeyControl(AKey: Word; AKeyChar: WideChar; out AControl: TFlightControl): Boolean;
begin
  Result := True;
  case AKey of
    vkUp: AControl := fcFaster;
    vkDown: AControl := fcSlower;
    vkLeft: AControl := fcTurnLeft;
    vkRight: AControl := fcTurnRight;
    vkPrior: AControl := fcClimb;
    vkNext: AControl := fcDescend;
    vkQ: AControl := fcTiltUp;
    vkA: AControl := fcTiltDown;
  else
    // Some systems send letters only as characters
    case UpCase(AKeyChar) of
      'Q': AControl := fcTiltUp;
      'A': AControl := fcTiltDown;
    else
      Result := False;
    end;
  end;
end;

procedure TTerrainView.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  LControl: TFlightControl;
begin
  inherited;
  if KeyControl(Key, KeyChar, LControl) then
  begin
    // A crash or a pause holds the flight
    if not FFlight.Crashed and not FPaused then
      Include(FHeld, LControl);
  end
  else if (Key = vkSpace) or ((Key = 0) and (KeyChar = ' ')) then
  begin
    // Once a press: a held key repeats, and some systems also send it
    // as a character
    if not FSpaceDown then
      Paused := not FPaused;
    FSpaceDown := True;
  end
  else if (Key = vkB) or ((Key = 0) and (UpCase(KeyChar) = 'B')) then
  begin
    if not FBookmarkKeyDown then
      AskForBookmark;
    FBookmarkKeyDown := True;
  end
  else if (Key = vkL) or ((Key = 0) and (UpCase(KeyChar) = 'L')) then
  begin
    // Once a press, as for Space
    if not FLabelsKeyDown then
    begin
      ShowLabels := not FShowLabels;
      if Assigned(FOnLabelsToggle) then
        FOnLabelsToggle(Self);
    end;
    FLabelsKeyDown := True;
  end
  else if (Key = vkH) or ((Key = 0) and (UpCase(KeyChar) = 'H')) then
  begin
    FFlight.Stop;
    UpdateInstruments;
  end
  else if (Key = vkM) or ((Key = 0) and (UpCase(KeyChar) = 'M')) then
  begin
    // Up to the speed of sound over a few seconds; Up, Down or H take over
    if not FFlight.Crashed and not FPaused then
      FFlight.SpeedTo(MACH_1_SPEED, MACH_1_SECONDS);
  end
  else if (Key = vkR) or ((Key = 0) and (UpCase(KeyChar) = 'R')) then
  begin
    ResetView;
    if Assigned(FOnRestart) then
      FOnRestart(Self);
  end
  else
    Exit;
  Key := 0;
  KeyChar := #0;
end;

procedure TTerrainView.KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  LControl: TFlightControl;
begin
  inherited;
  if KeyControl(Key, KeyChar, LControl) then
    Exclude(FHeld, LControl)
  else if (Key = vkSpace) or (KeyChar = ' ') then
    FSpaceDown := False
  else if (Key = vkB) or (UpCase(KeyChar) = 'B') then
    FBookmarkKeyDown := False
  else if (Key = vkL) or (UpCase(KeyChar) = 'L') then
    FLabelsKeyDown := False
  else
    Exit;
  Key := 0;
  KeyChar := #0;
end;

procedure TTerrainView.AskForBookmark;
begin
  if FBookmarkQueued or not FHasArea or not Assigned(FOnBookmark) then
    Exit;
  FBookmarkQueued := True;
  // After the key's handling, so the handler may open a modal dialog
  TThread.ForceQueue(nil,
    procedure
    begin
      FBookmarkQueued := False;
      if Assigned(FOnBookmark) then
        FOnBookmark(Self);
    end);
end;

procedure TTerrainView.SetPaused(AValue: Boolean);
begin
  if AValue = FPaused then
    Exit;
  FPaused := AValue;
  FHeld := [];
  if FPaused then
  begin
    FPauseBanner.ShowText('Paused', 'Press Space to carry on.');
    PlaceInstruments;
  end
  else
    FPauseBanner.Visible := False;
  // No jump when carrying on: the time paused is not flown
  FFlightWatch := TStopwatch.StartNew;
end;

procedure TTerrainView.StartLookingAt(ALatitude, ALongitude: Double);
begin
  // From the south, at the start height and the starting tilt
  StartLookingAlong(ALatitude, ALongitude, 0, FStartHeight, True, DEFAULT_FLIGHT_TILT);
end;

procedure TTerrainView.StartLookingAlong(ALatitude, ALongitude, AHeading, AHeight: Double;
  AAboveGround: Boolean; ATilt: Double);
var
  LPoint: TPoint3D;
begin
  if (FLod = nil) or not FLod.Started then
    Exit;
  FHeld := [];
  FBanner.Visible := False;
  FFlight.StartHeight := FStartHeight;
  FFlight.LookStretch := FExaggeration;
  FFlight.StartLookingAlong(ALatitude, ALongitude, AHeading, AHeight, AAboveGround, ATilt);
  LPoint := FLod.Frame.ToLocal(FFlight.Latitude, FFlight.Longitude, 0);
  if FLod.NeedsRebase(LPoint.X, LPoint.Z) then
    FLod.Start(Floor(FFlight.Latitude), Floor(FFlight.Longitude));
  BeginWork;
  FFlightWatch := TStopwatch.StartNew;
  PlaceCamera;
end;

function TTerrainView.GetCovered: Boolean;
begin
  Result := FCover.Visible;
end;

procedure TTerrainView.SetCovered(AValue: Boolean);
begin
  if AValue = FCover.Visible then
    Exit;
  if AValue then
  begin
    // A picture of the view as it is now, so it seems to stay still while
    // the new place is made underneath; the plain cover if none can be had
    FCover.SetPicture(PictureOfView);
    FCover.SetBounds(0, 0, Width, Height);
    FCover.BringToFront;
  end
  else
    FCover.SetPicture(nil);
  FCover.Visible := AValue;
end;

function TTerrainView.PictureOfView: TBitmap;
var
  LData: TBitmapData;
  LSeen: Boolean;
  I: Integer;
begin
  Result := nil;
  if not FHasArea or not ParentedVisible or (FViewport.Width < 1) or (FViewport.Height < 1) then
    Exit;
  try
    Result := FViewport.MakeScreenshot;
    LSeen := False;
    // A picture with nothing in it (the 3D drawing not caught) is no use:
    // a few pixels across the middle row must not all be clear
    if (Result <> nil) and not Result.IsEmpty and Result.Map(TMapAccess.Read, LData) then
    try
      for I := 1 to 15 do
        if TAlphaColorRec(LData.GetPixel(Result.Width * I div 16, Result.Height div 2)).A <> 0 then
          LSeen := True;
    finally
      Result.Unmap(LData);
    end;
    if not LSeen then
      FreeAndNil(Result);
  except
    FreeAndNil(Result);
  end;
  if Assigned(FOnLog) then
    if Result <> nil then
      FOnLog(Self, Format('3D: covered with a picture of the view (%d x %d) while it is got ' +
        'ready', [Result.Width, Result.Height]))
    else
      FOnLog(Self, '3D: covered while it is got ready (no picture of the view could be had)');
end;

procedure TTerrainView.UpdateAutopilotText;
begin
  if FSpeedPanel = nil then
    Exit;
  if not FFlight.Autopilot then
    FSpeedPanel.AutopilotText := ''
  else if FFlight.GroundHug then
  begin
    if FFlight.AutopilotClimbing then
      FSpeedPanel.AutopilotText := 'Hug climb'
    else if FFlight.AutopilotDescending then
      FSpeedPanel.AutopilotText := 'Hug descend'
    else
      FSpeedPanel.AutopilotText := 'Hugging';
  end
  else if FFlight.AutopilotClimbing then
    FSpeedPanel.AutopilotText := 'Auto climb'
  else
    FSpeedPanel.AutopilotText := 'Autopilot';
end;

function TTerrainView.GetGroundHug: Boolean;
begin
  Result := FFlight.GroundHug;
end;

procedure TTerrainView.SetGroundHug(AValue: Boolean);
begin
  FFlight.GroundHug := AValue;
  UpdateAutopilotText;
end;

function TTerrainView.GetAutopilot: Boolean;
begin
  Result := FFlight.Autopilot;
end;

procedure TTerrainView.SetAutopilot(AValue: Boolean);
begin
  FFlight.Autopilot := AValue;
  UpdateInstruments;
end;

procedure TTerrainView.SetFlownKm(AValue: Double);
begin
  if FSpeedPanel <> nil then
    FSpeedPanel.FlownKm := AValue;
end;

procedure TTerrainView.SetFlightSpeed(AValue: Double);
begin
  FFlight.SetSpeed(AValue);
  UpdateInstruments;
end;

function TTerrainView.Settled: Boolean;
begin
  Result := FHasArea and (FLod <> nil) and not FWasBusy;
end;

procedure TTerrainView.WorkProgress(out ADone, ATotal: Integer; out AText: string);
var
  LPatchesToCome, LTexturesToCome: Integer;
begin
  ADone := 0;
  ATotal := 0;
  AText := '';
  if FLod = nil then
    Exit;
  LPatchesToCome := FLod.PendingCount;
  if FRealistic and (FImagery <> nil) then
    LTexturesToCome := FImagery.Pending
  else
    LTexturesToCome := 0;
  ADone := FUploads + FTextures;
  ATotal := ADone + LPatchesToCome + LTexturesToCome;
  AText := Format('Ground: %d patches made, %d to come', [FUploads, LPatchesToCome]);
  if FRealistic and (FImagery <> nil) then
    AText := AText + Format('; imagery: %d textures, %d to come', [FTextures,
      LTexturesToCome]);
end;

procedure TTerrainView.SetPlaceLabels(const AValue: TArray<TTerrainPlaceLabel>);
begin
  FPlaceLabels := AValue;
  FNearValid := False;
  UpdateLabels;
end;

procedure TTerrainView.SetShowLabels(AValue: Boolean);
begin
  if AValue = FShowLabels then
    Exit;
  FShowLabels := AValue;
  UpdateLabels;
end;

procedure TTerrainView.FindNearLabels;
var
  LCos, LKm: Double;
  I: Integer;
  LNear: TArray<Integer>;
begin
  if FNearValid and (KM_PER_DEGREE * Sqrt(Sqr(FFlight.Latitude - FNearLatitude) +
     Sqr((FFlight.Longitude - FNearLongitude) * Cos(DegToRad(FFlight.Latitude)))) <
     LABEL_REFRESH_KM) then
    Exit;
  FNearLatitude := FFlight.Latitude;
  FNearLongitude := FFlight.Longitude;
  FNearValid := True;
  LCos := Cos(DegToRad(FFlight.Latitude));
  LNear := nil;
  // A little beyond the range, so places come into it between refreshes
  for I := 0 to High(FPlaceLabels) do
  begin
    LKm := KM_PER_DEGREE * Sqrt(Sqr(FPlaceLabels[I].Latitude - FFlight.Latitude) +
      Sqr((WrapDegrees(FPlaceLabels[I].Longitude - FFlight.Longitude + 180) - 180) * LCos));
    if LKm <= LABEL_RANGE_KM + LABEL_REFRESH_KM then
      LNear := LNear + [I];
  end;
  // Most important first, so they win their place on the screen
  TArray.Sort<Integer>(LNear, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := CompareValue(FPlaceLabels[A].Rank, FPlaceLabels[B].Rank);
    end));
  FNearLabels := LNear;
end;

procedure TTerrainView.UpdateLabels;
var
  LScreen: TArray<TTerrainScreenLabel>;
  LItem: TTerrainScreenLabel;
  LCamera, LForward, LRight, LUp, LDelta, LPoint: TPoint3D;
  LTanX, LTanY, LX, LY, LZ, LGround, LWidth, LHeight: Double;
  I: Integer;
begin
  if FLabelLayer = nil then
    Exit;
  // The picture is the viewport's, so its size is what counts
  LWidth := FViewport.Width;
  LHeight := FViewport.Height;
  if not FShowLabels or (FLod = nil) or not FLod.Started or (Length(FPlaceLabels) = 0) or
     (LWidth < 1) or (LHeight < 1) then
  begin
    FLabelLayer.SetLabels(nil);
    Exit;
  end;
  FindNearLabels;
  // The camera's way ahead, right and up; up is -Y, and east is on the
  // right when looking north
  LCamera := FCamera.Position.Point;
  LForward := (FCentre.Position.Point - LCamera).Normalize;
  LRight := LForward.CrossProduct(Point3D(0, -1, 0)).Normalize;
  LUp := LRight.CrossProduct(LForward);
  LTanY := Tan(DegToRad(TERRAIN_FOV / 2));
  LTanX := LTanY * LWidth / LHeight;
  LScreen := nil;
  for I in FNearLabels do
  begin
    if not FLod.GroundHeight(FPlaceLabels[I].Latitude, FPlaceLabels[I].Longitude, LGround) then
      Continue;
    LPoint := FLod.Frame.ToLocal(FPlaceLabels[I].Latitude, FPlaceLabels[I].Longitude,
      LGround * FExaggeration / 1000);
    LDelta := LPoint - LCamera;
    LZ := LDelta.DotProduct(LForward);
    // Behind the camera, or nearer than it draws
    if LZ < FNearPlane then
      Continue;
    LX := LDelta.DotProduct(LRight);
    LY := LDelta.DotProduct(LUp);
    LItem.Ground := PointF(FViewport.Position.X + LWidth / 2 * (1 + LX / (LZ * LTanX)),
      FViewport.Position.Y + LHeight / 2 * (1 - LY / (LZ * LTanY)));
    // The ground must be on the screen, with room above it for the name
    if (LItem.Ground.X < 0) or (LItem.Ground.X > Width) or (LItem.Ground.Y < LABEL_POLE) or
       (LItem.Ground.Y > Height) then
      Continue;
    LItem.Text := FPlaceLabels[I].Name;
    LItem.Kind := FPlaceLabels[I].Kind;
    LScreen := LScreen + [LItem];
  end;
  FLabelLayer.SetLabels(LScreen);
end;

function TTerrainView.GetControlsCollapsed: Boolean;
begin
  Result := FControls.Collapsed;
end;

procedure TTerrainView.SetControlsCollapsed(AValue: Boolean);
begin
  FControls.Collapsed := AValue;
  PlaceInstruments;
end;

procedure TTerrainView.ControlsToggled(Sender: TObject);
begin
  PlaceInstruments;
  SetFocus;
  if Assigned(FOnControlsToggle) then
    FOnControlsToggle(Self);
end;

function TTerrainView.FlightState: TTerrainFlightState;
begin
  Result.Latitude := FFlight.Latitude;
  Result.Longitude := FFlight.Longitude;
  Result.Altitude := FFlight.Altitude;
  Result.Heading := FFlight.Heading;
  Result.Speed := FFlight.Speed;
  Result.Tilt := FFlight.Tilt;
end;

procedure TTerrainView.JumpTo(const AState: TTerrainFlightState; AAboveGround: Boolean);
var
  LPoint: TPoint3D;
begin
  if (FLod = nil) or not FLod.Started then
    Exit;
  FHeld := [];
  FBanner.Visible := False;
  if AAboveGround then
    FFlight.SetStateAboveGround(AState.Latitude, AState.Longitude, AState.Altitude,
      AState.Heading, AState.Speed, AState.Tilt)
  else
    FFlight.SetState(AState.Latitude, AState.Longitude, AState.Altitude, AState.Heading,
      AState.Speed, AState.Tilt);
  // Measured again from the tile under it if it is far from the frame's
  // point
  LPoint := FLod.Frame.ToLocal(FFlight.Latitude, FFlight.Longitude, 0);
  if FLod.NeedsRebase(LPoint.X, LPoint.Z) then
    FLod.Start(Floor(FFlight.Latitude), Floor(FFlight.Longitude));
  BeginWork;
  FFlightWatch := TStopwatch.StartNew;
  PlaceCamera;
end;

procedure TTerrainView.DoExit;
begin
  inherited;
  FHeld := [];
  FSpaceDown := False;
  FBookmarkKeyDown := False;
  FLabelsKeyDown := False;
  FDragging := False;
end;

end.
