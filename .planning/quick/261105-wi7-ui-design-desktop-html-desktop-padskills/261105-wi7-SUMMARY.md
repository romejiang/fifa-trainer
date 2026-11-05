---
phase: 261105-wi7-ui-design-desktop-html-desktop-padskills
plan: 01
subsystem: ui
tags: [pygame, desktop, gui, light-theme, procedural-drawing, design-tokens]

# Dependency graph
requires:
  - plan: 04-10
    provides: 桌面 gui.py 现有的识别接线、专项/修饰键/校准/快捷键交互与全部中文文案
provides:
  - 亮色主题的桌面练习窗口（全部视觉程序化绘制，无二进制资源）
  - 设计 token 与几何常量（色彩、边距、卡片矩形、字号）
  - 可复用的缓存绘制工具（圆角遮罩、横竖渐变、柔和阴影、白卡、键帽、chip、线框图标）
affects: [desktop-ui, design-system, gui-redraw]

# Actuals — 与计划 estimate 同尺度（chars/4 over 实际改动的文件）
actuals:
  tokens: 26725        # 106900 chars / 4，最终 gui.py
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "SRCALPHA 缓存渐变/阴影：按尺寸+颜色做 key，60fps 不重复生成"
    - "每帧重建命中区：_focus_hits / _modifier_hits / _hotkey_hits / _cal_hits / _cal_btn_hits"
    - "程序化线框图标与键帽：不依赖字体字形，避免 ✓/✗ 变方块"

key-files:
  created: []
  modified: [desktop/padskills/gui.py]

key-decisions:
  - "不嵌入设计稿里的两张 FIFA 宣传照片：Hero 改为程序化青色渐变 + 白色斜条带 + 球轮廓线，规避肖像与 EA/Adidas/Juventus/Jeep 商标"
  - "设计合同里 lead/sub 的三态文案表述有冲突：按设计稿语义落成 lead=朝向/右摇杆三态、sub=右摇杆状态；三句原文逐字保留"
  - "FontBook.get 接受浮点字号并四舍五入，落实 10.5 / 11.5 / 13.5 等设计字号，不新增字体文件"
  - "配置错误页右上角的 R 重新加载加白色胶囊底：原文直接压在青色 Hero 上对比度不足"

patterns-established:
  - "缓存绘制工具链：_cached → _round_mask / _vgrad_surface / _hgrad_surface / _shadow_surface → _card / _gradient_card"
  - "交互只通过命中区列表表达，绘制函数不直接触发业务动作"

requirements-completed: []

metrics:
  duration: 21min
  started: "2026-11-05T15:42:22Z"
  completed: "2026-11-05T16:04:17Z"
  tasks: 3
  files: 1
status: complete
commits: 5
plan_head_before: c8f97a7f041f0bce9251fcafe025dcb3a3d006ff
plan_head_after: 5d114d0
---

# Quick Task 261105-wi7: 桌面版亮色 UI 重做 Summary

**桌面练习窗口整体换成 design/desktop.html 的亮色风格：960x660 白卡布局、程序化青色 Hero、三态结果卡、五行动作面板与浅色校准弹窗，全部交互与文案逐字保留**

## Performance

- **Duration:** 21 min
- **Started:** 2026-11-05T15:42:22Z
- **Completed:** 2026-11-05T16:04:17Z
- **Tasks:** 3
- **Files modified:** 1 (`desktop/padskills/gui.py`)

## Accomplishments

- 亮色壳层端到端成立：`#F5F5F7` 背景 + 极淡绿/青晕染、白色顶栏（程序化青色 Hero + 2px 绿→青强调线 + 计时胶囊）、白色底栏（摇杆图 + 朝向/右摇杆 + 琥珀警告 chip + 5 个键帽快捷键 + 配置路径）
- 左面板改为五行整行可点：CN/EN 双行名、`成功 N` + `N/10`、绿色渐变进度条、行内实时状态/最近结果、数字键帽与绿色搓射的 RB/RT 键帽；选中行蓝色外发光
- 结果卡三态：空闲白卡灰圆、成功绿白渐变 + 绿色对勾、失败暖白渐变 + 橙红叉；含 chip、毫秒数与建议
- 最近尝试面板：空态时钟图标；5 行记录（时间/勾叉/动作名/毫秒/说明）+ 细滚动条，滚动与键盘行为未改
- 连接中 / 无手柄 / 配置错误统一白卡 + 浅蓝/浅红图标块 + 纯视觉键帽；校准弹窗改为半透明遮罩 + 白色圆角 16 对话框 + 浅蓝选中行 + 蓝色主按钮

## Task Commits

Each task was committed atomically:

1. **Task 1: 亮色壳层 —— 调色板、绘制工具、背景/顶栏/底栏** - `c290a0e` (feat)
2. **Task 2: 动作面板 + 结果卡 + 最近尝试** - `9640afb` (feat)
3. **Task 3: 连接中 / 无手柄 / 配置错误 / 校准弹窗 + 全量回归** - `65051df` (feat)
4. **精修：英雄区光带 / 状态胶囊 / 次级页面 / 紧凑布局** - `f7eba38` (fix)
5. **边界处理：长动作名 / 空动作列表** - `5d114d0` (fix)

_Note: 文档提交（SUMMARY/STATE/PLAN）由 orchestrator 处理，本 executor 未提交任何 .planning 产物。_

## Files Created/Modified

- `desktop/padskills/gui.py` — 只改绘制层与提示文案排版；识别、输入、震动、写盘、快捷键与滚动逻辑一行未动

## Verification

| 闸门 | 结果 |
|------|------|
| `uv run python -m py_compile padskills/gui.py` | 通过 |
| `uv run tests/test_detectors.py` | 205 项通过，0 失败 |
| `uv run tests/test_gui_smoke.py` | 97 项通过，0 失败 |
| `uv run python /tmp/fifa-ui-shots/shots.py` | `SHOTS_OK 10 张；像素检查通过` |
| 校准截图像素检查 | `CAL_SHOT_OK (255, 255, 255)` |

命中区不变量保持：`_focus_hits` 每个动作恰好 1 项、`_modifier_hits` 绿色搓射恰好 RB/RT 2 项、`_hotkey_hits` 恰好 5 项、`_cal_btn_hits` 恰好 save/clear/close 3 项。

### 截图与目测结论（`/tmp/fifa-ui-shots/`）

| 截图 | 目测结论 |
|------|----------|
| `01-idle.png` | 浅灰背景 + 白色卡片；五行动作、空进度条、数字键帽、绿色搓射 RB(蓝)/RT(灰)；结果空闲态、时钟空态、底栏完整 |
| `02-success.png` | 绿白渐变结果卡、绿色对勾圆、`做对了` chip、556 ms、绿色建议；尝试面板单行对齐 |
| `03-failure.png` | 暖白渐变结果卡、橙红叉圆、`没做对`、红色原因、琥珀建议；两条记录对齐 |
| `04-focus.png` | 绿色搓射行蓝色描边 + 外发光；其余行仅文字变灰，无深色面板；数字键帽 5 为蓝色 |
| `05-history.png` | 52 条记录时 5 行可见，右侧细滚动条出现；时间/勾叉/名称/毫秒/说明对齐 |
| `06-history-end.png` | 滚到最旧一端，滚动条滑块在底部，内容正确 |
| `07-calibration.png` | 半透明遮罩 + 白色圆角对话框；两列 13 行完整；X 行浅蓝选中 + `按手柄键…`；蓝色保存按钮与白色次按钮 |
| `08-config-error.png` | 白卡 + 浅红图标块 + 红色标题；报错在 CARD_SOFT 内嵌块；视觉键帽提示；顶栏红色状态 chip 与白色 R 提示胶囊 |
| `09-opening.png` | 白卡居中：浅蓝图标块 + `正在连接手柄…` + 说明，不再与顶栏重叠 |
| `10-no-device.png` | 白卡 + 浅蓝图标块 + `未检测到手柄` + 平台提示（4px 圆点）+ 蓝色重试文案 + 视觉键帽 |
| `11-sticks-progress.png` | 额外目测：绿色进度条 6/10 渐变填充；底栏朝向深色指针与右摇杆蓝色指针同时正确指向 |

## Decisions Made

- 不嵌入设计稿里的两张 FIFA 宣传照片（含真实球员肖像与 EA / Adidas / Juventus / Jeep 商标）；Hero 用程序化青色渐变、白色斜条带与球轮廓线表达同一视觉语言
- 配色、几何、字号全部按 design_contract 落成模块级常量；`W, H = 960, 660`，所有矩形落在窗口内
- 所有渐变/阴影/圆角遮罩挂在 `TrainerApp._cache`，键为尺寸+颜色元组；没有新增模块级可变状态
- 图标、键帽、chip 全部用 `pygame.draw` 程序化绘制，不依赖字体字形

## Deviations from Plan

### 解释性偏差（无功能范围变化）

**1. [设计合同歧义] lead/sub 三态文案的落位**
- **Found during:** Task 1（底栏）
- **Issue:** 合同一处写「lead 13 粗按三态文案」，另一处把三句原文列在「底栏 sub」下
- **Fix:** 按设计稿本身的语义拆成两行：lead = 朝向状态（`球员朝向 {direction}` / `左摇杆回中`），sub = 右摇杆状态（`右摇杆 · 居中` / `右摇杆 · 已推（无朝向基准）` / `右摇杆 相对 N°`）。三句原文全部逐字保留
- **Verification:** 截图 01（无朝向）与 11（朝向有效 + 右摇杆推出）均正确

**2. [Rule 2 - 视觉可读性] 配置错误顶栏的 `R 重新加载` 加白色胶囊底**
- **Found during:** Task 3（目测 08-config-error）
- **Issue:** 灰色小字直接压在青色 Hero 上对比度不足
- **Fix:** 文字下垫白色圆角胶囊（与计时胶囊同族）
- **Committed in:** `65051df`

**3. [实现细节] 新增可选参数/辅助**
- `_chip` 增加可选 `bold` 参数（后端 chip 用非粗体，结果 chip 用粗体）
- 新增 `_lerp_color`、`_dialog_mask`、`_keycap_row` 三个未列在合同里的辅助；均为纯绘制，无业务逻辑
- `FontBook.get` 接受浮点字号并四舍五入成像素，落实设计稿的 .5 字号

**Total deviations:** 3 处解释/实现性偏差，0 处行为偏差
**Impact on plan:** 交互、命中区、文案与写盘行为均未变；仅视觉排版与辅助方法有上述调整。

## Issues Encountered

- Task 1 的 09-opening / 10-no-device 截图里旧面板矩形（y=74）会压住新顶栏；这是计划预期的过渡态，Task 3 按 `Rect(20, 134, 920, 418)` 重排后消除。
- 无其他问题。

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 桌面版练习窗口已是亮色主题，自动化闸门全绿；`git status --porcelain` 只显示 `desktop/padskills/gui.py` 的三次提交和未跟踪的 `.planning/quick/`。
- 移动端、配置、测试、打包脚本与 `uv.lock` 均未改动。
- 剩余风险：设计稿的 macOS 交通灯与窗口阴影由系统窗口边框提供，未在 pygame 内模拟；如需完全 1:1，可在后续任务加自定义窗口装饰。

---

## Self-Check: PASSED

- `desktop/padskills/gui.py` 存在且为唯一修改文件
- 三个任务提交均存在于 HEAD 历史：`c290a0e`、`9640afb`、`65051df`
- 10 张截图全部生成且 ≥ 5000 字节；`SHOTS_OK` / `CAL_SHOT_OK` 均打印

---
*Plan: 261105-wi7*
*Completed: 2026-11-06*
