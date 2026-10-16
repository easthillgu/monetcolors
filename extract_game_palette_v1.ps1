# ============================================================
# extract_game_palette_v1.ps1 — Gamepics 区域调色板提取 (v1)
# 口径与 extract_palette_v3.ps1 (莫奈画作) 保持一致:
#   缩放取样 -> RGB 步长 16 量化 -> 滤除过暗/过亮 -> 按频次取 Top8
# 差异: 采样宽度 400 (v3 为 100, 更利于 UI 遮罩边界);
#       同区域多图合并统计; 附带 env (全分布加权 HSL) 供采样器使用。
# UI 遮罩: 带完整 UI 的截图按比例矩形排除 UI 区域后再统计。
# 输出: game_palette_v1.json + GamePalette_v1.html (含缩略图与遮罩示意)
# ============================================================
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$picsDir = Join-Path $root "Gamepics"

# ---- UI 遮罩 (x1,y1,x2,y2 均为图片宽高比例, 该区域不参与统计) ----
$uiMask = @(
    ,@(0.10, 0.00, 0.47, 0.44)    # 左上: 玩家/目标/目标的目标框架
    ,@(0.72, 0.00, 1.00, 0.45)    # 右上: 小地图 + 时钟/区域名 + 任务追踪
    ,@(0.00, 0.66, 0.28, 1.00)    # 左下: 聊天框 + 聊天页签
    ,@(0.27, 0.70, 0.71, 1.00)    # 中下: buff 行 + 动作条
    ,@(0.74, 0.85, 1.00, 1.00)    # 右下: 微型菜单/背包/FPS 文字
)
$maskFiles = @("贫瘠之地.jpg", "贫瘠之地2.jpg", "泽风岛2.jpg")

# ---- 区域定义 (mapID 取自 wuxianwow 图鉴, 经典 mapID 空间) ----
$zones = @(
    @{ zone = "贫瘠之地";         mapID = 1413; files = @("贫瘠之地.jpg", "贫瘠之地2.jpg") }
    @{ zone = "阿拉希高地";       mapID = 1417; files = @("阿拉希高地.jpg", "阿拉希高地2.jpg") }
    @{ zone = "银松森林";         mapID = 1421; files = @("银松森林.jpg", "银松森林2.jpg", "银松森林3.jpg") }
    @{ zone = "希尔斯布莱德丘陵"; mapID = 1424; files = @("希尔斯布莱德丘陵.jpg", "希尔斯布莱德丘陵2.jpg") }
    @{ zone = "艾尔文森林";       mapID = 1429; files = @("艾尔文森林.jpg", "艾尔文森林2.jpg") }
    @{ zone = "西部荒野";         mapID = 1436; files = @("西部荒野.jpg", "西部荒野2.jpg", "西部荒野3.jpg") }
    @{ zone = "奥格瑞玛";         mapID = 1454; files = @("奥格瑞玛.jpg") }
    @{ zone = "幽暗城";           mapID = 1458; files = @("幽暗城.jpg") }
    @{ zone = "泽风岛";           mapID = 2521; files = @("泽风岛.jpg", "泽风岛2.jpg", "泽风岛3.jpg") }
)

function Convert-RGBtoHSL($r, $g, $b) {
    $r = $r / 255.0; $g = $g / 255.0; $b = $b / 255.0
    $max = [math]::Max($r, [math]::Max($g, $b))
    $min = [math]::Min($r, [math]::Min($g, $b))
    $l = ($max + $min) / 2.0
    $h = 0.0; $s = 0.0
    if ($max -ne $min) {
        $d = $max - $min
        if ($l -gt 0.5) { $s = $d / (2.0 - $max - $min) }
        else { $s = $d / ($max + $min) }
        switch ($max) {
            $r { $h = ($g - $b) / $d; if ($g -lt $b) { $h += 6.0 } }
            $g { $h = ($b - $r) / $d + 2.0 }
            $b { $h = ($r - $g) / $d + 4.0 }
        }
        $h *= 60.0
    }
    return @{ H = [math]::Round($h, 1); S = [math]::Round($s, 3); L = [math]::Round($l, 3) }
}

# HSL (h:0-360, s/l:0-1) -> "rrggbb"
function Convert-HSLtoHex([double]$h, [double]$s, [double]$l) {
    $c = (1 - [math]::Abs(2 * $l - 1)) * $s
    $hp = $h / 60.0
    $x = $c * (1 - [math]::Abs(($hp % 2) - 1))
    $rp = 0.0; $gp = 0.0; $bp = 0.0
    if ($hp -lt 1) { $rp = $c; $gp = $x }
    elseif ($hp -lt 2) { $rp = $x; $gp = $c }
    elseif ($hp -lt 3) { $gp = $c; $bp = $x }
    elseif ($hp -lt 4) { $gp = $x; $bp = $c }
    elseif ($hp -lt 5) { $rp = $x; $bp = $c }
    else { $rp = $c; $bp = $x }
    $m = $l - $c / 2
    $R = [int][math]::Round(($rp + $m) * 255)
    $G = [int][math]::Round(($gp + $m) * 255)
    $B = [int][math]::Round(($bp + $m) * 255)
    return "{0:x2}{1:x2}{2:x2}" -f $R, $G, $B
}

function Test-InMask([double]$fx, [double]$fy, $mask) {
    if (-not $mask) { return $false }
    foreach ($r in $mask) {
        if ($fx -ge $r[0] -and $fx -le $r[2] -and $fy -ge $r[1] -and $fy -le $r[3]) { return $true }
    }
    return $false
}

# 将一张截图的量化频次并入 $colorMap (可选 UI 遮罩), 返回被遮罩像素数
function Add-ImageToMap($path, [hashtable]$colorMap, $mask) {
    $img = [System.Drawing.Image]::FromFile($path)
    $targetW = 400
    $targetH = [int][math]::Max(1, [math]::Floor($img.Height * ($targetW / [double]$img.Width)))
    $bmp = New-Object System.Drawing.Bitmap($targetW, $targetH)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $targetW, $targetH)
    $img.Dispose()
    $g.Dispose()

    $step = 16
    $maskedOut = 0
    for ($y = 0; $y -lt $targetH; $y++) {
        for ($x = 0; $x -lt $targetW; $x++) {
            if ($mask) {
                $fx = ($x + 0.5) / $targetW
                $fy = ($y + 0.5) / $targetH
                if (Test-InMask $fx $fy $mask) { $maskedOut++; continue }
            }
            $pixel = $bmp.GetPixel($x, $y)
            $qr = [math]::Floor($pixel.R / $step) * $step
            $qg = [math]::Floor($pixel.G / $step) * $step
            $qb = [math]::Floor($pixel.B / $step) * $step
            $key = "${qr}|${qg}|${qb}"
            if ($colorMap.ContainsKey($key)) { $colorMap[$key]++ }
            else { $colorMap[$key] = 1 }
        }
    }
    $bmp.Dispose()
    return $maskedOut
}

function Get-TopColors([hashtable]$colorMap, [int]$topN) {
    $entries = @()
    $totalValid = 0
    foreach ($key in $colorMap.Keys) {
        $parts = $key -split '\|'
        $r = [int]$parts[0]; $g = [int]$parts[1]; $b = [int]$parts[2]
        $maxC = [math]::Max($r, [math]::Max($g, $b))
        $minC = [math]::Min($r, [math]::Min($g, $b))
        $hsl = Convert-RGBtoHSL $r $g $b
        if ($hsl.L -lt 0.08 -or $hsl.L -gt 0.94) { continue }
        if ($maxC -lt 15) { continue }
        if ($maxC -gt 245 -and $minC -gt 235) { continue }
        $freq = $colorMap[$key]
        $entries += [PSCustomObject]@{ R = $r; G = $g; B = $b; H = $hsl.H; S = $hsl.S; L = $hsl.L; Freq = $freq }
        $totalValid += $freq
    }

    # env: 全部有效色块的频次加权 (色相用圆周加权均值)
    $env = $null
    if ($totalValid -gt 0) {
        $sumSin = 0.0; $sumCos = 0.0; $sumS = 0.0; $sumL = 0.0; $sumW = 0.0
        foreach ($e in $entries) {
            $rad = $e.H * [math]::PI / 180.0
            $sumCos += $e.Freq * [math]::Cos($rad)
            $sumSin += $e.Freq * [math]::Sin($rad)
            $sumS += $e.Freq * $e.S
            $sumL += $e.Freq * $e.L
            $sumW += $e.Freq
        }
        $envH = [math]::Atan2($sumSin, $sumCos) * 180.0 / [math]::PI
        if ($envH -lt 0) { $envH += 360.0 }
        $env = @{
            h = [math]::Round($envH, 1)
            s = [math]::Round($sumS / $sumW, 3)
            l = [math]::Round($sumL / $sumW, 3)
        }
    }

    $top = @($entries | Sort-Object Freq -Descending | Select-Object -First $topN)
    $palette = @()
    foreach ($e in $top) {
        $palette += @{
            r = $e.R; g = $e.G; b = $e.B; h = $e.H; s = $e.S; l = $e.L
            pct = [math]::Round($e.Freq / [double]$totalValid * 100, 2)
        }
    }
    return @{ palette = $palette; validPixels = $totalValid; distinct = $entries.Count; env = $env }
}

# ---------- 提取 ----------
$results = @()
foreach ($z in $zones) {
    $colorMap = @{}
    $maskedFiles = @()
    $totalMasked = 0
    foreach ($f in $z.files) {
        $path = Join-Path $picsDir $f
        if (-not (Test-Path $path)) { throw "Missing image: $path" }
        $m = $null
        if ($maskFiles -contains $f) { $m = $uiMask; $maskedFiles += $f }
        Write-Host "Processing [$($z.zone)]: $f$(if ($m) { ' (UI masked)' })"
        $n = Add-ImageToMap $path $colorMap $m
        if ($m) { $totalMasked += $n }
    }
    $r = Get-TopColors $colorMap 8
    $results += @{
        zone        = $z.zone
        mapID       = $z.mapID
        files       = @($z.files)
        uiMasked    = @($maskedFiles)
        maskedPx    = $totalMasked
        validPixels = $r.validPixels
        distinct    = $r.distinct
        palette     = $r.palette
        env         = $r.env
    }
}

$json = $results | ConvertTo-Json -Depth 6
$outJson = Join-Path $root "game_palette_v1.json"
[System.IO.File]::WriteAllText($outJson, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Saved: $outJson"

# ---------- HTML 色卡报告 ----------
function Get-JpegBase64([System.Drawing.Bitmap]$bmp, [long]$quality) {
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, $quality)
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, $codec, $ep)
    $bytes = $ms.ToArray(); $ms.Dispose(); $bmp.Dispose()
    return [Convert]::ToBase64String($bytes)
}

function Get-Thumb($path, $mask) {
    $img = [System.Drawing.Image]::FromFile($path)
    $w = 640
    $h = [int][math]::Max(1, [math]::Floor($img.Height * ($w / [double]$img.Width)))
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $w, $h)
    $img.Dispose(); $g.Dispose()
    if ($mask) {
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, 2)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 255, 0, 0))
        $g2 = [System.Drawing.Graphics]::FromImage($bmp)
        foreach ($r in $mask) {
            $rx = [int]($r[0] * $w); $ry = [int]($r[1] * $h)
            $rw = [int](($r[2] - $r[0]) * $w); $rh = [int](($r[3] - $r[1]) * $h)
            $g2.FillRectangle($brush, $rx, $ry, $rw, $rh)
            $g2.DrawRectangle($pen, $rx, $ry, $rw, $rh)
        }
        $g2.Dispose(); $pen.Dispose(); $brush.Dispose()
    }
    return Get-JpegBase64 $bmp 72
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">')
[void]$sb.AppendLine('<title>WoW 区域调色板 v1 — Gamepics 取色报告</title>')
[void]$sb.AppendLine(@'
<style>
body{background:#14161a;color:#d8dade;font-family:"Segoe UI",system-ui,sans-serif;margin:0;padding:32px;}
h1{font-size:22px;margin:0 0 6px} .sub{color:#8b9099;font-size:13px;margin-bottom:26px;line-height:1.7}
.zone{background:#1c1f25;border:1px solid #2a2e36;border-radius:10px;padding:20px 22px;margin-bottom:26px}
.zhead{display:flex;align-items:baseline;gap:14px;flex-wrap:wrap}
.zname{font-size:19px;font-weight:600} .mid{color:#9aa0aa;font-size:13px}
.envbox{display:flex;gap:16px;align-items:center;margin:14px 0 6px;background:#15171c;border:1px solid #2a2e36;border-radius:8px;padding:12px 14px;width:max-content}
.envsw{width:64px;height:64px;border-radius:8px;border:1px solid #3a3f48}
.envtxt{font-size:13px;line-height:1.7} .envtxt b{color:#fff}
.swrow{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
.sw{width:132px;background:#15171c;border:1px solid #2a2e36;border-radius:8px;overflow:hidden}
.sw .c{height:64px} .sw .m{padding:7px 9px;font-size:11.5px;line-height:1.55;color:#aeb3bc}
.sw .m b{color:#eceef1;font-weight:600}
.bar{height:5px;background:#262a31;border-radius:3px;overflow:hidden;margin-top:4px}
.bar i{display:block;height:100%;background:#5b9bd5}
.thumbs{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}
.thumbs img{width:320px;border-radius:6px;border:1px solid #2a2e36}
.note{color:#8b9099;font-size:12px;margin-top:12px;line-height:1.7}
.masktag{display:inline-block;background:#5a2830;color:#f0a8b0;font-size:11px;border-radius:4px;padding:2px 7px}
.legend{font-size:12.5px;color:#8b9099;margin-bottom:20px;line-height:1.8}
code{background:#22262d;padding:1px 5px;border-radius:4px;font-size:12px}
</style></head><body>
'@)
[void]$sb.AppendLine('<h1>WoW 区域调色板 v1</h1>')
[void]$sb.AppendLine('<div class="sub">源: Gamepics 19 张截图 · 9 区域 · 提取口径: 缩放 400px → RGB 步长 16 量化 → 滤除 L&lt;0.08 / L&gt;0.94 / 近黑 / 近白 → Top8 · <b>env</b> 为全部有效色块的频次加权 (色相取圆周均值)</div>')
[void]$sb.AppendLine('<div class="legend">用途: <code>SetEnvironmentSampler(fn)</code> 的区域 Palette 数据源 (Phase 2 / T2.1)。同区域多图按像素频次合并; 带 UI 的截图以比例矩形遮罩排除界面 (缩略图中<span style="color:#e08090">红色半透明区域</span>不参与统计)。</div>')

foreach ($r in $results) {
    [void]$sb.Append('<div class="zone"><div class="zhead">')
    [void]$sb.Append("<span class=""zname"">$($r.zone)</span>")
    [void]$sb.Append("<span class=""mid"">mapID $($r.mapID) · $($r.files.Count) 图 · 有效像素 $($r.validPixels) · 有效色块 $($r.distinct)</span>")
    if ($r.uiMasked.Count -gt 0) {
        [void]$sb.Append("<span class=""masktag"">UI 遮罩: $($r.uiMasked -join '、') (排除 $($r.maskedPx) px)</span>")
    }
    [void]$sb.AppendLine('</div>')

    # env 卡
    $envHex = Convert-HSLtoHex $r.env.h $r.env.s $r.env.l
    [void]$sb.AppendLine("<div class=""envbox""><div class=""envsw"" style=""background:#$envHex""></div>")
    [void]$sb.AppendLine("<div class=""envtxt"">环境代表色 <b>#$envHex</b><br>H <b>$($r.env.h)°</b> · S <b>$($r.env.s)</b> · L <b>$($r.env.l)</b> <span style=""color:#8b9099"">(sampler 直接输入)</span></div></div>")

    # Top8 色卡
    [void]$sb.AppendLine('<div class="swrow">')
    foreach ($p in $r.palette) {
        $hex = "{0:x2}{1:x2}{2:x2}" -f [int]$p.r, [int]$p.g, [int]$p.b
        $pctW = [math]::Min(100, [double]$p.pct * 4)
        [void]$sb.AppendLine("<div class=""sw""><div class=""c"" style=""background:#$hex""></div>")
        [void]$sb.AppendLine("<div class=""m""><b>#$hex</b><br>H $($p.h)° S $($p.s) L $($p.l)<br>")
        [void]$sb.AppendLine("<span style=""color:#7ea8d8"">$($p.pct)%</span><div class=""bar""><i style=""width:$pctW%""></i></div></div></div>")
    }
    [void]$sb.AppendLine('</div>')

    # 缩略图 (带遮罩示意)
    [void]$sb.AppendLine('<div class="thumbs">')
    foreach ($f in $r.files) {
        $m = $null
        if ($maskFiles -contains $f) { $m = $uiMask }
        $b64 = Get-Thumb (Join-Path $picsDir $f) $m
        [void]$sb.AppendLine("<img src=""data:image/jpeg;base64,$b64"" alt=""$f"">")
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')
}

[void]$sb.AppendLine('</body></html>')
$outHtml = Join-Path $root "GamePalette_v1.html"
[System.IO.File]::WriteAllText($outHtml, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "Saved: $outHtml"
Write-Host ""
Write-Host "=== Done! ==="
