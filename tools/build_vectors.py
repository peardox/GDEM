"""Builds maps/world_vectors.bin, the country borders, coastlines and
country outlines GDEMFetch draws on its world map, from Natural Earth.

Natural Earth (https://www.naturalearthdata.com) is in the public domain.
Get its GeoJSON files from https://github.com/nvkelso/natural-earth-vector
(the geojson folder); only these five are needed:

    ne_110m_admin_0_boundary_lines_land.geojson
    ne_50m_admin_0_boundary_lines_land.geojson
    ne_110m_coastline.geojson
    ne_50m_coastline.geojson
    ne_50m_admin_0_countries.geojson

Usage, from the repository root:

    python3 tools/build_vectors.py <folder with the geojson files> maps/world_vectors.bin

The output is read by GDEMVectors.pas, which documents the same format.
All numbers are little-endian.

    'GDVC'                magic
    UInt16 version        1
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

Points are rounded to a thousandth of a degree (about 110 m), far finer
than the 1:50m data itself, and repeated points left by the rounding are
dropped. Lines need at least 2 points and rings at least 4, or they are
left out.
"""
import json
import struct
import sys
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
    out = bytearray(b'GDVC' + struct.pack('<HH', 1, len(LAYERS)))
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
    target.write_bytes(out)
    print(f'wrote {target} ({len(out):,} bytes)')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build(Path(sys.argv[1]), Path(sys.argv[2]))
