---
gsd_state_version: "1.0"
current_phase: 2
current_phase_name: 安卓工具链 + 真机冒烟 APK
status: planning
stopped_at: Phase 1 complete, ready to plan Phase 2
last_updated: "2026-11-03T21:01:54.104Z"
last_activity: 2026-11-04
last_activity_desc: Phase 1 complete, transitioned to Phase 2
state_head: 3977d6911f7cb6b552cee57187d69e9c03dd5770
progress:
  total_phases: 10
  completed_phases: 1
  total_plans: 5
  completed_plans: 5
  percent: 10
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-04)

**Core value:** 用真手柄、在任何地方都能练，判定准、反馈看得懂。
**Current focus:** Phase 1 — 仓库拆分 + 配置单一真源 + 桌面回归闸门

## Current Position

Phase: 2 — 安卓工具链 + 真机冒烟 APK
Plan: Not started
Status: Ready to plan
Last activity: 2026-11-04 — Phase 1 complete, transitioned to Phase 2

Progress: [█░░░░░░░░░] 10%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: — min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 5 | - | - |

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
| Phase 1 P4 | 2min | 2 tasks | 3 files |
| Phase 1 P5 | 2min | 2 tasks | 2 files |

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
- [Phase 1]: 根 README 只做仓库地图（71 行），桌面手册保持单一位置（desktop/README.md 776 行不改，D-03）
- [Phase 1]: README 只描述、不复述坏命令形态：`--project` + 相对测试路径会 Failed to spawn，文档里不留可粘贴的失败示例
- [Phase 1]: CI 只保留 4 步（检出 → 装 uv → cd desktop && uv sync --locked → bash tools/check_desktop.sh）：不额外插 sync_config 步骤，闸门内部第一步已做，重复即第二套定义
- [Phase 1]: setup-uv 钉 0.9.5（与本机生成 uv.lock 的版本一致），避免新 uv 升级锁文件格式后 --locked 误红
- [Phase 1]: actions 按 40 位 commit SHA 固定并附 # vX.Y.Z 注释；run 步骤零 ${{ }} 插值、零 secrets、零 continue-on-error
- [Phase 1]: mobile/README.md 明确 Phase 2 才创建 project.godot（D-10），Phase 1 只放配置副本与文档
- [Phase 1]: 时序敏感的 test_engine_end_to_end 不在 01-04 修复：files_modified 不含 desktop/tests/，在 CI 加重试等于放宽闸门；结论已写入 deferred-items.md
- [Phase 1]: 干净 clone 脚本入口用 rc=2 拒绝脏工作区：clone 只复制提交，脏树下的绿指向旧代码；rc=2 表示「不接受这次运行」，与检查失败的 rc=1 区分
- [Phase 1]: 零漂移断言放在 clone 内而不是源仓库，证明 .venv/ 与 __pycache__/ 的忽略规则在全新检出上也成立
- [Phase 1]: --tamper 反例选 mobile/assets/config/skills_config.json：两份副本对 --check 等价，但移动端副本无运行期消费者，反例只暴露配置闸门本身
- [Phase 1]: 反例第 4 步除 --check 变绿外追加 git status --porcelain 为空，证明还原彻底且 clone 未被前次运行弄脏
- [Phase 1]: 反例把原始报错行打进日志；断言必须是「出现被点名文件」而非「出现不一致」，避免 pipefail 下 grep 空匹配静默退出
- [Phase 1]: 验证脚本零复制：不写死 230、不写死测试路径，只调 check_desktop.sh 与 sync_config.py

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

Last session: 2026-11-03T20:42:00.000Z
Stopped at: Phase 1 complete, ready to plan Phase 2
Resume file: None
