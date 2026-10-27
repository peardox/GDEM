{ @abstract(Shrinks an image by a whole factor with a Lanczos-3 filter, in
  linear light, for the best-looking result.)

  Made for building levels of detail, where quality matters more than
  speed:

  @unorderedList(
    @item(@bold(Lanczos-3), widened by the reduction: each output pixel is
      a weighted sum of the source pixels within 3 output pixels of it (6
      source pixels each way when halving, 24 at an eighth). A filter that
      does not widen (like a plain bicubic) lets fine detail alias into
      jagged edges and shimmer when shrinking.)
    @item(@bold(Linear light.) Pixels are stored gamma-encoded (sRGB);
      averaging those numbers directly darkens fine bright detail such as
      ice and cloud edges. Each value is turned into light, filtered, and
      turned back.)
    @item(@bold(Alpha) is filtered premultiplied, so transparent pixels do
      not bleed their colour into their neighbours.)
    @item(@bold(Edges.) Off the top and bottom the nearest row is used.
      Off the left and right either the nearest column is used or, for a
      map of the whole world, the image wraps round, since its left and
      right edges are neighbours.)
  )

  The factor is a whole number, so every output pixel sits at the same
  place among its source pixels and one set of weights serves the whole
  image. The filter is separable: each source row is filtered across once
  and kept in a small ring of rows, which the output rows are then
  filtered down from.

  This unit uses nothing but the run-time library, so any program can use
  it. }
unit GDEMResample;

interface

uses
  System.SysUtils;

const
  { Lanczos-3's reach: output pixels within this many of a point affect
    it. }
  LANCZOS_LOBES = 3;

  { How @link(ReduceImage) resamples, for recording alongside its output. }
  RESAMPLING_DESCRIPTION = 'lanczos3, linear light';

type
  { @abstract(An image in memory: 8-bit red, green, blue and alpha, rows
    top to bottom, alpha not premultiplied.) }
  TRGBA8Image = record
    { Width, in pixels. }
    Width: Integer;
    { Height, in pixels. }
    Height: Integer;
    { The pixels: 4 bytes each, R, G, B, A, @code(Width * 4) bytes a row,
      top row first. }
    Pixels: TBytes;

    { Makes an image of a size, every pixel transparent black.
      @param(AWidth Width, in pixels.)
      @param(AHeight Height, in pixels.)
      @returns(The image.) }
    class function Create(AWidth, AHeight: Integer): TRGBA8Image; static;

    { Bytes in one row of pixels.
      @returns(@code(Width * 4).) }
    function RowBytes: NativeUInt;

    { The address of a pixel, for handing the pixels to an encoder.
      @param(AX Column, 0 at the left.)
      @param(AY Row, 0 at the top.)
      @returns(A pointer to its red byte.) }
    function PixelAddress(AX, AY: Integer): Pointer;
  end;

  { Reports progress through @link(ReduceImage). It may raise an exception,
    such as a cancellation, to stop the work.
    @param(ADone Output rows finished.)
    @param(ATotal Output rows in all.) }
  TResampleProgressEvent = reference to procedure(ADone, ATotal: Integer);

{ Shrinks an image by a whole factor, with a Lanczos-3 filter in linear
  light.
  @param(ASource The image. Its width and height must be multiples of
    AFactor.)
  @param(AFactor How many times smaller to make it, 1 or more; 1 returns a
    copy.)
  @param(AWrapX @true if the left and right edges are neighbours, as for a
    map of the whole world; @false to treat them as edges.)
  @param(AOnProgress Called after each output row. May be @nil.)
  @returns(The smaller image, @code(ASource.Width div AFactor) by
    @code(ASource.Height div AFactor).)
  @raises(EArgumentException if the factor does not divide the size.) }
function ReduceImage(const ASource: TRGBA8Image; AFactor: Integer; AWrapX: Boolean;
  const AOnProgress: TResampleProgressEvent = nil): TRGBA8Image;

{ The Lanczos-3 weight at a distance, in output pixels.
  @param(AX The distance.)
  @returns(@code(sinc(x) * sinc(x / 3)) inside 3, otherwise 0.) }
function Lanczos3(AX: Double): Double;

implementation

uses
  System.Math;

const
  { Steps in the table that turns light back into sRGB values: fine enough
    that even the darkest values come out exact. }
  ENCODE_STEPS = 65535;

var
  { Light (0 to 1) for each 8-bit sRGB value. }
  DecodeTable: array[Byte] of Single;
  { The 8-bit sRGB value for each step of light from 0 to 1. }
  EncodeTable: array[0..ENCODE_STEPS] of Byte;

{ Fills @link(DecodeTable) and @link(EncodeTable) from the sRGB curve. }
procedure BuildTables;
var
  LIndex: Integer;
  LValue, LLight: Double;
begin
  for LIndex := 0 to 255 do
  begin
    LValue := LIndex / 255;
    if LValue <= 0.04045 then
      DecodeTable[LIndex] := LValue / 12.92
    else
      DecodeTable[LIndex] := Power((LValue + 0.055) / 1.055, 2.4);
  end;
  for LIndex := 0 to ENCODE_STEPS do
  begin
    LLight := LIndex / ENCODE_STEPS;
    if LLight <= 0.0031308 then
      LValue := LLight * 12.92
    else
      LValue := 1.055 * Power(LLight, 1 / 2.4) - 0.055;
    EncodeTable[LIndex] := EnsureRange(Round(LValue * 255), 0, 255);
  end;
end;

{ TRGBA8Image }

class function TRGBA8Image.Create(AWidth, AHeight: Integer): TRGBA8Image;
begin
  Result.Width := AWidth;
  Result.Height := AHeight;
  SetLength(Result.Pixels, Int64(AWidth) * AHeight * 4);
end;

function TRGBA8Image.RowBytes: NativeUInt;
begin
  Result := NativeUInt(Width) * 4;
end;

function TRGBA8Image.PixelAddress(AX, AY: Integer): Pointer;
begin
  Result := @Pixels[(Int64(AY) * Width + AX) * 4];
end;

function Lanczos3(AX: Double): Double;
var
  LPiX: Double;
begin
  AX := Abs(AX);
  if AX < 1e-12 then
    Exit(1);
  if AX >= LANCZOS_LOBES then
    Exit(0);
  LPiX := Pi * AX;
  Result := LANCZOS_LOBES * Sin(LPiX) * Sin(LPiX / LANCZOS_LOBES) / (LPiX * LPiX);
end;

{ The weights for shrinking by a whole factor, and where they start
  relative to the first source pixel of an output pixel's own block.
  @param(AFactor The factor.)
  @param(AFirst Receives the offset of the first weight: source pixel
    @code(output * AFactor + AFirst).)
  @returns(The weights, adding up to 1.) }
function ReductionWeights(AFactor: Integer; out AFirst: Integer): TArray<Single>;
var
  LCentre, LReach, LSum: Double;
  LLast, LTap: Integer;
  LWeights: TArray<Double>;
begin
  // An output pixel's centre, measured from the first source pixel of its
  // block: (output + 0.5) * factor - 0.5
  LCentre := (AFactor - 1) / 2;
  LReach := LANCZOS_LOBES * AFactor;
  AFirst := Ceil(LCentre - LReach);
  LLast := Floor(LCentre + LReach);
  SetLength(LWeights, LLast - AFirst + 1);
  LSum := 0;
  for LTap := 0 to High(LWeights) do
  begin
    // Distance in output pixels, so the filter widens with the factor
    LWeights[LTap] := Lanczos3((AFirst + LTap - LCentre) / AFactor);
    LSum := LSum + LWeights[LTap];
  end;
  SetLength(Result, Length(LWeights));
  for LTap := 0 to High(LWeights) do
    Result[LTap] := LWeights[LTap] / LSum;
end;

function ReduceImage(const ASource: TRGBA8Image; AFactor: Integer; AWrapX: Boolean;
  const AOnProgress: TResampleProgressEvent): TRGBA8Image;
var
  LWeights: TArray<Single>;
  LFirst, LTaps, LOutWidth, LOutHeight: Integer;
  // Source rows filtered across, premultiplied light, 4 values a pixel
  LRing: TArray<TArray<Single>>;
  // Which source row each slot of LRing holds; -1 when empty
  LRingRow: TArray<Integer>;
  // Source column for each output column and tap, after wrapping or
  // clamping
  LColumns: TArray<Integer>;
  LOutY, LOutX, LTap, LSourceY, LSlot, LIndex: Integer;
  LRow: TArray<Single>;
  LRed, LGreen, LBlue, LAlpha, LWeight: Single;
  LOut: PByte;

  { Filters one source row across into a ring slot, unless it is there
    already.
    @param(ARow The source row, already kept inside the image.)
    @returns(The slot holding it.) }
  function FilteredRow(ARow: Integer): Integer;
  var
    LX, LT, LSource: Integer;
    LR, LG, LB, LA, LW, LA8: Single;
    LPixel: PByte;
    LLine: TArray<Single>;
  begin
    Result := ARow mod LTaps;
    if LRingRow[Result] = ARow then
      Exit;
    LLine := LRing[Result];
    for LX := 0 to LOutWidth - 1 do
    begin
      LR := 0;
      LG := 0;
      LB := 0;
      LA := 0;
      for LT := 0 to LTaps - 1 do
      begin
        LSource := LColumns[LX * LTaps + LT];
        LPixel := @ASource.Pixels[(Int64(ARow) * ASource.Width + LSource) * 4];
        LW := LWeights[LT];
        LA8 := LPixel[3] / 255;
        // Premultiplied light: colour weighted by how opaque it is
        LR := LR + LW * DecodeTable[LPixel[0]] * LA8;
        LG := LG + LW * DecodeTable[LPixel[1]] * LA8;
        LB := LB + LW * DecodeTable[LPixel[2]] * LA8;
        LA := LA + LW * LA8;
      end;
      LLine[LX * 4] := LR;
      LLine[LX * 4 + 1] := LG;
      LLine[LX * 4 + 2] := LB;
      LLine[LX * 4 + 3] := LA;
    end;
    LRingRow[Result] := ARow;
  end;

  { Turns filtered light back into an 8-bit sRGB value. Lanczos's negative
    lobes can overshoot a little either way, so the light is kept to 0
    to 1.
    @param(ALight The light.)
    @returns(The value.) }
  function Encode(ALight: Single): Byte;
  begin
    Result := EncodeTable[EnsureRange(Round(ALight * ENCODE_STEPS), 0, ENCODE_STEPS)];
  end;

begin
  if (AFactor < 1) or (ASource.Width mod AFactor <> 0) or (ASource.Height mod AFactor <> 0) then
    raise EArgumentException.CreateFmt('Cannot shrink %d x %d by %d',
      [ASource.Width, ASource.Height, AFactor]);
  if AFactor = 1 then
  begin
    Result := ASource;
    Result.Pixels := Copy(ASource.Pixels);
    Exit;
  end;

  LOutWidth := ASource.Width div AFactor;
  LOutHeight := ASource.Height div AFactor;
  Result := TRGBA8Image.Create(LOutWidth, LOutHeight);
  LWeights := ReductionWeights(AFactor, LFirst);
  LTaps := Length(LWeights);

  // Where each tap of each output column reads from
  SetLength(LColumns, LOutWidth * LTaps);
  for LOutX := 0 to LOutWidth - 1 do
    for LTap := 0 to LTaps - 1 do
    begin
      LIndex := LOutX * AFactor + LFirst + LTap;
      if AWrapX then
      begin
        LIndex := LIndex mod ASource.Width;
        if LIndex < 0 then
          Inc(LIndex, ASource.Width);
      end
      else
        LIndex := EnsureRange(LIndex, 0, ASource.Width - 1);
      LColumns[LOutX * LTaps + LTap] := LIndex;
    end;

  // One slot per tap: the rows one output row needs are all different
  // modulo the tap count, and moving down keeps those still needed
  SetLength(LRing, LTaps);
  SetLength(LRingRow, LTaps);
  for LSlot := 0 to LTaps - 1 do
  begin
    SetLength(LRing[LSlot], LOutWidth * 4);
    LRingRow[LSlot] := -1;
  end;

  for LOutY := 0 to LOutHeight - 1 do
  begin
    LOut := Result.PixelAddress(0, LOutY);
    for LOutX := 0 to LOutWidth - 1 do
    begin
      LRed := 0;
      LGreen := 0;
      LBlue := 0;
      LAlpha := 0;
      for LTap := 0 to LTaps - 1 do
      begin
        // Rows off the top or bottom repeat the edge row
        LSourceY := EnsureRange(LOutY * AFactor + LFirst + LTap, 0, ASource.Height - 1);
        LRow := LRing[FilteredRow(LSourceY)];
        LWeight := LWeights[LTap];
        LRed := LRed + LWeight * LRow[LOutX * 4];
        LGreen := LGreen + LWeight * LRow[LOutX * 4 + 1];
        LBlue := LBlue + LWeight * LRow[LOutX * 4 + 2];
        LAlpha := LAlpha + LWeight * LRow[LOutX * 4 + 3];
      end;
      LAlpha := EnsureRange(LAlpha, 0, 1);
      if LAlpha > 0 then
      begin
        // Back from premultiplied
        LOut[0] := Encode(LRed / LAlpha);
        LOut[1] := Encode(LGreen / LAlpha);
        LOut[2] := Encode(LBlue / LAlpha);
      end
      else
      begin
        LOut[0] := 0;
        LOut[1] := 0;
        LOut[2] := 0;
      end;
      LOut[3] := Round(LAlpha * 255);
      Inc(LOut, 4);
    end;
    if Assigned(AOnProgress) then
      AOnProgress(LOutY + 1, LOutHeight);
  end;
end;

initialization
  BuildTables;

end.
