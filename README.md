# LibMonetColor-1.0

> WoW 动态环境色彩计算引擎 —— 一个基于"印象派（莫奈）色彩规则"的实时调色中间件，为 UI 插件输出自适应的「5+3」主题色系统。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Interface](https://img.shields.io/badge/WoW-Retail%2012.x-orange.svg)
![Tests](https://img.shields.io/badge/tests-155-brightgreen.svg)
![Lua 5.1](https://img.shields.io/badge/Lua-5.1-blue.svg)

仓库：<https://github.com/easthillgu/monetcolors>

它不是一个静态的颜色查找表，而是随着**当前区域环境色**实时推导 UI 配色：把"你所在的地图"转译成一组协调、耐看、有莫奈味道的界面颜色。

---

## ✨ 特性

- **环境驱动**：颜色由当前地图/区域的环境色实时推导，随区域切换平滑变化。
- **5+3 色彩模型**：功能色与风格色严格分离，保证可读性优先。
- **莫奈规则引擎**：环境互补色 + 明度 S 曲线钳制 + 色相域细分 + 无彩域兜底注入。
- **状态染色层（可选）**：`LibMonetColor-Anim-1.0` 把**玩家状态**（战斗 / 休息 / 低血 / PvP / 载具）翻译成颜色修饰——边框、动作条背景、装饰线都能直接用，接入方不写一行状态判定。
- **一个共享 ticker**：所有闪烁动画共用一个帧、64 点查表波形、15 fps、空闲自动停表。
- **事件驱动 + 防抖**：仅当颜色变化超过 Delta E 阈值时才通知订阅者，杜绝重绘风暴。
- **永不抛错**：所有公开 API 异常时回退中性灰，保证接入方 UI 不崩。
- **保密值安全**：受限状态下血量读不到就只关掉低血效果，绝不抛错。
- **可扩展**：生产者可注册自定义规则 Profile。

---

## 🗺️ 区域环境数据（可选模块）

引擎只认 `mapID → HSL`，色值从哪来由数据层决定。`MonetColorMapData-1.0.lua` 是
**生成文件（勿手改）**，由 `data/game_palette_v1.json` 经 `tools/gen_map_env.ps1` 产出，
覆盖 **25 个区域**；底账每条带 `source` 标签（当前 `trip` 18 / `game` 7）。

色源优先级（2026-11-08 拍板）：**官方地图美术贴图 > wuxianwow/trip 旅拍 > 自己的游戏截图**。
前一级有数据就用前一级，缺的才往下退。`data/trip_sources.json` 记每个取景点，
`format: v1|v2` 区分出图口径（v1 屏幕截图裁剪、v2 相机原图；v2 整体 s 更高、l 更低）。
差异落在取景点与构图的天然散布内，**不做比例校正**，结论见 `data/source_bias.json`。

> 贴图覆盖层不随本库分发：官方地图贴图只有 17 个区域，由消费方（MonetUI）在自己的
> `Libs/` 里另挂一层 `RegisterMapEnv` override。加上本库 25 区与 3 条大陆 / 世界层父链派生，
> 该消费方最终得到 **33 个精确区域 = 贴图 17 + trip 15 + game 1**（另有 3 条父层兜底）。
> 唯一缺口是银月城 2393（旅拍站点不覆盖）。幽暗城 1458 有意保留 game 色：
> 旅拍取点落在洛丹伦废墟地表，不是地下城内部。

---

## 🧠 5+3 色彩架构

| 域 | 颜色 | 归属 | 说明 |
| :--- | :--- | :--- | :--- |
| **功能色 (Functional Core)** | Primary | UI 插件 | 主色，仅允许 ±10° 色相微调 |
| | Health / Resource / Danger | UI 插件 | 血条红/资源蓝/危险色 —— **严禁莫奈化** |
| | Neutral | 本库 | 莫奈化中性灰，用于文本与分割线 |
| **风格色 (Monet Signature)** | Edge Glow | 本库 | 边缘发光色（边框） |
| | Ambient Tint | 本库 | 环境氛围色（背景浸染） |
| | Highlight Wash | 本库 | 高光色（顶部渐变叠加） |

> 设计原则：**功能色优先**。任何"很有艺术感但看不清字"的效果都应立即回退。

---

## 🚀 快速接入

作为标准 LibStub 库，请使用静默模式获取，防止库未加载时外部插件报错。

```lua
local LMC = LibStub("LibMonetColor-1.0", true)

if LMC then
    -- 获取当前区域的莫奈风格边缘色（已缓存，可安全高频调用）
    local r, g, b, a = LMC:GetCurrentEdgeColor()
    MyFrame:SetBackdropBorderColor(r, g, b, a or 0.8)
else
    -- 优雅降级：库不存在时使用插件自身的默认颜色
    MyFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
end
```

### 事件驱动（推荐）

```lua
local LMC = LibStub("LibMonetColor-1.0", true)
if LMC then
    LMC:RegisterCallback("OnThemeColorsChanged", function(event, entry)
        -- entry = { mapID, envH, envS, envL, edge, ambient, highlight, neutral }
        MyFrame:ApplyTheme(entry)
    end)
end
```

### 一次性取全部颜色

```lua
local er, eg, eb, ea,   -- edge
      ar, ag, ab, aa,   -- ambient
      hr, hg, hb,       -- highlight
      nr, ng, nb        = LMC:GetAllThemeColors()
```

---

## 🎨 状态染色（可选）

`LibMonetColor-Anim-1.0` 把**玩家状态**变成颜色修饰：战斗中提亮、低血变红脉冲、脱战降亮、休息转冷调、PvP / 载具染色。**接入方不订阅事件、不算血量、不写 OnUpdate。**

```lua
local LMC  = LibStub("LibMonetColor-1.0", true)
local Anim = LMC and LMC.Anim

-- 边框：参与战斗闪烁与低血脉冲
Anim:RegisterColorSink(function(r, g, b, a)
    MyFrame:SetBackdropBorderColor(r, g, b, a)
end, { base = "edge", pulse = true })

-- 动作条背景：只跟随环境氛围，不要低血红
Anim:RegisterColorSink(function(r, g, b, a)
    MyBar:SetVertexColor(r, g, b, a)
end, { base = "ambient", modifiers = { lowHealth = false } })

-- 拉取式
local r, g, b, a = Anim:GetColor("neutral")
```

| 文件 | 职责 |
| :--- | :--- |
| `LibMonetColor-1.0.lua` | 纯色彩引擎（环境色 / 4 个色彩槽） |
| `LibMonetColor-Anim-1.0.lua` | 玩家状态采样 + 颜色修饰 + 共享 ticker |

两者可独立使用：只要环境色的项目不需要加载 Anim，也就不会多出事件帧和 ticker。

---

## 📚 API 摘要

消费者 API（全部为 O(1) 缓存读取）：

| API | 返回 | 说明 |
| :--- | :--- | :--- |
| `GetCurrentEdgeColor()` | `r,g,b,a` | 边缘发光色（alpha 默认 0.8） |
| `GetCurrentAmbientTint()` | `r,g,b,a` | 氛围色（alpha 0.15–0.30，随环境自适应） |
| `GetCurrentHighlightWash()` | `r,g,b` | 高光色 |
| `GetCurrentNeutral()` | `r,g,b` | 莫奈化中性灰（饱和度 < 0.05） |
| `GetAllThemeColors()` | 14 值 | 一次性取全部主题色 |
| `GetEdgeColorForMap(mapID)` | `r,g,b,a` | 指定地图的边缘色（不改动活动缓存） |
| `Refresh()` | — | 强制重算当前地图（事件仍受防抖约束） |
| `SetDeltaEThreshold(t)` | — | 设置事件触发阈值（默认 5.0） |
| `GetMapEnv(mapID)` | `h,s,l,name,source` | 解析地图环境色：运行时覆盖 → 区域数据 → 父地图链 → 回退 |
| `RegisterMapEnv(mapID,h,s,l,name?)` | `bool` | 运行时扩展/覆盖单个地图的环境色（优先于数据模块） |
| `SetFallbackEnv(h,s,l)` | `bool` | 设置未收录地图的回退环境色（默认中性无彩） |
| `SetEnvironmentSampler(fn)` | `bool` | 整体替换环境采样器（默认已内置，一般无需调用） |

色彩工具函数（1.2.0，**纯函数**：不读缓存、不发事件）：

| API | 返回 | 说明 |
| :--- | :--- | :--- |
| `ContrastRatio(r1,g1,b1, r2,g2,b2)` | `number >= 1` | WCAG 2.x 对比度；1.0 = 等亮看不出。读不出的分量**返回 1**（保守答"分不开"） |
| `AtLightness(r,g,b, targetL)` | `r,g,b` | 保住色相与饱和度，按 CIE L\* 重定位亮度；目标够不到时返回最接近的那个 |

状态染色层（`LibMonetColor-Anim-1.0`）：

| API | 返回 | 说明 |
| :--- | :--- | :--- |
| `RegisterColorSink(fn, opts)` | handle | 订阅最终颜色；`opts.base` / `opts.pulse` / `opts.modifiers` |
| `GetColor(base, atTime?, modifiers?)` | `r,g,b,a` | 拉取式取色（任意色彩槽或自定义基色） |
| `GetPlayerState()` | table | 玩家状态（战斗/休息/血量/PvP/载具…） |
| `SetStyle(tbl)` / `GetStyle()` / `ResetStyle()` | — | 深合并样式 / 读取 / 恢复默认 |
| `RefreshAll()` | — | 强制重绘所有订阅者 |

生产者 API：

| API | 说明 |
| :--- | :--- |
| `RegisterProfile(name, rules)` | 注册自定义规则 Profile |
| `SetActiveProfile(name)` | 激活 Profile（`"Monet"` 为内置） |
| `GetActiveProfile()` | 当前 Profile 名 |
| `GetRules()` | 当前规则表（自定义 Profile 缺省字段自动补全） |
| `ClearCache()` | 清空颜色缓存 |

完整契约见 [`LibMonetColor-1.0-API.md`](LibMonetColor-1.0-API.md)。

---

## 🛡️ 契约与降级

| 契约 | 保证 |
| :--- | :--- |
| **永不抛错** | 异常时返回有效 RGB `(0.5, 0.5, 0.5)` |
| **值域保证** | 所有返回值均在 `[0, 1]` |
| **事件防抖** | 仅 Delta E > 5.0 时触发（`OnThemeRefreshed` 每次重算必发） |
| **输入宽容** | 无效 Profile 回退 `"Monet"`，无效 MapID 回退当前地图，非法样式钳制 |
| **版本兼容** | 1.x 生命周期内公开 API 向后兼容 |
| **警告冷却** | 重复警告间隔 30 秒 |
| **消费者隔离** | 某个消费者的回调抛错不影响其它消费者 |
| **保密值安全** | 血量读不到时只关低血效果，绝不抛错 |
| **空闲零开销** | 无 sink 无回调时不订阅事件，ticker 不运行 |

---

## ✅ 最佳实践

1. **事件驱动** —— 优先订阅 `OnThemeColorsChanged`，避免每帧轮询。
2. **批量读取** —— 需要多种颜色时用 `GetAllThemeColors()`，减少查找次数。
3. **优雅降级** —— 始终检查 `LibStub` 返回值，库缺失时用插件默认色。
4. **性能红线** —— 禁止在 `OnUpdate` 中每帧调用颜色 API；使用事件或节流轮询。
5. **状态判定交给库** —— 战斗/低血/休息的判断放在 `LibMonetColor-Anim-1.0`，接入方只负责把返回的 RGBA 画出来。
6. **视觉验收** —— 单元测试只保证"不报错"，"好不好看"必须在真实地图上亲眼看。

---

## 🧪 开发与测试

零依赖，本机安装 [Lua 5.4](https://www.lua.org/) 即可运行测试（无需进入游戏）：

```bash
lua tests/test_phase1.lua        # 45 个核心算法测试
lua tests/test_hardening.lua     # 14 个加固回归测试
lua tests/test_map_sampler.lua   # 16 个 T2.1 地图采样测试
lua tests/test_libstub_order.lua # 4 个 LibStub 加载顺序测试
lua tests/test_anim_state.lua    # 33 个状态染色 / 取色测试
lua tests/test_anim_runtime.lua  # 19 个 sink / ticker / 事件运行时测试
lua tests/test_color_tools.lua   # 24 个色彩工具函数测试（对比度 / L* 重定位）
```

GitHub Actions 在每次 push / PR 时跑同一组命令（见 `.github/workflows/tests.yml`，按 `tests/test_*.lua` 通配）。VSCode 用户可直接运行任务：`Run Phase 1 Tests` / `Run Hardening Tests` / `Run Map Sampler Tests` / `Run LibStub Order Tests` / `Run Anim State Tests` / `Run Anim Runtime Tests`。

版本变更见 [`CHANGELOG.md`](CHANGELOG.md)；提交前请先跑上面 7 组测试，全部 `PASSED` 再提交。

### 目录结构

```
LibMonetColor-1.0.lua             核心库（单文件，惰性加载可选地图数据）
LibMonetColor-Anim-1.0.lua        状态染色层（玩家状态 + 颜色修饰 + 共享 ticker）
LibMonetColor-1.0.toc             独立 addon 声明（内嵌 LibStub；LoadOnDemand）
Libs/LibStub/LibStub.lua          内嵌 LibStub（Public Domain，勿手改）
MonetColorMapData-1.0.lua         25 区域环境色数据模块（game + trip 混合，生成文件，勿手改）
MonetColorBaseline.lua            v3 规则基线快照（引擎内置副本的来源，运行时不加载）
LibMonetColor-1.0-API.md          对外接口契约（唯一真理源）
tests/test_phase1.lua             核心算法单元测试
tests/test_hardening.lua          加固回归测试
tests/test_map_sampler.lua        T2.1 地图采样测试
tests/test_libstub_order.lua      LibStub 加载顺序回归测试
tests/test_anim_state.lua         状态染色层：取色与修饰测试
tests/test_anim_runtime.lua       状态染色层：sink / ticker / 事件测试
tests/test_color_tools.lua        色彩工具函数：对比度 / L* 重定位
tools/gen_map_env.ps1             data/game_palette_v1.json → 地图数据 Lua 模块生成器
tools/extract_game_palette_v1.ps1 游戏截图 / trip 照片 → 区域调色板取色管线
data/game_palette_v1.json         25 区域 × Top8 色样 + env + source（取色底账）
data/trip_sources.json            旅拍取点账本（format: v1|v2 + skipped 例外）
data/source_bias.json             v1/v2 口径差对照与「不做校正」结论
data/monet_palette_v3.json        15 幅画 × 8 色样（提取源数据）
data/monet_red_domain_v3.json     Red/Warm 域专项色样
Monet_Paintings/MANIFEST.md       原图清单（含尺寸与 SHA-256，原图不入库）
.github/workflows/tests.yml       CI：7 组测试
```

> 截图（`Gamepics/`）、莫奈原画（`Monet_Paintings/*.jpg`）、渲染产物与中间态色料 JSON 都只在本地，不入库——见 `.gitignore`。

### 打包与部署

`LibMonetColor-1.0.toc` 是**独立发布**用的声明：它先加载内嵌的 `Libs/LibStub/LibStub.lua`，再加载引擎与数据模块，所以不依赖外部 LibStub 插件。部署时把本目录改名为 `LibMonetColor-1.0` 放进 `Interface/AddOns/`（文件夹名必须与 `.toc` 同名）。`## LoadOnDemand: 1` 表示不会被自动加载，需由消费方用 `## OptionalDeps: LibMonetColor-1.0` 或 `LoadAddOn` 拉起。

以 vendored 方式接入（MonetUI 当前做法）：把 `LibMonetColor-1.0.lua`、`LibMonetColor-Anim-1.0.lua`、`MonetColorMapData-1.0.lua` 和 `Libs/LibStub/LibStub.lua` 拷进消费方插件的 `Libs/`，按顺序在 `.toc` 里登记即可。MonetUI 还在同目录另挂了两个 `RegisterMapEnv` 覆盖层（父链派生色 + 官方地图贴图色），加载顺序与色源优先级见其 `Libs/Libs.xml`；这两个文件属消费方，不在本仓分发。

> ⚠️ 同一个客户端里**不要同时**存在"独立 addon"与"被消费方 vendored 的副本"：两份都会向 LibStub 注册同一 MAJOR，本能升级守卫会让第二份直接退出，实际生效的是加载顺序靠前的那份，另一份的缓存与事件帧白跑。二选一即可（当前 MonetUI 走的是 vendored 方式）。

---

## 🗺️ 版本状态

- ✅ **Phase 1** 核心算法（HSL 转换 / 莫奈规则引擎 / Delta E 缓存防抖 / 生产者 API）
- ✅ **+ 加固** LibStub 注册、Profile 生效、按地图采样、R-01 Alpha 公式
- ✅ **Phase 2 (T2.1)** 真实地图色彩采样：`MonetColorMapData-1.0` 数据模块（**25 区域**，游戏截图 + wuxianwow/trip 旅拍取色产出）+ 解析链（覆盖 → 数据 → 父地图 → 回退）+ 16 项测试
- ✅ **1.1.0 状态染色层** `LibMonetColor-Anim-1.0`：玩家状态 → 颜色修饰（战斗增亮 / 进入战斗闪烁 / 战斗脉搏 / 低血红与加速脉搏 / 脱战降亮 / 休息冷调 / PvP / 载具 / 死亡灰化）+ 单共享 ticker + 52 项测试
- ✅ **1.2.0 色彩工具函数** `ContrastRatio`（WCAG 对比度）/ `AtLightness`（按 CIE L\* 重定位，保色相保饱和）——纯函数，接入方自己排亮度阶梯；补的是决策日志 **R-04** 预留的口子（对比度校验不内置进主题计算），+ 24 项测试
- ✅ **数据覆盖（2026-11-08）** 底账 25 区（trip 18 / game 7）；消费方 MonetUI 再挂 17 区官方地图贴图 override 与 3 条大陆 / 世界层父链派生，最终 **33 个精确区域**（贴图 17 / trip 15 / game 1），父链断掉时回退中性灰。唯一已知缺口是银月城 2393（旅拍站点不覆盖）；官方 atlas 也只有 17 区，其余区域是「按优先级择优」而非全量统一到贴图色。
- ✅ **2026-11-08 数据层升级（无 API 变更）** 补拍 7 区 trip v2 出图（阿拉希高地 / 提瑞斯法林地 / 银松森林 / 希尔斯布莱德丘陵 / 艾尔文森林 / 西部荒野 / 奥格瑞玛）并重生成 25 区数据；地图采样测试改为从数据模块读期望值，不再硬编码色值。7 组共 **155 项**全通过，实机 33/33 对账 PASS。
- 🔜 **Phase 2** TestHarness 插件（T2.2）、三地图视觉验收（T2.3）
- 🔜 **Phase 3** 打包分发（CurseForge / Wago 式独立包）

---

## 协议

[MIT License](LICENSE) © 2026 EastHillGu。莫奈画作源数据来自 Wikimedia Commons（公有领域），原图不入库，清单见 [`Monet_Paintings/MANIFEST.md`](Monet_Paintings/MANIFEST.md)。
