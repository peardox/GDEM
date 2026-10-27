{ @abstract(Cuts an image into a tile set: square tiles at several levels
  of detail, described by a @code(tileset.json).)

  @link(LoadSourceImage) decodes the image with Skia into memory.
  @link(PlanTileSet) works out the levels (the image, then each half the
  size of the last, until one is about a screen across) and checks that
  the tile size cuts every one exactly; see @code(GDEMFactors).
  @link(WriteTileSet) then makes each level from the full image with
  @code(ReduceImage) (Lanczos-3 in linear light, see @code(GDEMResample)),
  cuts it into tiles, encodes them with Skia, and writes
  @code(tileset.json) last, so a folder without it is unfinished.

  No FMX: Skia's own units do the decoding and encoding, so this could run
  in any program. }
unit GDEMTiler;

interface

uses
  System.SysUtils, System.Types,
  GDEMResample, GDEMTileSet;

type
  {$SCOPEDENUMS ON}
  { @abstract(The file type tiles are written in.) }
  TTileImageFormat = (
    { JPEG: small and quick to decode; suits photographs and imagery. Has
      no transparency. }
    Jpeg,
    { WebP: about a third smaller than JPEG at the same quality. }
    WebP,
    { PNG: lossless and keeps transparency, but much larger for a
      photograph. }
    Png);
  {$SCOPEDENUMS OFF}

const
  { The extension each format is written with, which is also how
    @code(tileset.json) names it. }
  TILE_FORMAT_EXTENSIONS: array[TTileImageFormat] of string = ('jpg', 'webp', 'png');

  { How each format is shown to the user. }
  TILE_FORMAT_CAPTIONS: array[TTileImageFormat] of string = ('JPEG', 'WebP', 'PNG');

  { The quality tiles are encoded at unless chosen otherwise. }
  DEFAULT_TILE_QUALITY = 90;

  { The name written into @code(tileset.json) as the program that made
    it. }
  TILER_GENERATOR = 'TileMaker';

type
  { @abstract(Raised when an image cannot be read or tiled.) }
  ETilerError = class(Exception);

  { Reports progress. It may raise an exception, such as @code(EAbort),
    to stop the work.
    @param(AStage What is being done, such as
      @code(Level 1 of 4: resampling to 5400 x 2700).)
    @param(ADone Steps of that stage done.)
    @param(ATotal Steps in that stage.) }
  TTilerProgressEvent = reference to procedure(const AStage: string; ADone, ATotal: Integer);

  { Receives a line for the log.
    @param(Msg The line.) }
  TTilerLogEvent = reference to procedure(const Msg: string);

  { @abstract(How to cut a tile set.) }
  TTileOptions = record
    { Width and height of each tile, in pixels. It must cut every level
      exactly; see @code(TileSizesFor) in @code(GDEMFactors). }
    TileSize: Integer;
    { Stop halving once a level is no wider than this. }
    CoarsestWidth: Integer;
    { The tiles' file type. }
    ImageFormat: TTileImageFormat;
    { Encoding quality, 1 to 100; ignored for PNG. }
    Quality: Integer;
    { What the image covers, in degrees for a map. }
    Bounds: TTileSetBounds;
    { The projection, such as @code(equirectangular); empty for an image
      that is not a map. }
    Projection: string;
    { @true if the left and right edges are neighbours, as for a map of the
      whole world, so resampling wraps round there. }
    WrapEastWest: Boolean;

    { The defaults for a map of the whole world: tile size 0 (to be
      chosen), @code(DEFAULT_COARSEST_WIDTH), JPEG at
      @link(DEFAULT_TILE_QUALITY), the whole world, equirectangular,
      wrapping east to west.
      @returns(The options.) }
    class function Defaults: TTileOptions; static;
  end;

{ Reads an image into memory, as 8-bit RGBA. Any format Skia decodes will
  do: JPEG, PNG, WebP, BMP, GIF and others.
  @param(AFileName The image file.)
  @returns(The pixels.)
  @raises(ETilerError if it cannot be read or decoded.) }
function LoadSourceImage(const AFileName: string): TRGBA8Image;

{ Works out a tile set for an image, without writing anything.
  @param(ASourceFileName The image's file name; only its name is kept.)
  @param(AWidth The image's width.)
  @param(AHeight The image's height.)
  @param(AOptions How to cut it.)
  @returns(The description, with every level and its tile counts.)
  @raises(ETilerError if the tile size does not cut every level exactly.) }
function PlanTileSet(const ASourceFileName: string; AWidth, AHeight: Integer;
  const AOptions: TTileOptions): TTileSet;

{ Makes a tile set: each level from the full image, cut into tiles, each
  tile encoded into its level's folder, then @code(tileset.json) last.
  An existing @code(tileset.json) in the folder is deleted first, so an
  interrupted run never leaves an old description over new tiles.
  @param(ASource The full image, as from @link(LoadSourceImage).)
  @param(ATileSet The plan, as from @link(PlanTileSet); its
    @code(Created) time is filled in.)
  @param(AFolder The tile set's folder; created if need be.)
  @param(AOptions How to cut it: the format, quality and wrapping are
    used.)
  @param(AOnProgress Called as each row of a level is resampled and as each
    tile is written. May be @nil.)
  @param(AOnLog Called with a line as each level starts and when all is
    done. May be @nil.)
  @raises(ETilerError if a folder or tile cannot be written.) }
procedure WriteTileSet(const ASource: TRGBA8Image; var ATileSet: TTileSet;
  const AFolder: string; const AOptions: TTileOptions;
  const AOnProgress: TTilerProgressEvent; const AOnLog: TTilerLogEvent);

implementation

uses
  System.IOUtils, System.DateUtils, System.Diagnostics, System.StrUtils,
  System.Skia,
  GDEMFactors;

const
  { Skia's encoder for each format. }
  SKIA_FORMATS: array[TTileImageFormat] of TSkEncodedImageFormat =
    (TSkEncodedImageFormat.JPEG, TSkEncodedImageFormat.WEBP, TSkEncodedImageFormat.PNG);

{ TTileOptions }

class function TTileOptions.Defaults: TTileOptions;
begin
  Result.TileSize := 0;
  Result.CoarsestWidth := DEFAULT_COARSEST_WIDTH;
  Result.ImageFormat := TTileImageFormat.Jpeg;
  Result.Quality := DEFAULT_TILE_QUALITY;
  Result.Bounds := TTileSetBounds.World;
  Result.Projection := PROJECTION_EQUIRECTANGULAR;
  Result.WrapEastWest := True;
end;

{ Skia's description of 8-bit RGBA pixels, alpha not premultiplied, as in
  @code(TRGBA8Image).
  @param(AWidth Width, in pixels.)
  @param(AHeight Height, in pixels.)
  @returns(The description.) }
function RGBA8Info(AWidth, AHeight: Integer): TSkImageInfo;
begin
  Result := TSkImageInfo.Create(AWidth, AHeight, TSkColorType.RGBA8888,
    TSkAlphaType.Unpremul);
end;

function LoadSourceImage(const AFileName: string): TRGBA8Image;
var
  LImage: ISkImage;
begin
  if not TFile.Exists(AFileName) then
    raise ETilerError.CreateFmt('%s does not exist.', [AFileName]);
  try
    LImage := TSkImage.MakeFromEncodedFile(AFileName);
  except
    on E: Exception do
      raise ETilerError.CreateFmt('Could not read %s: %s', [AFileName, E.Message]);
  end;
  if LImage = nil then
    raise ETilerError.CreateFmt('%s is not an image Skia can decode.', [AFileName]);
  Result := TRGBA8Image.Create(LImage.Width, LImage.Height);
  if not LImage.ReadPixels(RGBA8Info(Result.Width, Result.Height), @Result.Pixels[0],
     Result.RowBytes) then
    raise ETilerError.CreateFmt('Could not decode %s (%d x %d).',
      [AFileName, Result.Width, Result.Height]);
end;

function PlanTileSet(const ASourceFileName: string; AWidth, AHeight: Integer;
  const AOptions: TTileOptions): TTileSet;
var
  LSizes: TArray<TSize>;
  LLevel: Integer;
begin
  LSizes := LevelSizes(AWidth, AHeight, AOptions.CoarsestWidth);
  if (AOptions.TileSize < 1) or
     (LSizes[High(LSizes)].cx mod AOptions.TileSize <> 0) or
     (LSizes[High(LSizes)].cy mod AOptions.TileSize <> 0) then
    raise ETilerError.CreateFmt('Tiles of %d pixels do not cut the smallest level, ' +
      '%d x %d, exactly. Choose one of the sizes offered.',
      [AOptions.TileSize, LSizes[High(LSizes)].cx, LSizes[High(LSizes)].cy]);

  Result := Default(TTileSet);
  Result.Format := TILESET_FORMAT;
  Result.Name := TPath.GetFileNameWithoutExtension(ASourceFileName);
  Result.Source := TPath.GetFileName(ASourceFileName);
  Result.SourceWidth := AWidth;
  Result.SourceHeight := AHeight;
  Result.TileSize := AOptions.TileSize;
  Result.ImageFormat := TILE_FORMAT_EXTENSIONS[AOptions.ImageFormat];
  if AOptions.ImageFormat = TTileImageFormat.Png then
    Result.Quality := 100
  else
    Result.Quality := AOptions.Quality;
  Result.Resampling := RESAMPLING_DESCRIPTION;
  Result.Projection := AOptions.Projection;
  Result.Bounds := AOptions.Bounds;
  Result.Generator := TILER_GENERATOR;
  SetLength(Result.Levels, Length(LSizes));
  for LLevel := 0 to High(LSizes) do
  begin
    Result.Levels[LLevel].Width := LSizes[LLevel].cx;
    Result.Levels[LLevel].Height := LSizes[LLevel].cy;
    Result.Levels[LLevel].Columns := LSizes[LLevel].cx div AOptions.TileSize;
    Result.Levels[LLevel].Rows := LSizes[LLevel].cy div AOptions.TileSize;
    Result.Levels[LLevel].Folder := TTileSet.LevelFolderName(LSizes[LLevel].cx,
      LSizes[LLevel].cy);
  end;
end;

procedure WriteTileSet(const ASource: TRGBA8Image; var ATileSet: TTileSet;
  const AFolder: string; const AOptions: TTileOptions;
  const AOnProgress: TTilerProgressEvent; const AOnLog: TTilerLogEvent);
var
  LLevel, LRow, LColumn, LTiles, LDone: Integer;
  LImage: TRGBA8Image;
  LStage, LFileName: string;
  LInfo: TSkImageInfo;
  LClock: TStopwatch;
  LBytes: Int64;
  LOnProgress: TTilerProgressEvent;

  { Passes a line to AOnLog, if set.
    @param(Msg The line.) }
  procedure Log(const Msg: string);
  begin
    if Assigned(AOnLog) then
      AOnLog(Msg);
  end;

begin
  ATileSet.Validate;
  if (ASource.Width <> ATileSet.SourceWidth) or (ASource.Height <> ATileSet.SourceHeight) then
    raise ETilerError.CreateFmt('The image is %d x %d but the plan is for %d x %d.',
      [ASource.Width, ASource.Height, ATileSet.SourceWidth, ATileSet.SourceHeight]);
  // Copied so the resampler's anonymous method can use it
  LOnProgress := AOnProgress;
  LClock := TStopwatch.StartNew;
  LBytes := 0;
  try
    ForceDirectories(AFolder);
    // An old description must not outlive the tiles it described
    if TFile.Exists(TPath.Combine(AFolder, TILESET_FILE_NAME)) then
      TFile.Delete(TPath.Combine(AFolder, TILESET_FILE_NAME));
  except
    on E: Exception do
      raise ETilerError.CreateFmt('Could not prepare %s: %s', [AFolder, E.Message]);
  end;

  for LLevel := 0 to High(ATileSet.Levels) do
  begin
    LStage := Format('Level %d of %d (%d x %d)', [LLevel + 1, Length(ATileSet.Levels),
      ATileSet.Levels[LLevel].Width, ATileSet.Levels[LLevel].Height]);
    Log(LStage + ': ' + IfThen(LLevel = 0, 'the full image',
      Format('resampling to 1/%d', [1 shl LLevel])));

    // Every level straight from the full image, so no error builds up
    if LLevel = 0 then
      LImage := ASource
    else
      LImage := ReduceImage(ASource, 1 shl LLevel, AOptions.WrapEastWest,
        procedure(ADone, ATotal: Integer)
        begin
          if Assigned(LOnProgress) then
            LOnProgress(LStage + ': resampling', ADone, ATotal);
        end);

    try
      ForceDirectories(TPath.Combine(AFolder, ATileSet.Levels[LLevel].Folder));
    except
      on E: Exception do
        raise ETilerError.CreateFmt('Could not create %s: %s',
          [TPath.Combine(AFolder, ATileSet.Levels[LLevel].Folder), E.Message]);
    end;

    // Each tile is encoded straight from the level's pixels: the encoder
    // is given the tile's top-left pixel and the level's row length
    LInfo := RGBA8Info(ATileSet.TileSize, ATileSet.TileSize);
    LTiles := ATileSet.Levels[LLevel].Rows * ATileSet.Levels[LLevel].Columns;
    LDone := 0;
    for LRow := 0 to ATileSet.Levels[LLevel].Rows - 1 do
      for LColumn := 0 to ATileSet.Levels[LLevel].Columns - 1 do
      begin
        LFileName := TPath.Combine(AFolder, ATileSet.TileFileName(LLevel, LRow, LColumn));
        if not TSkImageEncoder.EncodeToFile(LFileName, LInfo,
           LImage.PixelAddress(LColumn * ATileSet.TileSize, LRow * ATileSet.TileSize),
           LImage.RowBytes, SKIA_FORMATS[AOptions.ImageFormat], ATileSet.Quality) then
          raise ETilerError.CreateFmt('Could not write %s.', [LFileName]);
        Inc(LBytes, TFile.GetSize(LFileName));
        Inc(LDone);
        if Assigned(AOnProgress) then
          AOnProgress(LStage + ': writing tiles', LDone, LTiles);
      end;
    // The smaller levels are made again from the full image, so this one
    // can go
    LImage.Pixels := nil;
  end;

  ATileSet.Created := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
  ATileSet.Save(AFolder);
  Log(Format('Wrote %d level(s) of %d-pixel tiles, %s, in %.1f s, to %s',
    [Length(ATileSet.Levels), ATileSet.TileSize, FormatFloat('0.0', LBytes / (1024 * 1024)) + ' MB',
     LClock.Elapsed.TotalSeconds, AFolder]));
end;

end.
