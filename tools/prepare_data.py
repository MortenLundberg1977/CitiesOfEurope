#!/usr/bin/env python3
"""Python port of prepare_data.ps1: builds build/cities.prg, build/maps.prg and the
title files. See prepare_data.ps1 for the file layouts.
Usage: python3 tools/prepare_data.py   (run from anywhere; needs Pillow)
"""
import csv
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")


def write_prg(name, load_address, data):
    with open(os.path.join(BUILD, name), "wb") as f:
        f.write(bytes([load_address & 0xFF, load_address >> 8]) + bytes(data))


def coord(value, width):
    text = ("-" if value < 0 else "+") + f"{abs(value):.2f}"
    if len(text) > width:
        raise SystemExit(f"Coordinate {value} does not fit in {width} characters.")
    return text.rjust(width)


def load_regions():
    with open(os.path.join(ROOT, "data", "regions.csv")) as f:
        regions = list(csv.DictReader(f))
    for i, r in enumerate(regions):
        if int(r["ID"]) != i + 1:
            raise SystemExit("data/regions.csv: IDs must be 1, 2, 3... in order.")
        if len(r["NAME"]) > 16:
            raise SystemExit(f"Region name {r['NAME']} is longer than 16 characters.")
    return regions


def old_counts():
    """Answer counts from build/oldcities.prg (CITIES copied off the old disk)."""
    path = os.path.join(BUILD, "oldcities.prg")
    counts = {}
    if os.path.exists(path):
        old = open(path, "rb").read()
        o = 2
        while o + 59 <= len(old) and old[o] != 0 and old[o + 58] == 13:
            counts[old[o:o + 33].decode("ascii")] = old[o + 51:o + 58].decode("ascii")
            o += 59
        os.remove(path)
    return counts


def cities(regions):
    counts = old_counts()
    out = bytearray()
    count = kept = 0
    per_region = [0] * len(regions)
    with open(os.path.join(ROOT, "data", "cities.csv")) as f:
        next(f)
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 5 or not parts[0]:
                continue
            city, country = parts[0].strip().upper(), parts[1].strip().upper()
            if len(city) > 16 or len(country) > 16:
                raise SystemExit(f"Name longer than 16 characters: {city} / {country}")
            lat, lon, rid = float(parts[2]), float(parts[3]), int(parts[4])
            if not 1 <= rid <= len(regions):
                raise SystemExit(f"{city} has an unknown region {rid}.")
            r = regions[rid - 1]
            dlon = round(lon * 100) - int(r["LON0"]) * 100
            if dlon < 0:
                dlon += 36000
            px = dlon // int(r["DX"])
            py = (int(r["LAT0"]) * 100 - round(lat * 100)) // int(r["DY"])
            if px >= 320 or py < 0 or py >= 160:
                raise SystemExit(f"{city} is outside the {r['NAME']} map.")
            per_region[rid - 1] += 1
            key = city.ljust(16) + "," + country.ljust(16)
            stats = counts.get(key, "000,000")
            if stats != "000,000":
                kept += 1
            rec = (key + "," + coord(lat, 6) + "," + coord(lon, 7) + "," +
                   str(rid) + "," + stats + "\r")
            out += rec.encode("ascii")
            count += 1
    if count > 250:
        raise SystemExit(f"data/cities.csv has {count} cities; the game holds at most 250.")
    for r, n in zip(regions, per_region):
        if n < 3:
            raise SystemExit(f"Region {r['NAME']} needs at least 3 cities, has {n}.")
    out.append(0)
    write_prg("cities.prg", 0x3900, out)
    if kept:
        print(f"Kept the answer counts of {kept} cities from the old disk.")


def maps(regions):
    base = 0x7400
    header = bytearray([len(regions)])
    packed = bytearray()
    start = base + 1 + 24 * len(regions)
    for r in regions:
        path = os.path.join(ROOT, "assets", "maps", f"region{r['ID']}.png")
        img = Image.open(path).convert("RGB")
        if img.size != (320, 160):
            raise SystemExit(f"{path} must be 320x160 pixels.")
        bitmap = bytearray(6400)
        for y in range(160):
            for x in range(320):
                if sum(img.getpixel((x, y))) < 384:
                    bitmap[(y // 8) * 320 + (x // 8) * 8 + (y % 8)] |= 0x80 >> (x % 8)
        address = start + len(packed)
        i = 0
        while i < 6400:
            b = bitmap[i]
            if b in (0, 255):
                run = 1
                while i + run < 6400 and run < 255 and bitmap[i + run] == b:
                    run += 1
                packed += bytes([b, run])
                i += run
            else:
                packed.append(b)
                i += 1
        for word in (int(r["LON0"]) * 100, int(r["LAT0"]) * 100):
            header += (word & 0xFFFF).to_bytes(2, "little")
        header += bytes([int(r["DX"]), int(r["DY"])])
        header += address.to_bytes(2, "little")
        header += r["NAME"].upper().ljust(16).encode("ascii")
    data = header + packed
    if base + len(data) > 0xC000:
        raise SystemExit(f"The maps take {len(data)} bytes: too big for $7400-$BFFF.")
    write_prg("maps.prg", base, data)
    print(f"Maps: {len(data)} bytes for {len(regions)} regions.")



PALETTE = [0x000000, 0xFFFFFF, 0x813338, 0x75CEC8, 0x8E3C97, 0x56AC4D, 0x2E2C9B, 0xEDF171,
           0x8E5029, 0x553800, 0xC46C71, 0x4A4A4A, 0x7B7B7B, 0xA9FF9F, 0x706DEB, 0xB2B2B2]
RGB = [((c >> 16) & 255, (c >> 8) & 255, c & 255) for c in PALETTE]


def dist(p, i):
    r, g, b = RGB[i]
    return 3 * (p[0] - r) ** 2 + 4 * (p[1] - g) ** 2 + 2 * (p[2] - b) ** 2


def title():
    """assets/title.png -> multicolour bitmap, like prepare_data.ps1."""
    path = os.path.join(ROOT, "assets", "title.png")
    if not os.path.exists(path):
        return
    src = Image.open(path).convert("RGB")
    scale = min(320 / src.width, 200 / src.height)
    w, h = round(src.width * scale / 2), round(src.height * scale)
    small = Image.new("RGB", (160, 200))
    small.paste(src.resize((w, h), Image.BICUBIC), ((160 - w) // 2, (200 - h) // 2))
    bg = 0
    bitmap, screen, colour = bytearray(8000), bytearray(1000), bytearray(1000)
    for cy in range(25):
        for cx in range(40):
            pix = [small.getpixel((cx * 4 + i % 4, cy * 8 + i // 4)) for i in range(32)]
            counts = [0] * 16
            for p in pix:
                counts[min(range(16), key=lambda i: dist(p, i))] += 1
            counts[bg] = 0
            top = sorted((i for i in range(16) if counts[i]), key=lambda i: -counts[i])[:3]
            top += [bg] * (3 - len(top))
            choices = [bg] + top
            cell = cy * 40 + cx
            screen[cell] = (top[0] << 4) | top[1]
            colour[cell] = top[2]
            for row in range(8):
                byte = 0
                for col in range(4):
                    p = pix[row * 4 + col]
                    k = min(range(4), key=lambda k: dist(p, choices[k]))
                    byte |= k << (6 - 2 * col)
                bitmap[cell * 8 + row] = byte
    write_prg("titlescr.prg", 0xC000, screen + bytes(24) + colour + bytes([bg]))
    write_prg("titlebmp.prg", 0xE000, bitmap)


if __name__ == "__main__":
    os.makedirs(BUILD, exist_ok=True)
    regions = load_regions()
    cities(regions)
    maps(regions)
    title()
