{ @abstract(Prime factors, and what they say about an image: the sizes it
  can be halved to and the tile sizes that cut every level exactly.)

  Factorising a number shows at a glance what it divides into. For an
  image, factorising its width and height answers the questions that
  matter for tiling it into levels of detail:

  @unorderedList(
    @item(How often it can be halved and stay whole: the number of 2s that
      the width and height share. 10800 x 5400 is
      @code(2^4 x 3^3 x 5^2) by @code(2^3 x 3^3 x 5^2), so it halves three
      times, to 1350 x 675.)
    @item(Which square tile sizes cut every level exactly: the divisors of
      the greatest common divisor of the smallest level's width and height.
      Every larger level is that one doubled, so they divide those too. For
      1350 x 675 they are the divisors of 675 = @code(3^3 x 5^2), such as
      135, 225 and 675.)
  )

  @link(LevelSizes) works out the levels, @link(TileSizesFor) the tile
  sizes that fit them all, and @link(SuggestTileSize) the one nearest a
  convenient size. They suit any image, not only maps.

  This unit uses nothing but the run-time library, so any program can use
  it. }
unit GDEMFactors;

interface

uses
  System.SysUtils, System.Types;

const
  { The width at or below which @link(LevelSizes) stops halving by
    default: about a screen across, so the smallest level is roughly the
    size of a window showing all of the image. }
  DEFAULT_COARSEST_WIDTH = 2048;

  { The tile size @link(SuggestTileSize) aims for by default: big enough
    that a screen needs only a few dozen tiles, small enough that each is
    quick to decode. }
  DEFAULT_TARGET_TILE_SIZE = 256;

type
  { @abstract(One prime and how many times it divides a number.) }
  TPrimePower = record
    { The prime. }
    Prime: Integer;
    { How many times it divides the number; at least 1. }
    Power: Integer;
  end;

  { A number's prime factors, smallest prime first. Empty for 1. }
  TPrimeFactors = TArray<TPrimePower>;

{ Factorises a whole number into primes.
  @param(AValue The number; 1 or more.)
  @returns(Its prime factors, smallest first; empty for 1.)
  @raises(EArgumentException if AValue is less than 1.) }
function PrimeFactors(AValue: Integer): TPrimeFactors;

{ Writes prime factors the usual way, such as @code(2^4 x 3^3 x 5^2), in
  ASCII so it can go anywhere.
  @param(AFactors The factors.)
  @returns(The text; @code(1) when there are none.) }
function FactorsText(const AFactors: TPrimeFactors): string;

{ How many times a prime divides a number.
  @param(AValue The number; 1 or more.)
  @param(APrime The prime.)
  @returns(The power of APrime in AValue; 0 if it does not divide it.) }
function PrimePower(AValue, APrime: Integer): Integer;

{ The greatest common divisor of two numbers.
  @param(A A whole number, 0 or more.)
  @param(B Another, 0 or more.)
  @returns(The largest number dividing both; the other number when one of
    them is 0.) }
function GreatestCommonDivisor(A, B: Integer): Integer;

{ Every number that divides a number exactly, built from its prime
  factors.
  @param(AValue The number; 1 or more.)
  @returns(Its divisors, smallest first, from 1 to AValue itself.) }
function Divisors(AValue: Integer): TArray<Integer>;

{ The sizes of an image's levels of detail: the image itself, then each
  half the size of the last. Halving stops when either side would no
  longer be whole, or once the width is at most ACoarsestWidth.
  @param(AWidth The full width, in pixels.)
  @param(AHeight The full height, in pixels.)
  @param(ACoarsestWidth Stop halving once a level is no wider than this.)
  @returns(The levels, full size first; always at least the full size.) }
function LevelSizes(AWidth, AHeight: Integer;
  ACoarsestWidth: Integer = DEFAULT_COARSEST_WIDTH): TArray<TSize>;

{ The square tile sizes that cut every level exactly: the divisors of the
  greatest common divisor of the smallest level's width and height. Every
  other level is that one doubled, so they cut those exactly too.
  @param(ALevels Levels from @link(LevelSizes), full size first.)
  @returns(The tile sizes, smallest first; empty if ALevels is.) }
function TileSizesFor(const ALevels: TArray<TSize>): TArray<Integer>;

{ Picks the tile size nearest a target, by ratio rather than difference,
  so 225 is nearer 256 than 135 is.
  @param(ACandidates Tile sizes, such as from @link(TileSizesFor).)
  @param(ATarget The size to aim for.)
  @returns(The nearest candidate, the smaller of two equally near; 0 if
    there are none.) }
function SuggestTileSize(const ACandidates: TArray<Integer>;
  ATarget: Integer = DEFAULT_TARGET_TILE_SIZE): Integer;

implementation

uses
  System.Math, System.Generics.Collections;

function PrimeFactors(AValue: Integer): TPrimeFactors;
var
  LPrime, LPower: Integer;
begin
  if AValue < 1 then
    raise EArgumentException.CreateFmt('Cannot factorise %d', [AValue]);
  Result := nil;
  LPrime := 2;
  while Int64(LPrime) * LPrime <= AValue do
  begin
    LPower := 0;
    while AValue mod LPrime = 0 do
    begin
      AValue := AValue div LPrime;
      Inc(LPower);
    end;
    if LPower > 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Prime := LPrime;
      Result[High(Result)].Power := LPower;
    end;
    // 2, then the odd numbers; composite ones never divide what is left
    if LPrime = 2 then
      LPrime := 3
    else
      Inc(LPrime, 2);
  end;
  // What is left over is itself prime
  if AValue > 1 then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Prime := AValue;
    Result[High(Result)].Power := 1;
  end;
end;

function FactorsText(const AFactors: TPrimeFactors): string;
var
  LIndex: Integer;
begin
  if Length(AFactors) = 0 then
    Exit('1');
  Result := '';
  for LIndex := 0 to High(AFactors) do
  begin
    if LIndex > 0 then
      Result := Result + ' x ';
    Result := Result + IntToStr(AFactors[LIndex].Prime);
    if AFactors[LIndex].Power > 1 then
      Result := Result + '^' + IntToStr(AFactors[LIndex].Power);
  end;
end;

function PrimePower(AValue, APrime: Integer): Integer;
begin
  Result := 0;
  if (AValue < 1) or (APrime < 2) then
    Exit;
  while AValue mod APrime = 0 do
  begin
    AValue := AValue div APrime;
    Inc(Result);
  end;
end;

function GreatestCommonDivisor(A, B: Integer): Integer;
var
  LRest: Integer;
begin
  A := Abs(A);
  B := Abs(B);
  while B <> 0 do
  begin
    LRest := A mod B;
    A := B;
    B := LRest;
  end;
  Result := A;
end;

function Divisors(AValue: Integer): TArray<Integer>;
var
  LFactors: TPrimeFactors;
  LFactor, LIndex, LPower, LCount: Integer;
  LMultiple: Integer;
begin
  LFactors := PrimeFactors(AValue);
  // Start from 1 and, for each prime, multiply every divisor so far by
  // each of its powers
  Result := [1];
  for LFactor := 0 to High(LFactors) do
  begin
    LCount := Length(Result);
    for LIndex := 0 to LCount - 1 do
    begin
      LMultiple := Result[LIndex];
      for LPower := 1 to LFactors[LFactor].Power do
      begin
        LMultiple := LMultiple * LFactors[LFactor].Prime;
        Result := Result + [LMultiple];
      end;
    end;
  end;
  TArray.Sort<Integer>(Result);
end;

function LevelSizes(AWidth, AHeight, ACoarsestWidth: Integer): TArray<TSize>;
begin
  if (AWidth < 1) or (AHeight < 1) then
    raise EArgumentException.CreateFmt('Cannot plan levels for %d x %d', [AWidth, AHeight]);
  Result := [TSize.Create(AWidth, AHeight)];
  while (AWidth > ACoarsestWidth) and (AWidth mod 2 = 0) and (AHeight mod 2 = 0) do
  begin
    AWidth := AWidth div 2;
    AHeight := AHeight div 2;
    Result := Result + [TSize.Create(AWidth, AHeight)];
  end;
end;

function TileSizesFor(const ALevels: TArray<TSize>): TArray<Integer>;
begin
  if Length(ALevels) = 0 then
    Exit(nil);
  Result := Divisors(GreatestCommonDivisor(ALevels[High(ALevels)].cx,
    ALevels[High(ALevels)].cy));
end;

function SuggestTileSize(const ACandidates: TArray<Integer>; ATarget: Integer): Integer;
var
  LCandidate: Integer;
  LDistance, LBest: Double;
begin
  Result := 0;
  LBest := MaxDouble;
  for LCandidate in ACandidates do
  begin
    if (LCandidate < 1) or (ATarget < 1) then
      Continue;
    // Ratio, so twice as big counts the same as half the size
    LDistance := Abs(Ln(LCandidate / ATarget));
    if (LDistance < LBest) or ((LDistance = LBest) and (LCandidate < Result)) then
    begin
      LBest := LDistance;
      Result := LCandidate;
    end;
  end;
end;

end.
