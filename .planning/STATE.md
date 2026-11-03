---
gsd_state_version: "1.0"
current_phase: 1
current_phase_name: 仓库拆分 + 配置单一真源 + 桌面回归闸门
status: executing
stopped_at: Phase 1 context gathered
last_updated: "2026-11-03T20:03:04.635Z"
last_activity: 2026-11-04
last_activity_desc: "Roadmap created: 10 phases, 37/37 v1 requirements mapped"
state_head: d15e3d8bf51d094c5f75fca539970780d4fa9f1d
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 5
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-04)

**Core value:** 用真手柄、在任何地方都能练，判定准、反馈看得懂。
**Current focus:** Phase 1 — 仓库拆分 + 配置单一真源 + 桌面回归闸门

## Current Position

Phase: 1 (仓库拆分 + 配置单一真源 + 桌面回归闸门) — READY TO EXECUTE
Plan: 0 of 0
Status: Ready to execute
Last activity: 2026-11-04 — Roadmap created: 10 phases, 37/37 v1 requirements mapped

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: — min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Init] 仓库拆成 `desktop/` + `mobile/` + `shared/`；先搬目录再写移动端，230 项检查是唯一回归红线（Phase 1 闸门）
- [Init] `shared/skills_config.json` 唯一真源 + 同步脚本 + hash 校验，Phase 1 就必须建立，避免第二份手写副本
- [Init] 判定对等性用 Python 侧生成的 `shared/golden_vectors.json` 证明，不靠「看起来一样」；0 差异是进 UI 的闸门
- [Init] 采样走 `_input()` 事件捕获 + `Time.get_ticks_usec()/1000.0`；`delta` 与墙钟时间禁止进判定路径
- [Init] 震动三级契约：桌面手柄马达 → 手机本体 → 静默。安卓只会走到手机本体，UI 必须标注「手机震动」
- [Init] 先做绿色搓射一条竖切（Phase 4），5 个动作的对等性在 Phase 5 收口；不做横向分层
- [Init] Phase 10 触觉可选可砍，任何阶段都不等它；发布阶段（9）不依赖它

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 2 / 4 之前需备齐 **2 台不同 OEM 手机 + Xbox 与 DualSense 手柄**；模拟器不能替代真机验证
- 60 Hz 抽稀是否保住 `release_hold_ms = 120` 与 `global_cooldown_ms = 60` 尚未实测，由 Phase 5 的抽稀矩阵回答；在此之前不动任何阈值
- 中文 UI 字体必须在 Phase 2 定案（内嵌 Noto Sans SC 子集，或 SystemFont + 内嵌兜底），否则朋友的非 Pixel 机型是豆腐块
- `set_use_accumulated_input(false)` 在安卓上是否真的产生亚帧时间戳未验证（Phase 4 真机记录 `t_ms` 直方图）

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-11-03T18:58:52.949Z
Stopped at: Phase 1 context gathered
Resume file: .planning/phases/01-repo-split-config-single-source/01-CONTEXT.md
