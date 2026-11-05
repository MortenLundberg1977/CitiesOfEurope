# World Cities

A "name the capital" game for the Commodore 64, written in 6502/6510
assembler (ACME syntax), plus a companion data-file editor. Two PRGs,
one data file, one disk.

## How to get the ready-made disk image

1. Go to the **Actions** tab of this repository.
2. Open the latest **Build** run (it starts automatically on every push,
   or run it manually with "Run workflow").
3. At the bottom of the run page, download the artifact **worldcities-d64**.
4. Unzip it: you get `worldcities.d64`.

## Running (VICE or a real 1541)

Attach `worldcities.d64` as drive 8, then:

```
LOAD"WORLDCITIES",8,1
RUN
```

10 random cities are marked one by one on the world map; pick the
right city name from three options with keys **1-3**. Needs the
CHARMAP, COLMAP and CITIES files that are on the same disk.

The editor:

```
LOAD"CITYEDIT",8,1
RUN
```

CITYEDIT edits the CITIES data file (record: city, country, lat, lon).
Keys: cursor up/down to select, **A** add, **E** edit, **D** delete,
**S** save, **R** reload, **Q** quit to title.

## Building from source

You need `acme` (the cross-assembler) and Python 3:

```
cd src
acme --cpu 6510 worldcities.asm     # -> worldcities.prg
acme --cpu 6510 cityedit.asm        # -> cityedit.prg
```

Then build the data files and the disk image:

```
python3 tools/csv2c64.py data/cities.csv build/CITIES
python3 tools/mask2c64.py assets/worldmask.txt build/CHARMAP build/COLMAP
python3 tools/mkd64.py build/worldcities.d64 "MY DISK" \
   src/worldcities.prg WORLDCITIES prg \
   src/cityedit.prg CITYEDIT prg \
   build/CITIES CITIES seq \
   build/CHARMAP CHARMAP seq \
   build/COLMAP COLMAP seq
```

Or just push to GitHub and download the artifact from Actions, which
does all of the above for you (`.github/workflows/build.yml`).

## Data format

CITIES is a raw (no load address) file of fixed-width records,
40 bytes each:

| cols  | field   | notes                          |
|-------|---------|--------------------------------|
| 0-12  | city    | 13 chars, space padded         |
| 13    | ","     |                                |
| 14-23 | country | 10 chars, space padded         |
| 24    | ","     |                                |
| 25-30 | lat     | 6 chars, e.g. `-55.68`        |
| 31    | ","     |                                |
| 32-38 | lon     | 7 chars, e.g. `+123.45`      |
| 39    | CR      | $0D                            |

Maximum 160 records. `data/cities.csv` is the readable master;
`data/CITIES` is the generated C64 file.

## Map

The game screen is a 40x20-cell world map (see `assets/MAP_NOTE.md`
for why the originally uploaded image could not be used). Land is a
solid block, sea blank; each round's target city is marked in red.

## Status

v0.1, untested on real hardware. Written in ACME 6510 assembler by
request; expect minor bugs and rounding in the map projection.
