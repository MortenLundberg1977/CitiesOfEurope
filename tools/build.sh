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
ka src/worldcities.asm -odir ../build -symbolfile
ka src/cityedit.asm -odir ../build
python3 "$TOOLS/prepare_data.py"

# Like build.bat: a fresh disk each time. Names must be lowercase for c1541.
rm -f build/worldcities.d64
c1541 -format "worldcities,64" d64 build/worldcities.d64 \
  -write build/worldcities.prg worldcities \
  -write build/cityedit.prg cityedit \
  -write build/cities.prg cities \
  -write build/worldmap.prg worldmap >/dev/null
if [ -f assets/title.png ]; then
  c1541 build/worldcities.d64 -write build/titlescr.prg titlescr -write build/titlebmp.prg titlebmp >/dev/null
fi
echo "Built build/worldcities.prg ($(wc -c <build/worldcities.prg | tr -d ' ') bytes) and build/worldcities.d64"

if [ "${1:-}" = "run" ]; then
  if [ "${2:-}" = "editor" ]; then
    x64sc -8 build/worldcities.d64 -autostart build/cityedit.prg
  else
    x64sc -8 build/worldcities.d64 -autostart build/worldcities.prg
  fi
fi
