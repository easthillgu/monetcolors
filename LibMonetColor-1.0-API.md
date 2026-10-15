# 📖 LibMonetColor-1.0 API Reference

> **版本**: 1.0.0 (Phase 1 核心算法 + 加固) | **协议**: MIT | **依赖**: `LibStub`, `CallbackHandler-1.0`
> 
> **定位**：WoW 动态环境色彩计算引擎。它不是静态的颜色查找表，而是基于"印象派（莫奈）色彩规则"的实时调色中间件，为 UI 插件提供自适应的"5+3"主题色系统。
> 
> **Phase 1 状态**: 核心算法已实现，**45 个单元测试 + 11 个加固回归测试**全部通过。已完成加固：修正 LibStub 注册、修复 Profile 规则未生效、`GetEdgeColorForMap` 支持按地图采样、R-01 Alpha 自适应公式落地。`sampleEnvironmentColor()` 仍为占位实现，Phase 2（T2.1）将替换为真实地图色彩采样。

---

## 📑 目录
1. [核心概念：5+3 色彩架构](#-核心概念53-色彩架构)
2. [快速接入 (Quick Start)](#-快速接入-quick-start)
3. [消费者 API (Consumer API)](#-消费者-api-consumer-api)
4. [生产者 API (Producer API)](#-生产者-api-producer-api)
5. [事件与回调 (Events & Callbacks)](#-事件与回调-events--callbacks)
6. [数据结构定义 (Data Structures)](#-数据结构定义-data-structures)
7. [契约、安全与降级机制](#️-契约安全与降级机制)
8. [最佳实践与开发自查](#-最佳实践与开发自查)

---

## 🧠 核心概念：5+3 色彩架构

在调用 API 前，需理解本库输出的颜色在 UI 中的语义定位：

*   **5 个功能色**（Primary, Health, Resource, Danger, Neutral）：由 UI 插件自身管理。本库**不干预**其核心机制色（如血条绿、法力蓝），但提供“莫奈化中性灰（Neutral）”的计算。
*   **3 个风格色**（Edge Glow, Ambient Tint, Highlight Wash）：本库的**核心输出**，完全由环境光驱动，赋予 UI 印象派氛围。

---

## 🚀 快速接入 (Quick Start)

作为标准的 LibStub 库，必须使用静默模式获取，防止在库未加载时导致外部插件报错。

```lua
local LMC = LibStub("LibMonetColor-1.0", true)

if LMC then
    -- 获取当前区域的莫奈风格边缘色（已缓存，可安全高频调用）
    local r, g, b, a = LMC:GetCurrentEdgeColor()
    if r then
        MyFrame:SetBackdropBorderColor(r, g, b, a)
    end
else
    -- 优雅降级：如果库不存在，使用插件自身的默认颜色
    MyFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
end
```

---

## 🧩 消费者 API (Consumer API)

所有消费者 API 均为**缓存读取**，在地图未切换时时间复杂度为 O(1)，可安全高频调用。

### GetCurrentEdgeColor

获取当前区域的莫奈风格边缘发光色。

```lua
-- @return r, g, b, a  边缘色 RGBA，值域 [0,1]，alpha 默认 0.8
function LMC:GetCurrentEdgeColor()
```

**示例**：
```lua
local r, g, b, a = LMC:GetCurrentEdgeColor()
MyFrame:SetBackdropBorderColor(r, g, b, a)
```

---

### GetCurrentAmbientTint

获取当前区域的环境氛围色（背景浸染）。

```lua
-- @return r, g, b, a  氛围色 RGBA，值域 [0,1]，alpha 范围 0.15-0.30
function LMC:GetCurrentAmbientTint()
```

**Alpha 自适应公式（R-01 已决策，2026-10-15）**：

```
alpha = alphaMin + (alphaMax - alphaMin) * (1 - envL) * (1 - saturationGuard * envS)
```

- 环境越暗 → alpha 越高（氛围更浓）；环境越饱和 → alpha 越低（避免 UI 二次饱和）。
- 结果钳制在 `[alphaMin, alphaMax]`，默认 `[0.15, 0.30]`。
- 参数可在规则表的 `ambient` 字段覆盖：`{ alphaMin, alphaMax, saturationGuard }`。
- 视觉验收（T2.3）待三地图实测后可能微调参数，公式本身冻结。

**示例**：
```lua
local r, g, b, a = LMC:GetCurrentAmbientTint()
MyFrame:SetBackdropColor(r, g, b, a)
```

---

### GetCurrentHighlightWash

获取当前区域的高光色（顶部渐变叠加）。

```lua
-- @return r, g, b  高光色 RGB，值域 [0,1]
function LMC:GetCurrentHighlightWash()
```

**示例**：
```lua
local r, g, b = LMC:GetCurrentHighlightWash()
MyHighlightTexture:SetVertexColor(r, g, b, 0.3)
```

---

### GetCurrentNeutral

获取当前区域的莫奈化中性灰（用于文本/分割线）。

```lua
-- @return r, g, b  中性色 RGB，值域 [0,1]，饱和度极低 (<0.05)
function LMC:GetCurrentNeutral()
```

**示例**：
```lua
local r, g, b = LMC:GetCurrentNeutral()
MyDividerTexture:SetVertexColor(r, g, b, 0.6)
```

---

### GetAllThemeColors

一次性获取全部 14 个主题色值（最高效，单次缓存查找）。

```lua
-- @return edgeR, edgeG, edgeB, edgeA,    -- 边缘色
--         ambR, ambG, ambB, ambA,        -- 氛围色
--         hlR, hlG, hlB,                  -- 高光色
--         neuR, neuG, neuB                -- 中性色
function LMC:GetAllThemeColors()
```

**示例**：
```lua
local er, eg, eb, ea, ar, ag, ab, aa, hr, hg, hb, nr, ng, nb = LMC:GetAllThemeColors()
```

---

### GetEdgeColorForMap

获取指定地图的边缘色（不改变当前缓存状态）。

```lua
-- @param mapID number  WoW 地图 ID（无效值回退当前地图）
-- @return r, g, b, a  边缘色 RGBA
function LMC:GetEdgeColorForMap(mapID)
```

**行为**：若该地图已有缓存条目则直接读取；否则用环境采样器即时计算该地图的颜色，且**不写入**活动缓存。采样器可接收 `mapID` 参数（见 `SetEnvironmentSampler`）。

---

### Refresh

强制刷新当前地图的颜色缓存。在已知环境变化时（如区域切换）调用。

```lua
function LMC:Refresh()
```

---

### SetDeltaEThreshold

设置事件触发的 Delta E 阈值。

```lua
-- @param threshold number  Delta E 阈值，默认 5.0
function LMC:SetDeltaEThreshold(threshold)
```

---

### SetEnvironmentSampler

设置环境色彩采样器（Phase 2 集成用）。

```lua
-- @param sampler function(mapID)  返回 h, s, l 的函数；mapID 为可选参数
-- @return boolean                  是否设置成功
function LMC:SetEnvironmentSampler(sampler)
```

采样器可忽略 `mapID`（简单实现），也可据此返回不同地图的颜色。设置成功后会**清空缓存并立即刷新**，必要时触发 `OnThemeColorsChanged`。

---

## 🏭 生产者 API (Producer API)

生产者 API 供高级用户注册自定义色彩规则 Profile。

### RegisterProfile

注册自定义色彩规则 Profile。

```lua
-- @param name   string  Profile 名称
-- @param rules  table   规则结构（格式同 DEFAULT_MONET_RULES）
-- @return boolean        是否注册成功
function LMC:RegisterProfile(name, rules)
```

**规则结构**：
```lua
{
    domains = {
        {name="DomainName", range={start1, end1, start2, end2, ...},
         hueShift=180, satMult=0.8, lBias=0.0},
        -- ...
    },
    complementaryPairs = {
        {h=0, complement=170},
        -- ...
    },
    saturationCompensation = {factor=1.05, minSaturation=0.10},
    lightnessMin = 0.18,
    lightnessMax = 0.82,
    achromaticThreshold = 0.06,
    achromaticWarmHue = 300,
    achromaticCoolHue = 210,
    achromaticSat = 0.12,
}
```

---

### SetActiveProfile

激活指定 Profile。

```lua
-- @param name string  Profile 名称（"Monet" 为默认内置）
-- @return boolean     是否激活成功
function LMC:SetActiveProfile(name)
```

---

### GetActiveProfile

获取当前激活的 Profile 名称。

```lua
-- @return string  当前 Profile 名称
function LMC:GetActiveProfile()
```

---

### GetRules

获取当前激活 Profile 的规则表（只读，请勿直接修改）。

```lua
-- @return table  规则表
function LMC:GetRules()
```

自定义 Profile 未提供的字段会自动用内置默认值补全（例如省略 `complementaryPairs` 则继承默认互补色对；显式传 `complementaryPairs = {}` 可关闭）。补全结果会被缓存。

---

### ClearCache

清空颜色缓存。

```lua
function LMC:ClearCache()
```

---

## 🔔 事件与回调 (Events & Callbacks)

### OnThemeColorsChanged

当环境色彩变化超过 Delta E 阈值时触发。

```lua
LMC:RegisterCallback("OnThemeColorsChanged", function(event, entry)
    -- entry = {
    --     mapID = number,
    --     envH = number, envS = number, envL = number,
    --     edge = {r, g, b, a},
    --     ambient = {r, g, b, a},
    --     highlight = {r, g, b},
    --     neutral = {r, g, b},
    -- }
    MyFrame:UpdateTheme(entry)
end)
```

**触发条件**（以下任一，且**边缘色 Delta E > 阈值**时才会真正触发）：

- 区域切换（ZONE_CHANGED / ZONE_CHANGED_INDOORS / ZONE_CHANGED_NEW_AREA / PLAYER_ENTERING_WORLD）
- 手动调用 `LMC:Refresh()` 或 `LMC:SetEnvironmentSampler()` / `LMC:SetActiveProfile()`
- 环境色彩 Delta E > 5.0（默认阈值，可用 `SetDeltaEThreshold` 调整）

> 注意：`Refresh()` 是"强制重算"，但**事件仍受 Delta E 防抖约束**——若重算后颜色变化不足阈值则不发事件，以避免 UI 重绘风暴。

---

## 📐 数据结构定义 (Data Structures)

### ColorEntry

缓存条目结构：

```lua
{
    mapID    = number,       -- WoW 地图 ID
    envH     = number,       -- 环境色相 [0, 360]
    envS     = number,       -- 环境饱和度 [0, 1]
    envL     = number,       -- 环境明度 [0, 1]
    edge     = {r, g, b, a}, -- 边缘发光色
    ambient  = {r, g, b, a}, -- 环境氛围色
    highlight = {r, g, b},   -- 高光色
    neutral  = {r, g, b},    -- 中性灰
}
```

### ProfileRules

自定义规则结构（同 RegisterProfile 参数）。

---

## 🛡️ 契约、安全与降级机制

| 契约 | 保证 |
|------|------|
| **永不抛错** | 所有公开 API 在异常时返回有效 RGB `(0.5, 0.5, 0.5)` |
| **值域保证** | 所有返回值均在 `[0, 1]` 范围内 |
| **事件防抖** | `OnThemeColorsChanged` 仅在 Delta E > 5.0 时触发 |
| **输入宽容** | 无效 Profile 回退 `"Monet"`，无效 MapID 回退当前地图 |
| **版本兼容** | 1.x 生命周期内公开 API 签名、返回值、事件名向后兼容 |
| **警告冷却** | 重复警告间隔 30 秒，避免刷屏 |

---

## ✅ 最佳实践与开发自查

1. **事件驱动** — 优先使用 `OnThemeColorsChanged` 事件更新 UI，避免每帧轮询。
2. **GetAllThemeColors** — 需要多种颜色时，优先调用 `GetAllThemeColors()` 减少缓存查找次数。
3. **优雅降级** — 始终检查 `LibStub` 返回值，库不存在时使用插件默认颜色。
4. **性能红线** — 禁止在 `OnUpdate` 中每帧调用颜色 API。
5. **视觉验收** — 单元测试只能保证"不报错"，不能保证"好看"。务必在典型地图上亲自验证。