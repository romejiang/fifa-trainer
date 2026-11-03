# Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-04
**Phase:** 1-仓库拆分 + 配置单一真源 + 桌面回归闸门
**Areas discussed:** 搬家深度、配置分发、回归闸门、mobile 骨架

---

## 会议形式说明

本次讨论未逐题选择题。用户在灰色地带选择环节明确回复：

> 「这些细节你来决定我也看不懂，你来决定」

因此四个灰色地带全部转入 **agent discretion**，由助手基于代码事实与研究结论做出决定，并把理由写入 CONTEXT.md。下面的表格保留当时呈现的备选方案，供日后回溯。

---

## 搬家深度

| Option | Description | Selected |
|--------|-------------|----------|
| 最小平移 | 只把现有文件平移到 `desktop/`，`padskills/` 内部结构不动 | ✓ |
| 同时整理 | 顺便拆 `tests/`、改 `src/` 布局、顺手清理大模块 | |

**User's choice:** 委托助手决定
**Notes:** 选择最小平移。理由是验收标准是「行为零变化」，任何额外结构改动都会让回归失败无法归因；`CONCERNS.md` 中的大模块债务属独立阶段。

---

## 配置分发

| Option | Description | Selected |
|--------|-------------|----------|
| 两份生成副本 | `shared/` 同步出 `desktop/` 与 `mobile/` 两份只读副本 + `.sha256` | ✓ |
| 桌面直读 shared | 桌面运行时直接读 `../shared/skills_config.json` | |
| 各自维护 | 两端各存一份手写配置 | |

**User's choice:** 委托助手决定
**Notes:** 选两份生成副本。桌面冻结后是单目录分发，运行时不能依赖仓库相对路径；生成副本保持 `default_config_path()` 语义不变，从而保护行为闸门。两份副本均非手写源且受 hash 保护，不构成第二真源。

---

## 回归闸门

| Option | Description | Selected |
|--------|-------------|----------|
| 根级脚本 + CI | 单一脚本为唯一定义，GitHub Actions 调用同一脚本 | ✓ |
| 仅根级脚本 | 只写 README + 脚本，靠自觉 | |
| pre-commit hook | 本地提交时强制 | |

**User's choice:** 委托助手决定
**Notes:** 选脚本 + CI。远程仓库已存在，CI 是唯一无法用 `--no-verify` 绕过的闸门；复用同一脚本避免第二套检查定义。hook 易被绕过且增加提交摩擦，未采用。

---

## mobile 骨架

| Option | Description | Selected |
|--------|-------------|----------|
| 空壳 | 只建 `mobile/README.md` + `assets/config/` 同步目标 | ✓ |
| 先建 Godot 项目 | 直接生成 `project.godot`，Phase 2 直接导出 | |

**User's choice:** 委托助手决定
**Notes:** 选空壳。Phase 1 不应依赖本机已装 Godot 4.7.2；由未知版本生成的 `project.godot` 会在 Phase 2 被静默重写。项目文件创建权归锁定工具链的 Phase 2。

---

## the agent's Discretion

用户明确委托的范围（原话：「这些细节你来决定我也看不懂，你来决定」）：

- 同步脚本的参数形态（除 `--check` 必须存在）
- `.sha256` 文件格式与存放位置
- `expected_checks.txt` 文本格式
- CI 的 Python 版本矩阵
- 搬迁过程中的提交粒度

## Deferred Ideas

- 桌面版上帝模块拆分 —— 独立重构，不混入搬迁
- pre-commit hook —— 不采用
- 移动端 GDScript 测试 CI —— Phase 2 之后
- `shared/golden_vectors.json` —— Phase 4/5
- iOS 目录与构建配置 —— 明确延期
