{ @abstract(Finds countries, towns and cities, and the user's markers by
  name, forgiving spelling mistakes.)

  A @link(TPlaceSearch) is filled once from a @code(TWorldVectors) and a
  @code(TMarkerList) (and again when the markers change), then asked as
  the user types. Names and what is typed are both reduced to plain
  lower-case ASCII words first (@link(TPlaceSearch.Fold)): accents dropped,
  so @code(sao paulo) finds Sao Paulo spelt with its accents, and
  punctuation turned into spaces, so @code(st johns) finds
  @code(St. John's).

  Each name is then tried, best first:
  @orderedList(
    @item(the whole name, such as @code(paris);)
    @item(the start of the name, such as @code(pari);)
    @item(the start of a later word, such as @code(york) for New York;)
    @item(anywhere in the name, from two letters typed;)
    @item(the start of the name or of a later word with a few mistakes:
      letters wrong, missing, extra or swapped, such as @code(lodnon) or
      @code(edinbrugh). The mistakes allowed grow with what is typed (see
      @link(TPlaceSearch.MaxMistakes)), none below four letters.)
  )
  The easter eggs (see @code(GDEMEasterEggs)) are found the same way, by
  name or by any of their other names, though they are never drawn on the
  map.

  A place is also found by its other names, such as @code(Antioch) for
  Antakya; the list then shows that name after the place.

  Mistakes are counted with the optimal string alignment distance (a
  Damerau-Levenshtein distance), worked out only against the start of each
  word and given up as soon as it must exceed the limit, so a search of
  every name, about 8,200, takes a few milliseconds per letter typed.

  Matches are ranked by how they matched, then by fewer mistakes, then
  markers before countries before places, and places by importance (the
  order @code(TWorldVectors.Places) holds them in).

  No FMX: any program can use it. }
unit GDEMSearch;

interface

uses
  System.SysUtils, System.Generics.Collections,
  GDEMVectors, GDEMMarkers, GDEMEasterEggs;

const
  { Most matches returned unless asked otherwise. }
  DEFAULT_MAX_HITS = 12;

type
  { What a match is. In order of preference when two match equally well. }
  TSearchKind = (
    { One of the user's markers; see @code(TMarkerList). }
    skMarker,
    { A country; see @code(TWorldVectors.Countries). }
    skCountry,
    { An easter egg: a hidden place; see @code(GDEMEasterEggs). }
    skEgg,
    { A town or city; see @code(TWorldVectors.Places). }
    skPlace
  );

  { How a name matched; see the unit's description. In order of
    preference. }
  TSearchMatch = (
    { The whole name. }
    smExact,
    { The start of the name. }
    smPrefix,
    { The start of a later word. }
    smWordPrefix,
    { Somewhere inside the name. }
    smInside,
    { The start of the name or a word, with mistakes. }
    smFuzzy
  );

  { @abstract(One thing found.) }
  TSearchHit = record
    { What it is. }
    Kind: TSearchKind;
    { Its index: in the marker list, @code(TWorldVectors.Countries), the
      easter eggs or @code(TWorldVectors.Places). }
    Index: Integer;
    { How to show it in a list, such as @code(London, Ontario, Canada),
      @code(Jersey (country)) or @code(Home (marker)). }
    Text: string;
    { How it matched. }
    Match: TSearchMatch;
    { Mistakes allowed for, for a fuzzy match; otherwise 0. }
    Mistakes: Integer;
  end;

  { @abstract(Something that can be found, with its name ready for
    matching.) }
  TSearchEntry = record
    { What it is. }
    Kind: TSearchKind;
    { Its index; as for @link(TSearchHit.Index). }
    Index: Integer;
    { The name, after @link(TPlaceSearch.Fold). }
    Key: string;
    { How to show it in a list. }
    Text: string;
    { Lower is more important, among entries of the same kind. }
    Rank: Integer;
  end;

  { @abstract(Searches the names of countries, places and markers.) }
  TPlaceSearch = class
  private
    { Everything that can be found. }
    FEntries: TArray<TSearchEntry>;
    { Row of the distance table two query letters back. }
    FRowBack2: TArray<Integer>;
    { Row of the distance table one query letter back. }
    FRowBack1: TArray<Integer>;
    { Row of the distance table being worked out. }
    FRow: TArray<Integer>;

    { Adds an entry, unless its name has nothing to match.
      @param(AList The entries so far.)
      @param(AKind What it is.)
      @param(AIndex Its index.)
      @param(AName The name to match against; folded here.)
      @param(AText How to show it.)
      @param(ARank Its importance among its kind; lower first.) }
    class procedure AddEntry(AList: TList<TSearchEntry>; AKind: TSearchKind; AIndex: Integer;
      const AName, AText: string; ARank: Integer); static;

    { The fewest mistakes that turn the query into the start of a text from
      a given position, giving up once more than a limit are needed.
      @param(AQuery The folded query.)
      @param(AText The folded name.)
      @param(AStart Where in AText to start, from 0.)
      @param(ALimit The most mistakes of interest.)
      @returns(The number of mistakes, or ALimit + 1 if more are needed.) }
    function PrefixMistakes(const AQuery, AText: string; AStart, ALimit: Integer): Integer;

    { Tries one entry against the query.
      @param(AEntry The entry.)
      @param(AQuery The folded query.)
      @param(ALimit The most mistakes allowed.)
      @param(AMatch Receives how it matched.)
      @param(AMistakes Receives the mistakes allowed for.)
      @returns(@true if it matched.) }
    function MatchEntry(const AEntry: TSearchEntry; const AQuery: string; ALimit: Integer;
      out AMatch: TSearchMatch; out AMistakes: Integer): Boolean;

    { Reader for @link(Count).
      @returns(How many entries there are.) }
    function GetCount: Integer;
  public
    { Reduces text to what is matched: lower-case ASCII letters and
      digits in words separated by single spaces. Latin letters with
      accents lose them (and sharp s becomes @code(ss)); other letters,
      such as Cyrillic, are kept in lower case; apostrophes are dropped, so
      @code(St. John's) gives @code(st johns); everything else is a
      space.
      @param(AText The text.)
      @returns(The folded text, with no spaces at either end.) }
    class function Fold(const AText: string): string; static;

    { How many mistakes a query of a given length may have.
      @param(ALength Letters in the folded query.)
      @returns(0 below 4 letters, 1 below 7, 2 below 11, then 3.) }
    class function MaxMistakes(ALength: Integer): Integer; static;

    { Fills the search with every country, town and city, marker and
      easter egg, replacing what was there.
      @param(AVectors The countries and places; may be @nil.)
      @param(AMarkers The markers; may be @nil.)
      @param(AEggs The easter eggs; may be empty.) }
    procedure Build(AVectors: TWorldVectors; AMarkers: TMarkerList;
      const AEggs: TArray<TEasterEgg>);

    { Finds what matches a query, best first.
      @param(AQuery As typed.)
      @param(AMaxHits The most matches to return.)
      @returns(The matches; empty if the query has no letters or digits.) }
    function Search(const AQuery: string; AMaxHits: Integer = DEFAULT_MAX_HITS): TArray<TSearchHit>;

    { How many things can be found. }
    property Count: Integer read GetCount;
  end;

implementation

uses
  // System.Character for Char's IsLetter and ToLower
  System.Math, System.Character, System.Generics.Defaults;

type
  { @abstract(A match with what it is ranked by.) }
  TScoredHit = record
    { The match. }
    Hit: TSearchHit;
    { The entry's rank among its kind. }
    Rank: Integer;
    { Length of the entry's folded name: shorter is nearer the query. }
    KeyLength: Integer;
  end;

const
  { Latin-1 Supplement and Latin Extended-A letters without their accents,
    in lower case; empty for the multiplication and division signs. Made
    from Unicode's decompositions, with the letters that have none
    (ae, eth, o with stroke, thorn, sharp s, d with stroke, l with stroke
    and so on) spelt out. }
  FOLD_LATIN: array[$00C0..$017F] of string = (
    'a', 'a', 'a', 'a', 'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e',
    'i', 'i', 'i', 'i', 'd', 'n', 'o', 'o', 'o', 'o', 'o', '',
    'o', 'u', 'u', 'u', 'u', 'y', 'th', 'ss', 'a', 'a', 'a', 'a',
    'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i',
    'd', 'n', 'o', 'o', 'o', 'o', 'o', '', 'o', 'u', 'u', 'u',
    'u', 'y', 'th', 'y', 'a', 'a', 'a', 'a', 'a', 'a', 'c', 'c',
    'c', 'c', 'c', 'c', 'c', 'c', 'd', 'd', 'd', 'd', 'e', 'e',
    'e', 'e', 'e', 'e', 'e', 'e', 'e', 'e', 'g', 'g', 'g', 'g',
    'g', 'g', 'g', 'g', 'h', 'h', 'h', 'h', 'i', 'i', 'i', 'i',
    'i', 'i', 'i', 'i', 'i', 'i', 'ij', 'ij', 'j', 'j', 'k', 'k',
    'k', 'l', 'l', 'l', 'l', 'l', 'l', 'l', 'l', 'l', 'l', 'n',
    'n', 'n', 'n', 'n', 'n', 'n', 'n', 'n', 'o', 'o', 'o', 'o',
    'o', 'o', 'oe', 'oe', 'r', 'r', 'r', 'r', 'r', 'r', 's', 's',
    's', 's', 's', 's', 's', 's', 't', 't', 't', 't', 't', 't',
    'u', 'u', 'u', 'u', 'u', 'u', 'u', 'u', 'u', 'u', 'u', 'u',
    'w', 'w', 'y', 'y', 'y', 'z', 'z', 'z', 'z', 'z', 'z', 's'
  );

  { What follows a marker's name in a list. }
  MARKER_SUFFIX = ' (marker)';

  { What follows a country's name in a list. }
  COUNTRY_SUFFIX = ' (country)';

{ TPlaceSearch }

class function TPlaceSearch.Fold(const AText: string): string;
var
  LBuilder: TStringBuilder;
  LChar: Char;
  LCode: Integer;
  LSpace: Boolean;

  { Adds letters, after a space if one is due.
    @param(ALetters The letters.) }
  procedure Put(const ALetters: string);
  begin
    if ALetters = '' then
      Exit;
    if LSpace and (LBuilder.Length > 0) then
      LBuilder.Append(' ');
    LSpace := False;
    LBuilder.Append(ALetters);
  end;

begin
  LBuilder := TStringBuilder.Create(Length(AText));
  try
    LSpace := False;
    for LChar in AText do
    begin
      LCode := Ord(LChar);
      case LChar of
        'a'..'z', '0'..'9':
          Put(LChar);
        'A'..'Z':
          Put(Chr(LCode + 32));
        // Apostrophes join letters: John's, N'Djamena
        '''', '`', #$2019, #$02BC:
          ;
      else
        if InRange(LCode, Low(FOLD_LATIN), High(FOLD_LATIN)) then
        begin
          if FOLD_LATIN[LCode] <> '' then
            Put(FOLD_LATIN[LCode])
          else
            LSpace := True;
        end
        else if (LCode > $7F) and LChar.IsLetter then
          Put(LChar.ToLower)
        else
          // Spaces, punctuation and marks all just separate words
          LSpace := True;
      end;
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

class function TPlaceSearch.MaxMistakes(ALength: Integer): Integer;
begin
  if ALength < 4 then
    Result := 0
  else if ALength < 7 then
    Result := 1
  else if ALength < 11 then
    Result := 2
  else
    Result := 3;
end;

function TPlaceSearch.GetCount: Integer;
begin
  Result := Length(FEntries);
end;

class procedure TPlaceSearch.AddEntry(AList: TList<TSearchEntry>; AKind: TSearchKind;
  AIndex: Integer; const AName, AText: string; ARank: Integer);
var
  LEntry: TSearchEntry;
begin
  LEntry.Kind := AKind;
  LEntry.Index := AIndex;
  LEntry.Key := Fold(AName);
  LEntry.Text := AText;
  LEntry.Rank := ARank;
  if LEntry.Key <> '' then
    AList.Add(LEntry);
end;

procedure TPlaceSearch.Build(AVectors: TWorldVectors; AMarkers: TMarkerList;
  const AEggs: TArray<TEasterEgg>);
var
  LIndex: Integer;
  LCountries: TGeoLayer;
  LPlace: TGeoPlace;
  LEntries: TList<TSearchEntry>;
  LName, LOther, LText, LCountry: string;
begin
  LEntries := TList<TSearchEntry>.Create;
  try
    if AMarkers <> nil then
      for LIndex := 0 to AMarkers.Count - 1 do
        AddEntry(LEntries, skMarker, LIndex, AMarkers[LIndex].Name,
          AMarkers[LIndex].Name + MARKER_SUFFIX, LIndex);
    if AVectors <> nil then
    begin
      LCountries := AVectors.Countries;
      if LCountries <> nil then
        for LIndex := 0 to High(LCountries.Features) do
          AddEntry(LEntries, skCountry, LIndex, LCountries.Features[LIndex].Name,
            LCountries.Features[LIndex].Name + COUNTRY_SUFFIX, 0);
    end;
    for LIndex := 0 to High(AEggs) do
    begin
      // Named with the country it is in, where the outlines hold it
      LText := AEggs[LIndex].Name;
      if AVectors <> nil then
      begin
        LCountry := AVectors.CountryAt(AEggs[LIndex].Lat, AEggs[LIndex].Lon);
        if LCountry <> '' then
          LText := LText + ', ' + LCountry;
      end;
      AddEntry(LEntries, skEgg, LIndex, AEggs[LIndex].Name, LText, LIndex);
      for LOther in AEggs[LIndex].Aliases do
        AddEntry(LEntries, skEgg, LIndex, LOther, LText + ' (' + LOther + ')', LIndex);
    end;
    if AVectors <> nil then
    begin
      for LIndex := 0 to High(AVectors.Places) do
      begin
        LPlace := AVectors.Places[LIndex];
        // The file's plain ASCII name, where the name itself is not
        if LPlace.SearchName <> '' then
          LName := LPlace.SearchName
        else
          LName := LPlace.Name;
        AddEntry(LEntries, skPlace, LIndex, LName, AVectors.PlaceText(LIndex), LIndex);
        for LOther in LPlace.OtherNames do
          AddEntry(LEntries, skPlace, LIndex, LOther,
            AVectors.PlaceText(LIndex) + ' (' + LOther + ')', LIndex);
      end;
    end;
    FEntries := LEntries.ToArray;
  finally
    LEntries.Free;
  end;
end;

function TPlaceSearch.PrefixMistakes(const AQuery, AText: string;
  AStart, ALimit: Integer): Integer;
var
  LQueryLength, LTextLength, LRow, LColumn, LValue, LRowBest: Integer;
  LSwap: TArray<Integer>;
  LQueryChar, LTextChar: Char;
begin
  LQueryLength := Length(AQuery);
  // Past the query's length plus the mistakes allowed, a longer stretch of
  // text can only cost more
  LTextLength := Min(Length(AText) - AStart, LQueryLength + ALimit);
  if Length(FRow) < LTextLength + 1 then
  begin
    SetLength(FRowBack2, LTextLength + 1);
    SetLength(FRowBack1, LTextLength + 1);
    SetLength(FRow, LTextLength + 1);
  end;

  // Row 0: none of the query against the first LColumn letters of text
  for LColumn := 0 to LTextLength do
    FRowBack1[LColumn] := LColumn;

  for LRow := 1 to LQueryLength do
  begin
    LQueryChar := AQuery.Chars[LRow - 1];
    FRow[0] := LRow;
    LRowBest := LRow;
    for LColumn := 1 to LTextLength do
    begin
      LTextChar := AText.Chars[AStart + LColumn - 1];
      // Change, extra letter in the query, or letter missing from it
      LValue := FRowBack1[LColumn - 1];
      if LQueryChar <> LTextChar then
        Inc(LValue);
      LValue := Min(LValue, Min(FRowBack1[LColumn], FRow[LColumn - 1]) + 1);
      // Two letters swapped
      if (LRow > 1) and (LColumn > 1) and (LQueryChar = AText.Chars[AStart + LColumn - 2]) and
         (AQuery.Chars[LRow - 2] = LTextChar) then
        LValue := Min(LValue, FRowBack2[LColumn - 2] + 1);
      FRow[LColumn] := LValue;
      LRowBest := Min(LRowBest, LValue);
    end;
    // Every later row is at least this row's best, so give up early
    if LRowBest > ALimit then
      Exit(ALimit + 1);
    LSwap := FRowBack2;
    FRowBack2 := FRowBack1;
    FRowBack1 := FRow;
    FRow := LSwap;
  end;

  // The best match of the whole query against any start of the text
  Result := ALimit + 1;
  for LColumn := 0 to LTextLength do
    Result := Min(Result, FRowBack1[LColumn]);
end;

function TPlaceSearch.MatchEntry(const AEntry: TSearchEntry; const AQuery: string;
  ALimit: Integer; out AMatch: TSearchMatch; out AMistakes: Integer): Boolean;
var
  LPosition, LMistakes, LBest: Integer;
begin
  AMistakes := 0;
  Result := True;
  if AEntry.Key = AQuery then
    AMatch := smExact
  else if AEntry.Key.StartsWith(AQuery) then
    AMatch := smPrefix
  else if AEntry.Key.Contains(' ' + AQuery) then
    AMatch := smWordPrefix
  else if (Length(AQuery) >= 2) and AEntry.Key.Contains(AQuery) then
    AMatch := smInside
  else if ALimit > 0 then
  begin
    // Against the start of every word
    LBest := ALimit + 1;
    LPosition := 0;
    while LPosition >= 0 do
    begin
      LMistakes := PrefixMistakes(AQuery, AEntry.Key, LPosition, ALimit);
      LBest := Min(LBest, LMistakes);
      if LBest <= 1 then
        Break;
      LPosition := AEntry.Key.IndexOf(' ', LPosition);
      if LPosition >= 0 then
        Inc(LPosition);
    end;
    Result := LBest <= ALimit;
    AMatch := smFuzzy;
    AMistakes := LBest;
  end
  else
    Result := False;
end;

function TPlaceSearch.Search(const AQuery: string; AMaxHits: Integer): TArray<TSearchHit>;
var
  LQuery: string;
  LLimit, LIndex, LMistakes: Integer;
  LMatch: TSearchMatch;
  LScored: TList<TScoredHit>;
  LItem: TScoredHit;
  LSeen: TDictionary<Int64, Boolean>;
  LKey: Int64;
begin
  Result := nil;
  LQuery := Fold(AQuery);
  if (LQuery = '') or (AMaxHits < 1) then
    Exit;
  LLimit := MaxMistakes(Length(LQuery));

  LScored := TList<TScoredHit>.Create;
  try
    for LIndex := 0 to High(FEntries) do
      if MatchEntry(FEntries[LIndex], LQuery, LLimit, LMatch, LMistakes) then
      begin
        LItem.Hit.Kind := FEntries[LIndex].Kind;
        LItem.Hit.Index := FEntries[LIndex].Index;
        LItem.Hit.Text := FEntries[LIndex].Text;
        LItem.Hit.Match := LMatch;
        LItem.Hit.Mistakes := LMistakes;
        LItem.Rank := FEntries[LIndex].Rank;
        LItem.KeyLength := Length(FEntries[LIndex].Key);
        LScored.Add(LItem);
      end;

    LScored.Sort(TComparer<TScoredHit>.Construct(
      function(const A, B: TScoredHit): Integer
      begin
        Result := Ord(A.Hit.Match) - Ord(B.Hit.Match);
        if Result = 0 then
          Result := A.Hit.Mistakes - B.Hit.Mistakes;
        if Result = 0 then
          Result := Ord(A.Hit.Kind) - Ord(B.Hit.Kind);
        if (Result = 0) and (A.Hit.Kind = skCountry) then
          Result := A.KeyLength - B.KeyLength;
        if Result = 0 then
          Result := A.Rank - B.Rank;
      end));

    // A place found by two of its names is listed once, by the better
    LSeen := TDictionary<Int64, Boolean>.Create;
    try
      for LItem in LScored do
      begin
        if Length(Result) >= AMaxHits then
          Break;
        LKey := (Int64(Ord(LItem.Hit.Kind)) shl 32) or Cardinal(LItem.Hit.Index);
        if LSeen.ContainsKey(LKey) then
          Continue;
        LSeen.Add(LKey, True);
        Result := Result + [LItem.Hit];
      end;
    finally
      LSeen.Free;
    end;
  finally
    LScored.Free;
  end;
end;

end.
