"""Builds maps/world_vectors.bin, the country borders, coastlines,
country outlines and towns and cities GDEMFetch draws on its world map,
from Natural Earth.

Natural Earth (https://www.naturalearthdata.com) is in the public domain.
Get its GeoJSON files from https://github.com/nvkelso/natural-earth-vector
(the geojson folder); only these seven are needed:

    ne_110m_admin_0_boundary_lines_land.geojson
    ne_50m_admin_0_boundary_lines_land.geojson
    ne_110m_coastline.geojson
    ne_50m_coastline.geojson
    ne_50m_admin_0_countries.geojson
    ne_10m_populated_places_simple.geojson
    ne_10m_geography_regions_elevation_points.geojson

Usage, from the repository root:

    python3 tools/build_vectors.py <folder with the geojson files> maps/world_vectors.bin

The output is read by GDEMVectors.pas, which documents the same format.
All numbers are little-endian.

    'GDVC'                magic
    UInt16 version        3
    UInt16 layer count
    for each layer:
      UInt8  kind         1 = lines, 2 = areas (closed rings)
      UInt8  name length, then the name in ASCII, such as 'coast50'
      UInt32 feature count
      for each feature:
        UInt16 name length, then the name in UTF-8 (empty for lines)
        UInt32 part count
        for each part (a line, or a ring of an area):
          UInt32 point count
          Int32 lon, Int32 lat of the first point, in thousandths of a degree
          for each further point:
            Int16 dlon, Int16 dlat: the change from the previous point; or,
            if either change does not fit in -32767..32767, Int16 -32768
            followed by Int32 lon, Int32 lat of the point itself
    UInt32 place count    (version 2 on)
    for each place, most important first (smallest min zoom, then
    largest population):
      UInt16 name length, then the name in UTF-8
      UInt16 key length, then the name in plain ASCII for searching, or
             nothing when the name is plain ASCII already
      UInt16 region length, then the region (state, province) in UTF-8
      UInt16 length, then other names in UTF-8, separated by '|', such as
             'Antioch' for Antakya (often empty)
      UInt16 country: its feature's index in countries50, or 65535
      Int32 lon, Int32 lat, in thousandths of a degree
      UInt8  min zoom x 10: Natural Earth's web map zoom level (256-pixel
             tiles) from which the place should be labelled
      UInt8  flags: 1 = national capital
      UInt32 population
    UInt32 peak count     (version 3 on)
    for each named high (or low) point, most important first (smallest
    min zoom, then highest):
      UInt16 name length, then the name in UTF-8
      UInt16 key length, then the name in plain ASCII for searching, or
             nothing when the name is plain ASCII already
      UInt16 length, then other names in UTF-8, separated by '|', such as
             'Mt. McKinley' for Denali (often empty)
      UInt16 country: its feature's index in countries50, or 65535
      UInt16 second country, for a peak on a border, or 65535
      Int32 lon, Int32 lat, in thousandths of a degree
      Int16  elevation in metres (below sea level for a depression)
      UInt8  kind: 1 mountain, 2 spot height, 3 depression, 4 plateau,
             5 pass, 0 anything else
      UInt8  min zoom x 10

Points are rounded to a thousandth of a degree (about 110 m), far finer
than the 1:50m data itself, and repeated points left by the rounding are
dropped. Lines need at least 2 points and rings at least 4, or they are
left out.
"""
import json
import struct
import sys
import unicodedata
from pathlib import Path

UNITS = 1000          # points per degree
ESCAPE = -32768

LAYERS = [
    # (name in the file, kind, GeoJSON file, take country names)
    ('borders110', 1, 'ne_110m_admin_0_boundary_lines_land.geojson', False),
    ('borders50', 1, 'ne_50m_admin_0_boundary_lines_land.geojson', False),
    ('coast110', 1, 'ne_110m_coastline.geojson', False),
    ('coast50', 1, 'ne_50m_coastline.geojson', False),
    ('countries50', 2, 'ne_50m_admin_0_countries.geojson', True),
]

PLACES_FILE = 'ne_10m_populated_places_simple.geojson'
PEAKS_FILE = 'ne_10m_geography_regions_elevation_points.geojson'
PEAK_KINDS = {'mountain': 1, 'spot elevation': 2, 'depression': 3, 'plateau': 4, 'pass': 5}
COUNTRIES_LAYER = 'countries50'
NO_COUNTRY = 0xFFFF
FLAG_CAPITAL = 1


def clean(text):
    """Drops invisible marks (Natural Earth has a few left-to-right marks)
    and runs of spaces ('St.  Paul')."""
    if not text:
        return ''
    text = ''.join(ch for ch in text if unicodedata.category(ch) != 'Cf')
    return ' '.join(text.split())


def other_names(properties, name):
    """Natural Earth's alternative names for a place: namealt (several
    separated by commas) and namepar, without repeats or the name itself."""
    result = []
    for field in ('namealt', 'namepar'):
        for alias in (properties.get(field) or '').split(','):
            alias = clean(alias)
            if alias and alias.lower() != name.lower() and \
                    alias.lower() not in (a.lower() for a in result):
                result.append(alias)
    return '|'.join(result)


def ascii_key(name, ascii_name):
    """The name in plain ASCII, for searching: Natural Earth's own ASCII
    name when it is ASCII, otherwise the name with its accents removed."""
    if name.isascii():
        return ''
    if ascii_name and ascii_name.isascii():
        return ascii_name
    decomposed = unicodedata.normalize('NFKD', name)
    return ''.join(ch for ch in decomposed if ch.isascii())


def utf8_field(text):
    encoded = text.encode('utf-8')
    return struct.pack('<H', len(encoded)) + encoded


def encode_places(source, countries):
    """The places section: every populated place, linked to its country by
    the country's ADM0_A3 code, or failing that its name."""
    data = json.loads((source / PLACES_FILE).read_text(encoding='utf-8'))
    by_code = {}
    by_name = {}
    for index, properties in enumerate(countries):
        by_code.setdefault(properties.get('ADM0_A3'), index)
        by_name.setdefault(properties.get('ADMIN'), index)
    places = []
    unlinked = 0
    for feature in data['features']:
        properties = feature['properties']
        name = clean(properties['name'])
        if not name:
            continue
        lon, lat = feature['geometry']['coordinates'][:2]
        country = by_code.get(properties.get('adm0_a3'),
                              by_name.get(properties.get('adm0name'), NO_COUNTRY))
        if country == NO_COUNTRY:
            unlinked += 1
        places.append({
            'name': name,
            'key': ascii_key(name, clean(properties.get('nameascii'))),
            'region': clean(properties.get('adm1name')),
            'aliases': other_names(properties, name),
            'country': country,
            'lon': round(lon * UNITS),
            'lat': round(lat * UNITS),
            'zoom': round(float(properties['min_zoom']) * 10),
            'flags': FLAG_CAPITAL if properties.get('adm0cap') else 0,
            'population': max(0, int(properties.get('pop_max') or 0)),
        })
    places.sort(key=lambda p: (p['zoom'], -p['population'], p['name']))
    out = bytearray(struct.pack('<I', len(places)))
    for place in places:
        out += utf8_field(place['name'])
        out += utf8_field(place['key'])
        out += utf8_field(place['region'])
        out += utf8_field(place['aliases'])
        out += struct.pack('<HiiBBI', place['country'], place['lon'], place['lat'],
                           place['zoom'], place['flags'], place['population'])
    print(f'places: {len(places)}, {unlinked} not linked to a country, '
          f'{sum(1 for p in places if p["aliases"])} with other names')
    return out


def inside(point, rings):
    """Whether a point lies inside a country: crossings of a ray east from
    it, over all the country's rings, so holes count out (even-odd)."""
    x, y = point
    crossings = 0
    for ring in rings:
        for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                crossings += 1
    return crossings % 2 == 1


def encode_peaks(source, countries, country_rings):
    """The peaks section: Natural Earth's named elevation points (mountains,
    spot heights, depressions, plateaus, passes), each linked to the
    countries Natural Earth gives for it (nation1, nation2), or failing
    those the country whose outline holds it. Unnamed points are left out:
    nothing could find them."""
    data = json.loads((source / PEAKS_FILE).read_text(encoding='utf-8'))
    # nation1 and nation2 hold two-letter ISO codes for most points and
    # country names for a few, so both are looked up
    by_name = {}
    for index, properties in enumerate(countries):
        for field in ('ADMIN', 'NAME', 'NAME_LONG', 'ISO_A2', 'ISO_A2_EH', 'WB_A2'):
            value = properties.get(field)
            if value and value != '-99':
                by_name.setdefault(value, index)
    peaks = []
    unlinked = 0
    for feature in data['features']:
        properties = feature['properties']
        name = clean(properties.get('name') or properties.get('name_en') or
                     properties.get('label'))
        if not name:
            continue
        aliases = []
        for field in ('name_alt', 'name_en', 'label'):
            alias = clean(properties.get(field))
            if alias and alias.lower() != name.lower() and \
                    alias.lower() not in (a.lower() for a in aliases):
                aliases.append(alias)
        lon, lat = feature['geometry']['coordinates'][:2]
        point = (round(lon * UNITS), round(lat * UNITS))
        linked = [by_name[n] for n in (properties.get('nation1'), properties.get('nation2'))
                  if n and n in by_name]
        if not linked:
            linked = [i for i, rings in enumerate(country_rings) if inside(point, rings)][:1]
        if not linked:
            unlinked += 1
        linked = (linked + [NO_COUNTRY, NO_COUNTRY])[:2]
        peaks.append({
            'name': name,
            'key': ascii_key(name, ''),
            'aliases': '|'.join(aliases),
            'countries': linked,
            'lon': point[0],
            'lat': point[1],
            'elevation': int(properties.get('elevation') or 0),
            'kind': PEAK_KINDS.get(properties.get('featurecla'), 0),
            'zoom': round(float(properties.get('min_zoom') or 9) * 10),
        })
    peaks.sort(key=lambda p: (p['zoom'], -p['elevation'], p['name']))
    out = bytearray(struct.pack('<I', len(peaks)))
    for peak in peaks:
        out += utf8_field(peak['name'])
        out += utf8_field(peak['key'])
        out += utf8_field(peak['aliases'])
        out += struct.pack('<HHiihBB', peak['countries'][0], peak['countries'][1],
                           peak['lon'], peak['lat'], peak['elevation'], peak['kind'],
                           peak['zoom'])
    print(f'peaks: {len(peaks)}, {unlinked} not in any country, '
          f'{sum(1 for p in peaks if p["countries"][1] != NO_COUNTRY)} on a border, '
          f'{sum(1 for p in peaks if p["aliases"])} with other names')
    return out


def parts_of(geometry):
    """Yields every line or ring of a GeoJSON geometry."""
    kind = geometry['type']
    coords = geometry['coordinates']
    if kind == 'LineString':
        yield coords
    elif kind in ('MultiLineString', 'Polygon'):
        yield from coords
    elif kind == 'MultiPolygon':
        for polygon in coords:
            yield from polygon
    else:
        raise ValueError('unexpected geometry ' + kind)


def quantise(points):
    """Rounds points to whole units and drops repeats."""
    result = []
    for lon, lat, *_ in points:
        point = (round(lon * UNITS), round(lat * UNITS))
        if not result or point != result[-1]:
            result.append(point)
    return result


def encode_part(points):
    out = bytearray(struct.pack('<Iii', len(points), *points[0]))
    prev = points[0]
    for point in points[1:]:
        dlon, dlat = point[0] - prev[0], point[1] - prev[1]
        if -32767 <= dlon <= 32767 and -32767 <= dlat <= 32767:
            out += struct.pack('<hh', dlon, dlat)
        else:
            out += struct.pack('<hii', ESCAPE, *point)
        prev = point
    return out


def build(source, target):
    out = bytearray(b'GDVC' + struct.pack('<HH', 3, len(LAYERS)))
    countries = []
    country_rings = []
    for name, kind, file_name, named in LAYERS:
        data = json.loads((source / file_name).read_text(encoding='utf-8'))
        features = []
        for feature in data['features']:
            minimum = 4 if kind == 2 else 2
            parts = [quantise(p) for p in parts_of(feature['geometry'])]
            parts = [p for p in parts if len(p) >= minimum]
            if not parts:
                continue
            label = feature['properties']['ADMIN'] if named else ''
            features.append((label, parts))
            if name == COUNTRIES_LAYER:
                countries.append(feature['properties'])
                country_rings.append(parts)
        if kind == 1:
            # Lines need no names, so one feature holds them all
            features = [('', [p for _, parts in features for p in parts])]
        out += struct.pack('<BB', kind, len(name)) + name.encode('ascii')
        out += struct.pack('<I', len(features))
        points = 0
        for label, parts in features:
            encoded = label.encode('utf-8')
            out += struct.pack('<H', len(encoded)) + encoded
            out += struct.pack('<I', len(parts))
            for part in parts:
                out += encode_part(part)
                points += len(part)
        print(f'{name}: {len(features)} feature(s), '
              f'{sum(len(p) for _, p in features)} part(s), {points} point(s)')
    out += encode_places(source, countries)
    out += encode_peaks(source, countries, country_rings)
    target.write_bytes(out)
    print(f'wrote {target} ({len(out):,} bytes)')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build(Path(sys.argv[1]), Path(sys.argv[2]))
