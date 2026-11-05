#!/usr/bin/env bash
# Linux/macOS equivalent of build.bat: assemble, make the data files, make the D64.
# Usage: tools/build.sh [run [editor]]   ("run" starts the game in VICE afterwards)
# Needs Java, VICE (c1541, x64sc), Python 3 with Pillow, and KickAss.jar.
set -euo pipefail
TOOLS="$(cd "$(dirname "$0")" && pwd)"
DIR="$(dirname "$TOOLS")"
cd "$DIR"

if [ -z "${KICKASS_JAR:-}" ]; then
  for c in "$DIR/../KickAss.jar" "$TOOLS/KickAss.jar" "$DIR/KickAss.jar"; do
    [ -f "$c" ] && KICKASS_JAR="$c" && break
  done
fi
[ -f "${KICKASS_JAR:-}" ] || { echo "KickAss.jar not found. Set KICKASS_JAR to its full path."; exit 1; }

mkdir -p build
# -odir is relative to the source file, so ../build is this folder's build.
ka() { java -jar "$KICKASS_JAR" "$@" >build/kickass.log 2>&1 || { grep -v JAVA_TOOL build/kickass.log; exit 1; }; }
ka src/citiesofeurope.asm -odir ../build -symbolfile
ka src/cityedit.asm -odir ../build
# Keep the right/wrong answer counts the game saved in CITIES on the old disk.
rm -f build/oldcities.prg
if [ -f build/citiesofeurope.d64 ]; then
  c1541 build/citiesofeurope.d64 -read cities build/oldcities.prg >/dev/null 2>&1 || true
fi
python3 "$TOOLS/prepare_data.py"

# Like build.bat: a fresh disk each time. Names must be lowercase for c1541.
rm -f build/citiesofeurope.d64
c1541 -format "europe,64" d64 build/citiesofeurope.d64 \
  -write build/citiesofeurope.prg citiesofeurope \
  -write build/cityedit.prg cityedit \
  -write build/cities.prg cities \
  -write build/maps.prg maps \
  -write build/flags.prg flags >/dev/null
if [ -f assets/title.png ]; then
  c1541 build/citiesofeurope.d64 -write build/titlescr.prg titlescr -write build/titlebmp.prg titlebmp >/dev/null
fi
echo "Built build/citiesofeurope.prg ($(wc -c <build/citiesofeurope.prg | tr -d ' ') bytes) and build/citiesofeurope.d64"

if [ "${1:-}" = "run" ]; then
  if [ "${2:-}" = "editor" ]; then
    x64sc -8 build/citiesofeurope.d64 -autostart build/cityedit.prg
  else
    x64sc -8 build/citiesofeurope.d64 -autostart build/citiesofeurope.prg
  fi
fi
