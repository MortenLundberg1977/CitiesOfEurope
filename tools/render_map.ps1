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
#
# Optional: -Borders ne_50m_admin_0_boundary_lines_land.geojson (dotted lines) and
# -Rivers ne_50m_rivers_lake_centerlines.geojson (solid lines; only rivers with a
# scalerank up to -RiverRank, so the maps don't get crowded).
param([Parameter(Mandatory = $true)][string]$GeoJson, [string]$Borders, [string]$Rivers, [int]$RiverRank = 5)

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

$lines = New-Object System.Collections.Generic.List[object]
function Add-Lines([string]$path, [bool]$dotted, [int]$maxRank) {
    if (-not $path) { return }
    Write-Output "Reading $path"
    foreach ($feature in (Get-Content -Raw $path | ConvertFrom-Json).features) {
        if ($maxRank -ge 0 -and $feature.properties.scalerank -gt $maxRank) { continue }
        if ($feature.properties.featurecla -and $feature.properties.featurecla -notmatch 'River|Boundary|International|Disputed|Line') { continue }
        $geometry = $feature.geometry
        if (-not $geometry) { continue }
        $parts = New-Object System.Collections.Generic.List[object]
        if ($geometry.type -eq "LineString") { $parts.Add($geometry.coordinates) }
        elseif ($geometry.type -eq "MultiLineString") { foreach ($p in $geometry.coordinates) { $parts.Add($p) } }
        foreach ($p in $parts) { $lines.Add([pscustomobject]@{ Points = $p; Dotted = $dotted }) }
    }
}
Add-Lines $Borders $true -1
Add-Lines $Rivers $false $RiverRank

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
    # Rivers (solid) and country borders (dotted) in sea colour on the land.
    # The hi-res map has only two colours per 8x8 block, so they can't be a third colour.
    foreach ($line in $lines) {
        foreach ($shift in @(-360.0, 0.0, 360.0)) {
            $step = 0
            for ($i = 1; $i -lt $line.Points.Count; $i++) {
                $x0 = ($line.Points[$i - 1][0] + $shift - $lon0) / $dx; $y0 = ($lat0 - $line.Points[$i - 1][1]) / $dy
                $x1 = ($line.Points[$i][0] + $shift - $lon0) / $dx; $y1 = ($lat0 - $line.Points[$i][1]) / $dy
                if ([Math]::Max($x0, $x1) -lt 0 -or [Math]::Min($x0, $x1) -ge $width -or [Math]::Max($y0, $y1) -lt 0 -or [Math]::Min($y0, $y1) -ge $height) { continue }
                $n = [int][Math]::Ceiling([Math]::Max([Math]::Abs($x1 - $x0), [Math]::Abs($y1 - $y0)))
                if ($n -lt 1) { $n = 1 }
                for ($k = 0; $k -le $n; $k++) {
                    $px = [int][Math]::Floor($x0 + ($x1 - $x0) * $k / $n); $py = [int][Math]::Floor($y0 + ($y1 - $y0) * $k / $n)
                    if ($px -lt 0 -or $px -ge $width -or $py -lt 0 -or $py -ge $height) { continue }
                    $step++
                    if ($line.Dotted -and ($step % 3) -ne 0) { continue }
                    # keep a pixel of land on both sides, so lines don't eat small countries
                    if ($land[$px, $py]) { $land[$px, $py] = $false }
                }
            }
        }
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
