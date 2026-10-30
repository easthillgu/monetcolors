# 📖 LibMonetColor-1.0 API Reference

> **版本**: 1.2.0 (Phase 1 核心算法 + 加固 + Phase 2 T2.1 地图采样 + 状态染色层 `LibMonetColor-Anim-1.0` + 色彩工具函数) | **协议**: MIT | **依赖**: `LibStub`（随包内嵌于 `Libs/LibStub/`，或由接入方提供） | **可选**: `CallbackHandler-1.0`（缺失时使用库内置回调注册表） | **可选数据**: `MonetColorMapData-1.0`
> 
> **定位**：WoW 动态环境色彩计算引擎。它不是静态的颜色查找表，而是基于"印象派（莫奈）色彩规则"的实时调色中间件，为 UI 插件提供自适应的"5+3"主题色系统。
> 
> **当前状态**: 核心算法已实现并加固，**45 个核心 + 14 个加固回归 + 16 个 T2.1 采样 + 4 个 LibStub 加载顺序 + 33 个状态染色 + 19 个运行时 + 24 个色彩工具函数（共 155）**全部通过。Phase 2（T2.1）已完成：`sampleEnvironmentColor()` 默认实现为基于 `MonetColorMapData-1.0` 区域数据的查表采样器（14 区域，源自游戏截图取色管线），未知地图回退中性无彩 env 并走无彩域注入路径。1.1.0 新增独立的**状态染色层** `LibMonetColor-Anim-1.0`：把玩家的战斗 / 休息 / 血量 / PvP / 载具状态翻译成颜色修饰，并用**一个共享 ticker** 驱动所有闪烁。1.2.0 新增**色彩工具函数** `ContrastRatio` / `AtLightness`：纯函数，把"量得准"这一层交给库，把"要几级阶梯"留给接入方（接入案例见 MonetUI 的 `Utils/Color.lua` 表面分层）。

---

## 📑 目录
1. [核心概念：5+3 色彩架构](#-核心概念53-色彩架构)
2. [快速接入 (Quick Start)](#-快速接入-quick-start)
3. [消费者 API (Consumer API)](#-消费者-api-consumer-api)
4. [环境取色数据与 API (Map Env API, T2.1)](#-环境取色数据与-api-map-env-api-t21)
5. [状态染色层 API (Anim API, 1.1.0)](#-状态染色层-api-anim-api-110)
6. [色彩工具函数 (Color Tools, 1.2.0)](#-色彩工具函数-color-tools-120)
7. [生产者 API (Producer API)](#-生产者-api-producer-api)
8. [事件与回调 (Events & Callbacks)](#-事件与回调-events--callbacks)
9. [数据结构定义 (Data Structures)](#-数据结构定义-data-structures)
10. [契约、安全与降级机制](#️-契约安全与降级机制)
11. [最佳实践与开发自查](#-最佳实践与开发自查)

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

**行为**：若该地图已有缓存条目则直接读取；否则用环境采样器即时计算该地图的颜色，且**不写入**活动缓存。默认采样器按 `mapID` 查 `MonetColorMapData-1.0` 区域数据（见 [Map Env API](#-环境取色数据与-api-map-env-api-t21)）。

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

设置环境色彩采样器。**默认采样器已内置**（T2.1）：基于 `MonetColorMapData-1.0` 区域数据按 `mapID` 查表；本 API 仅供接入方完全替换采样逻辑时使用。

```lua
-- @param sampler function(mapID)  返回 h, s, l 的函数；mapID 为可选参数
-- @return boolean                  是否设置成功
function LMC:SetEnvironmentSampler(sampler)
```

采样器可忽略 `mapID`（简单实现），也可据此返回不同地图的颜色。设置成功后会**清空缓存并立即刷新**，必要时触发 `OnThemeColorsChanged`。

若只想**扩展个别地图**的数据，不要用本 API 重写整个采样器，请使用 `RegisterMapEnv`。

---

## 🗺️ 环境取色数据与 API (Map Env API, T2.1)

默认采样器的数据来源是可选数据模块 **`MonetColorMapData-1.0`**：

```lua
-- 数据模块结构（自动生成，勿手改）
MDM.MapEnv = {
    [1413] = { name = "贫瘠之地", h = 47.0, s = 0.298, l = 0.395 },
    -- ...
}
```

*   **数据源**：`data/game_palette_v1.json` ← `tools/extract_game_palette_v1.ps1`（游戏截图取色管线）← `tools/gen_map_env.ps1`（生成本模块）。新增区域时重跑两条管线即可。
*   **加载顺序无关**：库通过 `LibStub("MonetColorMapData-1.0", true)` 或全局别名 `LibMonetColorMapData` **惰性查找**，数据模块先于/后于库加载均可。
*   **数据缺失安全**：数据模块不存在时库照常工作，所有未收录地图解析为 fallback env。

### 解析顺序

`GetMapEnv(mapID)` 按以下优先级解析，全程不抛错：

1.  **运行时覆盖**（`RegisterMapEnv` 注册的条目）
2.  **数据精确命中**（`MapEnv[mapID]`）
3.  **父地图链**（游戏内经 `C_Map.GetMapInfo` 向上查找最多 5 级，子区域/副本地图继承父区域环境色；返回 `source = "parent:..."`)
4.  **Fallback env**（默认 `{h=0, s=0, l=0.5}` 中性无彩 → 触发无彩域注入，输出安静的冷蓝 Edge Glow）

### GetMapEnv

解析指定地图的环境色 (h, s, l)。

```lua
-- @param mapID  number|nil  地图 ID（字符串会被容错转换；nil/0 → fallback）
-- @return h, s, l, name|nil, source
--         source: "override" | "data" | "parent:override" | "parent:data" | "fallback"
function LMC:GetMapEnv(mapID)
```

调试建议：配合 `/lmctest` 打印 `select(5, LMC:GetMapEnv(mapID))` 可立刻看出当前地图走的哪条解析路径。

### RegisterMapEnv

运行时注册/覆盖单个地图的环境色。优先级高于数据模块，供接入方**逐区域扩展覆盖**（无需 fork 数据模块）。

```lua
-- @param mapID  number      > 0
-- @param h      number      [0, 360]（自动 wrap）
-- @param s      number      [0, 1]（自动 clamp）
-- @param l      number      [0, 1]（自动 clamp）
-- @param name   string|nil  区域名（调试输出用）
-- @return boolean           是否注册成功（非法参数返回 false 并打印冷却警告）
function LMC:RegisterMapEnv(mapID, h, s, l, name)
```

注册后**清空缓存并立即刷新**。

### SetFallbackEnv

设置未收录地图的回退环境色。

```lua
-- @param h, s, l numbers   语义同上
-- @return boolean          是否设置成功
function LMC:SetFallbackEnv(h, s, l)
```

默认 `{h=0, s=0, l=0.5}`（中性无彩，走无彩域注入）。设置后**清空缓存并立即刷新**。

---

## 🎨 状态染色层 API (Anim API, 1.1.0)

`LibMonetColor-Anim-1.0` 是**独立文件、独立版本**的伴随库（`LibMonetColor-Anim-1.0.lua`）。它把**玩家状态**（战斗 / 休息 / 血量 / PvP / 载具 / 死亡）翻译成颜色修饰，并用**一个共享 ticker** 驱动所有闪烁动画。

> **为什么要分文件**：色彩引擎是纯函数 + 缓存，状态层带事件帧、ticker 和状态采样。分开后，色彩库可以在没有状态需求的项目里单独使用（零事件、零 ticker），动画层的 bug 也污染不到取色逻辑。

### 快速接入

```lua
local LMC  = LibStub("LibMonetColor-1.0", true)
local Anim = LMC and LMC.Anim   -- 或 LibStub("LibMonetColor-Anim-1.0", true)
```

`Anim` 挂载在核心库上（`LMC.Anim`），只拿一个句柄即可；也可以直接 `LibStub("LibMonetColor-Anim-1.0", true)` 取用。**加载顺序**：核心库必须在 Anim 之前加载（`.toc` 已保证）。

### 订阅式接入（推荐）

```lua
-- @param apply function(r, g, b, a, state, base)  收到最终颜色
-- @param opts   table
--   base      = "edge"（默认）| "ambient" | "highlight" | "neutral"
--   pulse     = true|false   是否参与闪烁（默认 false：背景/装饰线不需要）
--   modifiers = { combat=true, ooc=true, rest=true, lowHealth=true,
--                 pvp=true, vehicle=true, dead=true }   逐项开关
local handle = Anim:RegisterColorSink(function(r, g, b, a, state)
    MyFrame:SetBackdropBorderColor(r, g, b, a)
end, { base = "edge", pulse = true })
```

接入方**不需要**订阅任何游戏事件、不需要算血量百分比、不需要写 `OnUpdate`：

| 目标 | 推荐参数 |
| :--- | :--- |
| 单位框架边框 | `base="edge", pulse=true` |
| 动作条背景 | `base="ambient", pulse=false, modifiers={ lowHealth=false }` |
| 装饰线 / 分割线 | `base="neutral", pulse=false` |
| 顶部高光渐变 | `base="highlight", pulse=false` |

Handle 生命周期：

```lua
handle:Refresh()          -- 强制重采样并重绘
handle:SetEnabled(false)  -- 暂停（例如被悬停/仇恨高亮覆盖时）
handle:GetState()         -- 最近一次采样到的状态表
handle:GetColor()         -- 当前颜色（含此刻的脉搏）
handle:Unregister()       -- 注销
```

### 拉取式接入

```lua
local r, g, b, a = Anim:GetColor("edge")            -- 含此刻脉搏
local r, g, b, a = Anim:GetColor("edge", now)       -- 指定时刻（确定性，便于自绘动画/测试）
local r, g, b, a = Anim:GetColor("ambient", nil, { lowHealth = false })  -- 单次调用覆盖修饰开关
local r, g, b, a = Anim:GetColor({ r = .2, g = .2, b = .2, a = .9 })      -- 任意自定义基色
```

### GetPlayerState

```lua
-- @return state table（只读）
function Anim:GetPlayerState()
```

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `inCombat` | boolean | 玩家是否在战斗中 |
| `resting` | boolean | 是否在休息状态 |
| `healthPct` | number | 血量百分比 `[0,1]`（保密时为 1） |
| `healthKnown` | boolean | 血量是否可读（保密时为 false） |
| `tier` | string | `"healthy"` / `"low"` / `"critical"` / `"unknown"` |
| `lowHealth` | boolean | 是否低于阈值 |
| `dead` / `ghost` | boolean | 死亡 / 幽灵 |
| `pvp` / `ffaPvp` | boolean | PvP 标记 / 自由PvP |
| `vehicle` | boolean | 是否在载具中 |
| `afk` / `charmed` | boolean | 暂离 / 魅惑 |
| `combatStart` | number | 进入战斗的时刻（脉搏锚点） |
| `updatedAt` | number | 最近一次采样时刻 |

> 状态**只来自玩家**。目标、队伍、敌方的血量与状态一律不判定——这是本层的边界，也是它能保持轻量的原因。

### SetStyle / GetStyle / ResetStyle

```lua
Anim:SetStyle({
    combat = {
        enabled = true,
        lightnessBoost = 0.08,    -- 战斗时明度提升
        saturationBoost = 0.10,   -- 战斗时饱和度提升
        alphaScale = 1.10,        -- 战斗时 alpha 倍率
        enterFlash = true,        -- 进入战斗时闪烁
        flashDuration = 0.7,      -- 闪烁时长（秒）
        flashWavePeriod = 0.2,    -- 闪烁波形周期
        flashAmplitude = 0.28,    -- 闪烁振幅
        pulse = true,             -- 战斗中持续脉搏
        pulseAmplitude = 0.10,
        pulsePeriod = 1.6,
    },
    ooc = { enabled = true, lightnessScale = 0.88, alphaScale = 0.85 },
    lowHealth = {
        enabled = true,
        threshold = 0.35,         -- 低血阈值
        critical = 0.20,          -- 危急阈值
        color = { h = 0, s = 0.85, l = 0.52 },  -- 也接受 { r, g, b }
        blend = 0.55,             -- 阈值处的红色混合比例
        blendCritical = 1.0,      -- 危急处（纯正红）
        alphaBoost = 0.15,
        pulse = true, pulseAmplitude = 0.22,
        pulsePeriod = 0.75, criticalPeriod = 0.45,
    },
    rest    = { enabled = true, color = { h = 210, s = 0.45, l = 0.55 }, blend = 0.30, alphaScale = 0.95 },
    pvp     = { enabled = true, color = { h = 0, s = 0.70, l = 0.52 }, blend = 0.20 },
    vehicle = { enabled = true, color = { h = 42, s = 0.60, l = 0.55 }, blend = 0.20 },
    dead    = { enabled = true, lightness = 0.35, alpha = 0.30 },
    pulse   = { fps = 15 },
})
Anim:GetStyle()    -- 当前样式表（只读）
Anim:ResetStyle()  -- 恢复内置默认值
```

* `SetStyle` 做**深合并**，未提及的字段保持不变；数值越界自动钳制；颜色可写 HSL 或 RGB。
* 样式**不写 SavedVariables**——库不持有玩家配置，由接入方持久化后调用 `SetStyle` 还原。
* `SetStyle` 会立即重绘所有 sink。

### 修饰优先级

从底到顶依次叠加：

1. **基色**：`edge` / `ambient` / `highlight` / `neutral` / 自定义 `{r,g,b,a}`
2. **休息**（仅脱战时）：向休息色混合
3. **PvP** → **载具**：各自的色相混合
4. **战斗增亮**（战斗中）或 **脱战降亮**
5. **低血量**：向危险红做 **RGB 直混**（阈值 55% → 危急 100%），这是唯一接管色相的修饰——**不做莫奈互补**，可读性优先
6. **alpha 修饰**：战斗 ×1.10 / 脱战 ×0.85 / 低血 +0~0.15
7. **脉搏**：见下

**死亡短路**：灰度 + 明度 0.35 + alpha 0.30，停止一切脉搏与染色。

### 动画（省电设计）

* 波形用**预计算的 64 点余弦表**（LUT），tick 内**不做三角函数**。
* 用 `0.5-0.5*cos` 相位（而非 `0.5+0.5*sin`）：进入战斗时从基色平滑起振，**不会先跳一下**。
* 战斗波形与低血波形**每 tick 只算一次**，所有 sink 共用。
* 状态变化时算好静态 RGB，tick **只改 alpha**。
* alpha 变化小于 `1/128` 不触发重绘。
* 默认 15 fps（`pulse.fps`，可配 1–60），无活跃脉搏时 ticker 立刻 `Hide()`。
* 一个库**只有一个 ticker**，无论多少消费者。

### 事件

```lua
Anim:RegisterCallback("OnCombatStateChanged", function(_, inCombat) end)
Anim:RegisterCallback("OnPlayerStateChanged",   function(_, state) end)
Anim:RegisterCallback("OnStateColorChanged",    function(_, base, r, g, b, a, state) end)
```

* 事件只在**状态切换**时触发，不随脉搏刷屏。
* 只要注册了回调或 sink，库就会订阅游戏事件；两者都没有时**完全反注册**，空闲零开销。
* `OnStateColorChanged` 对每个 sink 触发一次（`base` 为该 sink 的基色槽）。

### 保密值（Secret values）

在受限制状态（战斗 / PvP / boss 战）下，客户端可能把血量交成 **secret** 值，任何比较或算术都会抛错。本层的处理：

* 所有单位 API 一律 `pcall` 包裹；
* 优先用 `C_Secrets.HasSecretRestrictions()` + `C_Secrets.ShouldUnitHealthMaxBeSecret("player")` 判定；**判定不了就按 secret 处理**（宁可少一个效果，也不冒错）；
* 血量读不到时 `healthKnown=false`、**低血效果关闭**，战斗 / 休息等其他效果照常。

---

## 🔬 色彩工具函数 (Color Tools, 1.2.0)

**纯函数**，不读缓存、不发事件、不碰 profile —— 它们只吃数值、吐数值，随时可以在测试里直接调用。

放这一层的理由：本库是仓库里唯一有 Lab / L\* 数学的地方，而"**条内对比度**"（血条填充 / 掉血空槽 /
面板底要拉得开）是决策日志 **R-04** 明确**不内置**的东西——策略归消费方（插件自己决定要几级阶梯、
差多少 L\*），这里只提供算得准的原语。**功能色仍然不 Monet 化。**

### ContrastRatio

两个颜色的 WCAG 2.x 对比度。

```lua
-- @param r1, g1, b1  number [0,1]  颜色 A
-- @param r2, g2, b2  number [0,1]  颜色 B
-- @return ratio       number >= 1   1.0 = 完全等亮（看不出差别），21.0 = 纯黑对纯白
function LMC.ContrastRatio(r1, g1, b1, r2, g2, b2)
```

* 相对亮度用 sRGB gamma 解码后的 Y 分量（D65），与 `RGBToLab` 同一套解码，**两者口径一致**。
* **不分前景/背景**，返回 `max/min` 那一种，所以 `ContrastRatio(a, b) == ContrastRatio(b, a)`。
* 判定线（仅作参考，用途由消费方定）：1.0 看不出、≈1.5 勉强、≥3.0 才算"一眼分得开"、正文文字要 ≥4.5。
* 输入非法（非数值 / secret 值 / 运算抛错）时返回 **1**，而不是 21 —— 让调用方得出"分不开"的保守结论，
  宁可少画一行，也不要在受限环境里把等亮的颜色当成拉开了。

### AtLightness

把颜色**按 CIE L\* 重定位**：保住色相与饱和度，只挪亮度。

```lua
-- @param r, g, b     number [0,1]   源色
-- @param targetL     number [0,100] 目标 L*（自动钳制）
-- @return r, g, b    number [0,1]
function LMC.AtLightness(r, g, b, targetL)
```

* 实现是在 HSL 的 `l` 轴上**二分**（`L*` 对 `l` 单调），命中容差 0.25 或跑满 24 次即停，返回**实际最接近**的那一个。
* **达不到目标就返回能达到的最接近值**，不抛错也不静默改色相：高饱和色本来就够不到 L\*=95，
  调用方要"准"就用 `RGBToLab(结果)` 回读一次自己判。
* 三个分量里**任何一个读不出来**（缺字段 / 非数值 / NaN / secret 值一碰就抛）→ 按契约返回中性灰
  `(0.5, 0.5, 0.5)` 并走 30 秒冷却警告；`targetL` 读不出来则**原色返回**（保持上一次的好值）。
* 用它的典型形状：面板底定在一个 L\*，空槽 = 面板 L\* + Δ，填充 = 空槽 L\* + Δ ——
  于是"亮区域主题变亮"时三层一起平移，**间距恒定**，不再靠手工乘数碰运气。
* **性能**：单次调用最多 24 轮（每轮一次 HSL→RGB→Lab），请在**主题刷新时算一次并缓存**，
  不要放进逐单位 / 每帧路径（性能红线同 `GetCurrent*`）。

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
    ambient = {alphaMin=0.15, alphaMax=0.30, saturationGuard=0.20},
    -- 高光/中性灰的成型参数，均可缺省（缺省即沿用内置 Monet 值）
    highlight = {hueShift=30, satMult=0.15, lOffset=0.25, lMax=0.95},
    neutral   = {saturation=0.02, lMin=0.35, lRange=0.30},
}
```

> `highlight` 与 `neutral` 由 `ComputeHighlightWash` / `ComputeNeutral` 读取；`neutral.saturation` 会被夹到 `0.05` 以内以守住契约，`highlight` 与 `neutral` 的明度结果都会被夹进 `[0, 1]`。只填部分键时其余键回退内置默认值。

---

### SetActiveProfile

激活指定 Profile。

```lua
-- @param name string  Profile 名称（"Monet" 为默认内置）
-- @return boolean     是否激活成功
function LMC:SetActiveProfile(name)
```

> 名称未知时**不会保持原样**：会打印一条警告、切回内置 `"Monet"` 并刷新，然后返回 `false`。这样失败的激活不会把界面留在半个自定义 Profile 上。

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

### OnThemeRefreshed

**每次重算都会触发**（不受 Delta E 防抖约束）。与 `OnThemeColorsChanged` 的区别：后者只在颜色"显著"变化时触发，前者是"我刚重算过，这是最新结果"。

```lua
LMC:RegisterCallback("OnThemeRefreshed", function(event, entry)
    -- entry 与 OnThemeColorsChanged 的 payload 相同
end)
```

> 状态染色层（`LibMonetColor-Anim-1.0`）订阅的就是这个事件：Profile 切换或细微换区时 `OnThemeColorsChanged` 可能不触发，但基色确实变了。

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
| **事件防抖** | `OnThemeColorsChanged` 仅在 Delta E > 5.0 时触发；`OnThemeRefreshed` 每次重算必发 |
| **输入宽容** | 无效 Profile 回退 `"Monet"`，无效 MapID 回退当前地图，非法样式参数钳制而非报错 |
| **版本兼容** | 1.x 生命周期内公开 API 签名、返回值、事件名向后兼容 |
| **警告冷却** | 每条消息各自 30 秒冷却（互不牵连），避免刷屏；无计时器环境（纯 Lua 工具）下每条消息最多打印一次 |
| **消费者隔离** | 状态层里某个消费者的回调抛错，不会影响其它消费者（`pcall` 隔离 + 一次告警） |
| **保密值安全** | 受限状态下血量读不到时只关闭低血效果，绝不抛错、绝不参与比较运算 |
| **空闲零开销** | 没有 sink 也没有回调时，状态层不订阅任何游戏事件，ticker 不运行 |
| **工具函数保守回退** | `ContrastRatio` / `AtLightness` 是纯函数（不读缓存、不发事件）；输入非法或运算抛错时，前者返回 **1**（"分不开"）、后者返回**原色**，绝不用一个漂亮数字骗过调用方 |

---

## ✅ 最佳实践与开发自查

1. **事件驱动** — 优先使用 `OnThemeColorsChanged` 事件更新 UI，避免每帧轮询。
2. **GetAllThemeColors** — 需要多种颜色时，优先调用 `GetAllThemeColors()` 减少缓存查找次数。
3. **优雅降级** — 始终检查 `LibStub` 返回值，库不存在时使用插件默认颜色。
4. **性能红线** — 禁止在 `OnUpdate` 中每帧调用颜色 API。
5. **对比度用工具函数验收，不用眼睛** — 界面构件之间要"看得出差别"，用 `ContrastRatio` 量一次并把数字
   打进诊断命令；`AtLightness` 负责把每一层放到自己的 L\* 台阶上，这样**换区域时间距不塌**。
6. **算一次、缓存住** — 这两个函数是刷新型开销（二分最多 24 轮），在主题刷新时算好存进插件自己的表，
   绘制路径只读表（同 `GetCurrent*` 的 O(1) 要求）。
5. **视觉验收** — 单元测试只能保证"不报错"，不能保证"好看"。务必在典型地图上亲自验证。