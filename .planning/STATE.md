---
gsd_state_version: "1.0"
current_phase: 1
current_phase_name: 仓库拆分 + 配置单一真源 + 桌面回归闸门
status: executing
stopped_at: Completed 01-03-PLAN.md
last_updated: "2026-11-03T20:33:51.349Z"
last_activity: 2026-11-04
last_activity_desc: Phase 1 execution started
state_head: dc0e7746a2a0b007b08f737fbf3be863a221dfe8
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 5
  completed_plans: 3
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-04)

**Core value:** 用真手柄、在任何地方都能练，判定准、反馈看得懂。
**Current focus:** Phase 1 — 仓库拆分 + 配置单一真源 + 桌面回归闸门

## Current Position

Phase: 1 (仓库拆分 + 配置单一真源 + 桌面回归闸门) — EXECUTING
Plan: 4 of 5
Status: Ready to execute
Last activity: 2026-11-04 — Phase 1 execution started

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
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 1 P01 | 2min | 3 tasks | 3 files |
| Phase 1 P2 | 4min | 3 tasks | 26 files |
| Phase 1 P3 | 2min | 2 tasks | 4 files |

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
- [Phase 1]: 基线 SHA-256 = 724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a，01-02 的 check_desktop.sh 需钉成常量
- [Phase 1]: 基线用 LC_ALL=C sort 排序（UTF-8 码点序==字节序），规避 BSD/GNU sort 的 locale collation 差异
- [Phase 1]: INFRA-01 不在 01-01 标记完成：本计划只交付搬迁前基线，仓库拆分与 230 项闸门由 01-02 收口
- [Phase 1]: 搬迁提交 02b03db 只含 git mv：19 条 rename、--numstat 全 0、0 删除，git log --follow 仍能追到 Initial commit
- [Phase 1]: check_desktop.sh 顺序即安全属性：先 sync_config.py --check、再钉 BASELINE_SHA256、最后才 uv sync --locked 跑测试；副本缺失时 load_config() 静默回退会让闸门假绿
- [Phase 1]: 配置真源字节 bccf123a…eee9 未改；两份副本 + .sha256 已提交，shasum -a 256 -c 双 OK；自测 23 项断言全绿
- [Phase 1]: default_config_path() 函数体零改动：冻结态与开发态的读取语义都是行为锚点，只新增写入侧的 shared_config_path() 与 write_config_target()
- [Phase 1]: --write-config 三级路由收敛到纯函数 write_config_target()：显式 -c > 冻结态用户目录 > 开发态 shared/；运行期读取仍是 desktop/skills_config.json
- [Phase 1]: .gitignore 必须用 desktop/build/* 而非 desktop/build/：目录被整体排除后 ! 白名单再也无法把两条打包脚本捞回来
- [Phase 1]: .gitattributes 只加 *.sha256 / *.txt 的 eol=lf：CI 只在 Linux 跑，给 YAML 加 eol 只会增加 Windows 检出时的 diff 噪音
- [Phase 1]: 未传 -c 的 --write-config 分支不做真跑验证：它会覆盖真源本身；改用 write_config_target() 纯函数断言覆盖同一判定
- [Phase 1]: plan 01-03 的 acceptance「不再出现 Path(args.config)」与其 action 示例代码冲突，按行为验收：显式路径只转一次 Path(...) 后复用 explicit_config

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

Last session: 2026-11-03T20:33:51.332Z
Stopped at: Completed 01-03-PLAN.md
Resume file: None
