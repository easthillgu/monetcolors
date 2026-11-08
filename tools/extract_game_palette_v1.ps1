# ============================================================
# extract_game_palette_v1.ps1 — Gamepics 区域调色板提取 (v1)
# 口径与 extract_palette_v3.ps1 (莫奈画作) 保持一致:
#   缩放取样 -> RGB 步长 16 量化 -> 滤除过暗/过亮 -> 按频次取 Top8
# 差异: 采样宽度 400 (v3 为 100, 更利于 UI 遮罩边界);
#       同区域多图合并统计; 附带 env (全分布加权 HSL) 供采样器使用。
# UI 遮罩: 带完整 UI 的截图按比例矩形排除 UI 区域后再统计。
# 输出: game_palette_v1.json + GamePalette_v1.html (含缩略图与遮罩示意)
#
# 2026-11-07 增加两个开关（为了把"网页渲染 vs 游戏截图"两种来源分开验证）：
#   -IncludeControl  只跑带 control 标记的条目（艾尔文森林 trip 对照组），用于量化来源偏差
#   -OutFile <path>  输出 JSON 路径（默认 data\game_palette_v1.json）
#   -SkipHtml        不写 GamePalette_v1.html（对照组只想要数字，不要报告）
# ============================================================
param(
    [switch]$IncludeControl,
    [string]$OutFile = "",
    [switch]$SkipHtml
)
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)  # repo root (script lives in tools/)
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
# 注意: 闪光平原是千针石林的子区域, 游戏内 GetBestMapForUnit 同返回 1441, 故合并统计。
# source: "game" = 游戏内截图（2026-10 那批）; "trip" = 艾泽拉斯旅拍网页3D 渲染截图
#   （https://wuxianwow.com/trip, MCP trip 工具按区域随机坐标取点、time=day、camera=风景机位）。
#   网页截图**没有 HUD** ⇒ 不进 $maskFiles（遮罩是逐文件 opt-in, 见下方提取循环）。
#   两条来源的 env 口径差异见 data/source_bias.json（对照区 艾尔文森林 各拍一次比出来的）。
#   2026-11-08 新增 trip v2 口径：相机「风景」模式 → 「保存原图」导出 1536x2048 PNG（无 UI/人物/二维码），
#   与 11-07 的 v1（屏幕截图裁剪）构图不同；v2 整体 s 更高、l 更低（均值 0.652/0.248 vs v1 0.42/0.363），
#   属取图口径差，不做比例校正（依据 source_bias.json 的 verdict），靠 data/trip_sources.json 的 format 留账。
$zones = @(
    @{ zone = "贫瘠之地";         mapID = 1413; files = @("贫瘠之地.jpg", "贫瘠之地2.jpg") }
    @{ zone = "灰谷";             mapID = 1440; files = @("灰谷.jpg", "灰谷2.jpg", "灰谷3.jpg", "灰谷4.jpg", "灰谷5.jpg", "灰谷6.jpg", "灰谷7.jpg") }
    @{ zone = "千针石林(含闪光平原)"; mapID = 1441; files = @("千针石林.jpg", "千针石林2.jpg", "千针石林3.jpg", "千针石林4.jpg", "闪光平原.jpg", "闪光平原2.jpg") }
    @{ zone = "菲拉斯";           mapID = 1444; files = @("菲拉斯.jpg", "菲拉斯2.jpg", "菲拉斯3.jpg") }
    @{ zone = "塔纳利斯";         mapID = 1446; files = @("塔纳利斯.jpg", "塔纳利斯2.jpg") }
    @{ zone = "泽风岛";           mapID = 2521; files = @("泽风岛.jpg", "泽风岛2.jpg", "泽风岛3.jpg") }

    # ---- 2026-11-08 补拍 trip：按色源优先级 贴图 > trip > game，把原先 7 个 game 区升级。
    #   取图口径：wuxianwow /trip 相机「风景」模式（第一人称、人物隐藏）、3:4、24mm、t=day，
    #   点「保存原图」导出 1536x2048 PNG（无 UI / 无地名 / 无二维码），转 JPEG 存 Gamepics。
    #   与 11-07 那批 trip（屏幕截图裁掉工具条与中轴人物）构图口径略不同，但同为 3D 渲染源。
    #   坐标与链接见 data/trip_sources.json 的 trip_new 段。
    @{ zone = "阿拉希高地";       mapID = 1417; files = @("阿拉希高地-trip1.jpg");       source = "trip" }
    @{ zone = "提瑞斯法林地";     mapID = 1420; files = @("提瑞斯法林地-trip1.jpg");     source = "trip" }
    @{ zone = "银松森林";         mapID = 1421; files = @("银松森林-trip1.jpg");         source = "trip"; note = "原 60,40 取景点贴地糊绿，改用 50,60（坡 4°）" }
    @{ zone = "希尔斯布莱德丘陵"; mapID = 1424; files = @("希尔斯布莱德丘陵-trip1.jpg"); source = "trip" }
    @{ zone = "艾尔文森林";       mapID = 1429; files = @("艾尔文森林-trip1.jpg");       source = "trip" }
    @{ zone = "西部荒野";         mapID = 1436; files = @("西部荒野-trip1.jpg");         source = "trip" }
    @{ zone = "奥格瑞玛";         mapID = 1454; files = @("奥格瑞玛-trip1.jpg");         source = "trip"; note = "取景点在建筑上的地面，画面以红土地表为主；与旧 game 色同为橙红系" }

    # 幽暗城：trip 站点的取点全部落在「提瑞斯法林地 · 洛丹伦废墟」地表，不是地下城内部，
    # 语义不符 → 有意保留 game 色（本仓 25 区里唯一的 game 特例）。
    @{ zone = "幽暗城";           mapID = 1458; files = @("幽暗城.jpg") }

    # ---- trip 来源（艾泽拉斯旅拍网页 3D 渲染, 2026-11-07 取点）：覆盖 HANDOFF §8.14.2 列的
    #      缺口 —— 四个新手区 / 四个首都 / 三个 1.60 新区。每区一个取景点（坐标与链接见
    #      data/trip_sources.json，可复现）。全部 t=day（与游戏内那批的白昼口径一致）、
    #      无相机参数（相机面板不打开 → 画面无 UI 覆盖），截图再裁掉顶部工具条/任务栏/中轴人物。
    @{ zone = "杜隆塔尔";         mapID = 1411; files = @("杜隆塔尔-trip1.jpg");     source = "trip" }
    @{ zone = "莫高雷";           mapID = 1412; files = @("莫高雷-trip1.jpg");       source = "trip" }
    @{ zone = "丹莫罗";           mapID = 1426; files = @("丹莫罗-trip1.jpg");       source = "trip" }
    @{ zone = "泰达希尔";         mapID = 1438; files = @("泰达希尔-trip1.jpg");     source = "trip" }
    @{ zone = "暴风城";           mapID = 1453; files = @("暴风城-trip1.jpg");       source = "trip"; note = "坐标换过一次：52.1,48.6 的取景点让场景空白，改用 50.6,53.5（贸易区地面）" }
    @{ zone = "铁炉堡";           mapID = 1455; files = @("铁炉堡-trip1.jpg");       source = "trip" }
    @{ zone = "雷霆崖";           mapID = 1456; files = @("雷霆崖-trip1.jpg");       source = "trip" }
    @{ zone = "达纳苏斯";         mapID = 1457; files = @("达纳苏斯-trip1.jpg");     source = "trip" }
    @{ zone = "海加尔山";         mapID = 2482; files = @("海加尔山-trip1.jpg");     source = "trip" }
    @{ zone = "河林";             mapID = 2548; files = @("河林-trip1.jpg");         source = "trip" }
    @{ zone = "辛德拉";           mapID = 2652; files = @("辛德拉-trip1.jpg");       source = "trip"; note = "重雾单调地貌, 量化色仅 33 种属正常（雾+单色坡）" }

    # ---- 对照组：**同一区**的 trip 版本。**默认不进主数据**（-IncludeControl 才跑），
    #      用途 = 量化"网页渲染 vs 游戏截图"两种来源的 env 偏差（结果写 data/source_bias.json）。
    #      选这两个区是因为 S/L 两轴都敏感：艾尔文森林（暖绿、中饱和）、灰谷（浓绿、高饱和）。
    @{ zone = "艾尔文森林(trip对照)"; mapID = 1429; files = @("艾尔文森林-ctrl1.jpg", "艾尔文森林-ctrl2.jpg"); source = "trip"; control = $true }
    @{ zone = "灰谷(trip对照)";     mapID = 1440; files = @("灰谷-ctrl1.jpg");     source = "trip"; control = $true }
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
    # 对照组条目默认排除；带 -IncludeControl 时则只跑对照组（两份结果互不混）
    if ($IncludeControl) { if (-not $z.control) { continue } } else { if ($z.control) { continue } }
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
        source      = $(if ($z.source) { [string]$z.source } else { "game" })
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
if ($OutFile) { $outJson = $OutFile } else { $outJson = Join-Path $root "data\game_palette_v1.json" }
[System.IO.File]::WriteAllText($outJson, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Saved: $outJson"

if (-not $SkipHtml) {
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
$totalFiles = (@($results | ForEach-Object { $_.files })).Count
$tripCount = (@($results | Where-Object { $_.source -eq "trip" })).Count
[void]$sb.AppendLine("<div class=""sub"">源: Gamepics $totalFiles 张截图 · $($results.Count) 区域 · trip 来源 $tripCount · 提取口径: 缩放 400px → RGB 步长 16 量化 → 滤除 L&lt;0.08 / L&gt;0.94 / 近黑 / 近白 → Top8 · <b>env</b> 为全部有效色块的频次加权 (色相取圆周均值)</div>")
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
} # end if (-not $SkipHtml)
