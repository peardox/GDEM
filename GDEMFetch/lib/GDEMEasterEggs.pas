{ @abstract(A few hidden places the search can find: easter eggs.)

  They come from @code(maps/easter_eggs.json), linked into the program as
  the @link(EASTER_EGGS_RESOURCE) RCDATA resource, so nothing is
  deployed. They are not drawn on the map: they turn up only when searched
  for, by name or by one of their other names (see @link(TEasterEgg)).

  The file is JSON, read with Neon: an object with a @code(format) number
  (see @link(EASTER_EGGS_FORMAT)) and a @code(places) array, each place an
  object with @code(name), @code(lat), @code(lon), and optionally
  @code(sizeKm), @code(aliases) (an array of strings) and @code(note).
  To add one, add an object to the array and rebuild. A place without a
  name, or with a position off the map, is left out and reported.

  No FMX: any program can use it. }
unit GDEMEasterEggs;

interface

uses
  System.SysUtils,
  Neon.Core.Attributes;

const
  { Name of the RCDATA resource holding @code(maps/easter_eggs.json). }
  EASTER_EGGS_RESOURCE = 'EASTEREGGS';

  { Version of the file this unit reads. }
  EASTER_EGGS_FORMAT = 1;

type
  { @abstract(Raised when the easter eggs cannot be read.) }
  EEasterEggError = class(Exception);

  { @abstract(One hidden place.) }
  TEasterEgg = record
    { Its name, such as @code(Area 51). }
    [NeonProperty('name')]
    Name: string;
    { Latitude of its middle, in degrees. }
    [NeonProperty('lat')]
    Lat: Double;
    { Longitude of its middle, in degrees. }
    [NeonProperty('lon')]
    Lon: Double;
    { How much to show round it when found, in kilometres across; 0 to
      move to it at the zoom already in use, as for a town. }
    [NeonProperty('sizeKm')]
    SizeKm: Double;
    { Other words that find it, such as @code(Groom Lake) or @code(UFO). }
    [NeonProperty('aliases')]
    Aliases: TArray<string>;
    { A line about it, shown when it is found. }
    [NeonProperty('note')]
    Note: string;
  end;

  { @abstract(The easter eggs file's contents.) }
  TEasterEggFile = record
    { Version of the file; see @link(EASTER_EGGS_FORMAT). }
    [NeonProperty('format')]
    Format: Integer;
    { The places. }
    [NeonProperty('places')]
    Places: TArray<TEasterEgg>;
  end;

{ Reads easter eggs from JSON text.
  @param(AJSON The file's text.)
  @param(ASkipped Receives a description of each place left out, such as
    @code(place 3: no name); empty when all were kept.)
  @returns(The places that make sense.)
  @raises(EEasterEggError if the text is not an easter eggs file this unit
    can read.) }
function ParseEasterEggs(const AJSON: string; out ASkipped: TArray<string>): TArray<TEasterEgg>;

{ Reads the easter eggs from the program's @link(EASTER_EGGS_RESOURCE)
  resource.
  @param(ASkipped Receives what was left out; see @link(ParseEasterEggs).)
  @returns(The places.)
  @raises(EResNotFound if the program has no such resource.)
  @raises(EEasterEggError if it cannot be read.) }
function LoadEasterEggs(out ASkipped: TArray<string>): TArray<TEasterEgg>;

implementation

uses
  {$IFDEF MSWINDOWS}
  // RT_RCDATA; other platforms have it in System.Types
  Winapi.Windows,
  {$ENDIF}
  System.Classes, System.Types, System.Math,
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON;

{ The Neon configuration: names exactly as in the [NeonProperty]
  attributes, and exceptions raised so a bad file is reported.
  @returns(The configuration.) }
function EasterEggsNeonConfig: INeonConfiguration;
begin
  Result := TNeonConfiguration.Create
    .SetMemberCase(TNeonCase.Unchanged)
    .SetRaiseExceptions(True);
end;

function ParseEasterEggs(const AJSON: string; out ASkipped: TArray<string>): TArray<TEasterEgg>;
var
  LFile: TEasterEggFile;
  LIndex: Integer;
  LEgg: TEasterEgg;
begin
  ASkipped := nil;
  Result := nil;
  try
    LFile := TNeon.JSONToValue<TEasterEggFile>(AJSON, EasterEggsNeonConfig);
  except
    on E: Exception do
      raise EEasterEggError.Create('Could not read the easter eggs: ' + E.Message);
  end;
  if LFile.Format > EASTER_EGGS_FORMAT then
    raise EEasterEggError.CreateFmt('The easter eggs are format %d; this program reads ' +
      'format %d', [LFile.Format, EASTER_EGGS_FORMAT]);

  for LIndex := 0 to High(LFile.Places) do
  begin
    LEgg := LFile.Places[LIndex];
    LEgg.Name := LEgg.Name.Trim;
    if LEgg.Name = '' then
      ASkipped := ASkipped + [Format('place %d: no name', [LIndex + 1])]
    else if IsNan(LEgg.Lat) or IsNan(LEgg.Lon) or not InRange(LEgg.Lat, -90, 90) or
       not InRange(LEgg.Lon, -180, 180) then
      ASkipped := ASkipped + [Format('place %d (%s): position %g, %g is off the map',
        [LIndex + 1, LEgg.Name, LEgg.Lat, LEgg.Lon])]
    else
    begin
      LEgg.SizeKm := Max(0, LEgg.SizeKm);
      Result := Result + [LEgg];
    end;
  end;
end;

function LoadEasterEggs(out ASkipped: TArray<string>): TArray<TEasterEgg>;
var
  LStream: TResourceStream;
  LBytes: TBytes;
begin
  LStream := TResourceStream.Create(HInstance, EASTER_EGGS_RESOURCE, RT_RCDATA);
  try
    SetLength(LBytes, LStream.Size);
    if Length(LBytes) > 0 then
      LStream.ReadBuffer(LBytes[0], Length(LBytes));
  finally
    LStream.Free;
  end;
  Result := ParseEasterEggs(TEncoding.UTF8.GetString(LBytes), ASkipped);
end;

end.
