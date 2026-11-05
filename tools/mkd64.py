#!/usr/bin/env python3
"""Minimal 1541 D64 image builder (no external deps).

Usage:
  python3 mkd64.py OUT.d64 "DISK NAME" FILE NAME TYPE [FILE NAME TYPE ...]

TYPE is "prg" or "seq". File contents are written as-is: for PRG files the
first two bytes of the input must be the load address (ACME .prg output
already has this).
"""
import sys

SECTORS = [21]*17 + [19]*7 + [18]*6 + [17]*5   # tracks 1..35

def track_offset(t):
    return sum(SECTORS[:t-1]) * 256

class D64:
    def __init__(self, name, disk_id=b"26"):
        self.data = bytearray(174848)
        self.bam = self.data[track_offset(18):track_offset(18)+256]
        self.bam[0] = 18
        # free-sector counts and allocation bitmaps start at offset 4
        # layout: t18 entry (1 count + 4 bytes) then tracks 1..35 (count + 3 bytes)
        self.bam[1] = 0  # sectors free on track 18 (set later)
        self.name = name
        self.disk_id = disk_id
        self.next_t, self.next_s = 1, 0
        self.dir_t, self.dir_s = 18, 1
        self.entries = []

    def _alloc_sector(self):
        t, s = self.next_t, self.next_s
        while t == 18:
            t += 1; s = 0
        if t > 35:
            raise RuntimeError("disk full")
        self.next_s += 1
        if self.next_s >= SECTORS[t-1]:
            self.next_t = t + 1
            self.next_s = 0
        return t, s

    def add_file(self, content, name, ftype):
        off = track_offset
        d = self.data
        data = bytes(content)
        first_t, first_s = self._alloc_sector()
        # write sector chain
        chunks = [data[i:i+254] for i in range(0, len(data), 254)] or [b""]
        prev_t, prev_s = first_t, first_s
        for i, ch in enumerate(chunks):
            t, s = prev_t, prev_s
            base = off(t) + s*256
            if i + 1 < len(chunks):
                nt, ns = self._alloc_sector()
                d[base] = nt; d[base+1] = ns
                d[base+2:base+2+len(ch)] = ch
                prev_t, prev_s = nt, ns
            else:
                d[base] = 0; d[base+1] = len(ch)
                d[base+2:base+2+len(ch)] = ch
        size = len(chunks)
        self.entries.append((ftype, first_t, first_s, name, size))

    def _bam_set(self, t, s, free):
        d = self.bam
        if t == 18:
            base = 2
            byte, bit = base + s // 8, 7 - (s % 8)
        else:
            base = 4 + (t-1)*4
            byte, bit = base + 1 + s // 8, 7 - (s % 8)
        if free:
            d[byte] |= (1 << bit)
        else:
            d[byte] &= ~(1 << bit) & 0xFF

    def finish(self):
        d = self.data
        # mark all sectors free in BAM, then clear allocated ones
        for t in range(1, 36):
            base = 4 + (t-1)*4
            d = None  # placeholder
        bam = self.bam
        # track 18: 4 bitmap bytes
        for s in range(19):
            self._bam_set(18, s, True)
        # tracks 1..35: 3 bitmap bytes each, entry at 4 + (t-1)*4
        for t in range(1, 36):
            bam[4 + (t-1)*4 + 1] = 0xFF
            bam[4 + (t-1)*4 + 2] = 0xFF
            bam[4 + (t-1)*4 + 3] = 0xFF
            n = SECTORS[t-1]
            if n == 21: bam[4 + (t-1)*4 + 3] = 0x1F   # 21 bits: 11111111 11111111 00011111? bits msb-first
            elif n == 19: bam[4 + (t-1)*4 + 3] = 0x7F
            elif n == 18: bam[4 + (t-1)*4 + 3] = 0x3F
        # 17 sectors: byte3 = 0x1F? -> only 16 bits... use special handling below
        # clear bits beyond sector count
        for t in range(1, 36):
            n = SECTORS[t-1]
            for s in range(n, 24):
                self._bam_set(t, s, False)
        # track 18: BAM + dir sectors used
        used18 = {0, 1}
        for e in self.entries:
            pass
        # mark allocated file sectors
        self._mark_allocated()
        # set free counts
        bam[1] = self._free_count(18)
        for t in range(1, 36):
            bam[4 + (t-1)*4] = self._free_count(t)
        # disk name / id / dos type
        nm = self.name.encode("ascii", "replace")[:16]
        bam[0x90:0x90+16] = nm.ljust(16, b"\xa0")
        bam[0xA2:0xA4] = self.disk_id
        bam[0xA4] = 0xA0
        bam[0xA5:0xA7] = b"2A"
        bam[0xA7] = 0xA0
        # directory at t18 s1 (and s2 if needed)
        self._write_dir()
        return self.data

    def _mark_allocated(self):
        # walk dir entries, clear their sectors in BAM
        for ftype, t, s, name, size in self.entries:
            while t:
                self._bam_set(t, s, False)
                base = track_offset(t) + s*256
                nt, ns = self.data[base], self.data[base+1]
                t, s = nt, ns

    def _free_count(self, t):
        n = SECTORS[t-1]
        cnt = 0
        for s in range(n):
            base = 2 if t == 18 else 5 + (t-1)*4
            byte = self.bam[base + s // 8]
            bit = 7 - (s % 8)
            if byte & (1 << bit):
                cnt += 1
        return cnt

    def _write_dir(self):
        d = self.data
        t, s = 18, 1
        entry_idx = 0
        while entry_idx < len(self.entries):
            base = track_offset(t) + s*256
            slot = 0
            while slot < 8 and entry_idx < len(self.entries):
                ftype, ft, fs, name, size = self.entries[entry_idx]
                e = base + slot*32
                d[e+2] = 0x82 if ftype == "prg" else 0x81
                d[e+3], d[e+4] = ft, fs
                nm = name.encode("ascii")[:16]
                d[e+5:e+5+16] = nm.ljust(16, b"\xa0")
                for i in range(e+21, e+30):
                    d[i] = 0xA0
                d[e+30], d[e+31] = size & 0xFF, size >> 8
                slot += 1
                entry_idx += 1
            if entry_idx < len(self.entries):
                nt = 18
                ns = s + 1
                d[base], d[base+1] = nt, ns
                t, s = nt, ns
            else:
                # rest of this sector: first byte 0 = no more entries
                for i in range(base + slot*32, base + 256):
                    d[i] = 0
                d[base], d[base+1] = 0, 0xFF if slot == 0 else 0
        # BAM marks dir sectors as used already via _mark_allocated? no:
        # dir sectors 1..s on track 18 must also be cleared in BAM
        for sec in range(1, s+1):
            self._bam_set(18, sec, False)

def main():
    out = sys.argv[1]
    name = sys.argv[2]
    d = D64(name)
    args = sys.argv[3:]
    for i in range(0, len(args), 3):
        path, fname, ftype = args[i], args[i+1], args[i+2]
        with open(path, "rb") as f:
            content = f.read()
        d.add_file(content, fname, ftype)
        print(f"added {fname} ({len(content)} bytes, {ftype})")
    img = d.finish()
    with open(out, "wb") as f:
        f.write(img)
    print(f"wrote {out} ({len(img)} bytes)")

if __name__ == "__main__":
    main()
