# World Cities

A "name the capital" game for the Commodore 64, written in 6502 assembly
with KickAssembler, plus a companion data-file editor.

## Gameplay

Press Space on the title screen once the disk has stopped loading (about a
minute on a real 1541; use warp in VICE to skip the wait). Ten capitals are
marked one by one with a flashing ring on a hi-res map of their part of the
world: Europe, Middle East, Africa, Asia, Oceania, North & Central America or
South America. Pick the right city from three choices with keys **1-3**; the
two wrong choices come from the same region. After each answer the game shows
the city and its country; press Space for the next one. At the end you get
your score out of 10, and Space starts a new game. A right answer plays a
rising chime, a wrong one a low buzz.

The game counts right and wrong answers for every city and saves the counts
to the CITIES file on the disk after each game ("SAVING SCORES..."). The
counts are kept when you rebuild the disk.

The city list (`data/cities.csv`) has the capitals of all 193 UN member
states plus Vatican City, Palestine, Kosovo and Taiwan: 197 in all. The game
holds up to 250.

## Build and run

Install Java and VICE, including `c1541.exe` and `x64sc.exe`, then run
`build.bat` from this directory. The script looks for `KickAss.jar` here or in
the parent directory. To use a different installation, set `KICKASS_JAR`.
`c1541.exe` must be on `PATH`, or set `C1541_EXE` to its full path.

```bat
build.bat
build.bat run
build.bat run editor
build.bat pull run
```

`pull` gets the latest version from GitHub before building (it needs Git for
Windows). Give a branch name to switch to that branch first
(`build.bat pull my-branch run`). If you have local changes that are not
committed, the pull stops so nothing is overwritten. `run` starts the game in
VICE; `run editor` starts CITYEDIT instead. Close VICE before building: the
build can't replace a disk that VICE has open.

The script assembles both programs, makes the data files with
`prepare_data.ps1`, and writes a fresh `build\worldcities.d64` with
`WORLDCITIES`, `CITYEDIT`, `CITIES`, `MAPS`, `TITLESCR` and `TITLEBMP`. The
cities come from `data/cities.csv`, with the answer counts copied from the old
disk (matched by city and country). Other changes saved with CITYEDIT are lost
on the next build: to keep a city, add it to `data/cities.csv`.

On Linux or macOS use `tools/build.sh` (needs Python 3 with Pillow). The
GitHub Actions workflow runs it on every push: open the latest **Build** run
on the **Actions** tab and download the **worldcities-d64** artifact.

On a C64 or in VICE without autostart:

```
LOAD"WORLDCITIES",8,1
RUN
```

## The region maps

Each region in `data/regions.csv` has a top-left corner (`LON0`, `LAT0`, in
degrees) and a scale (`DX`, `DY`: hundredths of a degree per pixel). Its map is
320x160 pixels, so it covers `3.2 × DX` degrees of longitude and `1.6 × DY`
degrees of latitude. The same numbers are used to draw the map
(`tools/render_map.ps1`) and to place the marker in the game:

```
x = (lon − LON0) / DX      the difference wraps at 360°, so a region may
y = (LAT0 − lat) / DY      cross the 180° line (Oceania does)
```

so the marker always lands where the city is on the map. `DY` is a little
larger than `DX × cos(latitude)` would make it, which stretches the maps
vertically so the regions fill the 2:1 map area.

Each city has a region number in the `REGION` column of `data/cities.csv`.
The build stops if a city lies outside its region's map, or if a region has
fewer than 3 cities.

To change a region, edit `data/regions.csv` and redraw the maps:

```bat
powershell -File tools\render_map.ps1 path\to\ne_50m_land.geojson
```

The GeoJSON is Natural Earth's public-domain 1:50m land outlines
(`geojson/ne_50m_land.geojson` in
https://github.com/nvkelso/natural-earth-vector). It takes a few minutes;
commit the new `assets/maps/region*.png`.

## CITYEDIT

Edits the CITIES file on the disk. Keys: cursor up/down to select, **A** add,
**E** edit, **D** delete, **S** save, **R** reload, **Q** back to the title.
While editing, type over the field, Delete to go back, Return for the next
field (city, country, latitude, longitude, region). Coordinates are degrees
with two decimals and a sign, e.g. `+55.68` and `-171.77`. CITYEDIT doesn't
check that a city fits its region's map; the build does.

## Project files

- `src/worldcities.asm` — the game: loading, region maps (unpacked into a
  bitmap with a raster split to text for the bottom five rows), marker sprite,
  questions, score, answer counts
- `src/cityedit.asm` — the CITIES editor
- `data/cities.csv` — the capitals: city, country, latitude, longitude, region
  (names up to 16 characters)
- `data/regions.csv` — the regions: name, corner and scale of each map
- `assets/maps/region*.png` — the region maps (320x160, black land, white sea)
- `assets/title.png` (optional) — the title picture, any size; the build
  scales it to fit the screen and converts it to a multicolour bitmap. It
  shows while the maps and cities load. Without it the game shows a text title.
- `prepare_data.ps1` — makes `CITIES` (59-byte records loading to `$3900`),
  `MAPS` (region table and RLE-packed maps loading to `$7400`) and the title
  files; the record and file layouts are described at the top of each part
- `build.bat` — KickAssembler build, D64 packaging, and optional VICE launch
- `tools/build.sh`, `tools/prepare_data.py` — the same build for Linux/macOS
- `tools/render_map.ps1` — draws `assets/maps/` from Natural Earth data
