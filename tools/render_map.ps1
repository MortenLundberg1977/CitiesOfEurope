# Renders the region maps assets\maps\region<ID>.png (320x160, black land on white
# sea) from Natural Earth land outlines, using the regions in data\regions.csv.
# Only needed when regions.csv changes; the build uses the committed PNGs.
#
# Usage: powershell -File tools\render_map.ps1 path\to\ne_50m_land.geojson
# The GeoJSON is public domain: https://github.com/nvkelso/natural-earth-vector
# (geojson/ne_50m_land.geojson).
#
# Projection, the same one src/citiesofeurope.asm (calc_pixel) uses to place the marker:
#   x = (lon - LON0) / DX     longitude wraps, so a region may cross 180 degrees
#   y = (LAT0 - lat) / DY     DX and DY are hundredths of a degree per pixel
param([Parameter(Mandatory = $true)][string]$GeoJson)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $root "assets\maps"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$width = 320
$height = 160
$scale = 4                  # draw large, then reduce, for cleaner coastlines

Write-Output "Reading $GeoJson"
$data = Get-Content -Raw $GeoJson | ConvertFrom-Json
$polygons = New-Object System.Collections.Generic.List[object]
foreach ($feature in $data.features) {
    $geometry = $feature.geometry
    if ($geometry.type -eq "Polygon") { $polygons.Add($geometry.coordinates) }
    elseif ($geometry.type -eq "MultiPolygon") { foreach ($p in $geometry.coordinates) { $polygons.Add($p) } }
}

foreach ($region in (Import-Csv (Join-Path $root "data\regions.csv"))) {
    $lon0 = [double]$region.LON0
    $lat0 = [double]$region.LAT0
    $dx = [double]$region.DX / 100.0      # degrees per pixel
    $dy = [double]$region.DY / 100.0

    $big = New-Object System.Drawing.Bitmap ($width * $scale), ($height * $scale), ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($big)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.Clear([System.Drawing.Color]::White)
    $dots = New-Object System.Collections.Generic.List[object]

    foreach ($shift in @(-360.0, 0.0, 360.0)) {
        foreach ($polygon in $polygons) {
            $first = $true
            foreach ($ring in $polygon) {
                $points = New-Object 'System.Drawing.PointF[]' $ring.Count
                $minX = [double]::MaxValue; $maxX = [double]::MinValue
                $minY = [double]::MaxValue; $maxY = [double]::MinValue
                for ($i = 0; $i -lt $ring.Count; $i++) {
                    $x = ($ring[$i][0] + $shift - $lon0) / $dx
                    $y = ($lat0 - $ring[$i][1]) / $dy
                    if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
                    $points[$i] = New-Object System.Drawing.PointF ([single]($x * $scale)), ([single]($y * $scale))
                }
                if ($maxX -lt 0 -or $minX -ge $width -or $maxY -lt 0 -or $minY -ge $height) { $first = $false; continue }
                if ($first) {
                    $g.FillPolygon([System.Drawing.Brushes]::Black, $points)
                    # An island smaller than about a pixel would vanish: keep it as one pixel.
                    if ($maxX - $minX -lt 1.5 -and $maxY - $minY -lt 1.5) {
                        $dots.Add(@([int][Math]::Floor(($minX + $maxX) / 2), [int][Math]::Floor(($minY + $maxY) / 2)))
                    }
                } else {
                    $g.FillPolygon([System.Drawing.Brushes]::White, $points)   # lakes
                }
                $first = $false
            }
        }
    }
    $g.Dispose()

    # Reduce: a pixel is land when at least 6 of its 16 sub-pixels are land.
    $rect = New-Object System.Drawing.Rectangle 0, 0, $big.Width, $big.Height
    $lock = $big.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $big.PixelFormat)
    $stride = $lock.Stride
    $raw = New-Object byte[] ($stride * $big.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($lock.Scan0, $raw, 0, $raw.Length)
    $big.UnlockBits($lock)
    $big.Dispose()

    $map = New-Object System.Drawing.Bitmap $width, $height
    $land = New-Object 'bool[,]' $width, $height
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $count = 0
            for ($sy = 0; $sy -lt $scale; $sy++) {
                $row = ($y * $scale + $sy) * $stride + $x * $scale * 3
                for ($sx = 0; $sx -lt $scale; $sx++) {
                    if ($raw[$row + $sx * 3] -lt 128) { $count++ }
                }
            }
            $land[$x, $y] = ($count -ge 6)
        }
    }
    foreach ($d in $dots) {
        if ($d[0] -ge 0 -and $d[0] -lt $width -and $d[1] -ge 0 -and $d[1] -lt $height) { $land[$d[0], $d[1]] = $true }
    }
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            if ($land[$x, $y]) { $map.SetPixel($x, $y, [System.Drawing.Color]::Black) }
            else { $map.SetPixel($x, $y, [System.Drawing.Color]::White) }
        }
    }
    $out = Join-Path $outDir ("region" + $region.ID + ".png")
    $map.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $map.Dispose()
    Write-Output "Wrote $out ($($region.NAME))"
}
