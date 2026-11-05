# Renders Natural Earth land outlines into assets\worldmap.png (320x160, black land
# on white sea), the picture the build turns into the game's hi-res map.
# Only needed to remake the picture; the build uses the committed PNG.
#
# Usage: powershell -File tools\render_map.ps1 path\to\ne_110m_land.geojson
# The GeoJSON is public domain: https://github.com/nvkelso/natural-earth-vector
# (geojson/ne_110m_land.geojson).
#
# Projection: equirectangular, longitude -180..180 over x 0..319 and
# latitude 84N..60S over y 0..159. src/worldcities.asm (calc_pixel) uses the same.
param([Parameter(Mandatory = $true)][string]$GeoJson)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$width = 320
$height = 160
$scale = 4                  # draw large, then reduce, for cleaner coastlines
$latTop = 84.0
$latBottom = -60.0

$big = New-Object System.Drawing.Bitmap ($width * $scale), ($height * $scale)
$g = [System.Drawing.Graphics]::FromImage($big)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.Clear([System.Drawing.Color]::White)
$land = [System.Drawing.Brushes]::Black
$sea = [System.Drawing.Brushes]::White

function Convert-Ring($ring) {
    $points = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    foreach ($c in $ring) {
        $x = ($c[0] + 180.0) / 360.0 * $width * $scale
        $y = ($latTop - $c[1]) / ($latTop - $latBottom) * $height * $scale
        $points.Add((New-Object System.Drawing.PointF ([single]$x), ([single]$y)))
    }
    return , $points.ToArray()
}

function Draw-Polygon($rings) {
    $first = $true
    foreach ($ring in $rings) {
        $points = Convert-Ring $ring
        if ($points.Length -lt 3) { continue }
        # The first ring is the coast, the others are lakes.
        if ($first) { $g.FillPolygon($land, $points) } else { $g.FillPolygon($sea, $points) }
        $first = $false
    }
}

$data = Get-Content -Raw $GeoJson | ConvertFrom-Json
foreach ($feature in $data.features) {
    $geometry = $feature.geometry
    if ($geometry.type -eq "Polygon") {
        Draw-Polygon $geometry.coordinates
    } elseif ($geometry.type -eq "MultiPolygon") {
        foreach ($polygon in $geometry.coordinates) { Draw-Polygon $polygon }
    }
}
$g.Dispose()

# Reduce: a pixel is land when at least 6 of its 16 sub-pixels are land, so
# small islands survive.
$map = New-Object System.Drawing.Bitmap $width, $height
for ($y = 0; $y -lt $height; $y++) {
    for ($x = 0; $x -lt $width; $x++) {
        $count = 0
        for ($sy = 0; $sy -lt $scale; $sy++) {
            for ($sx = 0; $sx -lt $scale; $sx++) {
                if ($big.GetPixel($x * $scale + $sx, $y * $scale + $sy).R -lt 128) { $count++ }
            }
        }
        if ($count -ge 6) { $map.SetPixel($x, $y, [System.Drawing.Color]::Black) }
        else { $map.SetPixel($x, $y, [System.Drawing.Color]::White) }
    }
}
$big.Dispose()

$out = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\worldmap.png"
$map.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$map.Dispose()
Write-Output "Wrote $out"
