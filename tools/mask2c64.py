#!/usr/bin/env python3
"""Convert a 20x40 land/sea mask (rows of '#'=land, '.'=sea) into
the CHARMAP and COLMAP raw files used by WORLDCITIES.
Usage: python3 mask2c64.py assets/worldmask.txt build/CHARMAP build/COLMAP
CHARMAP: 1000 bytes of screen codes ($A0 land, $20 sea)
COLMAP : 1000 bytes of colour RAM values (land 13, sea 6)
"""
import sys

def main():
    inp, outc, outcol = sys.argv[1], sys.argv[2], sys.argv[3]
    rows = [l.rstrip("\n") for l in open(inp) if l.strip()]
    assert len(rows) == 20, f"expected 20 rows, got {len(rows)}"
    chars, cols = bytearray(1000), bytearray(1000)
    for y, row in enumerate(rows):
        assert len(row) == 40, f"row {y} has {len(row)} cols, need 40"
        for x, c in enumerate(row):
            if c == "#":
                chars[y*40+x], cols[y*40+x] = 0xA0, 13
            else:
                chars[y*40+x], cols[y*40+x] = 0x20, 6
    open(outc, "wb").write(chars)
    open(outcol, "wb").write(cols)
    print("wrote CHARMAP and COLMAP")

if __name__ == "__main__":
    main()
