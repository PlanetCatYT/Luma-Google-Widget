# Luma gif converter: turns gifs into the sprite sheets the Sky Animation slots use.
# Drag one or more .gif files onto luma_gif.bat. Each one becomes a folder inside "Luma_sky" next to this file.
#
# Part of Luma-Google-Widget: https://github.com/PlanetCatYT/Luma-Google-Widget
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)

Add-Type -AssemblyName System.Drawing

if (-not $Files -or $Files.Count -eq 0) {
    Write-Host "Drag one or more .gif files onto luma_gif.bat"
    exit 0
}

$outRoot = Join-Path $PSScriptRoot "Luma_sky"
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$maxSheet = 1024

foreach ($file in $Files) {
    try {
        if (-not (Test-Path -LiteralPath $file)) { Write-Host "Not found: $file"; continue }
        $name = [IO.Path]::GetFileNameWithoutExtension($file)
        $img = [System.Drawing.Image]::FromFile($file)
        $dimension = New-Object System.Drawing.Imaging.FrameDimension($img.FrameDimensionsList[0])
        $count = $img.GetFrameCount($dimension)

        $totalCentis = 0
        try {
            $delays = $img.GetPropertyItem(0x5100).Value
            for ($i = 0; $i -lt $count; $i++) { $totalCentis += [BitConverter]::ToInt32($delays, $i * 4) }
        } catch { $totalCentis = $count * 10 }
        if ($totalCentis -le 0) { $totalCentis = $count * 10 }
        $fps = [math]::Max(1, [math]::Round($count / ($totalCentis / 100.0)))

        # biggest grid that keeps the whole sheet inside 1024 x 1024
        $best = $null
        for ($cols = 1; $cols -le $count; $cols++) {
            $rows = [math]::Ceiling($count / $cols)
            $cell = [math]::Floor([math]::Min($maxSheet / $cols, $maxSheet / $rows))
            $scale = [math]::Min(1.0, $cell / [math]::Max($img.Width, $img.Height))
            $cw = [math]::Max(1, [math]::Floor($img.Width * $scale))
            $ch = [math]::Max(1, [math]::Floor($img.Height * $scale))
            $area = $cw * $ch
            if ($null -eq $best -or $area -gt $best.Area) { $best = @{ Cols = $cols; Rows = $rows; W = $cw; H = $ch; Area = $area } }
        }

        $sheet = New-Object System.Drawing.Bitmap ($best.Cols * $best.W), ($best.Rows * $best.H), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($sheet)
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        for ($i = 0; $i -lt $count; $i++) {
            [void]$img.SelectActiveFrame($dimension, $i)
            $x = ($i % $best.Cols) * $best.W
            $y = [math]::Floor($i / $best.Cols) * $best.H
            $g.DrawImage($img, $x, $y, $best.W, $best.H)
        }
        $g.Dispose()

        $dir = Join-Path $outRoot $name
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $sheet.Save((Join-Path $dir "anim.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $sheet.Dispose()
        $img.Dispose()
        [IO.File]::WriteAllText((Join-Path $dir "anim.txt"), "$($best.Cols) $($best.Rows) $count $fps $($best.W) $($best.H)")
        Write-Host "Done: $name  ($count frames, $fps fps)  ->  $dir"
    } catch {
        Write-Host "Failed on $file : $($_.Exception.Message)"
    }
}
Write-Host ""
Write-Host "Now copy the folders inside Luma_sky into your executor's workspace\Luma_sky folder."
