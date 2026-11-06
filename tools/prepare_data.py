#!/usr/bin/env python3
"""Python port of prepare_data.ps1 (see there for the file layouts): builds
build/cities.prg, maps.prg, landmarks.prg, hiscores.prg, flags.prg (if
data/flags.txt exists) and title.prg (if assets/title.png exists).
Usage: python3 tools/prepare_data.py   (run from anywhere; needs Pillow)
"""
import csv
import os
import shutil
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
LETTERS = "KWRCPGBYONLDMEAS"   # C64 colours 0-15
MAPS_BASE = 0x6C40


def write_prg(name, load_address, data):
    with open(os.path.join(BUILD, name), "wb") as f:
        f.write(bytes([load_address & 0xFF, load_address >> 8]) + bytes(data))


def coord(value, width):
    text = ("-" if value < 0 else "+") + f"{abs(value):.2f}"
    if len(text) > width:
        raise SystemExit(f"Coordinate {value} does not fit in {width} characters.")
    return text.rjust(width)


def rle(data):
    """$00 and $FF are followed by a run length (1-255), other bytes are literal."""
    out, i = bytearray(), 0
    while i < len(data):
        b = data[i]
        if b in (0, 255):
            run = 1
            while i + run < len(data) and run < 255 and data[i + run] == b:
                run += 1
            out += bytes([b, run])
            i += run
        else:
            out.append(b)
            i += 1
    return out


def packbits(data):
    """0-127: that many + 1 literal bytes follow; 128-255: one byte, repeated control - 125 times."""
    out, i, n = bytearray(), 0, len(data)
    while i < n:
        run = 1
        while i + run < n and run < 130 and data[i + run] == data[i]:
            run += 1
        if run >= 3:
            out += bytes([128 + run - 3, data[i]])
            i += run
        else:
            j = i
            while j < n and j - i < 128:
                r = 1
                while j + r < n and r < 3 and data[j + r] == data[j]:
                    r += 1
                if r >= 3:
                    break
                j += 1
            out.append(j - i - 1)
            out += data[i:j]
            i = j
    return out


def load_regions():
    with open(os.path.join(ROOT, "data", "regions.csv")) as f:
        regions = list(csv.DictReader(f))
    for i, r in enumerate(regions):
        if int(r["ID"]) != i + 1:
            raise SystemExit("data/regions.csv: IDs must be 1, 2, 3... in order.")
        if len(r["NAME"]) > 16:
            raise SystemExit(f"Region name {r['NAME']} is longer than 16 characters.")
    return regions


def read_cities():
    rows = []
    with open(os.path.join(ROOT, "data", "cities.csv")) as f:
        next(f)
        for line in f:
            parts = line.strip().split(",")
            if len(parts) >= 5 and parts[0]:
                rows.append(parts)
    return rows


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


def cities(regions, rows):
    counts = old_counts()
    out = bytearray()
    kept = 0
    per_region = [0] * len(regions)
    for parts in rows:
        city, country = parts[0].strip().upper(), parts[1].strip().upper()
        if len(city) > 16 or len(country) > 16:
            raise SystemExit(f"Name longer than 16 characters: {city} / {country}")
        lat, lon, rid = float(parts[2]), float(parts[3]), int(parts[4])
        if not 1 <= rid <= len(regions):
            raise SystemExit(f"{city} has an unknown region {rid}.")
        r = regions[rid - 1]
        dlon = round(lon * 100) - round(float(r["LON0"]) * 100)
        if dlon < 0:
            dlon += 36000
        px = dlon // int(r["DX"])
        py = (round(float(r["LAT0"]) * 100) - round(lat * 100)) // int(r["DY"])
        if px >= 320 or py < 0 or py >= 160:
            raise SystemExit(f"{city} is outside the {r['NAME']} map.")
        per_region[rid - 1] += 1
        key = city.ljust(16) + "," + country.ljust(16)
        stats = counts.get(key, "000,000")
        if stats != "000,000":
            kept += 1
        rec = key + "," + coord(lat, 6) + "," + coord(lon, 7) + "," + str(rid) + "," + stats + "\r"
        out += rec.encode("ascii")
    if len(rows) > 220:
        raise SystemExit(f"data/cities.csv has {len(rows)} cities; the game holds at most 220.")
    for r, n in zip(regions, per_region):
        if n < 3:
            raise SystemExit(f"Region {r['NAME']} needs at least 3 cities, has {n}.")
    out.append(0)
    write_prg("cities.prg", 0x3900, out)
    if kept:
        print(f"Kept the answer counts of {kept} cities from the old disk.")


def map_bitmap(path):
    img = Image.open(path).convert("RGB")
    if img.size != (320, 160):
        raise SystemExit(f"{path} must be 320x160 pixels.")
    bitmap = bytearray(6400)
    for y in range(160):
        for x in range(320):
            if sum(img.getpixel((x, y))) < 384:
                bitmap[(y // 8) * 320 + (x // 8) * 8 + (y % 8)] |= 0x80 >> (x % 8)
    return bitmap


def maps(regions):
    header = bytearray([len(regions)])
    packed = bytearray()
    start = MAPS_BASE + 1 + 24 * len(regions)
    for r in regions:
        address = start + len(packed)
        packed += rle(map_bitmap(os.path.join(ROOT, "assets", "maps", f"region{r['ID']}.png")))
        for word in (round(float(r["LON0"]) * 100), round(float(r["LAT0"]) * 100)):
            header += (word & 0xFFFF).to_bytes(2, "little")
        header += bytes([int(r["DX"]), int(r["DY"])])
        header += address.to_bytes(2, "little")
        header += r["NAME"].upper().ljust(16).encode("ascii")
    data = header + packed
    if MAPS_BASE + len(data) > 0xAB00:
        raise SystemExit(f"The maps take {len(data)} bytes: too big for $6C40-$AAFF.")
    write_prg("maps.prg", MAPS_BASE, data)
    print(f"Maps: {len(data)} bytes for {len(regions)} regions.")


def landmarks(rows):
    path = os.path.join(ROOT, "data", "landmarks.txt")
    lines = []
    if os.path.exists(path):
        lines = [l.rstrip("\n") for l in open(path) if l.strip() and not l.startswith("# ")]
    if len(lines) % 23:
        raise SystemExit("data/landmarks.txt: each picture is a name line, a colour letter and 21 rows of 24 characters.")
    names = {p[0].strip().upper() for p in rows}
    out = bytearray([len(lines) // 23])
    for f in range(0, len(lines), 23):
        name = lines[f].split("#")[0].strip().upper()
        if name not in names:
            raise SystemExit(f"Landmark city {name} is not in data/cities.csv.")
        colour = LETTERS.find(lines[f + 1].strip().upper())
        if colour < 0:
            raise SystemExit(f"Landmark {name}: unknown colour letter {lines[f + 1]}.")
        sprite = bytearray(64)
        for y in range(21):
            row = lines[f + 2 + y].strip()
            if len(row) != 24:
                raise SystemExit(f"Landmark {name}, row {y + 1}: needs 24 characters.")
            for x, ch in enumerate(row):
                if ch == "#":
                    sprite[y * 3 + x // 8] |= 0x80 >> (x % 8)
        out += name.ljust(16).encode("ascii") + bytes([colour, 0, 0, 0]) + sprite
    if len(out) > 1024:
        raise SystemExit("Too many landmarks for $AC00-$AFFF (12 at most).")
    write_prg("landmarks.prg", 0xAC00, out)
    print(f"Landmarks: {len(lines) // 23}.")


def hiscores():
    old = os.path.join(BUILD, "oldhiscores.prg")
    if os.path.exists(old):
        shutil.move(old, os.path.join(BUILD, "hiscores.prg"))
        print("Kept the high scores from the old disk.")
        return
    names = ["MAGELLAN", "COLUMBUS", "MARCO POLO", "DA GAMA", "IBN BATTUTA",
             "ZHENG HE", "AMUNDSEN", "COOK", "ERIKSSON", "TASMAN"]
    out = bytearray()
    for i, n in enumerate(names):
        out += n[:10].ljust(10).encode("ascii") + bytes([30 - 3 * i, 0])
    write_prg("hiscores.prg", 0xAB00, out)


def flags(rows):
    path = os.path.join(ROOT, "data", "flags.txt")
    if not os.path.exists(path):
        return                   # World Cities: the first hint is the country's name
    lines = [l.strip() for l in open(path) if l.strip() and not l.startswith("#")]
    if len(lines) % 17:
        raise SystemExit("data/flags.txt: each flag is a name line and 16 rows of 12 letters.")
    out = bytearray([len(lines) // 17])
    names = set()
    for f in range(0, len(lines), 17):
        name = lines[f].upper()
        if len(name) > 16:
            raise SystemExit(f"Flag name {name} is longer than 16 characters.")
        names.add(name)
        colours, sprite = [], bytearray(64)
        for y in range(16):
            row = lines[f + 1 + y].upper()
            if len(row) != 12:
                raise SystemExit(f"Flag {name}, row {y + 1}: needs 12 letters.")
            for x, ch in enumerate(row):
                c = LETTERS.find(ch)
                if c < 0:
                    raise SystemExit(f"Flag {name}, row {y + 1}: unknown colour letter {ch}.")
                if c == 0:
                    continue
                if c not in colours:
                    if len(colours) == 3:
                        raise SystemExit(f"Flag {name} has more than 3 colours besides K.")
                    colours.append(c)
                sprite[y * 3 + x // 4] |= (colours.index(c) + 1) << (6 - 2 * (x % 4))
        colours += [0] * (3 - len(colours))
        out += name.ljust(16).encode("ascii") + bytes(colours) + b"\0" + sprite
    for p in rows:
        if p[1].strip().upper() not in names:
            raise SystemExit(f"No flag for {p[1].strip()} in data/flags.txt.")
    write_prg("flags.prg", 0xB000, out)
    print(f"Flags: {len(names)}.")


PALETTE = [0x000000, 0xFFFFFF, 0x813338, 0x75CEC8, 0x8E3C97, 0x56AC4D, 0x2E2C9B, 0xEDF171,
           0x8E5029, 0x553800, 0xC46C71, 0x4A4A4A, 0x7B7B7B, 0xA9FF9F, 0x706DEB, 0xB2B2B2]
RGB = [((c >> 16) & 255, (c >> 8) & 255, c & 255) for c in PALETTE]


def dist(p, i):
    r, g, b = RGB[i]
    return 3 * (p[0] - r) ** 2 + 4 * (p[1] - g) ** 2 + 2 * (p[2] - b) ** 2


def title():
    """assets/title.png -> multicolour bitmap, packed into title.prg."""
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
    colours = screen + bytes(24) + colour + bytes([bg]) + bytes(23)      # 2048 bytes
    packed = packbits(colours) + packbits(bitmap)
    if 0x6C40 + len(packed) > 0xAB00:
        raise SystemExit("The packed title is too big.")
    write_prg("title.prg", 0x6C40, packed)
    print(f"Title: {len(packed)} bytes packed (from 10048).")


if __name__ == "__main__":
    os.makedirs(BUILD, exist_ok=True)
    regions = load_regions()
    rows = read_cities()
    cities(regions, rows)
    maps(regions)
    landmarks(rows)
    hiscores()
    flags(rows)
    title()
