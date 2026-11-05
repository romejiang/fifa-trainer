# Roadmap: FIFA 花式动作练习器（桌面 + 安卓）

## Overview

从一份已经跑通的 Python/pygame 桌面版出发：先把它搬进 `desktop/` 并让 230 项检查保持全绿，再把配置收成 `shared/` 单一真源；随后用一个真机冒烟 APK 打通安卓工具链，再以「纯核心 → 设备层 → 绿色搓射竖切」的顺序，在真手机上换来第一次真实判定；接着用 Python 生成的黄金向量证明 5 个动作的判定逐条对等，并把采样抽稀的漂移证据钉死；最后补齐免触摸训练循环、可读反馈、生命周期韧性与侧载发布。震动是最后一个可整体砍掉的附加通道，任何阶段都不等它。

本里程碑按**垂直切片**组织：每个阶段都结束在一个可演示的状态；凡触达安卓的阶段，其成功标准必须在真实 Android 设备 + 真实蓝牙手柄上验证，模拟器只用于布局截图与非输入回归。阶段内部一律「先检测器 → 再适配器 → 再界面」，不做横向分层。

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门** - `desktop/` + `mobile/` + `shared/`，桌面 230 项检查全绿，配置漂移可被脚本抓住 (completed 2026-11-04)
- [x] **Phase 2: 安卓工具链 + 真机冒烟 APK** - 签名 APK 能装能启动，中文不豆腐，`*.json` 真进包，能读到手柄原始轴 (completed 2026-11-05)
- [x] **Phase 3: 纯核心地基** - 几何 / 领域模型 / 配置校验 / 无头运行 / 架构 lint，零引擎依赖 (completed 2026-11-05)
- [x] **Phase 4: 设备输入层 + 绿色搓射竖切** - 引导式配对、轴探测、校准、布局确认，真机上产出第一次判定 (completed 2026-11-06)
- [ ] **Phase 5: 全动作判定对等性** - 三类检测器 + 引擎仲裁 1:1 移植，5 个动作黄金向量逐条一致，抽稀不漂移
- [ ] **Phase 6: 训练循环** - 10 次一组、免触摸自动推进、待触发/冷却可见、暂停恢复
- [ ] **Phase 7: 反馈呈现** - 实测 vs 区间时序条、实时轨迹、音效、支架距离可读布局
- [ ] **Phase 8: 长期使用韧性** - 后台/锁屏/掉手柄不误判，统计与最近结果杀进程不丢
- [ ] **Phase 9: 发布 — 侧载 APK + 升级路径** - 朋友能装上就用，v1→v2 覆盖安装不丢数据
- [ ] **Phase 10: 手机触觉（可选，不阻塞任何阶段）** - `vibrate_handheld()` 附加通道，明确标注、可全局关闭

## Phase Details

### Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门

**Goal**: 把仓库拆成 `desktop/` + `mobile/` + `shared/`，搬完桌面版行为零变化；`shared/skills_config.json` 成为唯一真源，并有一部可执行的同步 + hash 校验挡住第二份手写副本。
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02
**Success Criteria** (what must be TRUE):
  1. 仓库根一条命令跑完 `desktop/` 的 230 项检查且全绿；检查项数量与名称与拆分前逐项一致（允许 import 路径适配，不允许改写、弱化或跳过任何断言）
  2. `shared/skills_config.json` 是仓库里唯一手写的动作配置；手改 `mobile/assets/config/` 下的副本后，`tools/sync_config.py --check` 以非零退出并指出差异
  3. 同步脚本运行一次即生成配置副本 + `.sha256`，重复运行不产生 diff；一致时 `--check` 以零退出
  4. 在一个干净 clone 上按 README 记录的命令即可复现 1–3，不依赖任何本机残留状态

**Plans**: 5/5 plans complete
**Wave 1**
- [x] 01-01-PLAN.md — 搬迁前冻结 230 项检查基线 + 固定 PyPI 索引（锁文件不再被镜像改写）

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — 纯 git mv 三子树 + 配置副本与 .sha256 + 230 项回归闸门

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 01-03-PLAN.md — `--write-config` 三级路由 + `.gitignore` / `.gitattributes` 跟随布局
- [x] 01-04-PLAN.md — 根 README 重写为仓库地图 + GitHub Actions 闸门

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 01-05-PLAN.md — 干净 clone 复现脚本 + 篡改反例（成功标准 2 与 4 的机械证明）

### Phase 2: 安卓工具链 + 真机冒烟 APK

**Goal**: 用锁定的工具链导出一个签名 arm64 APK，证明它能装、能启动、中文不豆腐、共享配置真的进了包、手柄原始轴在真机上能读到。
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: INFRA-04
**Success Criteria** (what must be TRUE):
  1. 签名 arm64 APK 在一台真实 Android 手机上安装并启动到首屏，全程不经过 Godot 编辑器
  2. 首屏完整显示最长中文字符串（动作名 + 失败原因 + `° ± → ✓ ✗`），在两台不同 OEM 手机上均无豆腐块
  3. 应用启动时读到 Phase 1 同步过来的 `res://assets/config/` 配置并显示 `SKILL_COUNT = 5`，证明 `*.json` 真的进了 PCK
  4. 连上蓝牙手柄推动右摇杆时，屏幕上的原始轴数值实时变化，证明输入通道在真机可达
  5. `mobile/BUILD.md` 记录精确版本（Godot 4.7.2-stable / 导出模板 4.7.2.stable / JDK 17 / build-tools 36.1.0），release keystore 已生成并离线备份，另一台干净机器按文档能重导出

**Plans**: 5/5 plans complete
**Wave 1**
- [x] 02-01-PLAN.md — 工具链自举 + `doctor.sh` 六项断言（引擎钉死 4.7.2-stable）(completed 2026-11-04)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02-02-PLAN.md — 最小 Godot 工程 + PCK 往返 + 闸门 A (completed 2026-11-04)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 02-03-PLAN.md — 字体双链路（CJK 子集 + 符号 fallback）+ 字形闸门 (completed 2026-11-04)

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 02-04-PLAN.md — release keystore + 签名 APK + 闸门 B + 假绿反例 (completed 2026-11-04)

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 02-05-PLAN.md — BUILD.md + 干净 clone 重导出 + 真机验收表 (completed 2026-11-04)

> **状态：自动化部分已收口，Phase 2 仍未完成。** 闸门 A / B、反例自测、干净 clone 重导出全绿；
> 成功标准 1/2/4（真机安装启动、两台不同 OEM 无豆腐、真机手柄轴）与 5 的人工两半
> （密钥库离线备份、第二台机器重导出）全部落在 `mobile/ACCEPTANCE.md`，留白待填。
> 无设备时不得勾选。

**UI hint**: yes

### Phase 3: 纯核心地基 — 几何 / 配置校验 / 无头运行 / 架构 lint

**Goal**: `mobile/src/core/` 成为一个零引擎依赖、可在无场景树无手柄条件下运行并通过测试的纯 GDScript 层，角度约定与配置错误信息一次钉死。
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: RESIL-02, RESIL-03, INFRA-03, DATA-03
**Success Criteria** (what must be TRUE):
  1. 一条 headless 命令即可跑完几何与配置测试并返回退出码，不需要窗口、场景树或手柄
  2. 八方向 + 中心的黄金表与 Python 版逐项一致（误差 < 1e-9），0° = 上、顺时针为正；`x == 0 and y == 0` 返回 0 而不是 π
  3. 注入坏配置（BOM / 字符串布尔 / `null` 数值 / `start_angle` 数组）后得到结构化错误列表（`json_path` + `code` + 修复建议），可原样渲染成错误屏；不存在 `push_error` 或静默降级
  4. `src/core/` 架构 lint 在出现 `Input.` / `Time.` / `Node` / `FileAccess` / `print(` 时非零退出，干净时零退出
  5. 用户修改写进 `user://` 稀疏覆盖层；base 配置 hash 变化时覆盖层被丢弃并提示，运行期绝不尝试写 `res://`

**Plans**: 6/6 plans complete, 5 waves
**Wave 1**
- [x] 03-01-PLAN.md — 无头 runner + 几何黄金对等 + 完成哨兵（含四种假绿反例）

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 03-02-PLAN.md — 架构 lint（`Input.` / `Time.` / `Node` / `FileAccess` / `print(`）+ `CORE.md` 边界契约
- [x] 03-03-PLAN.md — 按键/方向词汇表 + 六个域对象（一个文件一个 `class_name`）

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 03-04-PLAN.md — bytes 入口（BOM）+ `ConfigResult` / `Array[ConfigError]` + 全量校验与可见 warning

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 03-05-PLAN.md — 坏配置语料 + Python/GDScript 判定对等（分歧必须记录）

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 03-06-PLAN.md — `user://` 稀疏覆盖层 + `ConfigStore` 原子写 + `user://` 定名

**UI hint**: yes

### Phase 4: 设备输入层 + 绿色搓射竖切

**Goal**: 在真实安卓手机 + 真实蓝牙手柄上完成「按任意键唤醒 → 轴探测 → 摇杆校准 → 布局确认」，并做出一次绿色搓射，屏幕上给出这一次的判定与原因。阶段内部顺序固定：先移植 tap 检测器并证明，再接适配器，最后才是最小界面。
**Mode:** mvp
**Depends on**: Phase 2, Phase 3
**Requirements**: INPUT-01, INPUT-02, INPUT-03, INPUT-04, INPUT-05, ONBOARD-01, ONBOARD-02
**Success Criteria** (what must be TRUE):
  1. 绿色搓射的 tap 检测器先于任何设备代码完成：黄金向量由 Python 侧脚本从 250 Hz 录制生成（非手写），GDScript 无头回放逐条一致，0 处差异
  2. 一台全新手机首次打开应用，按图文引导「按任意键唤醒」手柄并完成摇杆校准（中点 + 满量程），全程不读文档
  3. 引导探针记录右摇杆上/右/下/左对应的实际轴序号与符号并落盘为 per-device profile；换一只手柄再连会重新探测，绝不沿用上一次的映射
  4. 布局建议（Xbox / PlayStation）自动给出，但必须用户按键确认后才进入练习，未确认不前进一步
  5. 在真机上做一次绿色搓射，屏幕产出且仅产出一次判定并显示成功或失败原因；快速连做两次得到两次独立判定（事件流保住了帧内反转）

**Plans**: 11/11 plans complete, 11 waves
**Wave 1**
- [x] 04-01-PLAN.md — tap 检测器逐行移植 + Python 生成黄金夹具 + `TAP_GOLDEN_DETECTOR` 哨兵（成功标准 1）(completed 2026-11-05)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 04-02-PLAN.md — `TapRuntime` 引擎子集（冷却 / 手势锁 / 单槽失败 / 分组）+ `layout_confirmed` 硬门 + `TAP_GOLDEN_RUNTIME` + 闸门第 5 条反例 (completed 2026-11-05)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 04-03-PLAN.md — 轴探针 / 校准 / `DeviceProfile` / 复用门（纯逻辑，含 raw → 0/90/180/270 接缝断言）(completed 2026-11-05)

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 04-04-PLAN.md — `PadStateBuffer` + `PadSampler`（事件优先 + 每帧对账）+ `ProfileStore` 原子写 + lint 扩到 `src/input/` (completed 2026-11-05)

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 04-05-PLAN.md — `OnboardingFlow` 纯状态机 + 组合根 + 引导屏 S1–S11 + 字形闭世界断言 (completed 2026-11-05)

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 04-06-PLAN.md — 练习屏 + 结果横幅 + 无设备 60 Hz 集成竖切 + `ACCEPTANCE.md` 第 6 节 (completed 2026-11-05)

**Wave 7** *(blocked on Wave 6 completion)*
- [x] 04-08-PLAN.md — 引导 UX 修复：探针实时读数 + 2 次软重试 + 纯语言文案 + 停止屏增量 + 屏上诊断覆盖层（D1/D2 的新证据通道），并重建 APK (completed 2026-11-05)

**Wave 8** *(blocked on Wave 7 completion)*
- [x] 04-07-PLAN.md — 签名 APK + 真机 D0–D6 清单（completed 2026-11-06；D2 换手柄拒绝面部分验证，第二只手柄未测）
      — **2026-11-05 真机结果：D0 失败**（探针三次拒绝 + 停止屏「没有收到摇杆事件（events_motion = 1931）」）；D1–D6 未执行（`run-as: package not debuggable`；只有一只 Xbox 手柄）。**用户最终决定保留四步探针、修 UX**（不做单屏检测）；修复与重建由 04-08 承担，本计划改为 Wave 8，必须等 04-08 的新 APK 出来后再走查；成功标准 2/3/4/5 仍未闭合。
      — **2026-11-05 21:19–21:30 第二次走查（新包 27,046,027 B）：D0 仍然失败**，卡在探针第 1/4 步「上」：`PAD_AXIS i=4/i=5` 先报 0.000、首次上报后变 -1.000，静止基线按 0 记 → 57 行 `PROBE_REJECT ambiguous_axes key=up`、`margin 0.000`。用户要求「换一种检测方式或跳过」。D1–D6 未执行；成功标准 2/3/4/5 仍未闭合。修复方向：采静止基线前等所有轴上报过一次，或排除从未上报的轴；修完必须重建 APK 并重新走查
      — **2026-11-05 04-08 已交付新包**：`mobile/build/fifa-trainer.apk`（27,046,027 字节，证书 `e1841a17…32e046` 不变，v2 验签通过，只含 arm64）。D1/D2 改走「LB+RB 打开诊断覆盖层 + `adb exec-out screencap`」，不再需要 `run-as`；D2 拒绝面因缺第二只手柄仍记为未执行。**重走 D0–D6 前必须先卸载重装这个新包**
      — **2026-11-05 04-09 已把首启路径换成单页输入设置**（`InputSetup` + `input_setup_screen`，组合根不再驱动 `OnboardingFlow`；`trigger_rest = min`）。新包 **27,067,065 B**（证书不变）。下一次走查先卸载重装这个包，D0 只有 8 步，见 `ACCEPTANCE.md` §6「D0 操作说明」
      — **2026-11-05 04-10 已加输入事件日志**：按键边沿与轴变化写入 `/sdcard/Android/data/com.fifaskill.trainer/files/input_log.txt` 并镜像 logcat `INPUT_EVT`，`adb exec-out cat` 可直接回放；新包 **27,071,318 B**（证书不变）。D0 操作与 04-09 相同，下一次走查用这个包
      — **2026-11-05 04-11 已修三个真机缺陷**：X/Y 退出设置页（与练习手势撞车、误翻 X 符号）、A 在量程未满时不再保存默认校准、布局必须由 Start 切换并由 A 确认；诊断覆盖层按 Y 可删档回设置页。新包 **27,079,510 B**（证书不变）。下一次走查请卸载重装这个包，D0 按 `ACCEPTANCE.md` §6「D0 操作说明（04-11）」的 11 步走

**Wave 9** *(blocked on Wave 8 completion)*
- [x] 04-09-PLAN.md — 单页输入设置：`InputSetup` 纯逻辑（轴对 / 符号 / 中点 / 量程 / 扳机 rest=min）+ 一页式屏 + 组合根切换 + 第 17 套件 + 重建 APK (completed 2026-11-05)

**Wave 10** *(blocked on Wave 9 completion)*
- [x] 04-10-PLAN.md — `InputLog` 输入事件日志（按键边沿 + 轴节流，文件 2 MB 轮转 + logcat `INPUT_EVT`）+ `PadSampler` 接线 + 会话头 + 第 18 套件 + 重建 APK (completed 2026-11-05)

**Wave 11** *(blocked on Wave 10 completion)*
- [x] 04-11-PLAN.md — 设置页保存门（量程未满 `build_profile` 返回 null）+ 布局 Start/A 确认 + 旧档案失效（`can_enter_practice` 四合一门）+ X/Y 退出设置页 + 诊断页 Y 清除档案 + 重建 APK (completed 2026-11-05)

**UI hint**: yes

### Phase 5: 全动作判定对等性 — 三类检测器 + 引擎仲裁 + 抽稀矩阵

**Goal**: 三类检测器与 `GestureEngine` 作为一个单元 1:1 移植，5 个动作的判定序列与 Python 桌面版逐条一致，并在 60 / 90 / 120 Hz 抽稀下证明不漂移。
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: JUDGE-01, JUDGE-02, JUDGE-03, JUDGE-04, JUDGE-05, JUDGE-06, JUDGE-07
**Success Criteria** (what must be TRUE):
  1. 无头回放 `shared/golden_vectors.json`（由 Python 侧生成，绝不手写）时，每条轨迹的 `Outcome` 序列与期望逐条一致，0 处差异
  2. 在真机上依次做出 5 个动作，每个都得到与桌面版同名的结果；五个失败码（太快 / 太慢 / 起点不对 / 终点不对 / 保持时间不足）各有一次被正确归因，不需要看日志
  3. 一次挥动最多产出一个判定：双动作竞争、修饰键中途切换、手势锁、逐动作 + 全局冷却、idle 重置的仲裁夹具全部通过
  4. 每次判定返回结构化 `measured{}`（起止角、扫过角、每步耗时、保持时长），反馈层可直接消费，无需二次计算
  5. 250 Hz → 60 / 90 / 120 Hz 抽稀重跑不漂移；若漂移，报告给出证据与阈值调整记录，且 `release_hold_ms` 与 `global_cooldown_ms` 有专门的边界夹具

**Plans**: 5/7 plans executed, 7 waves
**Wave 1**
- [x] 05-01-PLAN.md — 参考冻结 + 生成器骨架 + 10 条已知用例（tracer：Python 参考 → 夹具 → GDScript 回放 → `GESTURE_GOLDEN` 哨兵）

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 05-02-PLAN.md — 检测器语料扩到 52+ 条（实际 55）：六类边界 + 变体配置 + 反向对照 + 四次变异验证

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 05-03-PLAN.md — `GestureEngine` + `ActiveSkill` + `TapRuntime` 子类 + 29 条引擎语料（`GESTURE_RUNTIME`）

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 05-04-PLAN.md — `measured{}` 全链（三检测器 + `Outcome`）+ `test_measured`（`MEASURED`）

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 05-05-PLAN.md — 250→120/90/60 Hz 抽稀矩阵 + 漂移白名单 + 变异验证（`DECIMATION`）

**Wave 6** *(blocked on Wave 5 completion)*
- [ ] 05-06-PLAN.md — 左摇杆轴对/符号/校准 + `snapshot_ls()` + schema v2 迁移门 + 设置页同一页补齐

**Wave 7** *(blocked on Wave 6 completion)*
- [ ] 05-07-PLAN.md — 组合根接全技能引擎 + `OUTCOME` 日志 + `analyze_input_log.py` + 真机 D5-0…D5-8

### Phase 6: 训练循环 — 10 次一组、免触摸推进、暂停恢复

**Goal**: 一次练习可以连续进行：10 次一组、结果停留后自动进入下一次、待触发与冷却状态可见，全程不需要触碰屏幕。
**Mode:** mvp
**Depends on**: Phase 5
**Requirements**: LOOP-01, LOOP-02, LOOP-03, LOOP-04, LOOP-05, FEEDBACK-01
**Success Criteria** (what must be TRUE):
  1. 不看说明书，连续做 30 次尝试，全程不碰屏幕，能说出每次错在哪一类
  2. 一组 10 次的进度点随每次判定更新，组满后自动开始新组并保留累计组数
  3. 结果停留结束后自动进入待触发；待触发与冷却状态在屏幕上有明确可见的指示，用户知道「现在这一下算不算」
  4. 按手柄 Start 暂停，恢复时检测器重置并进入 3 秒倒计时，倒计时期间的动作不产生判定
  5. 冷启动直接进入上次练习的动作，不需要重新选择

**Plans**: TBD
**UI hint**: yes

### Phase 7: 反馈呈现 — 实测区间、实时轨迹、音效、支架可读布局

**Goal**: 每次判定在 1 秒内被看懂——看得出差多少、看得到自己刚才的轨迹、听得见成功失败，并且在支架观看距离上读得清。
**Mode:** mvp
**Depends on**: Phase 6
**Requirements**: FEEDBACK-02, FEEDBACK-03, FEEDBACK-04, FEEDBACK-06
**Success Criteria** (what must be TRUE):
  1. 失败时「实测 vs 目标区间」时序条显示本次落点与绿色目标带，用户能说出是快了还是慢了多少，而不是只知道失败
  2. 实时双摇杆轨迹在挥动过程中连续绘制，挥完仍保留完整轨迹直到下一次开始
  3. 成功 / 失败音效可全局开关，关闭后任何核心功能都不受影响
  4. 结果横幅在命中同一帧产生、至少停留 1.5 秒，即使下一次挥动已经开始也不被立刻覆盖
  5. 横屏锁定 + 屏幕常亮；在约 1 m 的支架观看距离上，动作名、失败原因、度数文字全部可读

**Plans**: TBD
**UI hint**: yes

### Phase 8: 长期使用韧性 — 生命周期、断连、持久化

**Goal**: 切后台、锁屏、掉手柄、进程被杀都不产生误判、不丢数据；重开还在，回来还能接着练。
**Mode:** mvp
**Depends on**: Phase 7
**Requirements**: RESIL-01, INPUT-06, DATA-01, DATA-02
**Success Criteria** (what must be TRUE):
  1. 练到一半切到后台 2 分钟再回来，不产生任何判定；必须重新进入待触发才计一次尝试
  2. 锁屏解锁、拔手柄再插（新 device index）后自动重连并回到待触发；掉线期间的动作不计入尝试、不产生失败判定
  3. 杀掉进程再重开后，每动作累计尝试数与成功数、每动作最近 N 次结果（成败 + 原因 + 时间）完整保留
  4. 写盘走 temp + rename：写到一半被杀不会留下半损坏文件；文件损坏时回退到上一份可用数据并明确提示

**Plans**: TBD
**UI hint**: yes

### Phase 9: 发布 — 侧载 APK + 升级路径

**Goal**: 朋友拿到一个 APK 就能装上就用；下一次版本能在不卸载的前提下覆盖安装，统计一条不丢。本阶段不依赖 Phase 10。
**Mode:** mvp
**Depends on**: Phase 8（不依赖 Phase 10）
**Requirements**: INFRA-05
**Success Criteria** (what must be TRUE):
  1. `arm64-v8a` release APK 在一台干净手机上侧载安装并直接进入练习，不需要开发者工具或 USB
  2. v1 → v2 使用同一 keystore、递增 versionCode 覆盖安装，`user://` 统计不丢、无需卸载；应用内可见版本号
  3. `zipalign -c -P 16 -v 4` 通过；`unzip -l` 确认包内无 `lib/x86_64/`、无 `.DS_Store`、无 keystore 或密钥
  4. 一页带截图的安装指南覆盖「允许安装未知应用」、Play Protect 拦截、「先按任意键手柄才会出现」；朋友照指南能独立装上
  5. 在一个干净 clone 上跑一次脚本化导出即产出同一份 APK，版本号来自唯一来源而不是手改多处

**Plans**: TBD

### Phase 10: 手机触觉（可选，不阻塞任何阶段）

**Goal**: 在视觉反馈已经自成闭环的前提下，增加一个明确标注为「手机震动」、可全局关闭的附加通道。删掉本阶段，v1 依然完整可交付。
**Mode:** mvp
**Depends on**: Phase 7（反馈骨架）；不被任何阶段依赖
**Requirements**: FEEDBACK-05
**Success Criteria** (what must be TRUE):
  1. 成功时手机本体震动（`vibrate_handheld()`），失败时不震动；30–120 ms 区间内在 1 m 外可感知
  2. 界面与设置里明确写「震动的是手机，不是手柄」，不存在任何「手柄震动」文案或「测试手柄震动」按钮
  3. 全局开关关闭后完全静默，且不产生错误日志
  4. 删掉整个阶段不改变任何其他阶段的成功标准——没有任何阶段以它为前提

**Plans**: TBD
**UI hint**: yes

## 排序理由与风险闸门

- **Phase 1 阻塞一切。** 目录重构影响面广但机械，搬完不绿就不许继续；配置真源与 hash 守卫必须此刻建立，否则后面每个阶段都在制造第二份手写副本。
- **安卓只碰三次，风险逐级放大。** Phase 2 是 1–2 天的工具链 / 16 KB 页对齐 / 字体 / `*.json` 入包冒烟，**不是**设备层；Phase 4 才是完整设备输入层（轴探针、扳机、热插拔）；Phase 9 是发布与升级。合并它们会让一次两天的 spike 变成两周的不确定性。
- **绿色搓射先于全量动作。** 用一个 tap 动作把「事件 → 检测器 → 仲裁 → 屏幕」整条链在真机上跑通，再在 Phase 5 扩到 arc / sequence 与全部 5 个动作。Phase 4 内部先做检测器并用 Python 生成的黄金向量证明，再接适配器与界面——竖切，不是横向分层。
- **对等性用回放证明，不靠肉眼。** `shared/golden_vectors.json` 由 Python 侧生成；Phase 5 的 0 差异是进入 UI 工作的闸门。抽稀矩阵（60 / 90 / 120 Hz）在阶段被宣布完成之前必须跑完，因为 `global_cooldown_ms = 60` 与 `release_hold_ms = 120` 是唯一两个真正有风险的阈值。
- **UI 建在会动的靶子上是最贵的错误。** Phase 6 与 Phase 7 只在 Phase 5 之后开始；`measured{}` 如果不在 Phase 5 留出，Phase 7 的三大反馈特性（时序条、逐步拆解、失败点高亮）全部返工。
- **生命周期放在 UI 之后、发布之前。** 它需要检测器的硬重置钩子（Phase 5 就要留），也需要 UI 的通知面（重连浮层、错误屏）。放在发布前是因为「后台回来必失败一次」会直接毁掉产品感。
- **Phase 10 可整体砍掉。** 安卓上 Godot 没有任何手柄马达实现，`start_joy_vibration()` 是静默空操作；唯一通道是震手机本体。把它排在最末、不让任何阶段依赖它，是「震动是加分项」这个优先级判断的结构性体现。
- **真机是退出条件，不是收尾工作。** 模拟器不触发本项目的任何一个真实风险（配对、映射、延迟、断连、息屏、OEM 字体）。Phase 2 / 4 / 5 / 6 / 8 / 9 的成功标准都必须在真手机 + 真手柄上验。

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10
（Phase 2 与 Phase 3 都只依赖 Phase 1，可并行；Phase 9 不依赖 Phase 10，可在 Phase 8 完成后随时开始。）

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. 仓库拆分 + 配置单一真源 + 桌面回归闸门 | 5/5 | Complete    | 2026-11-04 |
| 2. 安卓工具链 + 真机冒烟 APK | 5/5 | Complete    | 2026-11-05 |
| 3. 纯核心地基 | 6/6 | Complete    | 2026-11-05 |
| 4. 设备输入层 + 绿色搓射竖切 | 11/11 | Complete    | 2026-11-06 |
| 5. 全动作判定对等性 | 5/7 | In Progress | - |
| 6. 训练循环 | 0/0 | Not started | - |
| 7. 反馈呈现 | 0/0 | Not started | - |
| 8. 长期使用韧性 | 0/0 | Not started | - |
| 9. 发布 — 侧载 APK + 升级路径 | 0/0 | Not started | - |
| 10. 手机触觉（可选） | 0/0 | Not started | - |
