$ErrorActionPreference = "Stop"

# Builds the data files of the game: CITIES, SCORES, MAPS, LANDMARKS, HISCORES,
# FLAGS (Cities of Europe) and TITLE. Each file is a PRG: a 2-byte load address
# followed by the data. tools/prepare_data.py does the same on Linux.

$projectRoot = $PSScriptRoot
$buildDirectory = Join-Path $projectRoot "build"
New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null

$culture = [System.Globalization.CultureInfo]::InvariantCulture

function Write-Prg {
    param(
        [string]$PrgName,
        [int]$LoadAddress,
        [byte[]]$Data
    )

    $bytes = New-Object byte[] ($Data.Length + 2)
    $bytes[0] = [byte]($LoadAddress -band 0xff)
    $bytes[1] = [byte](($LoadAddress -shr 8) -band 0xff)
    [System.Array]::Copy($Data, 0, $bytes, 2, $Data.Length)
    [System.IO.File]::WriteAllBytes((Join-Path $buildDirectory $PrgName), $bytes)
}

function Format-Coordinate {
    param(
        [double]$Value,
        [int]$Width
    )

    $sign = if ($Value -lt 0) { "-" } else { "+" }
    $text = $sign + [System.Math]::Abs($Value).ToString("0.00", $culture)
    if ($text.Length -gt $Width) { throw "Coordinate $Value does not fit in $Width characters." }
    return $text.PadLeft($Width)
}

# The LZ packing the game unpacks (unpack_lz in src/game.asm): a control byte
# 0-127 is followed by that many + 1 literal bytes; 128-253 means "copy
# (control - 128 + 4) bytes from (offset) bytes back in the output", with the
# offset in the next two bytes, low first; 254 and 255 are a run of $00 or $FF,
# with the length (1-256, 0 = 256) next. Written in C# for speed.
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
public static class Lz {
    public static byte[] Pack(byte[] d) {
        int n = d.Length;
        var outp = new List<byte>();
        var lit = new List<byte>();
        var head = new Dictionary<int, int>();
        var prev = new int[n];
        Action flush = () => {
            int k = 0;
            while (k < lit.Count) {
                int c = Math.Min(128, lit.Count - k);
                outp.Add((byte)(c - 1));
                for (int j = 0; j < c; j++) outp.Add(lit[k + j]);
                k += c;
            }
            lit.Clear();
        };
        Action<int> insert = pos => {
            if (pos + 4 > n) return;
            int h = d[pos] | (d[pos + 1] << 8) | (d[pos + 2] << 16) | (d[pos + 3] << 24);
            int old;
            prev[pos] = head.TryGetValue(h, out old) ? old : -1;
            head[h] = pos;
        };
        int i = 0;
        while (i < n) {
            int run = 0;
            if (d[i] == 0 || d[i] == 255) { while (i + run < n && run < 256 && d[i + run] == d[i]) run++; }
            int bestLen = 0, bestOff = 0;
            if (i + 4 <= n) {
                int h = d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);
                int cand, tries = 0;
                if (head.TryGetValue(h, out cand)) {
                    while (cand >= 0 && tries < 128 && i - cand <= 65535) {
                        int max = Math.Min(129, n - i), l = 0;
                        while (l < max && d[cand + l] == d[i + l]) l++;
                        if (l > bestLen) { bestLen = l; bestOff = i - cand; if (l == max) break; }
                        cand = prev[cand]; tries++;
                    }
                }
            }
            if (run >= 2 && run + 1 >= bestLen) {
                flush();
                outp.Add((byte)(d[i] == 0 ? 0xFE : 0xFF));
                outp.Add((byte)(run & 255));
                for (int k = 0; k < run; k++) insert(i + k);
                i += run;
            } else if (bestLen >= 4) {
                flush();
                outp.Add((byte)(0x80 | (bestLen - 4)));
                outp.Add((byte)(bestOff & 255));
                outp.Add((byte)(bestOff >> 8));
                for (int k = 0; k < bestLen; k++) insert(i + k);
                i += bestLen;
            } else {
                lit.Add(d[i]); insert(i); i++;
            }
        }
        flush();
        return outp.ToArray();
    }
    public static byte[] Unpack(byte[] p, int start, int outLen) {
        var o = new List<byte>();
        int s = start;
        while (o.Count < outLen) {
            int c = p[s++];
            if (c < 128) { for (int j = 0; j <= c; j++) o.Add(p[s++]); }
            else if (c >= 254) { int len = p[s++]; if (len == 0) len = 256; for (int j = 0; j < len; j++) o.Add((byte)(c == 254 ? 0 : 255)); }
            else { int len = (c & 127) + 4, off = p[s] | (p[s + 1] << 8); s += 2; for (int j = 0; j < len; j++) o.Add(o[o.Count - off]); }
        }
        return o.ToArray();
    }
}
"@

# REGIONS: data\regions.csv. Each region's map is assets\maps\region<ID>.png,
# drawn by tools\render_map.ps1 with the same corner (LON0, LAT0) and scale
# (DX, DY: hundredths of a degree per pixel) that the game uses for the marker.
$regions = @(Import-Csv (Join-Path $projectRoot "data\regions.csv"))
for ($i = 0; $i -lt $regions.Count; $i++) {
    if ([int]$regions[$i].ID -ne $i + 1) { throw "data\regions.csv: IDs must be 1, 2, 3... in order." }
    if ($regions[$i].NAME.Length -gt 16) { throw "Region name '$($regions[$i].NAME)' is longer than 16 characters." }
}

# CITIES: 59-byte records, then a 0 byte:
#   CITY(16),COUNTRY(16),LAT(6),LON(7),REGION(1),RIGHT(3),WRONG(3) + CR
# packed: the byte 1, the length (2 bytes), LZ data. Loads to $6C40; the game
# unpacks it to $3900. (CITYEDIT saves it plain; the game reads that too.)
# SCORES: the RIGHT and WRONG digits of every city, which the game saves after
# each game: the number of cities, then 6 digits a city. Loads to $2000.
# build.bat copies CITIES and SCORES off the old disk (build\oldcities.prg,
# build\oldscores.prg), so the counts carry over, matched by city and country.
$oldCounts = @{}
$oldPath = Join-Path $buildDirectory "oldcities.prg"
$oldScoresPath = Join-Path $buildDirectory "oldscores.prg"
if (Test-Path $oldPath) {
    $old = [System.IO.File]::ReadAllBytes($oldPath)
    if ($old.Length -gt 5 -and $old[2] -eq 1) {         # packed
        $plainOld = [Lz]::Unpack($old, 5, $old[3] + 256 * $old[4])
    } else {
        $plainOld = [byte[]]$old[2..($old.Length - 1)]
    }
    $oldKeys = New-Object System.Collections.Generic.List[string]
    for ($o = 0; $o + 59 -le $plainOld.Length -and $plainOld[$o] -ne 0; $o += 59) {
        if ($plainOld[$o + 58] -ne 13) { break }     # an older record layout: no counts
        $key = [System.Text.Encoding]::ASCII.GetString($plainOld, $o, 33)
        $oldKeys.Add($key)
        $oldCounts[$key] = [System.Text.Encoding]::ASCII.GetString($plainOld, $o + 51, 7)
    }
    if (Test-Path $oldScoresPath) {
        $sc = [System.IO.File]::ReadAllBytes($oldScoresPath)
        if ($sc.Length -ge 3 + 6 * $oldKeys.Count -and $sc[2] -eq $oldKeys.Count) {
            for ($k = 0; $k -lt $oldKeys.Count; $k++) {
                $d = [System.Text.Encoding]::ASCII.GetString($sc, 3 + 6 * $k, 6)
                $oldCounts[$oldKeys[$k]] = $d.Substring(0, 3) + "," + $d.Substring(3, 3)
            }
        }
    }
    Remove-Item $oldPath
}
if (Test-Path $oldScoresPath) { Remove-Item $oldScoresPath }
$records = New-Object System.Text.StringBuilder
$scoreDigits = New-Object System.Text.StringBuilder
$lines = Get-Content (Join-Path $projectRoot "data\cities.csv") | Select-Object -Skip 1
$count = 0
$kept = 0
foreach ($line in $lines) {
    $parts = $line.Trim().Split(",")
    if ($parts.Length -lt 5 -or $parts[0] -eq "") { continue }
    $city = $parts[0].Trim().ToUpperInvariant()
    $country = $parts[1].Trim().ToUpperInvariant()
    if ($city.Length -gt 16) { throw "City name '$city' is longer than 16 characters." }
    if ($country.Length -gt 16) { throw "Country name '$country' is longer than 16 characters." }
    $lat = [double]::Parse($parts[2], $culture)
    $lon = [double]::Parse($parts[3], $culture)
    $regionId = [int]$parts[4]
    if ($regionId -lt 1 -or $regionId -gt $regions.Count) { throw "$city has an unknown region $regionId." }
    $region = $regions[$regionId - 1]
    $dlon = [Math]::Round($lon * 100) - [Math]::Round([double]::Parse($region.LON0, $culture) * 100)
    if ($dlon -lt 0) { $dlon += 36000 }
    $px = [Math]::Floor($dlon / [int]$region.DX)
    $py = [Math]::Floor(([Math]::Round([double]::Parse($region.LAT0, $culture) * 100) - [Math]::Round($lat * 100)) / [int]$region.DY)
    if ($px -ge 320 -or $py -lt 0 -or $py -ge 160) { throw "$city is outside the $($region.NAME) map." }
    $key = $city.PadRight(16) + "," + $country.PadRight(16)
    $stats = "000,000"
    if ($oldCounts.ContainsKey($key)) {
        $stats = $oldCounts[$key]
        if ($stats -ne "000,000") { $kept++ }
    }
    $record = $key + "," + (Format-Coordinate $lat 6) + "," + (Format-Coordinate $lon 7) + "," +
        $regionId + "," + $stats + "`r"
    [void]$records.Append($record)
    [void]$scoreDigits.Append($stats.Substring(0, 3) + $stats.Substring(4, 3))
    $count++
}
if ($count -gt 220) { throw "data\cities.csv has $count cities; the game holds at most 220." }
foreach ($region in $regions) {
    $n = @($lines | Where-Object { $_.Trim().Split(",")[4] -eq $region.ID }).Count
    if ($n -lt 3) { throw "Region $($region.NAME) needs at least 3 cities, has $n." }
}
$cityBytes = [System.Text.Encoding]::ASCII.GetBytes($records.ToString()) + [byte]0
$cityPacked = [Lz]::Pack($cityBytes)
$cityFile = New-Object System.Collections.Generic.List[byte]
$cityFile.Add(1); $cityFile.Add([byte]($cityBytes.Length -band 255)); $cityFile.Add([byte]($cityBytes.Length -shr 8))
$cityFile.AddRange($cityPacked)
Write-Prg "cities.prg" 0x6C40 $cityFile.ToArray()
$scoreFile = New-Object System.Collections.Generic.List[byte]
$scoreFile.Add([byte]$count)
$scoreFile.AddRange([System.Text.Encoding]::ASCII.GetBytes($scoreDigits.ToString()))
Write-Prg "scores.prg" 0x2000 $scoreFile.ToArray()
Write-Output "Cities: $count, $($cityFile.Count) bytes packed (from $($cityBytes.Length))."
if ($kept) { Write-Output "Kept the answer counts of $kept cities from the old disk." }

# MAPS: every region map as a hi-res bitmap (40x20 cells of 8 bytes, bit 7 = leftmost
# pixel, set = land), each packed (LZ) on its own. Loads to $6C40:
#   count (1), then per region: LON0, LAT0 (signed words, hundredths of a degree),
#   DX, DY (bytes), address of its packed map (word), name (16 chars)
#   then the packed maps
Add-Type -AssemblyName System.Drawing
$mapsBase = 0x6C40
$header = New-Object System.Collections.Generic.List[byte]
$packed = New-Object System.Collections.Generic.List[byte]
$header.Add([byte]$regions.Count)
$dataStart = $mapsBase + 1 + 24 * $regions.Count
foreach ($region in $regions) {
    $png = Join-Path $projectRoot ("assets\maps\region" + $region.ID + ".png")
    if (-not (Test-Path $png)) { throw "$png is missing: run tools\render_map.ps1." }
    $image = New-Object System.Drawing.Bitmap $png
    if ($image.Width -ne 320 -or $image.Height -ne 160) { throw "$png must be 320x160 pixels." }
    $bitmap = New-Object byte[] 6400
    for ($y = 0; $y -lt 160; $y++) {
        for ($x = 0; $x -lt 320; $x++) {
            $pixel = $image.GetPixel($x, $y)
            if (($pixel.R + $pixel.G + $pixel.B) -lt 384) {
                $offset = [int][Math]::Floor($y / 8) * 320 + [int][Math]::Floor($x / 8) * 8 + ($y % 8)
                $bitmap[$offset] = $bitmap[$offset] -bor (0x80 -shr ($x % 8))
            }
        }
    }
    $image.Dispose()
    $address = $dataStart + $packed.Count
    $packed.AddRange([Lz]::Pack($bitmap))
    foreach ($word in @(([Math]::Round([double]::Parse($region.LON0, $culture) * 100)), ([Math]::Round([double]::Parse($region.LAT0, $culture) * 100)))) {
        $header.Add([byte]($word -band 0xff)); $header.Add([byte](($word -shr 8) -band 0xff))
    }
    $header.Add([byte][int]$region.DX); $header.Add([byte][int]$region.DY)
    $header.Add([byte]($address -band 0xff)); $header.Add([byte]($address -shr 8))
    $header.AddRange([System.Text.Encoding]::ASCII.GetBytes($region.NAME.ToUpperInvariant().PadRight(16)))
}
$maps = $header.ToArray() + $packed.ToArray()
if ($mapsBase + $maps.Length -gt 0xAB00) { throw "The maps take $($maps.Length) bytes: too big for `$6C40-`$AAFF." }
Write-Prg "maps.prg" $mapsBase $maps
Write-Output "Maps: $($maps.Length) bytes for $($regions.Count) regions."

# LANDMARKS: data\landmarks.txt, pictures shown next to the marker when the
# answer is revealed. Loads to $AC00: count (1), then per picture 84 bytes:
#   city name (16), colour, spare (3), sprite (64: hi-res, 3 bytes per row)
$letters = "KWRCPGBYONLDMEAS"     # C64 colours 0-15
$landBytes = New-Object System.Collections.Generic.List[byte]
$landPath = Join-Path $projectRoot "data\landmarks.txt"
$landLines = @()
if (Test-Path $landPath) {
    $landLines = @(Get-Content $landPath | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("# ") })
}
if ($landLines.Count % 23 -ne 0) { throw "data\landmarks.txt: each picture is a name line, a colour letter and 21 rows of 24 characters." }
$landBytes.Add([byte]($landLines.Count / 23))
$cityNames = @{}
foreach ($line in $lines) { $p = $line.Trim().Split(","); if ($p.Length -ge 2) { $cityNames[$p[0].Trim().ToUpperInvariant()] = $true } }
for ($f = 0; $f -lt $landLines.Count; $f += 23) {
    $name = ($landLines[$f] -replace '#.*$', '').Trim().ToUpperInvariant()
    if ($name.Length -gt 16) { throw "Landmark city '$name' is longer than 16 characters." }
    if (-not $cityNames.ContainsKey($name)) { throw "Landmark city '$name' is not in data\cities.csv." }
    $colour = $letters.IndexOf($landLines[$f + 1].Trim().ToUpperInvariant())
    if ($colour -lt 0) { throw "Landmark $name`: unknown colour letter '$($landLines[$f + 1])'." }
    $sprite = New-Object byte[] 64
    for ($y = 0; $y -lt 21; $y++) {
        $row = $landLines[$f + 2 + $y].Trim()
        if ($row.Length -ne 24) { throw "Landmark $name, row $($y + 1): needs 24 characters." }
        for ($x = 0; $x -lt 24; $x++) {
            if ($row[$x] -eq '#') { $sprite[$y * 3 + [Math]::Floor($x / 8)] = $sprite[$y * 3 + [Math]::Floor($x / 8)] -bor (0x80 -shr ($x % 8)) }
        }
    }
    $landBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($name.PadRight(16)))
    $landBytes.Add([byte]$colour); $landBytes.Add(0); $landBytes.Add(0); $landBytes.Add(0)
    $landBytes.AddRange($sprite)
}
if ($landBytes.Count -gt 1024) { throw "Too many landmarks for `$AC00-`$AFFF (12 at most)." }
Write-Prg "landmarks.prg" 0xAC00 $landBytes.ToArray()
Write-Output "Landmarks: $($landLines.Count / 23)."

# HISCORES: the top-10 table, loads to $AB00: per entry name (10), points, spare.
# build.bat copies the table off the old disk to build\oldhiscores.prg first.
$oldHs = Join-Path $buildDirectory "oldhiscores.prg"
if (Test-Path $oldHs) {
    Move-Item $oldHs (Join-Path $buildDirectory "hiscores.prg") -Force
    Write-Output "Kept the high scores from the old disk."
} else {
    $hs = New-Object System.Collections.Generic.List[byte]
    $names = @("MAGELLAN", "COLUMBUS", "MARCO POLO", "DA GAMA", "IBN BATTUTA", "ZHENG HE", "AMUNDSEN", "COOK", "ERIKSSON", "TASMAN")
    for ($i = 0; $i -lt 10; $i++) {
        $hs.AddRange([System.Text.Encoding]::ASCII.GetBytes($names[$i].Substring(0, [Math]::Min(10, $names[$i].Length)).PadRight(10)))
        $hs.Add([byte](30 - 3 * $i)); $hs.Add(0)
    }
    Write-Prg "hiscores.prg" 0xAB00 $hs.ToArray()
}

# FLAGS: data\flags.txt, one 12x16 grid of colour letters per country, as
# multicolour sprites. Loads to $B000: count (1), then per flag 84 bytes:
#   country name (16), colour for bits 01 ($D025), 10 (sprite colour), 11 ($D026),
#   spare (1), sprite (64: 3 bytes per row, 16 rows used)
# World Cities has no flags (its first hint is the country's name).
$flagsBase = 0xB000
$flagsPath = Join-Path $projectRoot "data\flags.txt"
if (Test-Path $flagsPath) {
$flagLines = @(Get-Content $flagsPath | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") })
if ($flagLines.Count % 17 -ne 0) { throw "data\flags.txt: each flag is a name line and 16 rows of 12 letters." }
$flagBytes = New-Object System.Collections.Generic.List[byte]
$flagBytes.Add([byte]($flagLines.Count / 17))
$flagNames = @{}
for ($f = 0; $f -lt $flagLines.Count; $f += 17) {
    $name = $flagLines[$f].Trim().ToUpperInvariant()
    if ($name.Length -gt 16) { throw "Flag name '$name' is longer than 16 characters." }
    $flagNames[$name] = $true
    $colours = New-Object System.Collections.Generic.List[int]
    $sprite = New-Object byte[] 64
    for ($y = 0; $y -lt 16; $y++) {
        $row = $flagLines[$f + 1 + $y].Trim().ToUpperInvariant()
        if ($row.Length -ne 12) { throw "Flag $name, row $($y + 1): needs 12 letters." }
        for ($x = 0; $x -lt 12; $x++) {
            $c = $letters.IndexOf($row[$x])
            if ($c -lt 0) { throw "Flag $name, row $($y + 1): unknown colour letter '$($row[$x])'." }
            if ($c -eq 0) { continue }                       # K: see-through
            $slot = $colours.IndexOf($c)
            if ($slot -lt 0) {
                if ($colours.Count -eq 3) { throw "Flag $name has more than 3 colours besides K." }
                $colours.Add($c); $slot = $colours.Count - 1
            }
            $bits = $slot + 1                                # 01, 10, 11
            $byte = $y * 3 + [Math]::Floor($x / 4)
            $sprite[$byte] = $sprite[$byte] -bor ($bits -shl (6 - 2 * ($x % 4)))
        }
    }
    while ($colours.Count -lt 3) { $colours.Add(0) }
    $flagBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($name.PadRight(16)))
    $flagBytes.Add([byte]$colours[0]); $flagBytes.Add([byte]$colours[1]); $flagBytes.Add([byte]$colours[2]); $flagBytes.Add(0)
    $flagBytes.AddRange($sprite)
}
foreach ($line in $lines) {
    $parts = $line.Trim().Split(",")
    if ($parts.Length -lt 2) { continue }
    $country = $parts[1].Trim().ToUpperInvariant()
    if ($country -and -not $flagNames.ContainsKey($country)) { throw "No flag for $country in data\flags.txt." }
}
if ($flagsBase + $flagBytes.Count -gt 0xC000) { throw "Too many flags for `$B000-`$BFFF." }
Write-Prg "flags.prg" $flagsBase $flagBytes.ToArray()
Write-Output "Flags: $($flagNames.Count)."
}

# TITLE: assets\title.png, any size, scaled to fit 320x200 and converted to a
# multicolour bitmap (160x200, double-wide pixels). Each 4x8 cell gets black
# as the background plus its three most used C64 colours.
#   titlescr.prg -> $C000: screen colours (1000), 24 spare, colour RAM (1000), background
#   titlebmp.prg -> $E000: bitmap (8000), in the RAM under the KERNAL ROM
$palette = @(0x000000, 0xFFFFFF, 0x813338, 0x75CEC8, 0x8E3C97, 0x56AC4D, 0x2E2C9B, 0xEDF171,
             0x8E5029, 0x553800, 0xC46C71, 0x4A4A4A, 0x7B7B7B, 0xA9FF9F, 0x706DEB, 0xB2B2B2)
$palR = $palette | ForEach-Object { ($_ -shr 16) -band 255 }
$palG = $palette | ForEach-Object { ($_ -shr 8) -band 255 }
$palB = $palette | ForEach-Object { $_ -band 255 }

function Get-Distance([int]$r, [int]$g, [int]$b, [int]$index) {
    $dr = $r - $palR[$index]; $dg = $g - $palG[$index]; $db = $b - $palB[$index]
    return 3 * $dr * $dr + 4 * $dg * $dg + 2 * $db * $db
}

$titlePath = Join-Path $projectRoot "assets\title.png"
$titleOut = Join-Path $buildDirectory "titlebmp.prg"
$titleFresh = (Test-Path $titleOut) -and (Test-Path $titlePath) -and
    ((Get-Item $titleOut).LastWriteTime -gt (Get-Item $titlePath).LastWriteTime) -and
    ((Get-Item $titleOut).LastWriteTime -gt (Get-Item $PSCommandPath).LastWriteTime)
# The conversion takes about a minute, so it only runs when the picture changed.
if ((Test-Path $titlePath) -and -not $titleFresh) {
    $source = New-Object System.Drawing.Bitmap $titlePath
    # Fit into 320x200 (keeping the shape), then halve the width for multicolour.
    $scale = [Math]::Min(320.0 / $source.Width, 200.0 / $source.Height)
    $w = [int][Math]::Round($source.Width * $scale / 2)
    $h = [int][Math]::Round($source.Height * $scale)
    $small = New-Object System.Drawing.Bitmap 160, 200
    $g = [System.Drawing.Graphics]::FromImage($small)
    $g.Clear([System.Drawing.Color]::Black)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($source, [int]((160 - $w) / 2), [int]((200 - $h) / 2), $w, $h)
    $g.Dispose()
    $source.Dispose()

    $background = 0
    $tbitmap = New-Object byte[] 8000
    $tscreen = New-Object byte[] 1000
    $tcolour = New-Object byte[] 1000
    $pixR = New-Object int[] 32; $pixG = New-Object int[] 32; $pixB = New-Object int[] 32
    for ($cy = 0; $cy -lt 25; $cy++) {
        for ($cx = 0; $cx -lt 40; $cx++) {
            $counts = New-Object int[] 16
            for ($i = 0; $i -lt 32; $i++) {
                $px = $small.GetPixel($cx * 4 + ($i % 4), $cy * 8 + [int][Math]::Floor($i / 4))
                $pixR[$i] = $px.R; $pixG[$i] = $px.G; $pixB[$i] = $px.B
                $best = 0; $bestD = [int]::MaxValue
                for ($c = 0; $c -lt 16; $c++) {
                    $d = Get-Distance $px.R $px.G $px.B $c
                    if ($d -lt $bestD) { $bestD = $d; $best = $c }
                }
                $counts[$best]++
            }
            $counts[$background] = 0
            $top = @(0..15 | Where-Object { $counts[$_] -gt 0 } | Sort-Object { -$counts[$_] } | Select-Object -First 3)
            while ($top.Count -lt 3) { $top += $background }
            $choices = @($background, $top[0], $top[1], $top[2])
            $cell = $cy * 40 + $cx
            $tscreen[$cell] = [byte](($top[0] -shl 4) -bor $top[1])
            $tcolour[$cell] = [byte]$top[2]
            for ($row = 0; $row -lt 8; $row++) {
                $byte = 0
                for ($col = 0; $col -lt 4; $col++) {
                    $i = $row * 4 + $col
                    $best = 0; $bestD = [int]::MaxValue
                    for ($k = 0; $k -lt 4; $k++) {
                        $d = Get-Distance $pixR[$i] $pixG[$i] $pixB[$i] $choices[$k]
                        if ($d -lt $bestD) { $bestD = $d; $best = $k }
                    }
                    $byte = $byte -bor ($best -shl (6 - 2 * $col))
                }
                $tbitmap[$cell * 8 + $row] = [byte]$byte
            }
        }
    }
    $small.Dispose()
    $scr = New-Object byte[] 2025
    [System.Array]::Copy($tscreen, 0, $scr, 0, 1000)
    [System.Array]::Copy($tcolour, 0, $scr, 1024, 1000)
    $scr[2024] = [byte]$background
    Write-Prg "titlescr.prg" 0xC000 $scr
    Write-Prg "titlebmp.prg" 0xE000 $tbitmap
}

# TITLE: both parts packed (LZ, each on its own) into one file, which loads faster. It loads to $6C40
# (before the maps load there) and the game unpacks it: 2048 bytes to $D000, the RAM under
# the I/O chips (the colours, padded; copied to $C000 and colour RAM when the picture shows),
# then 8000 bytes to $E000 (the bitmap).
if (Test-Path $titlePath) {
    $scrPart = [System.IO.File]::ReadAllBytes((Join-Path $buildDirectory "titlescr.prg"))
    $bmpPart = [System.IO.File]::ReadAllBytes((Join-Path $buildDirectory "titlebmp.prg"))
    $plain = New-Object byte[] (2048 + 8000)
    [System.Array]::Copy($scrPart, 2, $plain, 0, $scrPart.Length - 2)
    [System.Array]::Copy($bmpPart, 2, $plain, 2048, 8000)
    $titlePacked = New-Object System.Collections.Generic.List[byte]
    # the two parts separately: the game switches destination between them
    $titlePacked.AddRange([Lz]::Pack([byte[]]$plain[0..2047]))
    $titlePacked.AddRange([Lz]::Pack([byte[]]$plain[2048..10047]))
    if (0x6C40 + $titlePacked.Count -gt 0xAB00) { throw "The packed title is too big." }
    Write-Prg "title.prg" 0x6C40 $titlePacked.ToArray()
    Write-Output "Title: $($titlePacked.Count) bytes packed (from 10048)."
}
