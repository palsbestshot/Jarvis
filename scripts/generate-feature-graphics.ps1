# Generates illustrative PNGs for RAKHI_FEATURES.md.
# Pure System.Drawing (Windows PowerShell 5.1 compatible). ASCII-only
# source so no encoding gotchas; any glyphs we actually want rendered
# in the images are built from char codes at runtime.

Add-Type -AssemblyName System.Drawing

# --- Palette (matches lib/core/theme.dart RakhiTheme) -------------------
$pink      = [System.Drawing.Color]::FromArgb(255, 212, 123, 160) # D47BA0
$pinkDeep  = [System.Drawing.Color]::FromArgb(255, 155, 75, 109)  # 9B4B6D
$pinkLight = [System.Drawing.Color]::FromArgb(255, 255, 245, 248) # FFF5F8 bg
$pinkCard  = [System.Drawing.Color]::FromArgb(255, 253, 232, 239) # FDE8EF surface2
$white     = [System.Drawing.Color]::White
$plum      = [System.Drawing.Color]::FromArgb(255, 42, 26, 31)    # 2A1A1F text
$mauve     = [System.Drawing.Color]::FromArgb(255, 138, 106, 120) # 8A6A78 text2
$muted     = [System.Drawing.Color]::FromArgb(255, 184, 156, 169) # B89CA9 muted

$fontRegular = [System.Drawing.FontStyle]::Regular
$fontBold    = [System.Drawing.FontStyle]::Bold
$unitPixel   = [System.Drawing.GraphicsUnit]::Pixel
$smAA        = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$txAA        = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$sfCenter    = [System.Drawing.StringAlignment]::Center
$sfLeft      = [System.Drawing.StringAlignment]::Near

# Arrows + special characters produced at runtime so the script source
# stays ASCII.
$arrowRight = [char]0x2192  # ->
$arrowLeft  = [char]0x2190  # <-
$checkMark  = [char]0x2713  # check
$emDash     = [char]0x2014  # em-dash
$bullet     = [char]0x2022  # bullet

$outDir = Join-Path $PSScriptRoot '..\docs\features'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# --- Helper: rounded rectangle path -------------------------------------
function Get-RoundedRectPath {
    param([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-Canvas {
    param([int]$W, [int]$H)
    $bmp = [System.Drawing.Bitmap]::new($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = $smAA
    $g.TextRenderingHint = $txAA
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear($pinkLight)
    return @{ Bmp = $bmp; G = $g }
}

function Save-Canvas {
    param($Canvas, [string]$Name)
    $path = Join-Path $outDir $Name
    $Canvas.Bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $Canvas.G.Dispose()
    $Canvas.Bmp.Dispose()
    Write-Host "  wrote $path"
}

function Draw-Text {
    param($G, [string]$Text, [string]$FontName, [float]$Size, [float]$X, [float]$Y,
          [System.Drawing.Color]$Color, [System.Drawing.FontStyle]$Style = $fontRegular,
          [string]$Align = 'left', [float]$MaxWidth = 0)
    $font = [System.Drawing.Font]::new($FontName, $Size, $Style, $unitPixel)
    $brush = [System.Drawing.SolidBrush]::new($Color)
    $sf = [System.Drawing.StringFormat]::new()
    if ($Align -eq 'center') { $sf.Alignment = $sfCenter } else { $sf.Alignment = $sfLeft }
    $sf.LineAlignment = $sfLeft
    if ($MaxWidth -gt 0) {
        $rect = [System.Drawing.RectangleF]::new($X, $Y, $MaxWidth, 9999)
        $G.DrawString($Text, $font, $brush, $rect, $sf)
    } else {
        $G.DrawString($Text, $font, $brush, $X, $Y, $sf)
    }
    $brush.Dispose()
    $font.Dispose()
    $sf.Dispose()
}

function Fill-Rounded {
    param($G, [float]$X, [float]$Y, [float]$W, [float]$H, [float]$R,
          [System.Drawing.Color]$Color)
    $path = Get-RoundedRectPath -X $X -Y $Y -W $W -H $H -R $R
    $brush = [System.Drawing.SolidBrush]::new($Color)
    $G.FillPath($brush, $path)
    $brush.Dispose()
    $path.Dispose()
}

function Stroke-Rounded {
    param($G, [float]$X, [float]$Y, [float]$W, [float]$H, [float]$R,
          [System.Drawing.Color]$Color, [float]$Thickness = 1.5)
    $path = Get-RoundedRectPath -X $X -Y $Y -W $W -H $H -R $R
    $pen = [System.Drawing.Pen]::new($Color, $Thickness)
    $G.DrawPath($pen, $path)
    $pen.Dispose()
    $path.Dispose()
}

# =======================================================================
# 01 -- HERO (pink J logo + tagline)
# =======================================================================
Write-Host 'Drawing 01-hero.png'
$c = New-Canvas -W 1200 -H 600
$g = $c.G

$iconSize = 340; $iconX = 120; $iconY = 130
$iconPath = Get-RoundedRectPath -X $iconX -Y $iconY -W $iconSize -H $iconSize -R ($iconSize * 0.22)
$rect = [System.Drawing.Rectangle]::new($iconX, $iconY, $iconSize, $iconSize)
$grad = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $pink, $pinkDeep, 90)
$g.FillPath($grad, $iconPath)
$grad.Dispose()
$iconPath.Dispose()
Draw-Text -G $g -Text 'J' -FontName 'Georgia' -Size 260 `
    -X ($iconX + $iconSize / 2) -Y ($iconY + 30) -Color $white `
    -Style $fontRegular -Align 'center'

Draw-Text -G $g -Text 'Jarvis' -FontName 'Georgia' -Size 96 -X 540 -Y 180 -Color $plum
Draw-Text -G $g -Text 'Your kitchen + life companion' -FontName 'Segoe UI' `
    -Size 38 -X 540 -Y 300 -Color $mauve
Draw-Text -G $g -Text 'Chat, plan meals, remember tasks,' -FontName 'Segoe UI' `
    -Size 28 -X 540 -Y 370 -Color $muted
Draw-Text -G $g -Text 'track habits, all in one app.' -FontName 'Segoe UI' `
    -Size 28 -X 540 -Y 408 -Color $muted
Save-Canvas -Canvas $c -Name '01-hero.png'

# =======================================================================
# 02 -- CHAT (phone frame with chat bubbles)
# =======================================================================
Write-Host 'Drawing 02-chat.png'
$c = New-Canvas -W 1200 -H 800
$g = $c.G

Draw-Text -G $g -Text 'Chat or talk - in any language' -FontName 'Segoe UI' `
    -Size 42 -X 80 -Y 60 -Color $plum -Style $fontBold
Draw-Text -G $g -Text 'Type a message, or tap the mic and speak naturally.' `
    -FontName 'Segoe UI' -Size 26 -X 80 -Y 130 -Color $mauve

$phoneX = 120; $phoneY = 200; $phoneW = 400; $phoneH = 540
Fill-Rounded -G $g -X $phoneX -Y $phoneY -W $phoneW -H $phoneH -R 40 -Color $pinkDeep
Fill-Rounded -G $g -X ($phoneX + 6) -Y ($phoneY + 6) -W ($phoneW - 12) -H ($phoneH - 12) -R 34 -Color $pinkLight

Fill-Rounded -G $g -X ($phoneX + 120) -Y ($phoneY + 60) -W 250 -H 80 -R 18 -Color $pink
Draw-Text -G $g -Text 'I bought brinjal,' -FontName 'Segoe UI' -Size 20 `
    -X ($phoneX + 138) -Y ($phoneY + 75) -Color $white
Draw-Text -G $g -Text 'ladyfinger, potato.' -FontName 'Segoe UI' -Size 20 `
    -X ($phoneX + 138) -Y ($phoneY + 100) -Color $white

Fill-Rounded -G $g -X ($phoneX + 30) -Y ($phoneY + 170) -W 320 -H 200 -R 18 -Color $pinkCard
Draw-Text -G $g -Text "$checkMark  Week plan saved:" -FontName 'Segoe UI' -Size 18 `
    -X ($phoneX + 50) -Y ($phoneY + 185) -Color $plum -Style $fontBold
Draw-Text -G $g -Text "$bullet  Mon: Brinjal bharta + roti" -FontName 'Segoe UI' -Size 16 `
    -X ($phoneX + 50) -Y ($phoneY + 220) -Color $plum
Draw-Text -G $g -Text "$bullet  Tue: Aloo bhindi + dal" -FontName 'Segoe UI' -Size 16 `
    -X ($phoneX + 50) -Y ($phoneY + 250) -Color $plum
Draw-Text -G $g -Text "$bullet  Wed: Comfort dal-chawal" -FontName 'Segoe UI' -Size 16 `
    -X ($phoneX + 50) -Y ($phoneY + 280) -Color $plum
Draw-Text -G $g -Text "$bullet  Thu: Potato paratha" -FontName 'Segoe UI' -Size 16 `
    -X ($phoneX + 50) -Y ($phoneY + 310) -Color $plum
Draw-Text -G $g -Text '(toddler-friendly versions noted)' `
    -FontName 'Segoe UI' -Size 14 -X ($phoneX + 50) -Y ($phoneY + 340) -Color $mauve

Fill-Rounded -G $g -X ($phoneX + 30) -Y ($phoneY + 450) -W 250 -H 50 -R 25 -Color $white
Stroke-Rounded -G $g -X ($phoneX + 30) -Y ($phoneY + 450) -W 250 -H 50 -R 25 -Color $pinkCard
Draw-Text -G $g -Text 'Ask Jarvis...' -FontName 'Segoe UI' -Size 18 `
    -X ($phoneX + 50) -Y ($phoneY + 465) -Color $muted

# Mic button — plain round + 'mic' icon drawn as shape (no emoji to avoid
# missing-font render boxes).
$micBrush = [System.Drawing.SolidBrush]::new($pink)
$g.FillEllipse($micBrush, ($phoneX + 300), ($phoneY + 450), 50, 50)
$micBrush.Dispose()
$wp = [System.Drawing.Pen]::new($white, 2.5)
# Little mic: rounded rect + base
$g.FillRectangle([System.Drawing.SolidBrush]::new($white), ($phoneX + 320), ($phoneY + 462), 10, 18)
$g.DrawLine($wp, ($phoneX + 325), ($phoneY + 482), ($phoneX + 325), ($phoneY + 492))
$g.DrawLine($wp, ($phoneX + 319), ($phoneY + 492), ($phoneX + 331), ($phoneY + 492))
$wp.Dispose()

Draw-Text -G $g -Text 'Examples you can try:' -FontName 'Segoe UI' `
    -Size 24 -X 620 -Y 240 -Color $plum -Style $fontBold
$examples = @(
    '"Plan tomorrow''s dinner, light"',
    '"Remind me to call mom tomorrow 5pm"',
    '"What can I make with paneer + tomato?"',
    '"Spent 500 on groceries today"',
    '"Daily 7am walk for 30 minutes"',
    '"Thought: add methi to next paneer"'
)
$y = 300
foreach ($ex in $examples) {
    Draw-Text -G $g -Text $ex -FontName 'Segoe UI' -Size 22 -X 620 -Y $y -Color $mauve
    $y += 44
}
Save-Canvas -Canvas $c -Name '02-chat.png'

# =======================================================================
# 03 -- MEAL CALENDAR (monthly grid with pink dots)
# =======================================================================
Write-Host 'Drawing 03-meal-calendar.png'
$c = New-Canvas -W 1200 -H 800
$g = $c.G

Draw-Text -G $g -Text 'Monthly meal calendar' -FontName 'Segoe UI' `
    -Size 42 -X 80 -Y 60 -Color $plum -Style $fontBold
Draw-Text -G $g -Text 'Tap any day, pick meals. Dots show what is planned.' `
    -FontName 'Segoe UI' -Size 26 -X 80 -Y 130 -Color $mauve

Draw-Text -G $g -Text "$arrowLeft  April 2026  $arrowRight" -FontName 'Segoe UI' -Size 32 `
    -X 600 -Y 210 -Color $plum -Style $fontBold -Align 'center'

$cellW = 130; $cellH = 80; $gridX = 110; $gridY = 280
$weekdays = @('M', 'T', 'W', 'T', 'F', 'S', 'S')
for ($i = 0; $i -lt 7; $i++) {
    Draw-Text -G $g -Text $weekdays[$i] -FontName 'Segoe UI' -Size 22 `
        -X ($gridX + $i * $cellW + $cellW / 2) -Y $gridY -Color $muted `
        -Style $fontBold -Align 'center'
}

$days = @(
    @(0, 0, 1, 2, 3, 4, 5),
    @(6, 7, 8, 9, 10, 11, 12),
    @(13, 14, 15, 16, 17, 18, 19),
    @(20, 21, 22, 23, 24, 25, 26)
)
$planned = @{
    1  = @($true, $true, $true)
    2  = @($true, $true, $true)
    3  = @($false, $true, $true)
    8  = @($true, $true, $true)
    9  = @($true, $false, $true)
    15 = @($true, $true, $false)
    22 = @($true, $true, $true)
    23 = @($true, $true, $true)
}
$todayDay = 15
$rowIdx = 0
foreach ($row in $days) {
    for ($i = 0; $i -lt 7; $i++) {
        $d = $row[$i]
        if ($d -eq 0) { continue }
        $cx = $gridX + $i * $cellW
        $cy = $gridY + 40 + $rowIdx * ($cellH + 10)
        Fill-Rounded -G $g -X $cx -Y $cy -W ($cellW - 10) -H $cellH -R 12 -Color $pinkCard
        if ($d -eq $todayDay) {
            Stroke-Rounded -G $g -X $cx -Y $cy -W ($cellW - 10) -H $cellH -R 12 `
                -Color $pink -Thickness 2.5
        }
        $cellStyle = $fontRegular
        if ($d -eq $todayDay) { $cellStyle = $fontBold }
        Draw-Text -G $g -Text "$d" -FontName 'Segoe UI' -Size 22 `
            -X ($cx + ($cellW - 10) / 2) -Y ($cy + 8) -Color $plum `
            -Style $cellStyle -Align 'center'
        if ($planned.ContainsKey($d)) {
            $dots = $planned[$d]
            $dotSize = 8; $dotSpacing = 4
            $totalDotsW = 3 * $dotSize + 2 * $dotSpacing
            $startX = $cx + ($cellW - 10) / 2 - $totalDotsW / 2
            $dotY = $cy + 50
            for ($j = 0; $j -lt 3; $j++) {
                $color = if ($dots[$j]) { $pink } else { $muted }
                $brush = [System.Drawing.SolidBrush]::new($color)
                $g.FillEllipse($brush, ($startX + $j * ($dotSize + $dotSpacing)), $dotY, $dotSize, $dotSize)
                $brush.Dispose()
            }
        }
    }
    $rowIdx++
}

Draw-Text -G $g -Text 'Pink border = today. Pink dots = planned slots.' `
    -FontName 'Segoe UI' -Size 22 -X 600 -Y 720 -Color $mauve -Align 'center'
Save-Canvas -Canvas $c -Name '03-meal-calendar.png'

# =======================================================================
# 04 -- WEEKLY FROM GROCERIES (ingredients then 7-day plan)
# =======================================================================
Write-Host 'Drawing 04-weekly-from-groceries.png'
$c = New-Canvas -W 1200 -H 800
$g = $c.G

Draw-Text -G $g -Text 'Plan the week from your groceries' -FontName 'Segoe UI' `
    -Size 42 -X 80 -Y 60 -Color $plum -Style $fontBold
Draw-Text -G $g -Text 'Tell Jarvis what you bought. It builds a 7-day plan that uses up produce before it spoils.' `
    -FontName 'Segoe UI' -Size 24 -X 80 -Y 130 -Color $mauve -MaxWidth 1040

Draw-Text -G $g -Text 'You bought:' -FontName 'Segoe UI' -Size 26 `
    -X 80 -Y 220 -Color $plum -Style $fontBold
$ingredients = @('Potato', 'Brinjal', 'Ladyfinger', 'Cauliflower', '+ pantry staples')
$y = 280
foreach ($ing in $ingredients) {
    Fill-Rounded -G $g -X 80 -Y $y -W 340 -H 52 -R 12 -Color $pinkCard
    # Little dot marker on the left of each chip
    $brush = [System.Drawing.SolidBrush]::new($pink)
    $g.FillEllipse($brush, 102, ($y + 20), 12, 12)
    $brush.Dispose()
    Draw-Text -G $g -Text $ing -FontName 'Segoe UI' -Size 22 -X 130 -Y ($y + 12) -Color $plum
    $y += 64
}

Draw-Text -G $g -Text "$arrowRight" -FontName 'Segoe UI' -Size 70 `
    -X 500 -Y 440 -Color $pink -Style $fontBold

$weekDays = @(
    @('Mon', 'Aloo paratha', 'Aloo bhindi + dal', 'Brinjal bharta + roti'),
    @('Tue', 'Poha', 'Gobi matar + roti', 'Simple khichdi'),
    @('Wed', 'Upma', 'Dal-chawal', 'Aloo-gobi + phulka'),
    @('Thu', 'Idli + chutney', 'Bhindi masala + rice', 'Brinjal curry'),
    @('Fri', 'Thepla + curd', 'Mixed veg + dal', 'Stuffed paratha'),
    @('Sat', 'Dosa', 'Chole + rice', 'Veg pulao'),
    @('Sun', 'Pav bhaji', 'Rajma chawal', 'Light khichdi')
)
Draw-Text -G $g -Text 'Jarvis plans 7 days:' -FontName 'Segoe UI' -Size 26 `
    -X 620 -Y 220 -Color $plum -Style $fontBold

$y = 280
foreach ($d in $weekDays) {
    Fill-Rounded -G $g -X 620 -Y $y -W 500 -H 52 -R 10 -Color $white
    Stroke-Rounded -G $g -X 620 -Y $y -W 500 -H 52 -R 10 -Color $pinkCard
    Draw-Text -G $g -Text $d[0] -FontName 'Segoe UI' -Size 18 `
        -X 640 -Y ($y + 15) -Color $pink -Style $fontBold
    Draw-Text -G $g -Text "$($d[1])  .  $($d[2])  .  $($d[3])" `
        -FontName 'Segoe UI' -Size 14 -X 690 -Y ($y + 18) -Color $mauve
    $y += 62
}
Save-Canvas -Canvas $c -Name '04-weekly-from-groceries.png'

# =======================================================================
# 05 -- TASKS + HABITS (checklist)
# =======================================================================
Write-Host 'Drawing 05-tasks-habits.png'
$c = New-Canvas -W 1200 -H 600
$g = $c.G

Draw-Text -G $g -Text 'Tasks, habits, reminders' -FontName 'Segoe UI' `
    -Size 42 -X 80 -Y 60 -Color $plum -Style $fontBold
Draw-Text -G $g -Text 'One sentence in. A push notification when it is due.' `
    -FontName 'Segoe UI' -Size 26 -X 80 -Y 130 -Color $mauve

$panelX = 80; $panelY = 210; $panelW = 500; $panelH = 340
Fill-Rounded -G $g -X $panelX -Y $panelY -W $panelW -H $panelH -R 16 -Color $white
Stroke-Rounded -G $g -X $panelX -Y $panelY -W $panelW -H $panelH -R 16 -Color $pinkCard
Draw-Text -G $g -Text 'Today' -FontName 'Segoe UI' -Size 22 `
    -X ($panelX + 25) -Y ($panelY + 20) -Color $plum -Style $fontBold

$tasks = @(
    @('Call plumber', '10:00 AM', $false),
    @('Pay electricity bill', 'done', $true),
    @('Pick up dry cleaning', '4:00 PM', $false),
    @('Water plants', 'weekly - Wed', $false),
    @('Mom''s call', '5:00 PM', $false)
)
$y = $panelY + 65
foreach ($t in $tasks) {
    # Checkbox square
    $boxX = $panelX + 25
    $boxY = $y + 4
    $pen = [System.Drawing.Pen]::new($pink, 2)
    $g.DrawRectangle($pen, $boxX, $boxY, 20, 20)
    if ($t[2]) {
        # Draw a small check inside
        $g.DrawLine($pen, ($boxX + 3), ($boxY + 11), ($boxX + 9), ($boxY + 16))
        $g.DrawLine($pen, ($boxX + 9), ($boxY + 16), ($boxX + 18), ($boxY + 4))
    }
    $pen.Dispose()
    $tColor = if ($t[2]) { $muted } else { $plum }
    Draw-Text -G $g -Text $t[0] -FontName 'Segoe UI' -Size 22 `
        -X ($panelX + 60) -Y $y -Color $tColor
    Draw-Text -G $g -Text $t[1] -FontName 'Segoe UI' -Size 18 `
        -X ($panelX + 370) -Y ($y + 3) -Color $mauve
    $y += 50
}

Draw-Text -G $g -Text 'Just say:' -FontName 'Segoe UI' -Size 28 `
    -X 650 -Y 220 -Color $plum -Style $fontBold
$voiceExamples = @(
    '"Call plumber tomorrow 10am"',
    '"Daily 7am walk for 30 minutes"',
    '"Every Sunday, call mom"',
    '"Remind me to pay school fee on 5th"'
)
$y = 280
foreach ($ve in $voiceExamples) {
    Draw-Text -G $g -Text $ve -FontName 'Segoe UI' -Size 22 `
        -X 650 -Y $y -Color $mauve
    $y += 40
}
Save-Canvas -Canvas $c -Name '05-tasks-habits.png'

# =======================================================================
# 06 -- MORNING NUDGE (notification bubble)
# =======================================================================
Write-Host 'Drawing 06-morning-nudge.png'
$c = New-Canvas -W 1200 -H 600
$g = $c.G

Draw-Text -G $g -Text 'Morning meal-prep nudge' -FontName 'Segoe UI' `
    -Size 42 -X 80 -Y 60 -Color $plum -Style $fontBold
Draw-Text -G $g -Text '8 AM every day. Silent if nothing is planned - stays out of the way.' `
    -FontName 'Segoe UI' -Size 26 -X 80 -Y 130 -Color $mauve

$nx = 200; $ny = 260; $nw = 800; $nh = 160
Fill-Rounded -G $g -X $nx -Y $ny -W $nw -H $nh -R 24 -Color $white
Stroke-Rounded -G $g -X $nx -Y $ny -W $nw -H $nh -R 24 -Color $pinkCard

Fill-Rounded -G $g -X ($nx + 22) -Y ($ny + 22) -W 60 -H 60 -R 14 -Color $pink
Draw-Text -G $g -Text 'J' -FontName 'Georgia' -Size 42 `
    -X ($nx + 52) -Y ($ny + 22) -Color $white -Align 'center'

Draw-Text -G $g -Text 'JARVIS' -FontName 'Segoe UI' -Size 18 `
    -X ($nx + 105) -Y ($ny + 20) -Color $mauve -Style $fontBold
Draw-Text -G $g -Text 'now' -FontName 'Segoe UI' -Size 16 `
    -X ($nx + $nw - 70) -Y ($ny + 23) -Color $muted
Draw-Text -G $g -Text 'Meal prep' -FontName 'Segoe UI' -Size 24 `
    -X ($nx + 105) -Y ($ny + 50) -Color $plum -Style $fontBold
Draw-Text -G $g -Text "Today's plan - Lunch: Dal Rice. Dinner: Paneer Bhurji." `
    -FontName 'Segoe UI' -Size 20 -X ($nx + 105) -Y ($ny + 84) -Color $plum
Draw-Text -G $g -Text 'Shall I prep the ingredient list?' `
    -FontName 'Segoe UI' -Size 20 -X ($nx + 105) -Y ($ny + 112) -Color $plum

Draw-Text -G $g -Text 'Tap to open the day''s meal plan in the app.' `
    -FontName 'Segoe UI' -Size 22 -X 600 -Y 470 -Color $mauve -Align 'center'
Save-Canvas -Canvas $c -Name '06-morning-nudge.png'

# =======================================================================
# 07 -- VOICE + PHOTOS (two cards side-by-side)
# =======================================================================
Write-Host 'Drawing 07-voice-photos.png'
$c = New-Canvas -W 1200 -H 600
$g = $c.G

Draw-Text -G $g -Text 'Voice + photos' -FontName 'Segoe UI' `
    -Size 42 -X 80 -Y 60 -Color $plum -Style $fontBold
Draw-Text -G $g -Text 'Hands dirty from cooking? Just talk. Need to share a recipe page? Snap a photo.' `
    -FontName 'Segoe UI' -Size 24 -X 80 -Y 130 -Color $mauve -MaxWidth 1040

# Voice card
$cx = 150; $cy = 230; $cw = 420; $ch = 320
Fill-Rounded -G $g -X $cx -Y $cy -W $cw -H $ch -R 20 -Color $white
Stroke-Rounded -G $g -X $cx -Y $cy -W $cw -H $ch -R 20 -Color $pinkCard
$micBrush = [System.Drawing.SolidBrush]::new($pink)
$g.FillEllipse($micBrush, ($cx + $cw / 2 - 55), ($cy + 40), 110, 110)
$micBrush.Dispose()
# Mic glyph built from primitives
$whiteBrush = [System.Drawing.SolidBrush]::new($white)
$micCx = $cx + $cw / 2
$g.FillRectangle($whiteBrush, ($micCx - 12), ($cy + 64), 24, 44)
$g.FillEllipse($whiteBrush, ($micCx - 12), ($cy + 54), 24, 24)
$g.FillEllipse($whiteBrush, ($micCx - 12), ($cy + 96), 24, 14)
$wp = [System.Drawing.Pen]::new($white, 3)
$g.DrawLine($wp, $micCx, ($cy + 108), $micCx, ($cy + 126))
$g.DrawLine($wp, ($micCx - 15), ($cy + 126), ($micCx + 15), ($cy + 126))
$wp.Dispose()
$whiteBrush.Dispose()
Draw-Text -G $g -Text 'Voice' -FontName 'Segoe UI' -Size 28 `
    -X ($cx + $cw / 2) -Y ($cy + 170) -Color $plum -Style $fontBold -Align 'center'
Draw-Text -G $g -Text '"I bought tomato, paneer, mushroom. Plan tonight."' `
    -FontName 'Segoe UI' -Size 18 -X ($cx + 20) -Y ($cy + 220) -Color $mauve -MaxWidth ($cw - 40)

# Photo card
$cx2 = 630
Fill-Rounded -G $g -X $cx2 -Y $cy -W $cw -H $ch -R 20 -Color $white
Stroke-Rounded -G $g -X $cx2 -Y $cy -W $cw -H $ch -R 20 -Color $pinkCard
$camBrush = [System.Drawing.SolidBrush]::new($pink)
$g.FillEllipse($camBrush, ($cx2 + $cw / 2 - 55), ($cy + 40), 110, 110)
$camBrush.Dispose()
# Camera glyph: rounded body + lens circle
$whiteBrush = [System.Drawing.SolidBrush]::new($white)
$camCx = $cx2 + $cw / 2
Fill-Rounded -G $g -X ($camCx - 35) -Y ($cy + 70) -W 70 -H 55 -R 8 -Color $white
$g.FillEllipse([System.Drawing.SolidBrush]::new($pink), ($camCx - 16), ($cy + 82), 32, 32)
$g.FillEllipse($whiteBrush, ($camCx - 12), ($cy + 86), 24, 24)
# Flash bump on top
Fill-Rounded -G $g -X ($camCx - 12) -Y ($cy + 60) -W 24 -H 14 -R 3 -Color $white
$whiteBrush.Dispose()
Draw-Text -G $g -Text 'Photos' -FontName 'Segoe UI' -Size 28 `
    -X ($cx2 + $cw / 2) -Y ($cy + 170) -Color $plum -Style $fontBold -Align 'center'
Draw-Text -G $g -Text "Grocery receipts, recipe pages, what's in the fridge, today's cooked dish." `
    -FontName 'Segoe UI' -Size 18 -X ($cx2 + 20) -Y ($cy + 210) -Color $mauve `
    -MaxWidth ($cw - 40)
Save-Canvas -Canvas $c -Name '07-voice-photos.png'

# =======================================================================
# 08 -- QUICK-START CARD (things to try)
# =======================================================================
Write-Host 'Drawing 08-quick-start.png'
$c = New-Canvas -W 1200 -H 800
$g = $c.G

Draw-Text -G $g -Text 'Quick-start: try any of these' -FontName 'Segoe UI' `
    -Size 42 -X 80 -Y 60 -Color $plum -Style $fontBold

$starters = @(
    @('1.', "Plan tomorrow's meals - light dinner, toddler-friendly"),
    @('2.', 'I bought paneer, capsicum, tomato, cauliflower. Plan the week.'),
    @('3.', 'What can I make for lunch? I have dal and rice.'),
    @('4.', 'Remind me to call mom tomorrow at 5pm'),
    @('5.', 'Daily 7am walk for 30 minutes'),
    @('6.', 'Spent 350 on vegetables today'),
    @('7.', 'Plan brunch Sunday - fruit bowl and something light'),
    @('8.', 'Thought: try adding kasuri methi to the next paneer recipe')
)
$y = 170
foreach ($s in $starters) {
    Fill-Rounded -G $g -X 80 -Y $y -W 1040 -H 64 -R 12 -Color $white
    Stroke-Rounded -G $g -X 80 -Y $y -W 1040 -H 64 -R 12 -Color $pinkCard
    Draw-Text -G $g -Text $s[0] -FontName 'Segoe UI' -Size 24 `
        -X 105 -Y ($y + 18) -Color $pink -Style $fontBold
    Draw-Text -G $g -Text ('"' + $s[1] + '"') -FontName 'Segoe UI' -Size 22 `
        -X 155 -Y ($y + 18) -Color $plum
    $y += 76
}
Save-Canvas -Canvas $c -Name '08-quick-start.png'

Write-Host ''
Write-Host 'All graphics generated.' -ForegroundColor Green
Write-Host "Saved to: $outDir"
