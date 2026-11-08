# 更新日志

版本号与 `LibMonetColor-1.0.toc` 的 `## Version` 保持一致；对外 API 在 1.x 内向后兼容。

## 数据层 — 2026-11-08（引擎 API 与 MINOR 均未变更）

- `data/game_palette_v1.json` 扩到 **25 区**，每条带 `source`（当前 `trip` 18 / `game` 7）；`MonetColorMapData-1.0.lua` 由 `gen_map_env.ps1` 重生成，数值随底账。
- 补拍 7 区 trip **v2** 出图（相机原图 1536×2048）升级色源：阿拉希高地 / 提瑞斯法林地 / 银松森林 / 希尔斯布莱德丘陵 / 艾尔文森林 / 西部荒野 / 奥格瑞玛；其余 18 区逐字段零变化。幽暗城 1458 保留 game 色（旅拍取点落在洛丹伦废墟地表，语义不符）。
- 色源优先级定为 **官方地图美术贴图 > wuxianwow/trip > 自己的游戏截图**；`trip_sources.json` 记取点与 `format`，`source_bias.json` 记 v1/v2 口径差「不做比例校正」。
- `tests/test_map_sampler.lua` 不再硬编码区域 h/s/l，改从数据模块读期望值、区数下界 14 → 25；修掉本轮数据升级造成的 4 项回归。7 组共 **155 项**全通过。

## 1.2.0 — 2026-10-30

**色彩工具函数（纯函数，不读缓存、不发事件）**

- `LMC.ContrastRatio(r1,g1,b1, r2,g2,b2)` — WCAG 2.x 对比度，顺序无关，`>= 1`；1.0 即"等亮、看不出差别"。相对亮度复用 `RGBToXYZ` 的 Y（与 `RGBToLab` 同一套 sRGB 解码，口径一致）。
- `LMC.AtLightness(r,g,b, targetL)` — 保住色相与饱和度，把颜色按 **CIE L\*** 重定位（在 HSL 的 `l` 轴上二分，容差 0.25、最多 24 轮）；目标超出该色相可达范围时返回**最接近的那一个**，不静默改色相。
- 保守回退：`ContrastRatio` 遇到读不出来的分量（缺字段 / 非数值 / NaN / secret）**返回 1**——宁可得出"分不开"，也不拿一个猜出来的数字充数；`AtLightness` 同情况按契约返回中性灰，`targetL` 读不出则原色返回。
- 这两个函数补的是决策日志 **R-04** 留的口子：对比度校验**不内置进主题计算**（不碰每帧路径），只给原语，"要几级阶梯、差多少 L\*"归消费方自己定。**功能色依旧不 Monet 化。**
- `MINOR` 10002 → 10003（vendored 的接入方需要看见"更新的库"，否则 `NewLibrary` 直接返回 nil，新代码不加载）。
- 测试 24 项（`tests/test_color_tools.lua`），覆盖可达/不可达目标、色相与饱和度守恒、单调性、越界钳制、非法与 secret 输入；全套 155 项通过。

## 1.1.0 — 2026-10-21

**状态染色层 `LibMonetColor-Anim-1.0`（新文件）**

- 玩家状态 → 颜色修饰：战斗增亮 / 进战闪烁 / 战斗脉搏 / 低血红与加速脉搏 / 脱战降亮 / 休息冷调 / PvP / 载具 / 死亡灰化。
- `RegisterColorSink(fn, opts)` 订阅最终颜色，`opts.base` 选色彩槽、`opts.pulse` 控制脉冲、`opts.modifiers` 逐项关掉不需要的修饰。
- 全部闪烁共用**一个 ticker**：64 点查表波形、15 fps、空闲自动停表；无 sink 无回调时零开销。
- `GetColor(base, atTime?, modifiers?)` 拉取式取色，`GetPlayerState()` 暴露状态快照，`SetStyle / GetStyle / ResetStyle` 深合并样式。
- 保密值安全：受限状态读不到血量时只关掉低血效果，不抛错。

**核心引擎**

- `## Version` 升到 1.1.0。
- 抽出 `Libs/LibStub/LibStub.lua` 内嵌副本，自带 `LibMonetColor-1.0.toc`，可作为独立 addon（`LoadOnDemand`）加载。
- 测试补到 131 项，覆盖 LibStub 加载顺序、状态染色取色与 sink / ticker / 事件路径。

## 1.0.0 — 2026-10-16

首个可用版本：环境驱动配色引擎。

- HSL 转换、莫奈规则引擎（环境互补色 + S 曲线钳制 + 色相域细分 + 无彩域兜底）、Delta E 缓存防抖。
- 「5+3」色彩模型：功能色（Primary / Health / Resource / Danger / Neutral）与风格色（Edge / Ambient / Highlight）分离。
- 生产者 API：`RegisterProfile` / `SetActiveProfile` / `GetRules` / `ClearCache`。
- `MonetColorMapData-1.0` 数据模块（14 区域环境色，由 `tools/extract_game_palette_v1.ps1` → `tools/gen_map_env.ps1` 生成）。
- 环境解析链：运行时覆盖 → 区域数据 → 父地图 → 回退；未收录地图回退中性无彩。
- 契约：永不抛错、返回值钳制在 `[0, 1]`、事件防抖（Delta E > 5.0）、消费者回调隔离、警告冷却 30 秒。
- 测试 45 + 14 + 16 + 4 项，全部可脱离游戏用 `lua` 直接运行。
