# Adding places to GDEMFetch

GDEMFetch's search finds four kinds of place, and each is added a
different way:

| Kind | Shown on the map | Where it comes from | How to add one |
|------|------------------|---------------------|----------------|
| Markers | Yes, always (View > Show Markers) | `markers.json` in the settings folder | In the program, or by editing the file |
| Countries | As borders | `maps/world_vectors.bin` (Natural Earth) | Rebuild from Natural Earth |
| Towns and cities | As labels (View > Show Towns and Cities) | `maps/world_vectors.bin` (Natural Earth) | Rebuild from Natural Earth |
| Easter eggs | Never: only the search finds them | `maps/easter_eggs.json` | Edit the file and rebuild |

For your own places (Home, Work, a hill you want the elevation of), use
**markers**. Easter eggs are places shipped with the program for everyone.

## Finding a place's position

Every place needs a latitude and longitude in **decimal degrees**:

- latitude from -90 (south pole) to 90 (north pole), north positive;
- longitude from -180 to 180, east of Greenwich positive, west negative.

So Manchester is about `53.4808, -2.2426` and Area 51 `37.2333, -115.8083`.
Four decimal places is about 10 metres, which is plenty.

Ways to get one:

- **Google Maps:** right-click the spot; the first line of the menu is
  the position (`53.48083, -2.24263`), and clicking it copies it.
- **A Google Maps share link** (`maps.app.goo.gl/...`) often opens a
  **Plus Code** such as `8Q9833WH+Q8` rather than numbers. Paste the code
  into Google Maps' search box and right-click the pin it drops to get the
  numbers, or decode it with any Open Location Code tool.
- **Degrees, minutes and seconds** (`37°14′0″N 115°48′30″W`, as on
  Wikipedia): degrees + minutes / 60 + seconds / 3600, negative for south
  or west, so `37.2333, -115.8083`.
- **GDEMFetch itself:** the status bar shows the position under the
  pointer.

Check the result on a satellite view before relying on it: sites that
list "coordinates of" places are often wrong. One gave the Squid Game
island 27 km from where it really is.

## Markers

**In the program:** Ctrl + click the map (Cmd + click on a Mac), or use
**Markers > Add Marker at Map Centre...**, and type a name.
**Markers > Edit Markers...** goes to, renames or deletes them. Markers
are saved as soon as they change.

**By hand:** markers are kept in `markers.json` in the settings folder:

| System | Settings folder |
|--------|-----------------|
| Windows | `%APPDATA%\GDEM` |
| macOS | `~/Library/Application Support/GDEM` |
| Linux | `$XDG_CONFIG_HOME/GDEM`, or `~/.config/GDEM` |

```json
{
  "format": 1,
  "markers": [
    { "name": "Home", "lat": 53.4808, "lon": -2.2426 },
    { "name": "Work", "lat": 53.4794, "lon": -2.2453 }
  ]
}
```

Close GDEMFetch before editing it, or the program will write its own copy
over yours the next time a marker changes. A name may be up to 80
characters; line breaks are turned into spaces. A marker without a name,
or with a latitude outside -90 to 90, is dropped when the file is read.
Copying the file to another computer's settings folder copies the
markers.

## Easter eggs

Easter eggs are hidden places: never drawn on the map, found only by
searching. They live in `maps/easter_eggs.json`, which is built into the
program as the `EASTEREGGS` resource, so after editing it **rebuild
GDEMFetch** (nothing is deployed beside the program). If the IDE does not
notice the change, use Project > Build rather than Compile.

```json
{
  "format": 1,
  "places": [
    {
      "name": "Area 51",
      "lat": 37.2333,
      "lon": -115.8083,
      "sizeKm": 12,
      "aliases": ["Groom Lake", "Dreamland", "UFO", "Aliens"],
      "note": "UFOs, conspiracy theories and a very long runway."
    }
  ]
}
```

| Field | Needed | Meaning |
|-------|--------|---------|
| `name` | Yes | What the search lists, followed by the country it is in when the country outlines hold it (`Area 51, United States of America`). |
| `lat`, `lon` | Yes | The middle of the place, in decimal degrees. |
| `sizeKm` | No | How much to show when it is found, in kilometres across: the map zooms so that much fills most of the window. Leave it out, or 0, to move there at the zoom already in use. |
| `aliases` | No | Other words that find it. Each is listed as `Name (alias)` when it is what matched. |
| `note` | No | One line shown in the status bar and on the Debug tab when it is found. |

Choosing `sizeKm`: about the size of the thing itself, a little more for
context. An airbase, 10 to 15; an island of a few square kilometres, 4;
a building, 1. The map cannot zoom in further than about 400 pixels a
degree, so anything much under a kilometre is shown at that zoom.

An entry with no name, or with a latitude outside -90 to 90 or a
longitude outside -180 to 180, is left out, with a `WARNING: easter egg
left out: ...` line on the Debug tab saying which; the rest still load. A
file that is not valid JSON loses all of them, with a warning saying why.
Check the JSON in any validator before rebuilding.

## How names are matched

The same rules apply to every kind of place, so they are worth knowing
when choosing names and aliases:

- Case, accents and punctuation do not matter: `zurich` finds Zürich,
  `st johns` finds St. John's. Apostrophes join letters (`ndjamena`);
  other punctuation separates words.
- What is typed is matched against the whole name, then the start of the
  name, then the start of any later word (`york` finds New York), then
  anywhere inside it.
- Spelling mistakes are forgiven from four letters typed: one mistake
  (a wrong, missing, extra or swapped letter) from 4 letters, two from 7,
  three from 11. Up to three letters must be exact, so a short alias such
  as `UFO` is only found by typing it exactly.
- Markers are listed before countries, countries before easter eggs, and
  easter eggs before towns and cities, when they match equally well.

So an alias is worth adding for any name people might type instead: an
old or local name (`Seongapdo`), a nickname (`Dreamland`), or a word
someone looking for it would try (`UFO`). There is no need to add
spellings that differ only by accents, case or a typo.

## Towns, cities and countries

These come from [Natural Earth](https://www.naturalearthdata.com), in the
public domain, through `tools/build_vectors.py`, which writes
`maps/world_vectors.bin` (the `WORLDVECTORS` resource). Rather than
editing that file, add personal places as markers and shared ones as easter
eggs. To update the data from a newer Natural Earth, follow the script's
comments: it needs six GeoJSON files, which a sparse clone of
<https://github.com/nvkelso/natural-earth-vector> can fetch without the
whole repository. Then rebuild GDEMFetch. `GDEMVectors.pas` documents the
file's format.
