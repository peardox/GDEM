{ @abstract(Types and parsing for NASA CMR granule search results.)

  The NASA Common Metadata Repository (CMR) is a public catalogue of Earth
  observation data. It needs no login, so it is used to find out where the
  files for an ASTER GDEM V3 (ASTGTM.003) tile actually live before any
  authenticated download is attempted.

  This unit only models the small part of the CMR JSON response that the
  project uses, and deserialises it with the Neon JSON library
  (@url(https://github.com/paolo-rossi/delphi-neon)). Any keys in the
  response that are not declared here are ignored, so CMR can add fields
  without breaking the parser.

  The unit does no networking. @link(TGDEMDownloader) performs the HTTP
  request and hands the response text to @link(TCMRGranuleSearch.FromJSON). }
unit GDEMCMR;

interface

uses
  System.SysUtils, Neon.Core.Attributes;

const
  { Base URL of the CMR granule search endpoint, asking for JSON output. }
  CMR_GRANULE_SEARCH_URL = 'https://cmr.earthdata.nasa.gov/search/granules.json';

  { CMR short name of the ASTER Global Digital Elevation Model. }
  ASTGTM_SHORT_NAME = 'ASTGTM';

  { CMR version string of ASTER GDEM V3. }
  ASTGTM_VERSION = '003';

  { Prefix that every ASTER GDEM V3 granule and file name starts with. }
  ASTGTM_GRANULE_PREFIX = 'ASTGTMV003_';

  { Largest number of results CMR returns in one page. }
  CMR_MAX_PAGE_SIZE = 2000;

  { Response header giving the total number of matching results. }
  CMR_HITS_HEADER = 'CMR-Hits';

  { Header CMR returns with each page, and expects back on the request for
    the next page. Absent once there are no more pages. }
  CMR_SEARCH_AFTER_HEADER = 'CMR-Search-After';

  { Response header set to @code(true) when a query ran out of time and the
    results are incomplete. }
  CMR_TIMEOUT_HEADER = 'CMR-Time-Out';

type
  { @abstract(Raised when a CMR response cannot be understood.) }
  ECMRError = class(Exception);

  { @abstract(One link attached to a CMR granule.)

    A granule carries several links: the data files themselves, browse
    images, metadata and documentation. Only @link(Href) is needed to find
    the data files; the others are kept because they are useful when
    inspecting a response. }
  TCMRLink = record
    { Absolute URL the link points at. It may be @code(https://) or
      @code(s3://); only the https form is usable outside AWS. }
    [NeonProperty('href')]
    Href: string;

    { Relationship of the link to the granule, as a URI. Data links end
      with @code(/data#). }
    [NeonProperty('rel')]
    Rel: string;

    { MIME type of the linked resource, when CMR supplies one. }
    [NeonProperty('type')]
    &Type: string;

    { Human-readable description of the link, when CMR supplies one. }
    [NeonProperty('title')]
    Title: string;
  end;

  { Dynamic array of @link(TCMRLink). }
  TCMRLinkArray = TArray<TCMRLink>;

  { @abstract(One granule (one tile) in a CMR search result.)

    For ASTER GDEM V3 a granule is one 1 by 1 degree tile, and its links
    include both the @code(_dem.tif) and @code(_num.tif) files. }
  TCMRGranule = record
    { CMR's own identifier for the granule. }
    [NeonProperty('id')]
    Id: string;

    { Granule title, for ASTER GDEM V3 a name such as
      @code(ASTGTMV003_N50W002). }
    [NeonProperty('title')]
    Title: string;

    { Identifier the data producer gave the granule. }
    [NeonProperty('producer_granule_id')]
    ProducerGranuleId: string;

    { All links attached to the granule. }
    [NeonProperty('links')]
    Links: TCMRLinkArray;
  end;

  { Dynamic array of @link(TCMRGranule). }
  TCMRGranuleArray = TArray<TCMRGranule>;

  { @abstract(The @code(feed) object of a CMR JSON response.) }
  TCMRFeed = record
    { Matching granules. Empty when nothing matched the search. }
    [NeonProperty('entry')]
    Entry: TCMRGranuleArray;
  end;

  { @abstract(A complete CMR granule search response.)

    Use @link(FromJSON) to build one from the response text, then
    @link(DataFileURLs) to pick out the files to download. }
  TCMRGranuleSearch = record
    { The response's single top-level object. }
    [NeonProperty('feed')]
    Feed: TCMRFeed;

    { Builds the URL that searches CMR for ASTER GDEM V3 granules whose
      names start with AGranule.

      @param(AGranule Granule name such as @code(ASTGTMV003_N50W002).
        A trailing wildcard is added, so a prefix also works.)
      @returns(The complete search URL.) }
    class function SearchURL(const AGranule: string): string; static;

    { Builds the URL that lists every ASTER GDEM V3 granule in the world.
      Fetch it repeatedly, sending back the @link(CMR_SEARCH_AFTER_HEADER)
      value from each response, to page through all of them.
      @param(APageSize Results per page, at most @link(CMR_MAX_PAGE_SIZE).)
      @returns(The search URL.) }
    class function CollectionURL(APageSize: Integer = CMR_MAX_PAGE_SIZE): string; static;

    { Deserialises a CMR granule search response.

      @param(AJSON The response body as returned by
        @link(CMR_GRANULE_SEARCH_URL).)
      @returns(The parsed response.)
      @raises(ECMRError if the text is not JSON or does not have the
        expected shape.) }
    class function FromJSON(const AJSON: string): TCMRGranuleSearch; static;

    { Lists the https URLs of every file whose name ends with one of the
      given suffixes, across all granules in the response.

      Duplicates are removed and the result is sorted, so for ASTER GDEM
      the @code(_dem.tif) file comes before the @code(_num.tif) file.
      Matching is case-insensitive.

      @param(ASuffixes File name endings to accept, for example
        @code(['_dem.tif', '_num.tif']).)
      @returns(The matching URLs; empty if none match.) }
    function DataFileURLs(const ASuffixes: array of string): TArray<string>;
  end;

implementation

uses
  System.Generics.Collections, System.NetEncoding,
  Neon.Core.Types, Neon.Core.Persistence, Neon.Core.Persistence.JSON;

{ TCMRGranuleSearch }

class function TCMRGranuleSearch.SearchURL(const AGranule: string): string;
begin
  Result := CMR_GRANULE_SEARCH_URL +
    '?short_name=' + ASTGTM_SHORT_NAME +
    '&version=' + ASTGTM_VERSION +
    '&page_size=20' +
    '&options%5Breadable_granule_name%5D%5Bpattern%5D=true' +
    '&readable_granule_name=' + TNetEncoding.URL.Encode(AGranule) + '*';
end;

class function TCMRGranuleSearch.CollectionURL(APageSize: Integer): string;
begin
  Result := CMR_GRANULE_SEARCH_URL +
    '?short_name=' + ASTGTM_SHORT_NAME +
    '&version=' + ASTGTM_VERSION +
    '&page_size=' + IntToStr(APageSize);
end;

class function TCMRGranuleSearch.FromJSON(const AJSON: string): TCMRGranuleSearch;
var
  LConfig: INeonConfiguration;
begin
  // Names come from the [NeonProperty] attributes, so the member case is
  // left unchanged. Exceptions are raised rather than logged so that a
  // malformed response is reported instead of silently returning nothing.
  LConfig := TNeonConfiguration.Create
    .SetMemberCase(TNeonCase.Unchanged)
    .SetRaiseExceptions(True);
  try
    Result := TNeon.JSONToValue<TCMRGranuleSearch>(AJSON, LConfig);
  except
    on E: Exception do
      raise ECMRError.Create('Could not read the CMR search response: ' + E.Message);
  end;
end;

function TCMRGranuleSearch.DataFileURLs(const ASuffixes: array of string): TArray<string>;
var
  LFound: TList<string>;
  LGranule: TCMRGranule;
  LLink: TCMRLink;
  LLower, LSuffix: string;
begin
  LFound := TList<string>.Create;
  try
    for LGranule in Feed.Entry do
      for LLink in LGranule.Links do
      begin
        LLower := LowerCase(LLink.Href);
        if not LLower.StartsWith('https://') then
          Continue;
        for LSuffix in ASuffixes do
          if LLower.EndsWith(LowerCase(LSuffix)) then
          begin
            if not LFound.Contains(LLink.Href) then
              LFound.Add(LLink.Href);
            Break;
          end;
      end;
    LFound.Sort;
    Result := LFound.ToArray;
  finally
    LFound.Free;
  end;
end;

end.
