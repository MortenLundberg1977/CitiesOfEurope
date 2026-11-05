#!/usr/bin/env python3
"""Convert a world map image to CHARMAP/COLMAP.
Usage: python3 png2c64map.py map.png build/CHARMAP build/COLMAP
Needs Pillow: pip install Pillow
"""
import sys
from PIL import Image

def main():
    img = Image.open(sys.argv[1]).convert("L")
    img = img.resize((200, 100))          # oversample
    chars, cols = bytearray(1000), bytearray(1000)
    for y in range(20):
        for x in range(40):
            # a cell is land if most pixels in its block are dark
            dark = 0
            for py in range(y*5, y*5+5):
                for px in range(x*5, x*5+5):
                    if img.getpixel((px, py)) < 128:
                        dark += 1
            if dark > 12:
                chars[y*40+x], cols[y*40+x] = 0xA0, 13
            else:
                chars[y*40+x], cols[y*40+x] = 0x20, 6
    open(sys.argv[2], "wb").write(chars)
    open(sys.argv[3], "wb").write(cols)
    print("wrote CHARMAP and COLMAP")

if __name__ == "__main__":
    main()
