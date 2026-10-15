# LibMonetColor-1.0

> WoW 动态环境色彩计算引擎 —— 一个基于"印象派（莫奈）色彩规则"的实时调色中间件，为 UI 插件输出自适应的「5+3」主题色系统。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](#协议)
![Interface](https://img.shields.io/badge/WoW-Retail%2012.x-orange.svg)
![Tests](https://img.shields.io/badge/tests-45%20%2B%2011-brightgreen.svg)

它不是一个静态的颜色查找表，而是随着**当前区域环境色**实时推导 UI 配色：把"你所在的地图"转译成一组协调、耐看、有莫奈味道的界面颜色。

---

## ✨ 特性

- **环境驱动**：颜色由当前地图/区域的环境色实时推导，随区域切换平滑变化。
- **5+3 色彩模型**：功能色与风格色严格分离，保证可读性优先。
- **莫奈规则引擎**：环境互补色 + 明度 S 曲线钳制 + 色相域细分 + 无彩域兜底注入。
- **事件驱动 + 防抖**：仅当颜色变化超过 Delta E 阈值时才通知订阅者，杜绝重绘风暴。
- **永不抛错**：所有公开 API 异常时回退中性灰，保证接入方 UI 不崩。
- **可扩展**：生产者可注册自定义规则 Profile。

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
| `SetEnvironmentSampler(fn)` | `bool` | 设置环境采样器 `fn(mapID) -> h,s,l` |

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
| **事件防抖** | 仅 Delta E > 5.0 时触发 |
| **输入宽容** | 无效 Profile 回退 `"Monet"`，无效 MapID 回退当前地图 |
| **版本兼容** | 1.x 生命周期内公开 API 向后兼容 |
| **警告冷却** | 重复警告间隔 30 秒 |

---

## ✅ 最佳实践

1. **事件驱动** —— 优先订阅 `OnThemeColorsChanged`，避免每帧轮询。
2. **批量读取** —— 需要多种颜色时用 `GetAllThemeColors()`，减少查找次数。
3. **优雅降级** —— 始终检查 `LibStub` 返回值，库缺失时用插件默认色。
4. **性能红线** —— 禁止在 `OnUpdate` 中每帧调用颜色 API；使用事件或节流轮询。
5. **视觉验收** —— 单元测试只保证"不报错"，"好不好看"必须在真实地图上亲眼看。

---

## 🧪 开发与测试

零依赖，本机安装 [Lua 5.4](https://www.lua.org/) 即可运行测试（无需进入游戏）：

```bash
lua test_phase1.lua      # 45 个核心算法测试
lua test_hardening.lua   # 11 个加固回归测试
```

VSCode 用户可直接运行任务：`Run Phase 1 Tests` / `Run Hardening Tests`。

### 目录结构

```
LibMonetColor-1.0.lua         核心库（单文件）
LibMonetColor-1.0-API.md      对外接口契约（唯一真理源）
MonetColorBaseline.lua        v3 莫奈规则基线（7 域 + 6 互补色对）
test_phase1.lua               核心算法单元测试
test_hardening.lua            加固回归测试
monet_palette_v3.json         15 幅画 × 8 色样（提取源数据）
monet_red_domain_v3.json      Red/Warm 域专项色样
Monet_Paintings/MANIFEST.md   原图清单（含尺寸与 SHA-256，原图不入库）
```

---

## 🗺️ 版本状态

- ✅ **Phase 1** 核心算法（HSL 转换 / 莫奈规则引擎 / Delta E 缓存防抖 / 生产者 API）
- ✅ **+ 加固** LibStub 注册、Profile 生效、按地图采样、R-01 Alpha 公式
- 🔜 **Phase 2** 真实地图色彩采样（T2.1）、TestHarness 插件（T2.2）、三地图视觉验收（T2.3）
- 🔜 **Phase 3** 发布与打包

---

## 协议

MIT License. 莫奈画作源数据来自 Wikimedia Commons（公有领域）。
