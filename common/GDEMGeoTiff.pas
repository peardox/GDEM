{ @abstract(Reads GeoTIFF files, such as ASTER GDEM tiles, in pure Pascal.)

  A @link(TGeoTiff) opens a file, reads every image directory in it (the
  full image and any reduced-resolution overviews) and the GeoTIFF tags
  saying where it lies, and decodes any image into an array of samples on
  request. No native library is needed, so it works the same on every
  platform.

  What it reads, which covers ASTER GDEM V3 and most single-band GeoTIFFs
  that GDAL writes:
  @unorderedList(
    @item(classic TIFF, little- or big-endian (not BigTIFF);)
    @item(images in tiles or in strips;)
    @item(one sample per pixel, of 8 or 16 bits, signed or unsigned;)
    @item(no compression, LZW, Deflate or PackBits;)
    @item(horizontal differencing (predictor 2);)
    @item(the pixel scale and tie point, or a transformation matrix without
      rotation; the raster type (pixel is area or point); the geographic
      coordinate system; and GDAL's no-data value.)
  )

  An ASTER GDEM V3 @code(_dem.tif) is 3601 x 3601 signed 16-bit samples in
  256 x 256 tiles, LZW-compressed, followed by eight overviews (1801, 1201,
  901, 451, 401, 226, 57 and 45 pixels across, in 128 x 128 tiles). Its
  tie point puts the corner of the first pixel half a pixel north-west of
  the whole degree, with pixel is area, so the first pixel's centre lies
  exactly on the tile's south-west corner's longitude and the north edge's
  latitude. The @code(_num.tif) is laid out the same, with unsigned 8-bit
  samples.

  Overviews carry no GeoTIFF tags of their own; @link(TGeoTiff.Georeference)
  gives each image's position, worked out from the full image's as GDAL
  does: the same area, divided into the overview's pixels.

  A @link(TGeoTiff) reads from one stream, so it must be used from one
  thread at a time. No FMX: any program can use it. }
unit GDEMGeoTiff;

interface

uses
  System.SysUtils, System.Classes;

const
  { Sample format: unsigned integers. }
  SAMPLE_FORMAT_UNSIGNED = 1;
  { Sample format: signed integers. }
  SAMPLE_FORMAT_SIGNED = 2;
  { Sample format: IEEE floating point. }
  SAMPLE_FORMAT_FLOAT = 3;

  { Compression: none. }
  COMPRESSION_NONE = 1;
  { Compression: LZW. }
  COMPRESSION_LZW = 5;
  { Compression: Deflate, as numbered by Adobe. }
  COMPRESSION_DEFLATE = 8;
  { Compression: PackBits. }
  COMPRESSION_PACKBITS = 32773;
  { Compression: Deflate, as numbered by older writers. }
  COMPRESSION_DEFLATE_OLD = 32946;

  { The geographic coordinate system WGS 84, as an EPSG code. }
  EPSG_WGS84 = 4326;

type
  { @abstract(Raised when a file is not a TIFF this unit can read, or is
    damaged.) }
  EGeoTiffError = class(Exception);

  { @abstract(One image in a TIFF: the full image or a reduced-resolution
    overview.) }
  TGeoTiffImage = record
    { Width in pixels. }
    Width: Integer;
    { Height in pixels. }
    Height: Integer;
    { Bits in each sample: 8 or 16 for an image this unit can decode. }
    BitsPerSample: Integer;
    { @link(SAMPLE_FORMAT_UNSIGNED), @link(SAMPLE_FORMAT_SIGNED) or
      @link(SAMPLE_FORMAT_FLOAT). }
    SampleFormat: Integer;
    { Samples in each pixel: 1 for an image this unit can decode. }
    SamplesPerPixel: Integer;
    { The compression, such as @link(COMPRESSION_LZW). }
    Compression: Integer;
    { 1 for none, 2 for horizontal differencing. }
    Predictor: Integer;
    { @true if the image is stored in tiles, @false if in strips. }
    Tiled: Boolean;
    { Width of a tile; for strips, the image's width. }
    BlockWidth: Integer;
    { Height of a tile, or the rows in a strip. }
    BlockHeight: Integer;
    { Where each tile or strip starts in the file, left to right and top
      to bottom. }
    Offsets: TArray<Int64>;
    { How many bytes each tile or strip takes in the file; 0 for one that
      was never written (read as zeros). }
    ByteCounts: TArray<Int64>;
    { @true for a reduced-resolution copy of the full image. }
    IsOverview: Boolean;

    { Bytes in one sample.
      @returns(@link(BitsPerSample) divided by 8, rounded up.) }
    function BytesPerSample: Integer;

    { Tiles across the image; 1 for strips.
      @returns(The number of tiles in a row.) }
    function BlocksAcross: Integer;

    { Tiles or strips down the image.
      @returns(The number of rows of tiles, or of strips.) }
    function BlocksDown: Integer;
  end;

  { @abstract(Where an image lies: the GeoTIFF tags, in the units of its
    coordinate system, degrees for a geographic one.)

    Raster positions count pixels from the top-left corner of the image,
    columns to the right and rows down. Model positions are longitude
    (X) and latitude (Y) for a geographic coordinate system. }
  TGeoTiffGeoreference = record
    { @true if the file says where the image lies. }
    Valid: Boolean;
    { Model units per pixel across. }
    ScaleX: Double;
    { Model units per pixel down, positive when Y falls going down, as for
      latitude. }
    ScaleY: Double;
    { Raster column of the tie point. }
    TieI: Double;
    { Raster row of the tie point. }
    TieJ: Double;
    { Model X (longitude) of the tie point. }
    TieX: Double;
    { Model Y (latitude) of the tie point. }
    TieY: Double;
    { @true if raster positions name pixel centres (GeoTIFF's
      PixelIsPoint), @false if they name pixel corners (PixelIsArea, the
      default). }
    PixelIsPoint: Boolean;
    { The geographic coordinate system as an EPSG code, such as
      @link(EPSG_WGS84); 0 if the file does not say. }
    GeographicType: Integer;
    { @true if the file gives a no-data value (GDAL's tag 42113). }
    HasNoData: Boolean;
    { The no-data value, when @link(HasNoData). }
    NoData: Double;

    { The model X of the image's left edge.
      @returns(The western edge, for a geographic image.) }
    function West: Double;

    { The model Y of the image's top edge.
      @returns(The northern edge, for a geographic image.) }
    function North: Double;

    { The model X of a pixel's centre.
      @param(AColumn The pixel's column, 0 at the left.)
      @returns(Its longitude, for a geographic image.) }
    function CentreX(AColumn: Double): Double;

    { The model Y of a pixel's centre.
      @param(ARow The pixel's row, 0 at the top.)
      @returns(Its latitude, for a geographic image.) }
    function CentreY(ARow: Double): Double;

    { The same area divided into another image's pixels, as GDAL places an
      overview: the full image's edges, with the pixel size scaled by the
      ratio of the sizes.
      @param(AFullWidth The width of the image this describes.)
      @param(AFullHeight Its height.)
      @param(AWidth The other image's width.)
      @param(AHeight Its height.)
      @returns(The other image's georeference, with pixel is area.) }
    function Resized(AFullWidth, AFullHeight, AWidth, AHeight: Integer): TGeoTiffGeoreference;
  end;

  { @abstract(A GeoTIFF file, open for reading.) }
  TGeoTiff = class
  private
    { The file. }
    FStream: TStream;
    { @true if @link(FStream) is freed with this object. }
    FOwnsStream: Boolean;
    { The file's size in bytes. }
    FSize: Int64;
    { @true for a big-endian (MM) file. }
    FBigEndian: Boolean;
    { Backing field for @link(Images). }
    FImages: TArray<TGeoTiffImage>;
    { The full image's georeference. }
    FGeoreference: TGeoTiffGeoreference;

    { Reads bytes from the file.
      @param(AOffset Where to start.)
      @param(ACount How many bytes.)
      @returns(The bytes.)
      @raises(EGeoTiffError if they lie beyond the end of the file.) }
    function ReadBytes(AOffset, ACount: Int64): TBytes;

    { A 16-bit value from a buffer, in the file's byte order.
      @param(ABuffer The buffer.)
      @param(APosition Where the value starts.)
      @returns(The value.) }
    function GetU16(const ABuffer: TBytes; APosition: Integer): Word;

    { A 32-bit value from a buffer, in the file's byte order.
      @param(ABuffer The buffer.)
      @param(APosition Where the value starts.)
      @returns(The value.) }
    function GetU32(const ABuffer: TBytes; APosition: Integer): Cardinal;

    { A 64-bit floating-point value from a buffer, in the file's byte
      order.
      @param(ABuffer The buffer.)
      @param(APosition Where the value starts.)
      @returns(The value.) }
    function GetDouble(const ABuffer: TBytes; APosition: Integer): Double;

    { Reads the header and every image directory, and the GeoTIFF tags of
      the first.
      @raises(EGeoTiffError if the file is not a classic TIFF or is
        damaged.) }
    procedure ReadDirectories;

    { Reads a tile or strip and decodes it into a whole block of samples
      in the machine's byte order, before any predictor is undone.
      @param(AImage The image.)
      @param(ABlock Which tile or strip.)
      @param(ABuffer Receives the samples; it must hold @code(ACount)
        bytes.)
      @param(ACount Bytes a whole block holds.)
      @raises(EGeoTiffError if the compression is not supported or the
        data is damaged.) }
    procedure DecodeBlock(const AImage: TGeoTiffImage; ABlock: Integer;
      var ABuffer: TBytes; ACount: Integer);

    { Reader for @link(Images).
      @param(AIndex The image, 0 for the full image.)
      @returns(Its description.) }
    function GetImage(AIndex: Integer): TGeoTiffImage;

    { Reader for @link(ImageCount).
      @returns(The number of images.) }
    function GetImageCount: Integer;
  public
    { Opens a file and reads its directories.
      @param(AFileName The file.)
      @raises(EGeoTiffError if it is not a TIFF this unit can read.)
      @raises(EFOpenError if it cannot be opened.) }
    constructor Create(const AFileName: string);

    { Reads a TIFF held in a stream.
      @param(AStream The stream, positioned anywhere; the TIFF starts at
        its beginning.)
      @param(AOwnsStream @true to free the stream with this object, even
        if this raises.)
      @raises(EGeoTiffError if it is not a TIFF this unit can read.) }
    constructor CreateFromStream(AStream: TStream; AOwnsStream: Boolean = False);

    { Closes the file. }
    destructor Destroy; override;

    { Where an image lies. For the full image, the file's own GeoTIFF
      tags; for an overview, the same area divided into its pixels (see
      @link(TGeoTiffGeoreference.Resized)).
      @param(AIndex The image, 0 for the full image.)
      @returns(The georeference; not @code(Valid) if the file has none.) }
    function Georeference(AIndex: Integer = 0): TGeoTiffGeoreference;

    { Decodes a whole image into memory.
      @param(AIndex The image, 0 for the full image.)
      @param(ADest Where the samples go: @code(Width * Height *
        BytesPerSample) bytes, row by row from the top, each sample in the
        machine's byte order.)
      @raises(EGeoTiffError if the image is not one this unit can decode,
        or is damaged.) }
    procedure ReadInto(AIndex: Integer; ADest: Pointer);

    { Decodes a whole image of signed 16-bit samples, such as a GDEM
      @code(_dem.tif).
      @param(AIndex The image, 0 for the full image.)
      @returns(@code(Width * Height) samples, row by row from the top.)
      @raises(EGeoTiffError if the samples are not signed 16-bit, or the
        image cannot be decoded.) }
    function ReadInt16(AIndex: Integer = 0): TArray<SmallInt>;

    { Decodes a whole image of unsigned 8-bit samples, such as a GDEM
      @code(_num.tif).
      @param(AIndex The image, 0 for the full image.)
      @returns(@code(Width * Height) samples, row by row from the top.)
      @raises(EGeoTiffError if the samples are not unsigned 8-bit, or the
        image cannot be decoded.) }
    function ReadUInt8(AIndex: Integer = 0): TArray<Byte>;

    { The images in the file: the full image first, then its overviews,
      largest first, as written. }
    property Images[AIndex: Integer]: TGeoTiffImage read GetImage;

    { How many images the file holds. }
    property ImageCount: Integer read GetImageCount;
  end;

{ Decodes TIFF's LZW compression: codes of 9 to 12 bits, most significant
  bit first, with the code width growing one code early, as libtiff
  writes.
  @param(ASource The compressed bytes.)
  @param(ASourceLength How many of them to read.)
  @param(ADest Receives the decoded bytes; it must hold @code(ADestLength)
    bytes. Anything the data does not fill is left as it was.)
  @param(ADestLength How many bytes to decode at most.)
  @returns(How many bytes were decoded.)
  @raises(EGeoTiffError if the data holds a code that cannot occur.) }
function LzwDecode(const ASource: TBytes; ASourceLength: Integer; var ADest: TBytes;
  ADestLength: Integer): Integer;

{ Decodes PackBits compression.
  @param(ASource The compressed bytes.)
  @param(ASourceLength How many of them to read.)
  @param(ADest Receives the decoded bytes; it must hold @code(ADestLength)
    bytes.)
  @param(ADestLength How many bytes to decode at most.)
  @returns(How many bytes were decoded.) }
function PackBitsDecode(const ASource: TBytes; ASourceLength: Integer; var ADest: TBytes;
  ADestLength: Integer): Integer;

implementation

uses
  System.Math, System.ZLib;

const
  { TIFF tag: NewSubfileType; bit 0 marks a reduced-resolution image. }
  TAG_NEW_SUBFILE_TYPE = 254;
  { TIFF tag: ImageWidth. }
  TAG_IMAGE_WIDTH = 256;
  { TIFF tag: ImageLength. }
  TAG_IMAGE_LENGTH = 257;
  { TIFF tag: BitsPerSample. }
  TAG_BITS_PER_SAMPLE = 258;
  { TIFF tag: Compression. }
  TAG_COMPRESSION = 259;
  { TIFF tag: StripOffsets. }
  TAG_STRIP_OFFSETS = 273;
  { TIFF tag: SamplesPerPixel. }
  TAG_SAMPLES_PER_PIXEL = 277;
  { TIFF tag: RowsPerStrip. }
  TAG_ROWS_PER_STRIP = 278;
  { TIFF tag: StripByteCounts. }
  TAG_STRIP_BYTE_COUNTS = 279;
  { TIFF tag: Predictor. }
  TAG_PREDICTOR = 317;
  { TIFF tag: TileWidth. }
  TAG_TILE_WIDTH = 322;
  { TIFF tag: TileLength. }
  TAG_TILE_LENGTH = 323;
  { TIFF tag: TileOffsets. }
  TAG_TILE_OFFSETS = 324;
  { TIFF tag: TileByteCounts. }
  TAG_TILE_BYTE_COUNTS = 325;
  { TIFF tag: SampleFormat. }
  TAG_SAMPLE_FORMAT = 339;
  { GeoTIFF tag: ModelPixelScale, three doubles. }
  TAG_MODEL_PIXEL_SCALE = 33550;
  { GeoTIFF tag: ModelTiepoint, six doubles for each tie point. }
  TAG_MODEL_TIEPOINT = 33922;
  { GeoTIFF tag: ModelTransformation, sixteen doubles. }
  TAG_MODEL_TRANSFORMATION = 34264;
  { GeoTIFF tag: GeoKeyDirectory, shorts. }
  TAG_GEO_KEY_DIRECTORY = 34735;
  { GDAL's tag for the no-data value, as text. }
  TAG_GDAL_NODATA = 42113;

  { GeoTIFF key: GTRasterTypeGeoKey; 1 pixel is area, 2 pixel is point. }
  KEY_RASTER_TYPE = 1025;
  { GeoTIFF key: GeographicTypeGeoKey, an EPSG code. }
  KEY_GEOGRAPHIC_TYPE = 2048;
  { GTRasterTypeGeoKey's value for pixel is point. }
  RASTER_PIXEL_IS_POINT = 2;

  { TIFF field types: BYTE. }
  TYPE_BYTE = 1;
  { ASCII. }
  TYPE_ASCII = 2;
  { SHORT. }
  TYPE_SHORT = 3;
  { LONG. }
  TYPE_LONG = 4;
  { RATIONAL. }
  TYPE_RATIONAL = 5;
  { SBYTE. }
  TYPE_SBYTE = 6;
  { UNDEFINED. }
  TYPE_UNDEFINED = 7;
  { SSHORT. }
  TYPE_SSHORT = 8;
  { SLONG. }
  TYPE_SLONG = 9;
  { SRATIONAL. }
  TYPE_SRATIONAL = 10;
  { FLOAT. }
  TYPE_FLOAT = 11;
  { DOUBLE. }
  TYPE_DOUBLE = 12;

  { Most image directories read, against a file whose directories loop. }
  MAX_DIRECTORIES = 1000;

  { LZW: the code that resets the table. }
  LZW_CLEAR = 256;
  { LZW: the code that ends the data. }
  LZW_END = 257;
  { LZW: the first code the table assigns. }
  LZW_FIRST = 258;
  { LZW: the largest code. }
  LZW_MAX = 4095;

type
  { One entry of an image directory, with its value or values still in
    the file's byte order. }
  TIfdEntry = record
    { The tag. }
    Tag: Word;
    { The field type, such as @link(TYPE_SHORT). }
    FieldType: Word;
    { How many values. }
    Count: Cardinal;
    { The values' bytes. }
    Data: TBytes;
  end;

{ Bytes in one value of a TIFF field type.
  @param(AType The field type.)
  @returns(Its size; 0 for a type this unit does not know.) }
function TypeSize(AType: Word): Integer;
begin
  case AType of
    TYPE_BYTE, TYPE_ASCII, TYPE_SBYTE, TYPE_UNDEFINED: Result := 1;
    TYPE_SHORT, TYPE_SSHORT: Result := 2;
    TYPE_LONG, TYPE_SLONG, TYPE_FLOAT: Result := 4;
    TYPE_RATIONAL, TYPE_SRATIONAL, TYPE_DOUBLE: Result := 8;
  else
    Result := 0;
  end;
end;

function LzwDecode(const ASource: TBytes; ASourceLength: Integer; var ADest: TBytes;
  ADestLength: Integer): Integer;
var
  // Each code's string lies in what has been decoded already, so a code
  // is just where its string starts in ADest and how long it is
  LStart, LLength: array[LZW_FIRST..LZW_MAX] of Integer;
  LBits: Cardinal;
  LBitCount, LInPos, LWidth, LNext, LCode, LOut: Integer;
  LOldStart, LOldLength, LStringStart, LStringLength, I: Integer;
  LHaveOld: Boolean;
begin
  LInPos := 0;
  LBits := 0;
  LBitCount := 0;
  LOut := 0;
  LWidth := 9;
  LNext := LZW_FIRST;
  LHaveOld := False;
  LOldStart := 0;
  LOldLength := 0;
  ASourceLength := Min(ASourceLength, Length(ASource));
  ADestLength := Min(ADestLength, Length(ADest));

  while LOut < ADestLength do
  begin
    // The next code, most significant bit first
    while LBitCount < LWidth do
    begin
      if LInPos >= ASourceLength then
        Exit(LOut);
      LBits := (LBits shl 8) or ASource[LInPos];
      Inc(LInPos);
      Inc(LBitCount, 8);
    end;
    Dec(LBitCount, LWidth);
    LCode := (LBits shr LBitCount) and ((1 shl LWidth) - 1);
    // Bits already used are dropped, so the buffer never overflows
    LBits := LBits and ((1 shl LBitCount) - 1);

    if LCode = LZW_END then
      Break;
    if LCode = LZW_CLEAR then
    begin
      LWidth := 9;
      LNext := LZW_FIRST;
      LHaveOld := False;
      Continue;
    end;

    if LCode < 256 then
    begin
      // A single byte
      ADest[LOut] := Byte(LCode);
      LStringStart := LOut;
      LStringLength := 1;
    end
    else if not LHaveOld then
      raise EGeoTiffError.CreateFmt('LZW code %d before any string', [LCode])
    else if LCode < LNext then
    begin
      // A string in the table, decoded earlier, so it cannot overlap
      LStringLength := Min(LLength[LCode], ADestLength - LOut);
      Move(ADest[LStart[LCode]], ADest[LOut], LStringLength);
      LStringStart := LOut;
    end
    else if LCode = LNext then
    begin
      // The string about to be added: the last one and its own first
      // byte. Copied a byte at a time, as the last byte copies the first
      // byte written.
      LStringLength := Min(LOldLength + 1, ADestLength - LOut);
      for I := 0 to LStringLength - 1 do
        ADest[LOut + I] := ADest[LOldStart + I];
      LStringStart := LOut;
    end
    else
      raise EGeoTiffError.CreateFmt('LZW code %d is not in the table (next %d)',
        [LCode, LNext]);

    // The table gains the last string followed by this one's first byte,
    // which is the last string and the byte after it in ADest
    if LHaveOld and (LNext <= LZW_MAX) then
    begin
      LStart[LNext] := LOldStart;
      LLength[LNext] := LOldLength + 1;
      Inc(LNext);
      // libtiff widens the codes one code before the table needs it
      if (LNext >= (1 shl LWidth) - 1) and (LWidth < 12) then
        Inc(LWidth);
    end;

    LOldStart := LStringStart;
    LOldLength := LStringLength;
    LHaveOld := True;
    Inc(LOut, LStringLength);
  end;
  Result := LOut;
end;

function PackBitsDecode(const ASource: TBytes; ASourceLength: Integer; var ADest: TBytes;
  ADestLength: Integer): Integer;
var
  LInPos, LOut, LCount: Integer;
  LControl: ShortInt;
begin
  LInPos := 0;
  LOut := 0;
  ASourceLength := Min(ASourceLength, Length(ASource));
  ADestLength := Min(ADestLength, Length(ADest));
  while (LOut < ADestLength) and (LInPos < ASourceLength) do
  begin
    LControl := ShortInt(ASource[LInPos]);
    Inc(LInPos);
    if LControl >= 0 then
    begin
      // The next LControl + 1 bytes as they are
      LCount := Min(Min(LControl + 1, ASourceLength - LInPos), ADestLength - LOut);
      Move(ASource[LInPos], ADest[LOut], LCount);
      Inc(LInPos, LControl + 1);
      Inc(LOut, LCount);
    end
    else if LControl <> -128 then
    begin
      // The next byte, 1 - LControl times
      if LInPos >= ASourceLength then
        Break;
      LCount := Min(1 - LControl, ADestLength - LOut);
      FillChar(ADest[LOut], LCount, ASource[LInPos]);
      Inc(LInPos);
      Inc(LOut, LCount);
    end;
    // -128 is a no-op
  end;
  Result := LOut;
end;

{ TGeoTiffImage }

function TGeoTiffImage.BytesPerSample: Integer;
begin
  Result := (BitsPerSample + 7) div 8;
end;

function TGeoTiffImage.BlocksAcross: Integer;
begin
  Result := (Width + BlockWidth - 1) div BlockWidth;
end;

function TGeoTiffImage.BlocksDown: Integer;
begin
  Result := (Height + BlockHeight - 1) div BlockHeight;
end;

{ TGeoTiffGeoreference }

function TGeoTiffGeoreference.West: Double;
begin
  // The left edge is raster column 0 for pixel is area, and half a pixel
  // left of column 0's centre for pixel is point
  Result := TieX - TieI * ScaleX;
  if PixelIsPoint then
    Result := Result - ScaleX / 2;
end;

function TGeoTiffGeoreference.North: Double;
begin
  Result := TieY + TieJ * ScaleY;
  if PixelIsPoint then
    Result := Result + ScaleY / 2;
end;

function TGeoTiffGeoreference.CentreX(AColumn: Double): Double;
begin
  Result := West + (AColumn + 0.5) * ScaleX;
end;

function TGeoTiffGeoreference.CentreY(ARow: Double): Double;
begin
  Result := North - (ARow + 0.5) * ScaleY;
end;

function TGeoTiffGeoreference.Resized(AFullWidth, AFullHeight, AWidth,
  AHeight: Integer): TGeoTiffGeoreference;
begin
  Result := Self;
  if not Valid or (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  Result.TieI := 0;
  Result.TieJ := 0;
  Result.TieX := West;
  Result.TieY := North;
  Result.PixelIsPoint := False;
  Result.ScaleX := ScaleX * AFullWidth / AWidth;
  Result.ScaleY := ScaleY * AFullHeight / AHeight;
end;

{ TGeoTiff }

constructor TGeoTiff.Create(const AFileName: string);
begin
  CreateFromStream(TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite), True);
end;

constructor TGeoTiff.CreateFromStream(AStream: TStream; AOwnsStream: Boolean);
begin
  inherited Create;
  // Kept first, so the destructor frees it if reading raises
  FStream := AStream;
  FOwnsStream := AOwnsStream;
  FSize := FStream.Size;
  ReadDirectories;
end;

destructor TGeoTiff.Destroy;
begin
  if FOwnsStream then
    FStream.Free;
  inherited;
end;

function TGeoTiff.ReadBytes(AOffset, ACount: Int64): TBytes;
begin
  if (AOffset < 0) or (ACount < 0) or (AOffset + ACount > FSize) then
    raise EGeoTiffError.CreateFmt('The file is damaged: %d bytes at %d lie beyond its end (%d)',
      [ACount, AOffset, FSize]);
  SetLength(Result, ACount);
  if ACount > 0 then
  begin
    FStream.Position := AOffset;
    FStream.ReadBuffer(Result[0], ACount);
  end;
end;

function TGeoTiff.GetU16(const ABuffer: TBytes; APosition: Integer): Word;
begin
  if FBigEndian then
    Result := (Word(ABuffer[APosition]) shl 8) or ABuffer[APosition + 1]
  else
    Result := (Word(ABuffer[APosition + 1]) shl 8) or ABuffer[APosition];
end;

function TGeoTiff.GetU32(const ABuffer: TBytes; APosition: Integer): Cardinal;
begin
  if FBigEndian then
    Result := (Cardinal(GetU16(ABuffer, APosition)) shl 16) or GetU16(ABuffer, APosition + 2)
  else
    Result := (Cardinal(GetU16(ABuffer, APosition + 2)) shl 16) or GetU16(ABuffer, APosition);
end;

function TGeoTiff.GetDouble(const ABuffer: TBytes; APosition: Integer): Double;
var
  LBits: UInt64;
begin
  if FBigEndian then
    LBits := (UInt64(GetU32(ABuffer, APosition)) shl 32) or GetU32(ABuffer, APosition + 4)
  else
    LBits := (UInt64(GetU32(ABuffer, APosition + 4)) shl 32) or GetU32(ABuffer, APosition);
  Move(LBits, Result, SizeOf(Result));
end;

procedure TGeoTiff.ReadDirectories;
var
  LHeader, LDirectory: TBytes;
  LOffset: Int64;
  LEntries: TArray<TIfdEntry>;
  LCount, I: Integer;
  LImage: TGeoTiffImage;
  LVisited: TArray<Int64>;

  { The entry for a tag in the directory being read.
    @param(ATag The tag.)
    @param(AEntry Receives the entry.)
    @returns(@true if the directory has it.) }
  function FindEntry(ATag: Word; out AEntry: TIfdEntry): Boolean;
  var
    J: Integer;
  begin
    for J := 0 to High(LEntries) do
      if LEntries[J].Tag = ATag then
      begin
        AEntry := LEntries[J];
        Exit(True);
      end;
    Result := False;
  end;

  { An entry's values as integers.
    @param(AEntry The entry, of a BYTE, SHORT or LONG type, signed or
      not.)
    @returns(The values.)
    @raises(EGeoTiffError for another type.) }
  function Integers(const AEntry: TIfdEntry): TArray<Int64>;
  var
    J: Integer;
  begin
    SetLength(Result, AEntry.Count);
    for J := 0 to Integer(AEntry.Count) - 1 do
      case AEntry.FieldType of
        TYPE_BYTE, TYPE_UNDEFINED: Result[J] := AEntry.Data[J];
        TYPE_SBYTE: Result[J] := ShortInt(AEntry.Data[J]);
        TYPE_SHORT: Result[J] := GetU16(AEntry.Data, J * 2);
        TYPE_SSHORT: Result[J] := SmallInt(GetU16(AEntry.Data, J * 2));
        TYPE_LONG: Result[J] := GetU32(AEntry.Data, J * 4);
        TYPE_SLONG: Result[J] := Integer(GetU32(AEntry.Data, J * 4));
      else
        raise EGeoTiffError.CreateFmt('Tag %d has type %d where a whole number was expected',
          [AEntry.Tag, AEntry.FieldType]);
      end;
  end;

  { A tag's first value as an integer.
    @param(ATag The tag.)
    @param(ADefault The value if the directory does not have it.)
    @returns(The value.) }
  function IntegerTag(ATag: Word; ADefault: Int64): Int64;
  var
    LEntry: TIfdEntry;
    LValues: TArray<Int64>;
  begin
    Result := ADefault;
    if FindEntry(ATag, LEntry) then
    begin
      LValues := Integers(LEntry);
      if Length(LValues) > 0 then
        Result := LValues[0];
    end;
  end;

  { An entry's values as doubles.
    @param(AEntry The entry, of the DOUBLE or FLOAT type.)
    @returns(The values; empty for another type.) }
  function Doubles(const AEntry: TIfdEntry): TArray<Double>;
  var
    J: Integer;
    LSingle: Single;
    LBits: Cardinal;
  begin
    SetLength(Result, 0);
    case AEntry.FieldType of
      TYPE_DOUBLE:
        begin
          SetLength(Result, AEntry.Count);
          for J := 0 to Integer(AEntry.Count) - 1 do
            Result[J] := GetDouble(AEntry.Data, J * 8);
        end;
      TYPE_FLOAT:
        begin
          SetLength(Result, AEntry.Count);
          for J := 0 to Integer(AEntry.Count) - 1 do
          begin
            LBits := GetU32(AEntry.Data, J * 4);
            Move(LBits, LSingle, SizeOf(LSingle));
            Result[J] := LSingle;
          end;
        end;
    end;
  end;

  { Reads the GeoTIFF tags of the directory just read into
    @link(FGeoreference). }
  procedure ReadGeoreference;
  var
    LEntry: TIfdEntry;
    LValues: TArray<Double>;
    LKeys: TArray<Int64>;
    LText: string;
    LValue: Double;
    K: Integer;
  begin
    FGeoreference := Default(TGeoTiffGeoreference);
    if FindEntry(TAG_MODEL_PIXEL_SCALE, LEntry) then
    begin
      LValues := Doubles(LEntry);
      if Length(LValues) >= 2 then
      begin
        FGeoreference.ScaleX := LValues[0];
        FGeoreference.ScaleY := LValues[1];
      end;
    end;
    if FindEntry(TAG_MODEL_TIEPOINT, LEntry) then
    begin
      LValues := Doubles(LEntry);
      if Length(LValues) >= 6 then
      begin
        FGeoreference.TieI := LValues[0];
        FGeoreference.TieJ := LValues[1];
        FGeoreference.TieX := LValues[3];
        FGeoreference.TieY := LValues[4];
        FGeoreference.Valid := (FGeoreference.ScaleX <> 0) and (FGeoreference.ScaleY <> 0);
      end;
    end;
    // A transformation matrix instead, as long as it does not rotate
    if not FGeoreference.Valid and FindEntry(TAG_MODEL_TRANSFORMATION, LEntry) then
    begin
      LValues := Doubles(LEntry);
      if (Length(LValues) >= 8) and (LValues[1] = 0) and (LValues[4] = 0) and
         (LValues[0] <> 0) and (LValues[5] <> 0) then
      begin
        FGeoreference.ScaleX := LValues[0];
        FGeoreference.ScaleY := -LValues[5];
        FGeoreference.TieX := LValues[3];
        FGeoreference.TieY := LValues[7];
        FGeoreference.Valid := True;
      end;
    end;
    // Header of four shorts, then four for each key: its ID, where its
    // value is (0 for in the key itself), how many values, and the value
    if FindEntry(TAG_GEO_KEY_DIRECTORY, LEntry) then
    begin
      LKeys := Integers(LEntry);
      K := 4;
      while K + 3 < Length(LKeys) do
      begin
        if LKeys[K + 1] = 0 then
          case Integer(LKeys[K]) of
            KEY_RASTER_TYPE: FGeoreference.PixelIsPoint := LKeys[K + 3] = RASTER_PIXEL_IS_POINT;
            KEY_GEOGRAPHIC_TYPE: FGeoreference.GeographicType := Integer(LKeys[K + 3]);
          end;
        Inc(K, 4);
      end;
    end;
    if FindEntry(TAG_GDAL_NODATA, LEntry) and (LEntry.FieldType = TYPE_ASCII) then
    begin
      LText := TEncoding.ANSI.GetString(LEntry.Data).Trim([#0, ' ']);
      if TryStrToFloat(LText, LValue, TFormatSettings.Invariant) then
      begin
        FGeoreference.HasNoData := True;
        FGeoreference.NoData := LValue;
      end;
    end;
  end;

  { Reads every entry of the directory at LOffset into LEntries. }
  procedure ReadEntries;
  var
    J: Integer;
    LPos: Integer;
    LSize, LValueOffset: Int64;
  begin
    LDirectory := ReadBytes(LOffset, 2);
    LCount := GetU16(LDirectory, 0);
    LDirectory := ReadBytes(LOffset + 2, Int64(LCount) * 12 + 4);
    SetLength(LEntries, LCount);
    for J := 0 to LCount - 1 do
    begin
      LPos := J * 12;
      LEntries[J].Tag := GetU16(LDirectory, LPos);
      LEntries[J].FieldType := GetU16(LDirectory, LPos + 2);
      LEntries[J].Count := GetU32(LDirectory, LPos + 4);
      LSize := TypeSize(LEntries[J].FieldType) * Int64(LEntries[J].Count);
      if LSize <= 4 then
        // The value is in the entry itself
        LEntries[J].Data := Copy(LDirectory, LPos + 8, 4)
      else
      begin
        LValueOffset := GetU32(LDirectory, LPos + 8);
        LEntries[J].Data := ReadBytes(LValueOffset, LSize);
      end;
    end;
  end;

var
  LEntry, LByteEntry: TIfdEntry;
  LMagic: Word;
begin
  LHeader := ReadBytes(0, 8);
  if (LHeader[0] = Ord('I')) and (LHeader[1] = Ord('I')) then
    FBigEndian := False
  else if (LHeader[0] = Ord('M')) and (LHeader[1] = Ord('M')) then
    FBigEndian := True
  else
    raise EGeoTiffError.Create('Not a TIFF file');
  LMagic := GetU16(LHeader, 2);
  if LMagic = 43 then
    raise EGeoTiffError.Create('BigTIFF files are not supported');
  if LMagic <> 42 then
    raise EGeoTiffError.Create('Not a TIFF file');

  LOffset := GetU32(LHeader, 4);
  SetLength(FImages, 0);
  SetLength(LVisited, 0);
  while LOffset <> 0 do
  begin
    for I := 0 to High(LVisited) do
      if LVisited[I] = LOffset then
        raise EGeoTiffError.Create('The file is damaged: its image directories loop');
    if Length(LVisited) >= MAX_DIRECTORIES then
      raise EGeoTiffError.Create('The file has too many image directories');
    LVisited := LVisited + [LOffset];

    ReadEntries;
    if Length(FImages) = 0 then
      ReadGeoreference;

    LImage := Default(TGeoTiffImage);
    LImage.Width := Integer(IntegerTag(TAG_IMAGE_WIDTH, 0));
    LImage.Height := Integer(IntegerTag(TAG_IMAGE_LENGTH, 0));
    LImage.BitsPerSample := Integer(IntegerTag(TAG_BITS_PER_SAMPLE, 1));
    LImage.SampleFormat := Integer(IntegerTag(TAG_SAMPLE_FORMAT, SAMPLE_FORMAT_UNSIGNED));
    LImage.SamplesPerPixel := Integer(IntegerTag(TAG_SAMPLES_PER_PIXEL, 1));
    LImage.Compression := Integer(IntegerTag(TAG_COMPRESSION, COMPRESSION_NONE));
    LImage.Predictor := Integer(IntegerTag(TAG_PREDICTOR, 1));
    LImage.IsOverview := (IntegerTag(TAG_NEW_SUBFILE_TYPE, 0) and 1) <> 0;
    if FindEntry(TAG_TILE_OFFSETS, LEntry) then
    begin
      LImage.Tiled := True;
      LImage.BlockWidth := Integer(IntegerTag(TAG_TILE_WIDTH, 0));
      LImage.BlockHeight := Integer(IntegerTag(TAG_TILE_LENGTH, 0));
      if not FindEntry(TAG_TILE_BYTE_COUNTS, LByteEntry) then
        raise EGeoTiffError.Create('The file is damaged: tiles without their sizes');
    end
    else if FindEntry(TAG_STRIP_OFFSETS, LEntry) then
    begin
      LImage.Tiled := False;
      LImage.BlockWidth := LImage.Width;
      // RowsPerStrip is often 2^32 - 1, meaning one strip for the image
      LImage.BlockHeight := Integer(Min(IntegerTag(TAG_ROWS_PER_STRIP, LImage.Height),
        Int64(LImage.Height)));
      if not FindEntry(TAG_STRIP_BYTE_COUNTS, LByteEntry) then
        raise EGeoTiffError.Create('The file is damaged: strips without their sizes');
    end
    else
      raise EGeoTiffError.Create('The file has an image with neither tiles nor strips');
    if (LImage.Width <= 0) or (LImage.Height <= 0) or (LImage.BlockWidth <= 0) or
       (LImage.BlockHeight <= 0) then
      raise EGeoTiffError.Create('The file has an image with no size');
    LImage.Offsets := Integers(LEntry);
    LImage.ByteCounts := Integers(LByteEntry);
    if (Length(LImage.Offsets) < LImage.BlocksAcross * LImage.BlocksDown) or
       (Length(LImage.ByteCounts) < Length(LImage.Offsets)) then
      raise EGeoTiffError.Create('The file is damaged: an image is missing tiles or strips');
    FImages := FImages + [LImage];

    LOffset := GetU32(LDirectory, LCount * 12);
  end;
  if Length(FImages) = 0 then
    raise EGeoTiffError.Create('The file holds no images');
end;

function TGeoTiff.GetImage(AIndex: Integer): TGeoTiffImage;
begin
  if (AIndex < 0) or (AIndex > High(FImages)) then
    raise EGeoTiffError.CreateFmt('The file has no image %d', [AIndex]);
  Result := FImages[AIndex];
end;

function TGeoTiff.GetImageCount: Integer;
begin
  Result := Length(FImages);
end;

function TGeoTiff.Georeference(AIndex: Integer): TGeoTiffGeoreference;
var
  LImage: TGeoTiffImage;
begin
  LImage := GetImage(AIndex);
  if AIndex = 0 then
    Result := FGeoreference
  else
    Result := FGeoreference.Resized(FImages[0].Width, FImages[0].Height, LImage.Width,
      LImage.Height);
end;

procedure TGeoTiff.DecodeBlock(const AImage: TGeoTiffImage; ABlock: Integer;
  var ABuffer: TBytes; ACount: Integer);
var
  LSource: TBytes;
  LOut: Pointer;
  LOutSize: Integer;
  LSwap: Byte;
  I: Integer;
begin
  FillChar(ABuffer[0], ACount, 0);
  // A tile or strip never written reads as zeros, as GDAL's sparse files
  if (AImage.Offsets[ABlock] = 0) or (AImage.ByteCounts[ABlock] = 0) then
    Exit;
  LSource := ReadBytes(AImage.Offsets[ABlock], AImage.ByteCounts[ABlock]);
  case AImage.Compression of
    COMPRESSION_NONE:
      Move(LSource[0], ABuffer[0], Min(ACount, Length(LSource)));
    COMPRESSION_LZW:
      LzwDecode(LSource, Length(LSource), ABuffer, ACount);
    COMPRESSION_PACKBITS:
      PackBitsDecode(LSource, Length(LSource), ABuffer, ACount);
    COMPRESSION_DEFLATE, COMPRESSION_DEFLATE_OLD:
      begin
        LOut := nil;
        try
          ZDecompress(@LSource[0], Length(LSource), LOut, LOutSize, ACount);
          Move(LOut^, ABuffer[0], Min(ACount, LOutSize));
        finally
          FreeMem(LOut);
        end;
      end;
  else
    raise EGeoTiffError.CreateFmt('Compression %d is not supported', [AImage.Compression]);
  end;
  // Samples of more than a byte come in the file's byte order; this
  // machine is little-endian on every platform Delphi targets
  if FBigEndian and (AImage.BytesPerSample = 2) then
  begin
    I := 0;
    while I + 1 < ACount do
    begin
      LSwap := ABuffer[I];
      ABuffer[I] := ABuffer[I + 1];
      ABuffer[I + 1] := LSwap;
      Inc(I, 2);
    end;
  end;
end;

procedure TGeoTiff.ReadInto(AIndex: Integer; ADest: Pointer);
var
  LImage: TGeoTiffImage;
  LBuffer: TBytes;
  LBytes, LRowBytes, LBlockRows: Integer;
  LAcross, LBlockX, LBlockY, LX0, LY0, LCopyWidth, LCopyRows, LRow, LX: Integer;
  LRowStart: Integer;
  LDest: PByte;
  LWord: PWord;
begin
  LImage := GetImage(AIndex);
  if LImage.SamplesPerPixel <> 1 then
    raise EGeoTiffError.CreateFmt('Images with %d samples per pixel are not supported',
      [LImage.SamplesPerPixel]);
  if (LImage.BitsPerSample <> 8) and (LImage.BitsPerSample <> 16) then
    raise EGeoTiffError.CreateFmt('%d-bit samples are not supported', [LImage.BitsPerSample]);
  if LImage.SampleFormat = SAMPLE_FORMAT_FLOAT then
    raise EGeoTiffError.Create('Floating-point samples are not supported');
  if (LImage.Predictor <> 1) and (LImage.Predictor <> 2) then
    raise EGeoTiffError.CreateFmt('Predictor %d is not supported', [LImage.Predictor]);

  LBytes := LImage.BytesPerSample;
  LRowBytes := LImage.BlockWidth * LBytes;
  LAcross := LImage.BlocksAcross;
  SetLength(LBuffer, LRowBytes * LImage.BlockHeight);
  LDest := ADest;

  for LBlockY := 0 to LImage.BlocksDown - 1 do
    for LBlockX := 0 to LAcross - 1 do
    begin
      LX0 := LBlockX * LImage.BlockWidth;
      LY0 := LBlockY * LImage.BlockHeight;
      // A tile is always whole, padded past the image's edge; the last
      // strip holds only the rows left
      if LImage.Tiled then
        LBlockRows := LImage.BlockHeight
      else
        LBlockRows := Min(LImage.BlockHeight, LImage.Height - LY0);
      DecodeBlock(LImage, LBlockY * LAcross + LBlockX, LBuffer, LRowBytes * LBlockRows);

      if LImage.Predictor = 2 then
        // Each sample was stored as the change from the one to its left
        for LRow := 0 to LBlockRows - 1 do
        begin
          LRowStart := LRow * LRowBytes;
          if LBytes = 1 then
            for LX := 1 to LImage.BlockWidth - 1 do
              LBuffer[LRowStart + LX] := Byte(LBuffer[LRowStart + LX] +
                LBuffer[LRowStart + LX - 1])
          else
            for LX := 1 to LImage.BlockWidth - 1 do
            begin
              LWord := PWord(@LBuffer[LRowStart + LX * 2]);
              LWord^ := Word((Cardinal(LWord^) +
                PWord(@LBuffer[LRowStart + (LX - 1) * 2])^) and $FFFF);
            end;
        end;

      // The part of the block inside the image
      LCopyWidth := Min(LImage.BlockWidth, LImage.Width - LX0);
      LCopyRows := Min(LBlockRows, LImage.Height - LY0);
      for LRow := 0 to LCopyRows - 1 do
        Move(LBuffer[LRow * LRowBytes],
          (LDest + (NativeInt(LY0 + LRow) * LImage.Width + LX0) * LBytes)^,
          LCopyWidth * LBytes);
    end;
end;

function TGeoTiff.ReadInt16(AIndex: Integer): TArray<SmallInt>;
var
  LImage: TGeoTiffImage;
begin
  LImage := GetImage(AIndex);
  if (LImage.BitsPerSample <> 16) or (LImage.SampleFormat <> SAMPLE_FORMAT_SIGNED) then
    raise EGeoTiffError.CreateFmt('Image %d does not hold signed 16-bit samples', [AIndex]);
  SetLength(Result, NativeInt(LImage.Width) * LImage.Height);
  ReadInto(AIndex, @Result[0]);
end;

function TGeoTiff.ReadUInt8(AIndex: Integer): TArray<Byte>;
var
  LImage: TGeoTiffImage;
begin
  LImage := GetImage(AIndex);
  if (LImage.BitsPerSample <> 8) or (LImage.SampleFormat <> SAMPLE_FORMAT_UNSIGNED) then
    raise EGeoTiffError.CreateFmt('Image %d does not hold unsigned 8-bit samples', [AIndex]);
  SetLength(Result, NativeInt(LImage.Width) * LImage.Height);
  ReadInto(AIndex, @Result[0]);
end;

end.
