#!/usr/bin/env python3
"""Python port of prepare_data.ps1 (see there for the file layouts): builds
build/cities.prg, scores.prg, maps.prg, landmarks.prg, hiscores.prg, flags.prg (if
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


def lz_pack(d):
    """The LZ packing the game unpacks (see prepare_data.ps1): 0-127 literal
    (control + 1 bytes), 128-253 copy (control - 124 bytes) from an offset back
    (2 bytes, low first), 254/255 a run of $00/$FF with the length next (0 = 256)."""
    d = bytes(d)
    n = len(d)
    out, lit = bytearray(), bytearray()
    head, prev = {}, [-1] * n

    def flush():
        k = 0
        while k < len(lit):
            c = min(128, len(lit) - k)
            out.append(c - 1)
            out.extend(lit[k:k + c])
            k += c
        lit.clear()

    def insert(pos):
        if pos + 4 <= n:
            h = d[pos:pos + 4]
            prev[pos] = head.get(h, -1)
            head[h] = pos

    i = 0
    while i < n:
        run = 0
        if d[i] in (0, 255):
            while i + run < n and run < 256 and d[i + run] == d[i]:
                run += 1
        best_len = best_off = 0
        if i + 4 <= n:
            cand, tries = head.get(d[i:i + 4], -1), 0
            while cand >= 0 and tries < 128 and i - cand <= 65535:
                mx, l = min(129, n - i), 0
                while l < mx and d[cand + l] == d[i + l]:
                    l += 1
                if l > best_len:
                    best_len, best_off = l, i - cand
                    if l == mx:
                        break
                cand = prev[cand]
                tries += 1
        if run >= 2 and run + 1 >= best_len:
            flush()
            out += bytes([0xFE if d[i] == 0 else 0xFF, run & 255])
            for k in range(run):
                insert(i + k)
            i += run
        elif best_len >= 4:
            flush()
            out += bytes([0x80 | (best_len - 4), best_off & 255, best_off >> 8])
            for k in range(best_len):
                insert(i + k)
            i += best_len
        else:
            lit.append(d[i])
            insert(i)
            i += 1
    flush()
    return out


def lz_unpack(p, start, out_len):
    o, s = bytearray(), start
    while len(o) < out_len:
        c = p[s]
        s += 1
        if c < 128:
            o += p[s:s + c + 1]
            s += c + 1
        elif c >= 254:
            ln = p[s] or 256
            s += 1
            o += bytes([0 if c == 254 else 255]) * ln
        else:
            ln, off = (c & 127) + 4, p[s] | (p[s + 1] << 8)
            s += 2
            for _ in range(ln):
                o.append(o[-off])
    return o


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
    """Answer counts from the old disk: CITIES (packed or plain) for the names,
    SCORES (if there) for the counts, matched by position."""
    path = os.path.join(BUILD, "oldcities.prg")
    spath = os.path.join(BUILD, "oldscores.prg")
    counts = {}
    if os.path.exists(path):
        old = open(path, "rb").read()
        if len(old) > 5 and old[2] == 1:
            plain = lz_unpack(old, 5, old[3] | (old[4] << 8))
        else:
            plain = old[2:]
        keys, o = [], 0
        while o + 59 <= len(plain) and plain[o] != 0 and plain[o + 58] == 13:
            key = bytes(plain[o:o + 33]).decode("ascii")
            keys.append(key)
            counts[key] = bytes(plain[o + 51:o + 58]).decode("ascii")
            o += 59
        if os.path.exists(spath):
            sc = open(spath, "rb").read()
            if len(sc) >= 3 + 6 * len(keys) and sc[2] == len(keys):
                for k, key in enumerate(keys):
                    dg = sc[3 + 6 * k:9 + 6 * k].decode("ascii")
                    counts[key] = dg[:3] + "," + dg[3:]
        os.remove(path)
    if os.path.exists(spath):
        os.remove(spath)
    return counts


def cities(regions, rows):
    counts = old_counts()
    out, digits = bytearray(), bytearray()
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
        digits += (stats[:3] + stats[4:]).encode("ascii")
    if len(rows) > 220:
        raise SystemExit(f"data/cities.csv has {len(rows)} cities; the game holds at most 220.")
    for r, n in zip(regions, per_region):
        if n < 3:
            raise SystemExit(f"Region {r['NAME']} needs at least 3 cities, has {n}.")
    out.append(0)
    packed = lz_pack(out)
    write_prg("cities.prg", 0x6C40, bytes([1, len(out) & 255, len(out) >> 8]) + packed)
    write_prg("scores.prg", 0x2000, bytes([len(rows)]) + digits)
    print(f"Cities: {len(rows)}, {len(packed) + 3} bytes packed (from {len(out)}).")
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
        packed += lz_pack(map_bitmap(os.path.join(ROOT, "assets", "maps", f"region{r['ID']}.png")))
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
    packed = lz_pack(colours) + lz_pack(bitmap)
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
