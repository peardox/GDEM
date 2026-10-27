{ @abstract(GeoTiffCheck: decodes GeoTIFF files with GDEMGeoTiff and prints
  what it found, to check the reader against known answers.)

  Usage, from a command prompt or terminal:

  @preformatted(
GeoTiffCheck file.tif [file.tif ...]
  )

  For each file it prints where the image lies, then one line for each
  image (the full image, then its overviews): its size, the smallest and
  largest sample, how many samples are -9999 (ASTER GDEM's void), an
  FNV-1a checksum of the decoded samples as little-endian bytes, and how
  long decoding took. The checksums of a correct decoding match those
  libtiff gives; CLAUDE.md lists them for the two ASTER tiles in
  peardox/volatile's @code(img) folder.

  A console program with no FMX; it builds for Windows, macOS and Linux.
  Open this .dpr in Delphi and the IDE makes its project file. }
program GeoTiffCheck;

{$APPTYPE CONSOLE}
// FNV-1a wraps round 32 bits on purpose
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

uses
  System.SysUtils, System.StrUtils, System.Diagnostics,
  GDEMGeoTiff in '..\..\common\GDEMGeoTiff.pas';

{ FNV-1a, 32 bits, of a block of memory.
  @param(AData The first byte.)
  @param(ACount How many bytes.)
  @returns(The checksum.) }
function Fnv1a(AData: PByte; ACount: NativeInt): Cardinal;
var
  I: NativeInt;
begin
  Result := 2166136261;
  for I := 0 to ACount - 1 do
    Result := Cardinal((Result xor AData[I]) * 16777619);
end;

{ Decodes every image of one file and prints a line for each.
  @param(AFileName The file.) }
procedure CheckFile(const AFileName: string);
var
  LTiff: TGeoTiff;
  LImage: TGeoTiffImage;
  LGeo: TGeoTiffGeoreference;
  LData: TBytes;
  LCount, I: NativeInt;
  LIndex, LMin, LMax, LValue, LVoids: Integer;
  LWatch: TStopwatch;
  LInvariant: TFormatSettings;
begin
  LInvariant := TFormatSettings.Invariant;
  Writeln(ExtractFileName(AFileName));
  LTiff := TGeoTiff.Create(AFileName);
  try
    LGeo := LTiff.Georeference(0);
    if LGeo.Valid then
      Writeln(Format('  first pixel centre %.6f, %.6f; pixel %.9f x %.9f; EPSG %d; %s',
        [LGeo.CentreX(0), LGeo.CentreY(0), LGeo.ScaleX, LGeo.ScaleY, LGeo.GeographicType,
         IfThen(LGeo.PixelIsPoint, 'pixel is point', 'pixel is area')], LInvariant))
    else
      Writeln('  no georeference');
    for LIndex := 0 to LTiff.ImageCount - 1 do
    begin
      LImage := LTiff.Images[LIndex];
      LCount := NativeInt(LImage.Width) * LImage.Height;
      SetLength(LData, LCount * LImage.BytesPerSample);
      LWatch := TStopwatch.StartNew;
      LTiff.ReadInto(LIndex, @LData[0]);
      LWatch.Stop;
      LMin := MaxInt;
      LMax := -MaxInt;
      LVoids := 0;
      for I := 0 to LCount - 1 do
      begin
        if LImage.BytesPerSample = 1 then
          LValue := LData[I]
        else if LImage.SampleFormat = SAMPLE_FORMAT_SIGNED then
          LValue := PSmallInt(@LData[I * 2])^
        else
          LValue := PWord(@LData[I * 2])^;
        if LValue < LMin then
          LMin := LValue;
        if LValue > LMax then
          LMax := LValue;
        if LValue = -9999 then
          Inc(LVoids);
      end;
      Writeln(Format('  %d  %4d x %4d  min %5d  max %5d  voids %6d  fnv1a %.8X  %d ms',
        [LIndex, LImage.Width, LImage.Height, LMin, LMax, LVoids,
         Fnv1a(@LData[0], Length(LData)), LWatch.ElapsedMilliseconds]));
    end;
  finally
    LTiff.Free;
  end;
end;

var
  LArg: Integer;
begin
  if ParamCount = 0 then
  begin
    Writeln('Usage: GeoTiffCheck file.tif [file.tif ...]');
    ExitCode := 1;
    Exit;
  end;
  for LArg := 1 to ParamCount do
    try
      CheckFile(ParamStr(LArg));
    except
      on E: Exception do
      begin
        Writeln('  ', E.ClassName, ': ', E.Message);
        ExitCode := 2;
      end;
    end;
end.
