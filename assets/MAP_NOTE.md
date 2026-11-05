# About the map

The original world-map PNG uploaded at project start turned out to be a
164-byte placeholder image (a compass rose), so it could not be used as a
map source. Instead the game map is generated from `assets/worldmask.txt`,
a hand-authored 20x40 land/sea mask ('#' = land, '.' = sea), converted to the
CHARMAP/COLMAP files by `tools/mask2c64.py`.

If you have a proper world map image, `tools/png2c64map.py` can generate
CHARMAP/COLMAP from a PNG directly (needs Pillow).
