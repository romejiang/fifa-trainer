---
phase: 01-repo-split-config-single-source
reviewed: 2026-11-03T20:52:44Z
depth: deep
status: issues_found
files_reviewed: 14
files_reviewed_list:
  - tools/collect_checks.py
  - tools/sync_config.py
  - tools/test_sync_config.py
  - tools/check_desktop.sh
  - tools/verify_clean_clone.sh
  - .github/workflows/desktop-checks.yml
  - .gitignore
  - .gitattributes
  - README.md
  - mobile/README.md
  - desktop/main.py
  - desktop/padskills/config.py
  - shared/expected_checks.txt
  - shared/skills_config.json（含 desktop / mobile 两份副本与 .sha256）
severity_counts:
  blocker: 0
  high: 0
  medium: 4
  low: 5
  info: 6
---

# Phase 1 代码评审：仓库拆分 + 配置单一真源 + 桌面回归闸门

**评审范围：** `5e489a1..HEAD`（`5e489a1` 为 plan 01-01 完成点），重点为新增/修改的 source；
19 条纯 rename 的搬迁内容不逐行评审，仅验证其「内容零改动」。
**评审方式：** 逐文件静态阅读 + 实际执行闸门/反例/路由探针（见下表）。

## 验证记录（实际跑过的证据）

| 命令 / 探针 | 结果 |
|---|---|
| `bash tools/check_desktop.sh` | 退出 0；182 + 48 = 230 项全绿，名称与基线逐项一致 |
| `bash tools/verify_clean_clone.sh --tamper` | 退出 0；干净 clone 正向全绿、零漂移，篡改后两道关卡均非零、还原后恢复 |
| `python3 tools/test_sync_config.py` | 23 通过 / 0 失败，退出 0 |
| `python3 tools/sync_config.py --check`（分别在仓库根、`desktop/`、`mobile/`、`/tmp`） | 均为 0，路径锚定正确 |
| 删除 clone 中的 `desktop/skills_config.json` 后跑闸门 | 第 1 步即退出 1 并指名该文件（`load_config()` 静默回退的假绿路径被挡住） |
| 删除 clone 中的 `shared/expected_checks.txt` 后跑闸门 | 退出 1，但以 Python traceback 结束（见 LOW-02） |
| 构造 4 种畸形 `.sha256`（仅摘要 / 错文件名 / 单空格 / 多一行）后 `--check` | 4 种全部 rc=0（见 MED-02） |
| `git show --numstat -M100% 02b03db` | 19 条 rename，0 插入 / 0 删除，搬迁内容零改动 |
| `git ls-remote --tags` 校验 action SHA | `checkout v7.0.1`、`setup-uv v10.3.3` 的 40 位 SHA 均与注释版本一致 |
| `write_config_target()` 三级路由探针 | 开发态 → `<repo>/shared/skills_config.json`；冻结态（`sys.frozen=True`）→ `~/Library/Application Support/FifaSkillTrainer/skills_config.json`；显式 `-c` → 原样返回 |
| `uv --directory desktop run --no-sync python main.py --write-config -c /tmp/...` | 退出 0，生成 5 个动作的合法配置 |

**未发现 blocker / high。** 核心主张（230 项、基线锁定、配置一致、干净 clone 可复现、纯 rename、action 固定）均被实际执行证实，不是纸面声明。

---

## Medium

### MED-01：`--write-config` 之后打印的下一步命令在文档规定的工作目录里必然失败

**Severity:** medium
**File:** `desktop/main.py:247-248`（同类：`tools/sync_config.py:128`、`tools/check_desktop.sh:34`）
**What is wrong:** 开发态 `--write-config` 现在写 `shared/skills_config.json`，随后提示：

```python
print("提示：请运行 python3 tools/sync_config.py "
      "把真源同步到桌面/移动端副本")
```

但桌面版的文档规定所有命令都在 `desktop/` 里执行（根 `README.md:30-36`、`desktop/main.py` 模块 docstring 均如此）。从 `desktop/` 执行这条提示会得到：

```
python3: can't open file '.../desktop/tools/sync_config.py': [Errno 2] No such file or directory
```

**Why it matters:** 这是写入唯一真源后唯一的一条应用内指引；它是「`--write-config` → 同步 → 生效」闭环的最后一环。命令失败会让用户停在「已经生成但桌面副本仍是旧的」状态，而这正是本阶段要消灭的「多真源」体感。`tools/sync_config.py:128` 的「运行 python3 tools/sync_config.py 生成」与 `tools/check_desktop.sh:34` 的同类提示也有一样的问题（从 `desktop/` 调用闸门时）。
**Fix:** 打印绝对路径，任何 cwd 都能直接执行：

```python
if not is_frozen():
    tool = shared_config_path().parent.parent / "tools" / "sync_config.py"
    print(f"提示：运行 python3 {tool} 把真源同步到桌面/移动端副本")
```

`sync_config.py` / `check_desktop.sh` 的提示同理改为「在仓库根运行 …」或直接给出由脚本自身位置推导的绝对路径。

### MED-02：`.sha256` 校验只看第一个字段，畸形 sidecar 全部放行

**Severity:** medium
**File:** `tools/sync_config.py:139-143`
**What is wrong:** `check()` 只做 `fields[0] != digest` 比较，不校验文件名、字段数、分隔符或多余内容。实测以下四种 sidecar 都能让 `--check` 返回 0：

```text
<digest>\n                                  # 没有文件名
<digest>  wrong_name.json\n                 # 文件名错误
<digest> skills_config.json\n               # 只有一个空格
<digest>  skills_config.json\nextra junk\n  # 多余行
```

而 `sync()`（`tools/sync_config.py:98-102`）与自测（`tools/test_sync_config.py:68-71`）都明确保证格式是 `"<摘要>  <文件名>\n"`，根 `README.md:54` 也声称闸门会校验「`.sha256` 对得上」。
**Why it matters:** 副本字节一致这条主保护仍然成立（所以不是 high），但 sidecar 是给 `sha256sum -c` / 未来 Godot 构建消费的产物；一个文件名被改坏、只剩摘要的 sidecar 会一路绿灯进入提交，等真正执行 `sha256sum -c` 时才炸，且炸点离改动很远。这正是「闸门声称校验了 X、实际没校验 X」的典型。
**Fix:** 直接比较完整期望行，并把这个反例加进自测：

```python
expected = f"{digest}  {target.name}\n"
try:
    actual = side.read_text(encoding="utf-8")
except OSError as exc:
    problems.append(f"✗ {rel.as_posix()}{SIDECAR_SUFFIX} 读取失败：{exc}")
else:
    if actual != expected:
        problems.append(
            f"✗ {rel.as_posix()}{SIDECAR_SUFFIX} 格式或摘要不符"
            f"（应为「摘要 + 两个空格 + 文件名」）")
```

### MED-03：`tools/test_sync_config.py` 从未被闸门或 CI 执行，闸门的第一道防线没有测试保护

**Severity:** medium
**File:** `tools/test_sync_config.py`（未被引用；相关：`tools/check_desktop.sh:33`、`.github/workflows/desktop-checks.yml:26-29`）
**What is wrong:** 全仓库（除 `.planning/`）没有任何地方调用这个 23 项自测。`check_desktop.sh` 的第一步完全信任 `sync_config.py --check`；CI 也只跑闸门。也就是说，如果 `check()` 被后续改动成提前 `return 0`、或漏掉某类副本，闸门会**假绿**，而唯一能抓住它的自测永远不会运行。
**Why it matters:** 本阶段的最高优先级威胁（T-01-06，`load_config()` 静默回退）就靠这一步挡住；这一步的验证器却是死代码。计划只把它写成手工验证命令，但既然后续所有阶段都会复用这条闸门，把它接进自动化是完成闸门、而不是扩大范围。
**Fix:** 在 `check_desktop.sh` 的配置校验之后加一步（不改变 230 的计数，因为它不调用 `check()`）：

```bash
echo "▸ 校验同步脚本自测…"
if ! python3 "$repo_root/tools/test_sync_config.py" >&2; then
    echo "✗ tools/test_sync_config.py 未通过（同步脚本自身可能已损坏）" >&2
    exit 1
fi
```

如果不想增加闸门步骤，至少在 workflow 里加一个 `run: python3 tools/test_sync_config.py`。

### MED-04：根 README 的「以本文件为准」只覆盖了第九节，手册仍在教用户手改生成副本

**Severity:** medium
**File:** `README.md:71`（证据：`desktop/README.md:121`、`:152`、`:292`）
**What is wrong:** 根 README 只声明「`desktop/README.md` 的『九、项目结构』描述的是搬迁前的扁平布局」，但搬迁后产生的新矛盾不在第九节：

- `desktop/README.md:152`：「`uv run`（开发态）→ 项目根目录的 `skills_config.json`」——现在开发态读的是 `desktop/skills_config.json`，可手写的真源是 `shared/skills_config.json`；
- `desktop/README.md:292`：「**只需要改 `skills_config.json`**，不用动 Python 代码」——按新模型，手改 `desktop/skills_config.json` 会被同步覆盖、被闸门判红；
- `desktop/README.md:121`：`--write-config` 仍被描述为「重新生成一份默认 `skills_config.json`」，未说明开发态写到 `shared/`；
- `desktop/main.py:11` 的模块 docstring 同样只写「生成默认 skills_config.json」，`--write-config` 的 help（`:227-228`）也没有落点。

**Why it matters:** 本阶段的核心不变量是「只有 `shared/` 可手写」。手册是用户改配置的第一入口，却把他引向生成副本——用户会先看到改动生效（运行时确实读副本），随后被闸门判红、再被下一次同步覆盖，形成最难排查的一类「我的修改去哪了」。根 README 的免责声明只挡住第九节，挡不住这三处。
**Fix:** 做一次纯文档提交（不碰搬迁提交），把上述三处改成 `shared/skills_config.json` 为唯一手写真源、`desktop/skills_config.json` 为生成副本；`--write-config` 说明开发态写入 `shared/`、冻结态写入用户目录。`desktop/main.py:11` 的 docstring 同步改成「生成默认配置到 shared/（开发态）或用户目录（冻结态）」。若坚持不改手册，则根 README 的免责声明必须显式覆盖「二、配置文件放在哪」「五、怎么加自己的动作」「八、自测项数」「九、项目结构」。

---

## Low

### LOW-01：`--tamper` 的第二个断言恒真，无法证明闸门「指认了被篡改的文件」

**Severity:** low
**File:** `tools/verify_clean_clone.sh:93`
**What is wrong:**

```bash
if ! printf '%s' "$out" | grep -qF -e "$target" -e "配置"; then
```

`check_desktop.sh:32` 在任何检查之前都会无条件打印 `▸ 校验配置副本…`，而 `out` 捕获了 stdout+stderr，所以 `-e "配置"` 永远命中。这条断言实际只验证了「闸门非零退出」，没有验证「输出指名 `$target`」。任何与篡改无关的失败（`uv` 缺失、网络失败、基线缺失）都会让它通过。
**Why it matters:** 反例的价值在于区分「闸门因为这次篡改而咬人」和「闸门碰巧坏了」。前一条 `--check` 断言（`:80`）是具体的，但闸门这一半不是。`01-05` 的威胁模型 T-01-14 明确要求「输出含被改文件路径」。
**Fix:** 去掉恒真的 fallback，只要求目标路径：

```bash
if ! printf '%s' "$out" | grep -qF "$target"; then
    echo "✗ 闸门失败了，但输出没有指名 $target" >&2
    ...
fi
```

另外，还原后目前只重跑 `--check`（`:101`），而成功行说「还原后恢复绿」；若要让这句话覆盖闸门，还原后再跑一次 `bash tools/check_desktop.sh`（约 2 秒），或把措辞改成「还原后配置校验恢复」。

### LOW-02：基线文件缺失时闸门以 Python traceback 退出，而不是中文错误

**Severity:** low
**File:** `tools/check_desktop.sh:41-49`
**What is wrong:** 基线摘要由 `python3 - "$baseline" <<'PY' … Path(sys.argv[1]).read_bytes()` 计算。文件不存在时 Python 直接抛 `FileNotFoundError`，`set -e` 让脚本带着 traceback 退出，既没有「✗ 基线被修改/不存在」的中文提示，也把本机临时路径暴露在日志里（已实测复现）。
**Why it matters:** 基线是闸门的参照物；稀疏检出、误删、或 `shared/` 未同步时这是现实故障。闸门其它失败都给人话，唯独这里给栈，排障体验不一致。
**Fix:** 计算摘要前加一个存在性守卫：

```bash
if [ ! -f "$baseline" ]; then
    echo "✗ 基线不存在：$baseline" >&2
    echo "  基线应由 plan 01-01 交付；缺失时闸门无法判定 230 项是否与搬迁前一致。" >&2
    exit 1
fi
```

### LOW-03：`collect_checks.py` 用 `Path.write_text` 写 TSV，Windows 上会变成 CRLF 并让名称比对失败

**Severity:** low
**File:** `tools/collect_checks.py:50-53`
**What is wrong:** `Path.write_text(..., encoding="utf-8")` 的 `newline` 默认为 `None`，在写入时会把 `\n` 翻译成 `os.linesep`。在原生 Windows Python（Git Bash / MSYS 下调 `uv run python`）下生成的是 CRLF，而 `shared/expected_checks.txt` 被 `.gitattributes` 固定为 LF，`diff -u` 会因行尾差异报「名称不一致」——失败原因与代码无关。
**Why it matters:** 本项目有 Windows 打包目标，`.gitattributes` 明确为「Windows 检出后字节不变」服务；闸门若在 Windows 上因行尾假红，会诱导开发者去改基线或忽略闸门。
**Fix:** 用字节写入（3.9 也支持）：

```python
Path(args.out).write_bytes(
    "".join(f"{path.name}\t{name}\n" for name in names).encode("utf-8"))
```

（若同时想支持原生 Windows，还需在文档中注明闸门要求 macOS / Linux / WSL，因为 `mktemp -d` 的 `/tmp` 路径与 `python3` 命令在 MSYS 下也不可靠。）

### LOW-04：CI workflow 缺少最小权限、凭据不落盘与超时

**Severity:** low
**File:** `.github/workflows/desktop-checks.yml:14-29`
**What is wrong:** 工作流在 `pull_request` 上执行仓库代码，但没有 `permissions:`（继承仓库默认 token 权限）、`actions/checkout` 使用默认 `persist-credentials: true`（token 留在 `.git/config`）、也没有 `timeout-minutes`。其余供应链要求均满足：两个 action 都是 40 位 SHA（已用 `git ls-remote` 核对为 v7.0.1 / v10.3.3），`run:` 无 `${{ }}`、无 secrets、无 `continue-on-error`，`uv sync --locked` 到位。
**Why it matters:** 对一个会跑测试代码的 PR 工作流，最小权限与不落盘凭据是几乎零成本的加固；缺超时则一个挂起的 GUI 测试会占满 6 小时额度。
**Fix:**

```yaml
permissions:
  contents: read
jobs:
  desktop:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c...  # v7.0.1
        with:
          persist-credentials: false
```

### LOW-05：`collect_checks.py` 对加载失败/异常落盘的诊断不够健壮

**Severity:** low
**File:** `tools/collect_checks.py:30-34`、`:48-53`
**What is wrong:** 两处小问题：
1. `spec_from_file_location` 在路径不是 `.py` 时返回的 `spec.loader` 为 `None`，`spec.loader.exec_module` 会抛 `AttributeError`；`mod.main` 不存在时同理，错误信息不指向「你传错了测试脚本」。
2. `finally` 里的 `Path(args.out).write_text(...)` 若失败（父目录不存在、磁盘满），会**替换**掉 `mod.main()` 正在抛出的原始异常，真正的失败原因被吞掉。

**Why it matters:** 这是闸门的采集器；它坏掉时应该直接说清楚，而不是给一个与被测代码无关的栈。
**Fix:** 加载前显式检查并给出中文错误；落盘包一层 `try/except OSError`，失败时打印警告但不覆盖原始异常：

```python
if spec is None or spec.loader is None:
    raise SystemExit(f"无法按 Python 文件加载测试脚本: {path}")
...
if not hasattr(mod, "main"):
    raise SystemExit(f"测试脚本缺少 main(): {path}")
...
finally:
    payload = "".join(f"{path.name}\t{name}\n" for name in names)
    try:
        Path(args.out).write_bytes(payload.encode("utf-8"))
    except OSError as exc:
        print(f"⚠ 无法写入检查项文件 {args.out}: {exc}", file=sys.stderr)
```

---

## Info

### INFO-01：`sync_config.py` 说「任何第四份副本都会报错」，但跳过目录里的副本不会

**File:** `tools/sync_config.py:6-8`、`33-36`
**What:** 模块 docstring 与 `find_stray_copies` 的 docstring 写的是「任何第四份」；实际 `_SKIP_DIRS` 会跳过 `.planning`、`build`、`dist`、`export`、`.venv` 等目录。例如 `mobile/build/skills_config.json` 不会被报告。
**Why:** 跳过生成物/缓存目录是合理的，但文档的绝对化表述会让读者以为「第四份副本」已被完全封死。
**Fix:** docstring 改为「跳过生成物与缓存目录后，任何白名单之外的副本都会报错」。

### INFO-02：`sync()` 的错误走 stdout，`check()` 的错误走 stderr

**File:** `tools/sync_config.py:85-89`
**What:** `sync()` 的 `out` 默认 `sys.stdout`，缺少真源时 `✗ 缺少真源 …` 打到 stdout；`check()` 默认 `sys.stderr`。
**Why:** 管道/重定向时错误信息可能被静默吞掉；项目其它 CLI 的错误都走 stderr。
**Fix:** 该分支显式 `file=sys.stderr`，成功行保持 stdout。

### INFO-03：`tools/` 下的 Python 模块没有 `__all__`

**File:** `tools/sync_config.py:1-30`、`tools/collect_checks.py:1-16`
**What:** 项目约定是「每个公开模块在顶部声明 `__all__`」；`sync_config` 被自测 import，算公开模块。
**Why:** 一致性；也让 `from sync_config import *` 的边界明确。
**Fix:** 在 `sync_config.py` 顶部加 `__all__ = ["SOURCE", "TARGETS", "SIDECAR_SUFFIX", "repo_root", "sha256", "sidecar", "find_stray_copies", "sync", "check", "main"]`。脚本型 `collect_checks.py` 可加可不加。

### INFO-04：已知的时序敏感用例会让新 CI 偶发变红（不在本阶段修复）

**File:** `desktop/tests/test_detectors.py`（`test_engine_end_to_end`）；已记录于 `.planning/phases/01-repo-split-config-single-source/deferred-items.md`
**What:** `[8] 引擎端到端` 用真实 `perf_counter` 在 100–600ms 窗口内画弧，机器负载高时会偶发 3 项失败。本阶段禁止改测试，CI 也没有加重试（正确，重试等于放宽闸门）。
**Why:** 这是本阶段新引入的 CI 的第一个现实风险；它会以「桌面回归闸门」step 变红的形式暴露，不会被静默吞掉。
**Fix:** 本阶段不修。后续专项三选一并先记录：显式时间容差 / 测试内部单次重跑 / 标注时序敏感并单独成组。不要在工作流里加 `continue-on-error` 或重试。

### INFO-05：`--write-config` 会无确认地覆盖唯一可手写真源（既有语义，本阶段放大了影响面）

**File:** `desktop/main.py:243-249`、`desktop/padskills/config.py:77-83`
**What:** 开发态 `--write-config` 现在直接覆盖 `shared/skills_config.json`。这与搬迁前覆盖根 `skills_config.json` 的语义一致，但那个文件现在是文档指定的唯一手写入口，误执行的代价更高。
**Why:** 属于既有行为，不是本阶段引入；但「唯一真源」的定位让它更值得一次显式确认。
**Fix:** 本阶段不做行为变更（会违反 D-01）。后续可考虑 `--write-config` 前备份为 `skills_config.json.bak`，或仅在显式 `--force` 时覆盖；先记录，不要在本阶段夹带。

### INFO-06：`shared/skills_config.json` 不是当前 `DEFAULT_CONFIG` 的输出（已知且被计划接受）

**File:** `shared/skills_config.json` vs `desktop/padskills/config.py:DEFAULT_CONFIG`
**What:** 真源缺少 `DEFAULT_CONFIG` 里的 `input.invert` 模板与三行 `_readme` 说明（已用 `json.dumps(DEFAULT_CONFIG, indent=2)` 对比确认）。功能上无差异（`_parse_input` 对缺失的 `invert` 走默认 `{}`），且 01-02 明确决定不趁机对齐。
**Why:** 记录在案，避免第一次 `--write-config` 产生的 diff 被误判为回归；也提醒后续对齐时这是一次有意的内容变更。
**Fix:** 本阶段不改。下次合法改配置时再对齐，并在提交信息中说明。

---

## Summary

**结论：可以继续，但建议先修 MED-01 / MED-02 / MED-04（都是小改动），MED-03 作为三行闸门补强。**

本阶段的核心承诺是「搬迁零改动 + 配置单一真源 + 230 项机械化闸门」，这三件事都经得起实测：

- 搬迁提交 `02b03db` 是 19 条 100% rename、0 行增删；`desktop/README.md` 等 19 个文件内容与搬迁前逐字节一致。
- `bash tools/check_desktop.sh` 实际退出 0，182 + 48 = 230 项全绿，名称与 `shared/expected_checks.txt` 逐项一致；基线 SHA-256 常量与文件匹配。
- 配置副本与真源逐字节一致，`.sha256` 内容正确；删除桌面副本后闸门第 1 步即失败，`load_config()` 静默回退的假绿路径被正确挡住。
- `verify_clean_clone.sh --tamper` 在真正的 clone 上复现了「正向全绿 + 篡改被两道关卡抓住 + 还原后恢复」，且运行前后工作区零漂移。
- `--write-config` 三级路由正确：开发态写 `shared/`、冻结态写用户目录、显式 `-c` 优先；冻结态读取路径未被改变。
- CI 的两个 action 按 40 位 SHA 固定，且 SHA 与注释版本（v7.0.1 / v10.3.3）经 `git ls-remote` 核对一致；`run:` 无事件插值、无 secrets、无 `continue-on-error`。

没有发现会让 230 项**内容**假绿的当前缺陷。四个 medium 分别对应：一条会失败的用户指引（MED-01）、一个比宣称更弱的 `.sha256` 校验（MED-02，已用四种畸形 sidecar 复现）、闸门第一道防线的验证器未被自动化执行（MED-03）、以及手册仍在教用户手改生成副本（MED-04）。它们都不会破坏当前已通过的 230 项，但都会在「人按文档操作」或「后续改动同步脚本」时把闸门的可信度往下拉。

已知残留风险（均已被阶段记录或属既有行为，不在本次要求修复）：时序敏感的 `test_engine_end_to_end` 可能让 CI 偶发红（INFO-04）；`--write-config` 无确认覆盖唯一真源（INFO-05）；`shared/skills_config.json` 与 `DEFAULT_CONFIG` 的既有漂移（INFO-06）。

---

_Reviewed: 2026-11-03T20:52:44Z_
_Reviewer: gsd-code-reviewer (adversarial pass, deep)_
