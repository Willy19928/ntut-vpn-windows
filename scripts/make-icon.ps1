#requires -Version 5.1
<#
Draws assets\NTUT-VPN.ico: a white shield with a reconnect arrow on a blue tile.
Each size is drawn on its own (not scaled down) so small sizes stay sharp.
The .ico is committed; run this only to change the icon.
#>
[CmdletBinding()]
param(
    [string]$OutFile,
    [string]$PreviewDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (!$OutFile) {
    $OutFile = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'assets\NTUT-VPN.ico'
}
Add-Type -AssemblyName System.Drawing

$sizes = 16, 20, 24, 32, 40, 48, 64, 256

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}

function New-Shield([single]$s) {
    # Shield in a 256 grid, scaled to $s.
    $k = $s / 256.0
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $pt = { param($x, $y) New-Object System.Drawing.PointF(($x * $k), ($y * $k)) }
    $p.AddLine((& $pt 128 34), (& $pt 206 62))
    $p.AddBezier((& $pt 206 62), (& $pt 206 140), (& $pt 186 190), (& $pt 128 224))
    $p.AddBezier((& $pt 128 224), (& $pt 70 190), (& $pt 50 140), (& $pt 50 62))
    $p.CloseFigure()
    $p
}

function Get-IconBitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    $k = $s / 256.0

    # Blue tile.
    $inset = if ($s -le 24) { 0 } else { 8 * $k }
    $tile = New-RoundRect $inset $inset ($s - 2 * $inset) ($s - 2 * $inset) ([Math]::Max(2, 48 * $k))
    $rect = New-Object System.Drawing.RectangleF 0, 0, $s, $s
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(255, 37, 120, 214)), ([System.Drawing.Color]::FromArgb(255, 20, 70, 150)), 90
    $g.FillPath($grad, $tile)

    # White shield.
    $shield = New-Shield $s
    $g.FillPath([System.Drawing.Brushes]::White, $shield)

    # Reconnect arrow inside the shield: an open ring with an arrowhead.
    $blue = [System.Drawing.Color]::FromArgb(255, 24, 86, 176)
    $cx = 128 * $k; $cy = 122 * $k
    $r = 40 * $k
    $w = [Math]::Max(1.6, 17 * $k)
    $pen = New-Object System.Drawing.Pen $blue, $w
    $pen.StartCap = 'Flat'; $pen.EndCap = 'Flat'
    $start = -50; $sweep = 280
    $g.DrawArc($pen, ($cx - $r), ($cy - $r), (2 * $r), (2 * $r), $start, $sweep)

    # Arrowhead at the end of the arc, pointing along the direction of travel.
    $end = ($start + $sweep) * [Math]::PI / 180
    $ex = $cx + $r * [Math]::Cos($end); $ey = $cy + $r * [Math]::Sin($end)
    $tx = -[Math]::Sin($end); $ty = [Math]::Cos($end)     # tangent (clockwise)
    $nx = [Math]::Cos($end); $ny = [Math]::Sin($end)      # outward normal
    $len = 30 * $k; $half = 22 * $k
    $tip = New-Object System.Drawing.PointF ([single]($ex + $tx * $len)), ([single]($ey + $ty * $len))
    $a = New-Object System.Drawing.PointF ([single]($ex + $nx * $half)), ([single]($ey + $ny * $half))
    $b = New-Object System.Drawing.PointF ([single]($ex - $nx * $half)), ([single]($ey - $ny * $half))
    $brush = New-Object System.Drawing.SolidBrush $blue
    $g.FillPolygon($brush, [System.Drawing.PointF[]]@($a, $tip, $b))

    $g.Dispose()
    $bmp
}

$images = foreach ($s in $sizes) {
    $bmp = Get-IconBitmap $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    if ($PreviewDir) {
        New-Item -ItemType Directory -Force -Path $PreviewDir | Out-Null
        $bmp.Save((Join-Path $PreviewDir "icon-$s.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    }
    $bmp.Dispose()
    [pscustomobject]@{ Size = $s; Bytes = $ms.ToArray() }
}

# ICO container with PNG-compressed entries (supported since Windows Vista).
$out = New-Object System.IO.MemoryStream
$wr = New-Object System.IO.BinaryWriter $out
$wr.Write([uint16]0); $wr.Write([uint16]1); $wr.Write([uint16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($i in $images) {
    $dim = if ($i.Size -ge 256) { 0 } else { $i.Size }
    $wr.Write([byte]$dim); $wr.Write([byte]$dim); $wr.Write([byte]0); $wr.Write([byte]0)
    $wr.Write([uint16]1); $wr.Write([uint16]32)
    $wr.Write([uint32]$i.Bytes.Length); $wr.Write([uint32]$offset)
    $offset += $i.Bytes.Length
}
foreach ($i in $images) { $wr.Write($i.Bytes) }
$wr.Flush()

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
[IO.File]::WriteAllBytes($OutFile, $out.ToArray())
Write-Host "Wrote $OutFile ($($out.Length) bytes, sizes $($sizes -join ', '))"
