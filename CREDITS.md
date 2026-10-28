# Credits and licences

GDEM's own source code is under the MIT licence (see [LICENSE](LICENSE)),
the least restrictive licence that sits with everything else here: the
permissive libraries (Neon, Skia, Skia4Delphi) allow any licence, and the
commercial Gorilla3D runtime may be built into a program under MIT. The
non-commercial terms of the best imagery (Sentinel-2 cloudless, below)
bind whoever uses that imagery, not GDEM's code.

Everything below belongs to others and keeps its own terms. The table
says what each piece is, where it is, and what its licence asks of us;
the notes after it cover the ones that need care when GDEMFetch or
TileMaker is given to anyone else.

| What | Used for | Where it is | Licence | What it asks |
|------|----------|-------------|---------|--------------|
| **ASTER GDEM V3** (NASA, METI, AIST, Japan Space Systems, and the U.S./Japan ASTER Science Team; distributed by NASA's LP DAAC) | The elevation tiles GDEMFetch downloads and draws | Downloaded by each user; not in the repository | NASA's open data policy: no restrictions on use | Cite the data set (below) |
| **NASA Earthdata** (CMR search, Earthdata Login, Earthdata Cloud) | Finding and downloading the tiles | Services, used at run time | NASA's terms of use for its services | A free Earthdata account per user |
| **Natural Earth** 5.2.0-pre (commit `ca96624`) | Borders, coastlines, countries, towns and cities, mountains | Converted into `maps/world_vectors.bin` by `tools/build_vectors.py`; linked into GDEMFetch | Public domain | Nothing; credit given anyway |
| **World map image** `8081_earthmap10k` (Planet Pixel Emporium, James Hastings-Trew) | The high-resolution map | The source image is kept out of the repository; the tile set made from it is in `maps/tiles/` and `maps/tiles.zip`, and is linked into GDEMFetch | Free to use as a resource in rendering; not to be redistributed as is, nor included in a distributed program without permission | **To be settled:** see note 1 |
| **World map image** `maps/world_1080x540.jpg` | The map drawn under the tile set, and while it loads | Linked into GDEMFetch | **Not recorded** | **To be settled:** see note 1 |
| **Sentinel-2 cloudless** (EOX IT Services GmbH; contains modified Copernicus Sentinel data) | Planned: the 3D view's Realistic imagery | Will be downloaded by each user and cached; not in the repository | CC BY-NC-SA 4.0 for the recent years (2016's is CC BY 4.0) | Non-commercial use of the imagery only; EOX's credit shown legibly wherever the imagery is shown (note 5) |
| **Delphi Neon** (Paolo Rossi) | Reading and writing JSON | `delphi-neon/` (submodule) | MIT, Copyright (c) 2015 Paolo Rossi | Keep its copyright and licence notice |
| **FastMM5** (Pierre le Riche) | The memory manager and leak reports on Windows | `FastMM5/` (submodule); linked into Windows builds | Dual: GPL v3 at no cost, or a commercial licence | **A commercial licence is to be bought:** see note 2 |
| **Gorilla3D** 1.5.3 | The 3D tab | Installed in Delphi; not in the repository; its runtime is compiled into GDEMFetch | Commercial (held) | A licence for each developer who builds GDEMFetch; see its terms for shipping the runtime |
| **Skia** (Google) and **Skia4Delphi** | Drawing the map and instruments | Comes with Delphi; `sk4d.dll` or `libsk4d.so` is deployed beside GDEMFetch | Skia: BSD 3-clause; Skia4Delphi: MIT | Keep both copyright and licence notices with the program (note 3) |
| **RAD Studio** FMX runtime and **styles** (Embarcadero) | The program itself; the themes | The runtime is compiled in; the `.style` files from RAD Studio's `Redist\styles\Fmx` are kept in `styles/` and linked into GDEMFetch | RAD Studio's licence, which lets its `Redist` files be shipped as part of a program built with it | Note 4 |
| **Sprite3D** (peardox) | Code ported into GDEM: the themes, the Windows graphics processor choice, the display refresh rate | The owner's own project | The owner's | Nothing |

## Citing ASTER GDEM

NASA/METI/AIST/Japan Spacesystems and U.S./Japan ASTER Science Team
(2019). *ASTER Global Digital Elevation Model V003.* NASA EOSDIS Land
Processes Distributed Active Archive Center.
<https://doi.org/10.5067/ASTER/ASTGTM.003>

## Natural Earth

Made with Natural Earth. Free vector and raster map data at
<https://www.naturalearthdata.com>.

## Notes

1. **The world map images.** Planet Pixel Emporium's terms let its maps be
   used as a resource for rendering, a simulator or game included, but not
   redistributed as they are, and not included in a distributed program
   without permission. The tile set in `maps/tiles/` (and `maps/tiles.zip`,
   linked into GDEMFetch) is the image resampled and cut up, so the image
   is, in effect, in the public repository and in every copy of GDEMFetch.
   Until permission is confirmed, or the image is replaced by one with an
   open licence (NASA's Blue Marble is free of restrictions), treat the
   tile set as not covered by GDEM's licence. Where
   `maps/world_1080x540.jpg` came from is not recorded; add it here.
2. **FastMM5 and the GPL.** FastMM5 is free under the GPL v3, but a
   program built with it may then only be given out under the GPL, and the
   GPL cannot cover GDEMFetch's Windows builds, which also contain the
   commercial Gorilla3D runtime. So until the commercial FastMM5 licence is
   bought (planned), Windows builds of GDEMFetch should not be given to
   anyone else. (TileMaker has no Gorilla3D, so its Windows builds could be
   given out under the GPL v3 with their source, but not under MIT alone.)
   The source code can be shared freely: the repository only points to
   FastMM5 as a submodule. macOS and Linux builds do not use FastMM5. Once
   the licence is bought, update this note and the table above.
3. **Skia's notices.** Skia4Delphi's library carries Skia's code, so a
   copy of GDEMFetch given to anyone else should carry Skia's BSD 3-clause
   notice and Skia4Delphi's MIT notice, for example in a text file beside
   the program.
4. **RAD Studio's styles.** RAD Studio lets the files in its `Redist`
   folder be shipped as part of a program built with it, which covers the
   styles linked into GDEMFetch. Keeping copies in the public repository
   is a different matter; `styles/buildstyles.cmd` copies any missing
   style from RAD Studio's own folder before each build, so the copies
   in `styles/` could be dropped from the repository if that is a concern.

5. **Sentinel-2 cloudless.** EOX's licence
   (<https://cloudless.eox.at/documentation/license>) asks for its credit,
   which names EOX IT Services GmbH and says the imagery contains modified
   Copernicus Sentinel data of the year shown, to be legible wherever the
   imagery is shown; for an interactive map, in the map itself. The exact
   wording will be taken from that page when the imagery is added, and the
   3D view will draw it in a corner whenever Realistic is on. The
   non-commercial and share-alike terms apply to the imagery, not to
   GDEM's code: anyone using GDEM commercially would choose the 2016
   imagery (CC BY 4.0) or NASA's instead.

These notes summarise each licence as it was read on 28 October 2026;
they are not legal advice, and each licence's own text is what counts.
