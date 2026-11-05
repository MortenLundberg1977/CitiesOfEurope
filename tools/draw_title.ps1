# Draws assets\title.png (320x200, C64 colours) for the title screen: sky and
# clouds, a "CITIES OF EUROPE" banner under a ring of stars, a map of Europe
# with a crosshair, a compass and a suitcase on a wooden table.
# Only needed to remake the picture; the build converts the committed PNG.
#
# Usage: powershell -File tools\draw_title.ps1 path\to\ne_50m_land.geojson
param([Parameter(Mandatory = $true)][string]$GeoJson)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$pal = @(0x000000, 0xFFFFFF, 0x813338, 0x75CEC8, 0x8E3C97, 0x56AC4D, 0x2E2C9B, 0xEDF171,
         0x8E5029, 0x553800, 0xC46C71, 0x4A4A4A, 0x7B7B7B, 0xA9FF9F, 0x706DEB, 0xB2B2B2)
function C([int]$i) { $c = $pal[$i]; [System.Drawing.Color]::FromArgb(255, ($c -shr 16) -band 255, ($c -shr 8) -band 255, $c -band 255) }
function B([int]$i) { New-Object System.Drawing.SolidBrush (C $i) }
function P([int]$i, [float]$w) { New-Object System.Drawing.Pen (C $i), $w }

$img = New-Object System.Drawing.Bitmap 320, 200
$g = [System.Drawing.Graphics]::FromImage($img)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
$g.Clear((C 14))                                   # lavender sky

# clouds: clusters of chunky ellipses with a light grey underside
function Cloud($x, $y, $s) {
    foreach ($e in @(@(0, 6, 22, 10), @(8, 0, 18, 14), @(20, 3, 16, 12), @(30, 7, 16, 9))) {
        $g.FillEllipse((B 15), [int]($x + $e[0] * $s), [int]($y + $e[1] * $s + 2), [int]($e[2] * $s), [int]($e[3] * $s))
    }
    foreach ($e in @(@(0, 6, 22, 10), @(8, 0, 18, 14), @(20, 3, 16, 12), @(30, 7, 16, 9))) {
        $g.FillEllipse((B 1), [int]($x + $e[0] * $s), [int]($y + $e[1] * $s), [int]($e[2] * $s), [int]($e[3] * $s))
    }
}
Cloud 8 26 1.0; Cloud 14 62 0.8; Cloud 262 22 1.0; Cloud 268 60 0.75

# ring of 12 yellow stars on a dark blue disc, like the European flag
$g.FillEllipse((B 7), 136, 0, 48, 30)
$g.FillEllipse((B 6), 139, 2, 42, 26)
for ($i = 0; $i -lt 12; $i++) {
    $a = $i * [Math]::PI / 6
    $sx = 160 + 15 * [Math]::Cos($a); $sy = 15 + 9 * [Math]::Sin($a)
    $g.FillRectangle((B 7), [int]$sx - 2, [int]$sy - 1, 4, 3)
}

# banner
$g.FillRectangle((B 7), 66, 24, 188, 60)
$g.FillRectangle((B 6), 70, 28, 180, 52)
$g.FillRectangle((B 9), 70, 80, 184, 4)            # shadow under the banner
$fontSmall = New-Object System.Drawing.Font "Arial Black", 15, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fontBig = New-Object System.Drawing.Font "Arial Black", 30, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$g.DrawString("CITIES OF", $fontSmall, (B 12), (New-Object System.Drawing.RectangleF 72, 31, 180, 20), $fmt)
$g.DrawString("CITIES OF", $fontSmall, (B 1), (New-Object System.Drawing.RectangleF 70, 29, 180, 20), $fmt)
$g.DrawString("EUROPE", $fontBig, (B 8), (New-Object System.Drawing.RectangleF 73, 44, 180, 40), $fmt)
$g.DrawString("EUROPE", $fontBig, (B 7), (New-Object System.Drawing.RectangleF 70, 41, 180, 40), $fmt)

# wooden table
$g.FillRectangle((B 9), 0, 182, 320, 18)
for ($y = 185; $y -lt 200; $y += 5) { $g.DrawLine((P 8 1), 0, $y, 320, $y + 1) }

# map sheet: paper with a yellow edge, Europe in green on blue sea
$mx = 84; $my = 90; $mw = 152; $mh = 88
$g.FillRectangle((B 7), $mx - 5, $my - 5, $mw + 10, $mh + 10)
$g.FillRectangle((B 15), $mx - 3, $my - 3, $mw + 6, $mh + 6)
$g.FillRectangle((B 6), $mx, $my, $mw, $mh)
$lon0 = -14.0; $lon1 = 44.0; $lat0 = 70.0; $lat1 = 34.0
$g.SetClip((New-Object System.Drawing.Rectangle $mx, $my, $mw, $mh))
$data = Get-Content -Raw $GeoJson | ConvertFrom-Json
foreach ($feature in $data.features) {
    $geometry = $feature.geometry
    $polys = New-Object System.Collections.Generic.List[object]
    if ($geometry.type -eq "Polygon") { $polys.Add($geometry.coordinates) }
    else { foreach ($p in $geometry.coordinates) { $polys.Add($p) } }
    foreach ($poly in $polys) {
        $ring = $poly[0]
        $minLon = ($ring | ForEach-Object { $_[0] } | Measure-Object -Minimum -Maximum)
        if ($minLon.Maximum -lt $lon0 -or $minLon.Minimum -gt $lon1) { continue }
        $pts = New-Object 'System.Drawing.PointF[]' $ring.Count
        for ($i = 0; $i -lt $ring.Count; $i++) {
            $pts[$i] = New-Object System.Drawing.PointF ([single]($mx + ($ring[$i][0] - $lon0) / ($lon1 - $lon0) * $mw)), ([single]($my + ($lat0 - $ring[$i][1]) / ($lat0 - $lat1) * $mh))
        }
        if ($pts.Length -ge 3) { $g.FillPolygon((B 5), $pts) }
    }
}
$g.ResetClip()
function MapXY($lon, $lat) { @([int]($mx + ($lon - $lon0) / ($lon1 - $lon0) * $mw), [int]($my + ($lat0 - $lat) / ($lat0 - $lat1) * $mh)) }
foreach ($c in @(@(-0.13, 51.51), @(12.5, 41.9), @(13.4, 52.52), @(-3.7, 40.42), @(18.07, 59.33), @(23.73, 37.98))) {
    $p = MapXY $c[0] $c[1]; $g.FillRectangle((B 1), $p[0] - 2, $p[1] - 2, 5, 5); $g.FillRectangle((B 2), $p[0] - 1, $p[1] - 1, 3, 3)
}
$p = MapXY 2.35 48.86                               # crosshair on Paris
$g.DrawEllipse((P 1 2), $p[0] - 9, $p[1] - 9, 18, 18)
$g.DrawLine((P 1 2), $p[0], $p[1] - 14, $p[0], $p[1] + 14)
$g.DrawLine((P 1 2), $p[0] - 14, $p[1], $p[0] + 14, $p[1])
$g.FillRectangle((B 2), $p[0] - 2, $p[1] - 2, 4, 4)

# compass, bottom left
$g.FillEllipse((B 9), 14, 140, 54, 54)
$g.FillEllipse((B 7), 12, 137, 54, 54)
$g.FillEllipse((B 8), 16, 141, 46, 46)
$g.FillEllipse((B 1), 19, 144, 40, 40)
$g.FillRectangle((B 7), 34, 128, 10, 10)
$g.FillPolygon((B 2), [System.Drawing.Point[]]@((New-Object System.Drawing.Point 39, 148), (New-Object System.Drawing.Point 44, 164), (New-Object System.Drawing.Point 34, 164)))
$g.FillPolygon((B 11), [System.Drawing.Point[]]@((New-Object System.Drawing.Point 34, 164), (New-Object System.Drawing.Point 44, 164), (New-Object System.Drawing.Point 39, 180)))
$fontC = New-Object System.Drawing.Font "Arial Black", 8, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString("N", $fontC, (B 0), 35, 144); $g.DrawString("S", $fontC, (B 0), 35, 173)
$g.DrawString("W", $fontC, (B 0), 21, 158); $g.DrawString("E", $fontC, (B 0), 51, 158)

# suitcase, bottom right
$g.FillRectangle((B 9), 268, 128, 26, 6); $g.FillRectangle((B 14), 274, 131, 14, 4)   # handle
$g.FillRectangle((B 9), 250, 138, 64, 48)
$g.FillRectangle((B 8), 253, 141, 58, 42)
foreach ($k in @(@(250, 138), @(306, 138), @(250, 178), @(306, 178))) { $g.FillRectangle((B 7), $k[0], $k[1], 8, 8) }
$g.FillRectangle((B 14), 258, 147, 24, 14); $g.FillRectangle((B 6), 263, 152, 14, 4); $g.FillRectangle((B 6), 268, 149, 4, 10)  # plane sticker
$g.FillRectangle((B 15), 286, 146, 18, 20); $g.FillPolygon((B 9), [System.Drawing.Point[]]@((New-Object System.Drawing.Point 295, 148), (New-Object System.Drawing.Point 301, 164), (New-Object System.Drawing.Point 289, 164)))  # tower sticker
$g.FillRectangle((B 7), 264, 164, 20, 14); $g.FillRectangle((B 5), 268, 166, 12, 5); $g.FillRectangle((B 9), 273, 170, 2, 7)   # palm sticker

$g.Dispose()
$out = Join-Path (Split-Path $PSScriptRoot -Parent) "assets\title.png"
$img.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
Write-Output "Wrote $out"
