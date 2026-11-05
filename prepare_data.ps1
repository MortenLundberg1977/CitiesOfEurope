$ErrorActionPreference = "Stop"

# Builds the CITIES and WORLDMAP data files for the disk.
# Each file is a PRG: a 2-byte load address followed by the data.
# tools/prepare_data.py does the same on Linux.

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

# CITIES: 49-byte records "CITY(16),COUNTRY(16),LAT(6),LON(7)" + CR, then a 0 byte.
# Loads to $6000; the game and CITYEDIT hold at most 250 records.
$records = New-Object System.Text.StringBuilder
$lines = Get-Content (Join-Path $projectRoot "data\cities.csv") | Select-Object -Skip 1
$count = 0
foreach ($line in $lines) {
    $parts = $line.Trim().Split(",")
    if ($parts.Length -lt 4 -or $parts[0] -eq "") { continue }
    $city = $parts[0].Trim().ToUpperInvariant()
    $country = $parts[1].Trim().ToUpperInvariant()
    if ($city.Length -gt 16) { throw "City name '$city' is longer than 16 characters." }
    if ($country.Length -gt 16) { throw "Country name '$country' is longer than 16 characters." }
    $lat = [double]::Parse($parts[2], $culture)
    $lon = [double]::Parse($parts[3], $culture)
    $record = $city.PadRight(16) + "," + $country.PadRight(16) + "," +
        (Format-Coordinate $lat 6) + "," + (Format-Coordinate $lon 7) + "`r"
    [void]$records.Append($record)
    $count++
}
if ($count -gt 250) { throw "data\cities.csv has $count cities; the game holds at most 250." }
$cityBytes = [System.Text.Encoding]::ASCII.GetBytes($records.ToString()) + [byte]0
Write-Prg "cities.prg" 0x6000 $cityBytes

# WORLDMAP: assets\worldmap.png (320x160, dark = land) as a C64 hi-res bitmap
# for text rows 0-19, loaded to $2000. Each 8x8 cell is 8 bytes, top to bottom;
# bit 7 is the leftmost pixel. A set bit is land.
Add-Type -AssemblyName System.Drawing
$image = New-Object System.Drawing.Bitmap (Join-Path $projectRoot "assets\worldmap.png")
if ($image.Width -ne 320 -or $image.Height -ne 160) {
    throw "assets\worldmap.png must be 320x160 pixels."
}
$bitmap = New-Object byte[] 6400
for ($y = 0; $y -lt 160; $y++) {
    for ($x = 0; $x -lt 320; $x++) {
        $pixel = $image.GetPixel($x, $y)
        if (($pixel.R + $pixel.G + $pixel.B) -lt 384) {
            $offset = [int][System.Math]::Floor($y / 8) * 320 + [int][System.Math]::Floor($x / 8) * 8 + ($y % 8)
            $bitmap[$offset] = $bitmap[$offset] -bor (0x80 -shr ($x % 8))
        }
    }
}
$image.Dispose()
Write-Prg "worldmap.prg" 0x2000 $bitmap

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
