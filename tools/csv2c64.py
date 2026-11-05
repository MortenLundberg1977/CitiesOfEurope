#!/usr/bin/env python3
"""Convert a CSV file (CITY,COUNTRY,LAT,LON) to the fixed-width
CITIES file used by WORLDCITIES / CITYEDIT.
Usage: python3 csv2c64.py data/cities.csv data/CITIES
"""
import sys

def main():
    inp, outp = sys.argv[1], sys.argv[2]
    recs = []
    with open(inp) as f:
        next(f)  # skip header
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 4 or not parts[0]:
                continue
            city, country, lat, lon = parts[0], parts[1], parts[2], parts[3]
            city = city.strip().upper()[:13]
            country = country.strip().upper()[:10]
            la, lo = float(lat), float(lon)
            fmt = lambda v, w: (("-" if v < 0 else "+") + f"{abs(v):.2f}").rjust(w)[-w:]
            rec = (city.ljust(13) + "," + country.ljust(10) + "," +
                   fmt(la, 6) + "," + fmt(lo, 7))
            recs.append(rec.encode("ascii"))

    with open(outp, "wb") as f:
        for r in recs:
            f.write(r[:39] + b"\r")
    print(f"wrote {len(recs)} records to {outp}")

if __name__ == "__main__":
    main()
