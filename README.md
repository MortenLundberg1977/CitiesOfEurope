# World Cities

A "name the capital" game for the Commodore 64, written in 6502 assembly
with KickAssembler, plus a companion data-file editor. Two programs, two
data files, one disk.

## Gameplay

Press Space on the title screen. Ten capitals are marked one by one on a
hi-res world map with a flashing ring; pick the right city from three
choices with keys **1-3**. After each answer the game shows the city and
its country; press Space for the next one. At the end you get your score out
of 10. Space starts a new game (the map and cities stay in memory, so it
starts straight away).

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
VICE; `run editor` starts CITYEDIT instead.

The script assembles both programs, makes the data files with
`prepare_data.ps1`, and writes a fresh `build\worldcities.d64` with
`WORLDCITIES`, `CITYEDIT`, `CITIES` and `WORLDMAP`. Because the disk is made
fresh each time, changes saved with CITYEDIT are lost on the next build: to
keep a city, add it to `data/cities.csv`.

On Linux or macOS use `tools/build.sh` (needs Python 3 with Pillow). The
GitHub Actions workflow runs it on every push: open the latest **Build** run
on the **Actions** tab and download the **worldcities-d64** artifact.

On a C64 or in VICE without autostart:

```
LOAD"WORLDCITIES",8,1
RUN
```

## CITYEDIT

Edits the CITIES file on the disk. Keys: cursor up/down to select, **A** add,
**E** edit, **D** delete, **S** save, **R** reload, **Q** back to the title.
While editing, type over the field, Delete to go back, Return for the next
field (city, country, latitude, longitude). Coordinates are degrees with two
decimals and a sign, e.g. `+55.68` and `-171.77`.

## Project files

- `src/worldcities.asm` — the game: loading, map display (bitmap with a raster
  split to text for the bottom five rows), marker sprite, questions, score
- `src/cityedit.asm` — the CITIES editor
- `data/cities.csv` — the capitals: city, country, latitude, longitude
  (names up to 16 characters)
- `assets/worldmap.png` — the 320x160 world map (black land, white sea)
- `assets/title.png` (optional) — the title picture, any size; the build
  scales it to fit the screen and converts it to a multicolour bitmap
  (`TITLESCR` and `TITLEBMP` on the disk). It shows while the map and cities
  load. Without it the game shows a text title.
- `prepare_data.ps1` — turns the CSV and the map picture into `CITIES` and
  `WORLDMAP` (49-byte city records loading to `$6000`; a hi-res bitmap
  loading to `$2000`)
- `build.bat` — KickAssembler build, D64 packaging, and optional VICE launch
- `tools/build.sh`, `tools/prepare_data.py` — the same build for Linux/macOS
- `tools/render_map.ps1` — remakes `assets/worldmap.png` from Natural Earth's
  public-domain `ne_110m_land.geojson`

The map uses an equirectangular projection: longitude -180..180 across the 320
pixels and latitude 84°N..60°S down the 160 pixels (Antarctica is left out).
