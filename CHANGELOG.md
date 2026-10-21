# 更新日志

版本号与 `LibMonetColor-1.0.toc` 的 `## Version` 保持一致；对外 API 在 1.x 内向后兼容。

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
