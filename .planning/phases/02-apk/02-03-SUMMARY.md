---
phase: 02-apk
plan: 03
subsystem: infra

tags: [godot, fonts, fonttools, fontvariation, glyph-gate, import-sidecars, ofl]

# Dependency graph
requires:
  - phase: 02-apk
    plan: 02
    provides: "mobile/tools/gate-a.sh 六步闸门 + project.godot 的 [gui] 段留白 + *.gd.uid 边车惯例"
  - phase: 01-repo-split-config-single-source
    provides: "shared/skills_config.json 唯一真源（本计划的字符来源之一）"
provides:
  - "tools/make_font_subset.py：从源文件抽字符 → 清单 + 两个子集 + OFL 一次生成；--check 只读比对「清单 vs 源文件」"
  - "mobile/assets/fonts/required_glyphs.txt：810 个字符的唯一清单（含 ° ± → ✓ ✗ 与 %+.3f 所需 ASCII）"
  - "NotoSansSC-Subset.ttf（451,276 B）+ NotoSansSymbols2-Subset.ttf（21,928 B），以及两个 *.ttf.import 导入契约"
  - "mobile/assets/fonts/AppFont.tres：FontVariation，base_font = SC 子集，fallbacks = 符号子集（✗ 的唯一来源）"
  - "mobile/tools/glyph_coverage.gd：关闭系统兜底后逐字符断言（GLYPH_OK / GLYPH_MISSING / GLYPH_BASE_HAS_X）"
  - "project.godot [gui] theme/custom_font 接线；gate-a.sh 追加字形两步（--check → 字形闸门）"
affects: [02-04, 02-05, "04", "05"]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 8353
  tasks: 3
  commits: 2
  plan_head_before: fd0d375e7f18baa2f5602ded3e853e1c94778070
  plan_head_after: 51f3859d52f66a6d20c2b5965531818174c98f36

tech-stack:
  added:
    - "fonttools 4.60.2 仅一次性使用：uv run --with fonttools==4.60.2 pyftsubset 子进程；desktop/pyproject.toml 与 desktop/uv.lock 零改动"
    - "Godot FontVariation + 两个 FontFile 子集：SystemFont 兜底之外的确定性字体链路"
  patterns:
    - "生成物三件套同源：清单与两个子集由同一份字符集、同一次运行产出；--check 只读比对清单 vs 源文件"
    - "闸门分层：glyph_coverage.gd 只能证明「清单 vs 子集」，make_font_subset.py --check 补「清单 vs 源文件」，两条边合起来才封死漂移（T-02-07）"
    - "关闭系统兜底要逐层遍历：FontVariation 顶层的 `if font is FontFile` 永远不成立（T-02-09）"

key-files:
  created:
    - tools/make_font_subset.py
    - mobile/assets/fonts/required_glyphs.txt
    - mobile/assets/fonts/NotoSansSC-Subset.ttf
    - mobile/assets/fonts/NotoSansSC-Subset.ttf.import
    - mobile/assets/fonts/NotoSansSymbols2-Subset.ttf
    - mobile/assets/fonts/NotoSansSymbols2-Subset.ttf.import
    - mobile/assets/fonts/AppFont.tres
    - mobile/assets/fonts/OFL.txt
    - mobile/tools/glyph_coverage.gd
    - mobile/tools/glyph_coverage.gd.uid
  modified:
    - mobile/project.godot
    - mobile/tools/gate-a.sh

key-decisions:
  - "字符来源整文件扫描（含注释）：810 个字符而不是 RESEARCH 估的 139 个 —— 注释里的汉字也进子集，代价只是几十 KB，换来「以后往首屏加中文不用记得改常量」"
  - "两个子集共用同一份 --text-file：pyftsubset 只收字体里存在的字符，符号子集自然只拿 ASCII + 它补得上的 103 个码位；少一份「该给 fallback 哪些字」的人工判断"
  - "AppFont.tres 用纯路径 ext_resource，不手写 uid：首次 --import 后由 Godot 生成 UID 边车，干净 clone 的导入参数与资源身份跨机器一致"
  - "glyph_coverage.gd 断言 ThemeDB.fallback_font.resource_path 而不是只 load() 一次：只造一个没人引用的 .tres 也能让 has_char 全绿，屏幕上却是默认字体"
  - "gate-a.sh 里 make_font_subset.py 只以 `glyph_tool` 变量出现一次：验收要求 grep 恰好一条命中，失败提示用 $glyph_tool 还原原文"
  - "INFRA-04 仍不标记完成：字形链路只覆盖成功标准 2 的无设备部分，签名 APK 与真机冒烟由 02-04/02-05 收口"

patterns-established:
  - "生成物入库 + 只读 --check：清单/子集/许可证与 sync_config.py 的副本同构，重复运行零 diff（本次实测四次产物打印 `·`）"
  - "字体闸门必须在关闭系统兜底的前提下断言；信息行（GLYPH_BASE_HAS_X）与判定行分开打印"
  - "导入边车（*.ttf.import / *.gd.uid）是提交物：git check-ignore 对三个路径都必须非零"

requirements-completed: []

coverage:
  - id: D1
    description: "清单、两个子集、OFL 出自同一次生成；--check 只读且退出 0"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "python3 tools/make_font_subset.py --check（退出 0，810 个字符）；前后 git status --porcelain 逐字节相同"
        status: pass
    human_judgment: false
  - id: D2
    description: "双字体是硬需求：Noto Sans SC 子集不含 ✗，符号 fallback 补上；关闭系统兜底后 810 个字符全部可渲染"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "godot --headless --path mobile --script res://tools/glyph_coverage.gd（GLYPH_BASE_HAS_X=false / GLYPH_OK chars=810）"
        status: pass
    human_judgment: false
  - id: D3
    description: "闸门有牙（反例 1）：向清单追加子集里没有的 ☃，字形闸门必须变红"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "printf '☃\\n' >> required_glyphs.txt → 退出 1 且 stderr 含 GLYPH_MISSING 1: ☃；还原后恢复 GLYPH_OK"
        status: pass
    human_judgment: false
  - id: D4
    description: "闸门有牙（反例 2）：源文件新增一个只在注释里的 ☃，必须由 make_font_subset.py --check 抓住"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "printf '\\n# ☃\\n' >> smoke_screen.gd → gate-a.sh 退出 1，日志含「字形清单与源文件不一致」；还原后 git diff --quiet 通过"
        status: pass
    human_judgment: false
  - id: D5
    description: "系统兜底被逐层关闭，且项目设置真的接上 AppFont.tres"
    requirement: INFRA-04
    verification:
      - kind: unit
        ref: "glyph_coverage.gd 对 base_font 与每个 fallbacks 条目设 allow_system_fallback = false；断言 ThemeDB.fallback_font.resource_path == APP_FONT_PATH"
        status: pass
    human_judgment: false
  - id: D6
    description: "三个导入边车随产物入库且不被忽略"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "git ls-files --error-unmatch 两个 *.ttf.import + glyph_coverage.gd.uid；git check-ignore 三者均非零；source_file 指向对应子集"
        status: pass
    human_judgment: false
  - id: D7
    description: "桌面回归红线与依赖清单未被污染"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "bash tools/check_desktop.sh（230 项全绿）；desktop/pyproject.toml = 93a9d680…、desktop/uv.lock = 763caf7b… 与基线一致"
        status: pass
    human_judgment: false
  - id: D8
    description: "闸门 A 一条命令同时证明「配置在包里」「5 条动作」「清单与源文件一致」「全部字形可渲染」"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "bash mobile/tools/gate-a.sh（退出 0，含 PACK_OK skills=5 与 GLYPH_OK chars=810）"
        status: pass
    human_judgment: false

duration: 4min
completed: 2026-11-04
status: complete
---

# Phase 2 Plan 3: 字体双链路 + 字形闸门 Summary

**「中文与 `° ± → ✓ ✗` 不豆腐」从真机赌注变成一条无设备也能跑的断言：清单与两个子集同源生成，闸门在关掉系统兜底后逐字符报 810 个全绿，而反例证明它真的有牙**

## Performance

- **Duration:** 4 min
- **Started:** 2026-11-04T14:32:03Z
- **Completed:** 2026-11-04T14:35:58Z
- **Tasks:** 3（Task 1 为 blocking-human 检查点，上一会话已完成，无提交）
- **Files modified:** 12（10 新建 + 2 修改）

## Accomplishments

- `tools/make_font_subset.py` 从 `shared/skills_config.json`、`desktop/padskills/{gui,detectors}.py`、
  `mobile/src/smoke/*` 整文件抽出 **810 个字符**（含 `° ± → ✓ ✗` 与 `%+.3f` 需要的 ASCII），
  一次生成 `required_glyphs.txt` + 两个子集 + `OFL.txt`；`--check` 只读、不调子进程。
- 首次运行实测确认 RESEARCH §P6 的结论：**Noto Sans SC 子集不含 `✗`**（`GLYPH_BASE_HAS_X=false`），
  符号子集恰好补上；双字体是判据不是优化。
- `AppFont.tres`（FontVariation）+ `project.godot [gui] theme/custom_font` 接线，
  `glyph_coverage.gd` 先断言 `ThemeDB.fallback_font.resource_path`，再对 base 与每个 fallbacks
  条目**逐层**设 `allow_system_fallback = false`，最后逐字符 `has_char` → `GLYPH_OK chars=810`。
- 闸门 A 增加到七件事：`--check`（清单 vs 源文件）排在字形闸门（清单 vs 子集）**之前**，
  两条边合起来才封死漂移（T-02-07）；收尾行同时说明「PCK 内含 5 条动作」与「全部必需字形可渲染」。
- 两个反例都实测变红并复原：
  1. 清单追加 `☃` → `GLYPH_MISSING 1: ☃`，退出 1；
  2. `smoke_screen.gd` 追加一行 `# ☃` 注释 → 闸门 A 退出 1，日志含「字形清单与源文件不一致」。
- 三个导入边车（两个 `*.ttf.import` + `glyph_coverage.gd.uid`）随本计划入库，
  `git check-ignore` 对三者均为非零；`--import` 重跑不产生新的未跟踪文件。
- 桌面红线与依赖清单零污染：`bash tools/check_desktop.sh` 230 项全绿，
  `desktop/pyproject.toml` / `desktop/uv.lock` 的 SHA-256 与检查点基线逐字节相同。

## Task Commits

每个任务单独提交：

1. **Task 2: 一份字形清单 + 两个字体子集，同一次生成** - `ba69a1e` (feat)
2. **Task 3: 双字体挂进主题，关掉系统兜底后逐字符断言** - `51f3859` (feat)

**Plan metadata:** 本 SUMMARY 与 STATE/ROADMAP 的提交见最终 `docs(02-03)` 提交。

## Files Created/Modified

- `tools/make_font_subset.py`（新建，298 行）— 纯标准库（import 里没有任何 `font*` 模块）；
  `CHAR_SOURCES` / `EXTRA_SYMBOLS` / `ASCII_PRINTABLE` / 四个输出路径 / 三个官方 URL 集中为常量；
  `uv run --with fonttools==4.60.2 pyftsubset` 只出现在子进程参数里；`--check` 只读。
- `mobile/assets/fonts/required_glyphs.txt`（生成物，810 行）— 一行一个字符、LF、无表头。
- `mobile/assets/fonts/NotoSansSC-Subset.ttf`（451,276 B）/ `NotoSansSymbols2-Subset.ttf`（21,928 B）—
  合计 473,204 B，在 20 000–600 000 的验收区间内；两个文件都是变量/静态字体子集，随仓库分发。
- `mobile/assets/fonts/{NotoSansSC-Subset,NotoSansSymbols2-Subset}.ttf.import`（各 36 行）—
  `importer="font_data_dynamic"`、`source_file="res://assets/fonts/<子集>.ttf"`、资源 UID 钉死。
- `mobile/assets/fonts/AppFont.tres`（新建，12 行）— `[gd_resource type="FontVariation" format=3]`，
  两条 `ext_resource`，`base_font` + `fallbacks`；注释用 `;`。
- `mobile/assets/fonts/OFL.txt`（新建，92 行）— 下载的 SIL OFL 1.1 原文，未改写、未翻译。
- `mobile/tools/glyph_coverage.gd`（新建，80 行）+ `.gd.uid` — `extends SceneTree`；
  `GLYPH_BASE_HAS_X` 信息行 + `GLYPH_OK chars=%d` 成功行；失败 `GLYPH_MISSING` 走 stderr 并 `quit(1)`。
- `mobile/project.godot`（修改，+7 行）— 新增 `[gui]` 段与 `theme/custom_font="res://assets/fonts/AppFont.tres"`，
  其余段未动。
- `mobile/tools/gate-a.sh`（修改，+35/-3 行）— 文件头由「五件事」改为「七件事」并补顺序理由；
  读包之后插入 `glyph_tool` 变量、`--check` 步骤、字形闸门步骤；收尾行加入字形结论。

## Decisions Made

- **字符来源整文件扫描**：810 个字符远多于 RESEARCH 估的 139，因为 `gui.py` / `detectors.py`
  的中文注释也被收进来。代价是子集大几十 KB，收益是「往首屏加一句中文不需要有人记得重生成」；
  而且注释里的字符本来就可能在未来的界面里出现。零覆盖缺口（用 cmap 交叉核对过 810/810）。
- **两个子集共用同一份 `--text-file`**：`pyftsubset` 只收字体里存在的字符，符号子集自然只拿
  ASCII + 它补得上的 103 个码位。少一份「该给 fallback 哪些字」的人工判断，也就少一处漂移面。
- **`AppFont.tres` 不手写 uid**：手写的 UID 是编造的；让 `--import` 生成 `.import` 边车并把 UID
  钉在提交物里，才是「干净 clone 资源身份一致」的正确做法。
- **闸门先断言 `ThemeDB.fallback_font.resource_path`**：只 `load()` 一个 .tres 再对它的
  `has_char` 断言，会在「project.godot 没接上」时照样报绿 —— 那是一个和字体无关的假绿。
- **`glyph_tool` 变量而非重复字面量**：验收要求 `grep -n 'make_font_subset.py'` 恰好一条命中，
  失败提示里用 `$glyph_tool` 拼出与计划原文一致的路径。
- **INFRA-04 不在本计划标记完成**：字形链路只覆盖成功标准 2 的无设备部分；签名 APK 与
  真机冒烟仍由 02-04 / 02-05 收口（与 02-02 的裁定一致）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 验收可机械化] `gate-a.sh` 的失败提示改用变量拼接，保证 `make_font_subset.py` 只有一处字面量**
- **Found during:** Task 3（自检 acceptance 条款时）
- **Issue:** 计划要求的失败提示原文是 `✗ 字形清单与源文件不一致：运行 python3 tools/make_font_subset.py 重新生成`，
  含工具文件名；而同一条验收又要求 `grep -n 'make_font_subset.py' mobile/tools/gate-a.sh` **有且只有一条命中**。
  两条要求在字面上互斥。
- **Fix:** 定义 `glyph_tool="tools/make_font_subset.py"` 一次，命令与提示都引用变量。
  运行时打印的字符串与计划原文逐字相同，源码里只有一个命中。
- **Files modified:** mobile/tools/gate-a.sh
- **Verification:** `grep -n` 只剩第 100 行；反例日志实际打印出
  `✗ 字形清单与源文件不一致：运行 python3 tools/make_font_subset.py 重新生成`。
- **Committed in:** `51f3859`（Task 3 提交）

**2. [Rule 2 - 缺失的正确性] `--check` 补一条「字符集合相同但字节不同」的判定**
- **Found during:** Task 2（写 `check()` 时）
- **Issue:** 计划只要求比对字符集合（多了 / 少了）。若清单被重排或改了行尾，集合相同、`--check`
  会报绿，但文件已不再是脚本生成的那一份；`glyph_coverage.gd` 逐字符读取，不会发现这种漂移。
- **Fix:** 集合一致时再与 `render_glyphs()` 的结果做整串比较，不一致就报
  「字符集合正确，但行序或格式与生成结果不一致（不能手改）」。
- **Files modified:** tools/make_font_subset.py
- **Verification:** 手改清单行序时退出 1；正常生成时退出 0 且 `--check` 前后 `git status` 逐字节相同。
- **Committed in:** `ba69a1e`（Task 2 提交）

---

**Total deviations:** 2 auto-fixed（1 验收可机械化，1 缺失的正确性）
**Impact on plan:** 两条都只收紧判据，没有放宽任何验收；闸门行为与退出码符合计划预期。

## Issues Encountered

- 本机的 `gsd_run` / `gsd-tools` 运行时仍不可用（与 02-02 相同），STATE.md / ROADMAP.md 用直接文件编辑更新。
- `git.branching_strategy = "none"`，仓库历史所有计划提交都在 `main`；本计划沿用 02-01/02-02 的
  sequential-on-main 工作流提交。
- `python3` 是系统 3.9.6：脚本用 `from __future__ import annotations` + `typing.List/Optional/Dict`，
  没有用 PEP 585 内建泛型，所以在系统解释器下可直接运行。
- 源字体（`NotoSansSC-VF.ttf` 17.7 MB、`NotoSansSymbols2-Regular.ttf` 1.2 MB）缓存在
  `~/.cache/fifa-trainer/fonts`，不进仓库；仓库里只有裁剪产物。
- `pyftsubset` 产物与 fonttools 版本相关（PATTERNS 已警告）：本计划只保证「相同字节不落盘」，
  不承诺跨版本重跑零 diff；产物提交后构建链路不再需要该工具。
- 导出日志尾部仍有 `cannot connect to daemon at tcp:5037`（P10 的 adb 噪声），不影响退出码。

## User Setup Required

None — Task 1 的人工确认已完成（`fonttools==4.60.2` 作为一次性工具放行）；
本计划之后构建与闸门都不再需要 fonttools、导出模板、JDK 或真机。

## Next Phase Readiness

- 02-04 的闸门 B 可以假定字体链路已封口：`bash mobile/tools/gate-a.sh` 一条命令同时覆盖
  配置、版本、导入、语法、PCK、字形清单漂移、字形渲染七项。
- 真机字体风险只剩「安卓系统是否按 FontVariation 的 fallbacks 渲染」这一条，由 02-05 的
  真机验收表收口；无设备机器上的假绿路径已被两条反例堵死。
- `mobile/build/verify.pck` 留在原地供人工检查，已被 `.gitignore` 覆盖，仓库仍干净。

## Known Stubs

None.

## Self-Check: PASSED

- `tools/make_font_subset.py`、`mobile/assets/fonts/{required_glyphs.txt,NotoSansSC-Subset.ttf,NotoSansSymbols2-Subset.ttf,AppFont.tres,OFL.txt}`、
  `mobile/tools/glyph_coverage.gd` 与三个导入边车均存在。
- `ba69a1e`、`51f3859` 均在 HEAD 祖先链上。
- `python3 tools/make_font_subset.py --check` 退出 0；`bash mobile/tools/gate-a.sh` 退出 0，
  输出含 `PACK_OK skills=5` 与 `GLYPH_OK chars=810`。
- 反例 1（清单追加 `☃`）退出 1 且含 `GLYPH_MISSING`；反例 2（源文件注释追加 `☃`）
  退出 1 且含「字形清单与源文件不一致」；两者还原后均恢复绿，`git diff --quiet` 通过。
- `bash tools/check_desktop.sh` 退出 0，230 项全绿；`desktop/pyproject.toml` / `desktop/uv.lock`
  的 SHA-256 与基线一致。
- `git status --porcelain -- mobile/` 在两次任务提交后为空；`mobile/build/` 未出现在未跟踪列表。

---
*Phase: 02-apk*
*Completed: 2026-11-04*
