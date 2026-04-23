# scripts/generate-web-icons.ps1 -- generate the pink "J" PWA icons for
# Rakhi's Jarvis Web PWA.
#
# Run once (or any time you want to regenerate). Writes:
#   web/icons/Icon-192.png          (rounded pink tile, white serif J)
#   web/icons/Icon-512.png          (same at 512)
#   web/icons/Icon-maskable-192.png (full-bleed pink, safe-zone J)
#   web/icons/Icon-maskable-512.png (same at 512)
#   web/favicon.png                 (64x64 for the browser tab)

Add-Type -AssemblyName System.Drawing

$pink = [System.Drawing.Color]::FromArgb(255, 212, 123, 160)      # #D47BA0
$deepPlum = [System.Drawing.Color]::FromArgb(255, 155, 75, 109)   # #9B4B6D
$white = [System.Drawing.Color]::White
$webRoot = Join-Path $PSScriptRoot '..\web'
$iconDir = Join-Path $webRoot 'icons'

# Typed enums pulled out once — using them as positional args to
# New-Object in Windows PowerShell 5.1 trips parse errors.
$fontRegular = [System.Drawing.FontStyle]::Regular
$unitPixel = [System.Drawing.GraphicsUnit]::Pixel
$smAA = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$txAA = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$stringFmtCenter = [System.Drawing.StringAlignment]::Center

function Save-JIcon {
    param(
        [int]$Size,
        [string]$OutPath,
        [bool]$Maskable = $false
    )
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = $smAA
    $g.TextRenderingHint = $txAA

    if ($Maskable) {
        # Full-bleed pink so Android launcher masks (circle, squircle,
        # teardrop) still have colour all the way to the edge.
        $g.Clear($pink)
    } else {
        # Transparent background with a rounded-rectangle pink tile (22%
        # radius -- matches iOS squircle look close enough).
        $g.Clear([System.Drawing.Color]::Transparent)
        $radius = [int]($Size * 0.22)
        $d = $radius * 2
        $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $path.AddArc(0, 0, $d, $d, 180, 90)
        $path.AddArc($Size - $d, 0, $d, $d, 270, 90)
        $path.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
        $path.AddArc(0, $Size - $d, $d, $d, 90, 90)
        $path.CloseFigure()
        $rect = [System.Drawing.Rectangle]::new(0, 0, $Size, $Size)
        $gradBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $rect, $pink, $deepPlum, 90
        )
        $g.FillPath($gradBrush, $path)
        $gradBrush.Dispose()
        $path.Dispose()
    }

    # White serif "J" centred. Maskable gets a smaller letter so the
    # safe zone (central 80%) clears any launcher mask shape.
    $charScale = if ($Maskable) { 0.55 } else { 0.72 }
    $fontSize = [single]($Size * $charScale)
    $font = [System.Drawing.Font]::new('Georgia', $fontSize, $fontRegular, $unitPixel)

    $sf = [System.Drawing.StringFormat]::new()
    $sf.Alignment = $stringFmtCenter
    $sf.LineAlignment = $stringFmtCenter

    # Serif "J" sits visually low inside its bbox; lift it a few percent.
    $yOffset = [single](-($Size * 0.04))
    $rectF = [System.Drawing.RectangleF]::new([single]0, $yOffset, [single]$Size, [single]$Size)
    $whiteBrush = [System.Drawing.SolidBrush]::new($white)
    $g.DrawString('J', $font, $whiteBrush, $rectF, $sf)
    $whiteBrush.Dispose()
    $font.Dispose()
    $sf.Dispose()

    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Host "Wrote $OutPath ($Size px$(if ($Maskable) { ', maskable' }))"
}

Save-JIcon -Size 192 -OutPath (Join-Path $iconDir 'Icon-192.png')
Save-JIcon -Size 512 -OutPath (Join-Path $iconDir 'Icon-512.png')
Save-JIcon -Size 192 -OutPath (Join-Path $iconDir 'Icon-maskable-192.png') -Maskable $true
Save-JIcon -Size 512 -OutPath (Join-Path $iconDir 'Icon-maskable-512.png') -Maskable $true
Save-JIcon -Size 64 -OutPath (Join-Path $webRoot 'favicon.png')

Write-Host ''
Write-Host 'Pink J icons generated. Commit + redeploy to push to the PWA.' -ForegroundColor Green
