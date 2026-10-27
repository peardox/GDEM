"""Packs a tile set made by TileMaker into one zip file, so GDEMFetch can
link it into the program as a resource and nothing has to be deployed.

Usage, from the repository root:

    python3 tools/pack_tiles.py maps/tiles maps/tiles.zip

The first argument is the tile set's folder (the one holding
tileset.json), the second the zip to write. GDEMFetch links
maps/tiles.zip in as the MAPTILES resource; run this again whenever the
tile set changes, then rebuild.

The zip holds tileset.json and each level's tiles under the same names as
in the folder, with forward slashes (such as 10800x5400/r000_c000.jpg),
which is how GDEMTileCache.pas looks them up. Entries are stored, not
compressed, since JPEG, WebP and PNG tiles are compressed already, so a
tile is read straight out of the program's memory. They are written in
sorted order with a fixed date, so packing the same tile set twice gives
the same file.

Every tile tileset.json describes must be present, and nothing else is
packed; the script stops with a message if a tile is missing.
"""

import json
import os
import sys
import zipfile

# A fixed date for every entry, so the zip depends only on the tiles
FIXED_DATE = (1980, 1, 1, 0, 0, 0)


def tile_names(tileset):
    """The zip names of every tile tileset.json describes, in order."""
    ext = tileset['imageFormat']
    for level in tileset['levels']:
        for row in range(level['rows']):
            for col in range(level['columns']):
                yield '%s/r%03d_c%03d.%s' % (level['folder'], row, col, ext)


def add(zf, name, path):
    """Stores one file in the zip under name, with the fixed date."""
    info = zipfile.ZipInfo(name, FIXED_DATE)
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o644 << 16
    with open(path, 'rb') as f:
        zf.writestr(info, f.read())


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    folder, out = sys.argv[1], sys.argv[2]
    with open(os.path.join(folder, 'tileset.json'), 'rb') as f:
        tileset = json.loads(f.read().decode('utf-8'))

    names = list(tile_names(tileset))
    missing = [n for n in names if not os.path.isfile(os.path.join(folder, *n.split('/')))]
    if missing:
        sys.exit('%d tile(s) missing, such as %s' % (len(missing), missing[0]))

    temp = out + '.tmp'
    total = 0
    with zipfile.ZipFile(temp, 'w', zipfile.ZIP_STORED) as zf:
        add(zf, 'tileset.json', os.path.join(folder, 'tileset.json'))
        for name in sorted(names):
            path = os.path.join(folder, *name.split('/'))
            add(zf, name, path)
            total += os.path.getsize(path)
    os.replace(temp, out)
    print('%s: tileset.json and %d tiles, %.1f MB of tiles, %.1f MB in all'
          % (out, len(names), total / 1e6, os.path.getsize(out) / 1e6))


if __name__ == '__main__':
    main()
