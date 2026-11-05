---
gsd_state_version: "1.0"
current_phase: 5
current_phase_name: 全动作判定对等性 — 三类检测器 + 引擎仲裁 + 抽稀矩阵
current_plan: 5
status: executing
stopped_at: Completed 05-04-PLAN.md
last_updated: "2026-11-05T20:21:47.000Z"
last_activity: 2026-11-06
last_activity_desc: Phase 5 plan 04 complete — measured{} 全链 + 12 组断言 + 三次变异验证
state_head: 06b5a21c78f70a5e682a64dbdb86bd636acbce97
progress:
  total_phases: 10
  completed_phases: 4
  total_plans: 34
  completed_plans: 30
  percent: 40
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-04)

**Core value:** 用真手柄、在任何地方都能练，判定准、反馈看得懂。
**Current focus:** Phase 5 — 全动作判定对等性 — 三类检测器 + 引擎仲裁 + 抽稀矩阵

## Current Position

Current Plan: 5
Total Plans in Phase: 7
Phase: 5 (全动作判定对等性 — 三类检测器 + 引擎仲裁 + 抽稀矩阵) — EXECUTING
Plan: 5 of 7
Status: Executing Phase 5
Last activity: 2026-11-06 — 05-04 完成：measured{} 全链（三检测器 + Outcome）+ 12 组断言 + 三次变异验证

Progress: [████░░░░░░] 40%

## Performance Metrics

**Velocity:**
- Total plans completed: 30
- Average duration: — min
- Total execution time: 2.8 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 5 | - | - |
| 2 | 5 | - | - |
| 3 | 6 | - | - |
| 4 | 11 | - | - |
| 5 | 4 | - | - |

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
| Phase 2 P01 | 9min | 2 tasks | 1 file |
| Phase 2 P02 | 3min | 2 tasks | 9 files |
| Phase 2 P03 | 4min | 3 tasks | 12 files |
| Phase 2 P04 | 13min | 3 tasks | 4 files |
| Phase 2 P05 | 8min | 3 tasks | 6 files |
| Phase 3 P01 | 13min | 2 tasks | 13 files |
| Phase 3 P02 | 4min | 2 tasks | 5 files |
| Phase 3 P03 | 5min | 3 tasks | 21 files |
| Phase 3 P04 | 7min | 3 tasks | 13 files |
| Phase 3 P05 | 4min | 3 tasks | 6 files |
| Phase 3 P06 | 3min | 3 tasks | 12 files |
| Phase 4 P01 | 5min | 2 tasks | 16 files |
| Phase 4 P02 | 10min | 3 tasks | 12 files |
| Phase 4 P03 | 22min | 2 tasks | 11 files |
| Phase 4 P04 | 13min | 3 tasks | 18 files |
| Phase 4 P05 | 15min | 3 tasks | 17 files |
| Phase 4 P06 | 9min | 3 tasks | 16 files |
| Phase 4 P08 | 34min | 5 tasks | 15 files |
| Phase 4 P09 | 21min | 3 tasks | 14 files |
| Phase 4 P10 | 13min | 2 tasks | 9 files |
| Phase 4 P11 | 18min | 2 tasks | 16 files |
| Phase 5 P01 | 14min | 3 tasks | 16 files |
| Phase 5 P02 | 13min | 3 tasks | 4 files |
| Phase 5 P03 | 43min | 3 tasks | 12 files |
| Phase 5 P04 | 39min | 3 tasks | 12 files |

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
- [Phase 2]: `4.7.2.stable.` 只允许在 `mobile/tools/doctor.sh` 的 `readonly GODOT_VERSION_PREFIX` 定义一次；其它脚本一律调 `doctor.sh <断言名>`
- [Phase 2]: Godot 装仓库外 `$HOME/Applications/Godot-4.7.2.app`（官方 zip + SHA-512 `38aa16e5…b7ac69ca`），170 MB 二进制永不进 git
- [Phase 2]: `doctor.sh` 的 jdk 断言显式解析 JDK 17（JAVA_HOME 若不是 17 则退到 `~/.sdkman/candidates/java/17.0.12-oracle`），系统默认 JDK 25 一概不动
- [Phase 2]: 留空只跑 godot/template/jdk/sdk/keystore 五项构建断言；`device` 只在点名时运行且 0 台 fail-visible
- [Phase 2]: keystore 口令只从 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 读、只经 `keytool -storepass:env` 传给 keytool；输出只出现变量名
- [Phase 2]: bash 3.2 的 UTF-8 解析缺陷：变量紧邻全角标点必须写 `${VAR}`，否则变量名会吞掉半个汉字
- [Phase 2]: 闸门 A 第一步必须是 `sync_config.py --check`：副本被手改时 PCK 闸门照样能解析出 5 条动作并报绿（假绿）
- [Phase 2]: `--main-pack` 一律不带 `--path`：带 `--path` 时 `res://` 指回工程目录，读到源码而不是导出物
- [Phase 2]: `EXPECTED_SKILLS := 5` 硬编码并带注释；禁止改成「读到几条算几条」，否则断言永远绿（与 `BASELINE_SHA256` 同构）
- [Phase 2]: 首屏 `-1.000` 用 ASCII 连字符 U+002D，不用数学减号 U+2212（后者不在字形清单里，会造成字体闸门假绿）
- [Phase 2]: `*.gd.uid` 导入边车是提交物，不进 `.gitignore`；只有 `mobile/.godot/` 与 `mobile/build/` 是忽略物
- [Phase 2]: `project.godot` 的 `[gui] theme/custom_font` 留给 02-03 补：字体资产届时才存在
- [Phase 2]: 闸门 A 不接 GitHub Actions，CI 打发布包的决策归 Phase 9（本计划 `<objective>` 的范围裁定）
- [Phase 2]: 字形清单整文件扫描（含注释）→ 810 个字符；代价是子集大几十 KB，换来「往首屏加中文不必记得改常量」，cmap 交叉核对 810/810 有覆盖
- [Phase 2]: `make_font_subset.py` 纯标准库，`fonttools==4.60.2` 只出现在 `uv run --with` 子进程里；`--check` 只读比对「清单 vs 源文件」
- [Phase 2]: 闸门分层不可合并：`glyph_coverage.gd` 只看「清单 vs 子集」，源文件新增字符而清单未重生成时只有 `make_font_subset.py --check` 能抓住
- [Phase 2]: 关闭系统兜底要逐层遍历 FontVariation 的 base_font 与每个 fallbacks 条目；`if font is FontFile` 对顶层资源永远不成立
- [Phase 2]: 字形闸门额外断言 `ThemeDB.fallback_font.resource_path == AppFont.tres`：只造一个没人引用的 .tres 也能让 has_char 全绿
- [Phase 2]: `*.ttf.import` 与 `glyph_coverage.gd.uid` 是提交物；`git check-ignore` 对三个路径必须非零
- [Phase 2]: `rm -f` 必须先于 `--export-release`：导出器先写包后签名，缺 keystore 会留下大小正常的未签名 APK（P3），任何「文件存在即成功」的判据都是假的
- [Phase 2]: 验签一律用 `apksigner verify --verbose --print-certs`：只加 `--print-certs` 时 apksigner 0.9 不输出 `Verified using …` 行，v2 断言会永远红
- [Phase 2]: 闸门 B 只有一个必填输入（口令，`${VAR:?}` + export）；密钥库路径与别名由 `FIFA_KEYSTORE` / `FIFA_KEYSTORE_ALIAS` 解析出与 doctor.sh 逐字相同的默认值
- [Phase 2]: 口令守卫放在 doctor 之前：doctor 的 keystore 断言读同一个变量，放后面会先撞 doctor 的报错，误导成「密钥库坏了」
- [Phase 2]: 反例的 canary 必须用「上游一次产出固定字节 + 下游读到底」（`od -An -N12`）：无限产出 + 按字节截断的管道在 pipefail 下会 SIGPIPE 让反例脚本自己死掉
- [Phase 2]: 签名身份定死：包名 `com.fifaskill.trainer`、别名 `fifa-trainer`、`versionCode=1` / `versionName=0.1.0`；证书 SHA-256 `E1:84:1A:17:…:E0:46` 是 Phase 9 覆盖安装的可核对指纹
- [Phase 2]: `BUILD.md` 只给入口不给断言：版本前缀 / SHA-512 / 密钥库默认值全在 `doctor.sh`，导出与四段校验全在 `gate-b.sh`，文档里再抄一份就是第二份会漂移的规范
- [Phase 2]: `verify_clean_export.sh` 的入口守卫只判 `--untracked-files=no`（clone 只复制提交，未跟踪文件只能让 clone 失败，不可能让它假绿），clone 内的零漂移断言仍判全量 —— 两个范围不同是刻意的，注释里写明理由
- [Phase 2]: 五个 Godot 边车在跑闸门**之前**逐个 `ls-files --error-unmatch` 点名：跑完再发现只会得到一条 `??`，读者的第一反应会去改 `.gitignore` 而不是补提交
- [Phase 2]: `device-smoke.sh` 的工具缺失 / 无设备 / 装不上 / 起不来 / 5 秒内退出 / 空截图全部走同一条 `DEVICE_SMOKE_FAIL` 出口；`if ! pid=` 只出现一处，其余可能失败的赋值同样落在 `if` 里
- [Phase 2]: `ACCEPTANCE.md` 明写动作名是**机械覆盖**（`make_font_subset.py` → `required_glyphs.txt` → `glyph_coverage.gd`）：首屏只显示 `SKILL_COUNT = 5`，不逐条列五个动作名，不写清会被当成成功标准 2 少测一半
- [Phase 2]: Phase 2 的自动化部分收口，但 ROADMAP 的 Phase 2 复选框与 `INFRA-04` 都**不勾**：成功标准 1/2/4 需要两台不同 OEM + 真手柄，5 的两半需要人工备份与第二台机器；无设备时声称通过就是伪造信任点
- [Phase 3]: 几何黄金夹具放 `mobile/tests/fixtures/` 而非 `shared/`：唯一消费者是 GDScript 测试，Python 侧只是生成器；放 shared 等于给生成物再造一份要同步的副本
- [Phase 3]: `signed_delta` 固化 `[-180, 180)`（`signed_delta(0,180) == -180`）；黄金向量 + 精确断言一起钉死端点，禁止按 Python 文档字符串「修正」成 +180
- [Phase 3]: 核心闸门的唯一判据是 `^TESTS_DONE failures=0$` + `^TESTS_ASSERTIONS=0$` 拦截 + 看门狗；退出码 0 永不单独作判据，也刻意不加 `--check-only`（对解析错误同样返回 0）
- [Phase 3]: `core_runner.gd` 用内嵌 Reporter + 显式 `preload` 字典；不许改成运行时扫描目录（目录消失会「零套件、零失败」地绿），套件必须 `complete()`
- [Phase 3]: 闸门反例 stub 必须按 `--script` 参数分支：导入步骤没有看门狗，挂死型 stub 若对导入也 sleep 会先挂死自测脚本
- [Phase 3]: 看门狗子 shell 必须把 stdout/stderr 重定向到 /dev/null：否则 `test-core.sh | tail` / `$(...)` 会一直等到 sleep 睡满才 EOF，闸门自己变成「永远等下去」
- [Phase 3]: 架构 lint 用两档剥离：`strip_code` 剥注释+字符串（INFRA-03 五条硬规则），`strip_comments` 只剥注释（仅 `outer_layer_dep`）；字符串被空格化后依赖路径规则永远不可能命中
- [Phase 3]: lint 目标不存在或零个 `.gd` 一律 rc=2 + `LINT_INVALID`：路径写错时返回 0 等于自动通过
- [Phase 3]: lint 反例自测必须先于真扫描：写坏的规则会以「干净通过」保护一切；步骤横幅带脚本名，让「先于 Godot」可被 grep 机械验证
- [Phase 3]: lint 只扫 `mobile/src/core`；`tests/` 允许 print/printerr，不把测试的日志需求当边界违规
- [Phase 3]: 词汇表条目数即契约：`CANONICAL` 17 / `BUTTON_ALIASES` 39 / `DIRECTION_ALIASES` 42，`size()` 断言先于行为断言，增删必须同时改 `test_vocabulary.gd`
- [Phase 3]: 词汇表失败值是空串 / null，不是异常也不是原样返回；错误文本与 `json_path` 一律由校验层拼（core 零异常零日志）
- [Phase 3]: 字符串 `"-90"` 的负号按分隔符剥掉（与 Python 逐字一致）得 90.0，要 270° 必须写数字 `-90`；该既有语义被显式钉死，改成保留负号会让两端相差 180°
- [Phase 3]: 六个域对象一个文件一个 `class_name`：塞进一个文件只能退化成内嵌类，`Array[Skill]` / `Array[Pulse]` 直接编译不过
- [Phase 3]: 域对象零校验零日志（只有字段与 `_init`）；`Skill.pattern` 默认一条 `Pulse`（对应 Python 的 `(Pulse(),)`），不是空数组
- [Phase 3]: `InputConfig.axis_layout` / `button_names` 用 `Variant = null`：`null`（自动推断）与 `{}`（手动但为空）语义不同，禁止用空字典代替
- [Phase 3]: `AppConfig` 不移植 `path` 字段：Godot 无 pathlib，来源路径归 `ConfigResult.source_path`，域对象不记录 I/O 痕迹
- [Phase 3]: 配置入口只收 `PackedByteArray`，BOM 必须在解码前按 `bytes[0] == 0xEF` 判定；`get_file_as_string` 会剥 BOM，`JSON.parse_string` 会向 stderr 打 ERROR 且不给行号
- [Phase 3]: 每条 `ConfigError` 自带 `json_path` + `code` + 中文 `message` + 中文 `fix_hint`；`fix_hint` 为空视为缺陷，两套套件各有一条遍历断言
- [Phase 3]: `required_button: null` 是合法的「不需要修饰键」（真实配置 3/5 条这样写），绝不能被当成 `button_unknown`
- [Phase 3]: `params.direction` 在移动端严格化到七种写法；Python 的静默落 `any` 不再保留，未知值启动前报 `direction_unknown`，分歧由 03-05 语料记录
- [Phase 3]: `start_angle` 数组在校验期就报 `start_angle_not_scalar`，不留到 `ArcDetector` 构造才崩
- [Phase 3]: clamp 上界逐字照 Python 且不统一：`calibration_ms` 0~3000、`idle_reset_ms` / `gesture_release_ms` 0~5000；统一会让 4000 在两端表现不同且语料永远发现不了
- [Phase 3]: 静默 clamp 一律降级为 `SEVERITY_WARNING` 并带实际值与截断值；`deadzone` 这类不可截断的越界仍是 error
- [Phase 3]: `type` 非法只跳过专项子树，技能级字段继续查；收集式校验保证一个坏字段不会让其余错误消失
- [Phase 3]: 跨语言语料是唯一契约：同一份 JSON 用例被 GDScript 与 Python 各判一次，期望值只存在语料里，两侧都不许有第二份
- [Phase 3]: 故意分歧必须带非空 `divergence` + `python.note`；判定一致却还留着 divergence 也判红（记录已过时才需要删除）
- [Phase 3]: Python 侧基线只走 `json.loads(text)`；先 encode 再交给 json.loads 会按 `utf-8-sig` 接受 BOM，把基线本身弄错
- [Phase 3]: 对 `python: accept` 的用例再跑 `build_detector()`：`start_angle` 数组这类「parse 通过、构造检测器才崩」的晚失败只有这里抓得到
- [Phase 3]: 语料下限双层：`>= 4` 钉四个点名用例，`>= 16` 防「删掉大半语料仍通过」；唯一 id 断言让失败定位不失效
- [Phase 3]: `button_mode_invalid` 必须带 `required_button`：Python 在 required_button 为 None 时提前返回，根本不看 button_mode
- [Phase 3]: `user://` 目录名在任何用户数据产生之前定死为 `FifaSkillTrainer`（`use_custom_user_dir` + `custom_user_dir_name`）；发布后再改等于丢数据，Phase 9 覆盖安装依赖它不变
- [Phase 3]: 覆盖层以 skill name 为键，只允许 `enabled` / `required_button` / `button_mode`；`params` 阈值永不覆盖，改了历史统计就不可比
- [Phase 3]: 覆盖层的 schema / base 摘要 / 结构问题一律整体丢弃，不部分保留；丢弃后立刻删除 `overrides.json`，同一条提示最多打扰一次
- [Phase 3]: base 摘要取当前 base 文件字节的 `FileAccess.get_sha256`，不读可能过期或被手改的 `.sha256` 边车；比较忽略大小写
- [Phase 3]: 覆盖层写入必须 temp → flush → close → rename；rename 失败清理临时文件，成功后 `.tmp` 必须不存在
- [Phase 3]: `load_config` 必须把 `merged.warnings` 追加进 `ConfigResult`：纯合并测试全绿而生产路径丢 warning 是本次明确防的假绿
- [Phase 3]: 配置读盘先取长度再分配缓冲：超过 1 MiB 在内存分配之前拒绝；仍然按字节读，BOM 不会被 `get_file_as_string()` 静默剥掉
- [Phase 3]: `save_overrides` 只接受 `user://` 目标与临时路径；`res://` 与绝对路径一律 `ERR_UNAUTHORIZED`，且不创建目录或文件
- [Phase 4]: `Frame.now` 用秒、`buttons` 用 canonical 名 → true 的 Dictionary；与参考实现 `(now - t0) * 1000.0` 和 frozenset 语义逐字对齐
- [Phase 4]: tap 黄金夹具只能是 `tools/gen_tap_golden.py` 的产物；生成器直接跑 `desktop/padskills/detectors.py`，`--check` 逐字节比对且绝不写盘
- [Phase 4]: 回放必须复刻引擎分支：修饰键不满足时 `observe()` 然后 `reset()`（顺序不能反），否则 `hold_short` 一条都不会出现
- [Phase 4]: `reset()` 产 `hold_short`、`abandon()` 静默，两者不可合并；`abandon()` 最后一行按 `_prev_pressed` 重算 `_armed`
- [Phase 4]: 4ms 网格上取不到 450ms / 750ms：`det_success_mid_450` 用 448、`det_too_slow_boundary_750` 尾巴停在 748；超时严格大于由 752 的用例证明
- [Phase 4]: `elapsed_ms` 的整性判据用 1e-6 容差 + `round()`，不用 `float.is_integer()`：`(548/1000 - 100/1000)*1000` 会带 1e-13 噪声
- [Phase 4]: 正向哨兵 `TAP_GOLDEN_DETECTOR cases=N mismatches=0` 必须打印在 `r.complete()` 之前；`cases` 是实际回放的 detector 条数，`mismatches` 只统计真实比较差异
- [Phase 4]: `layout_confirmed == false` 是 `TapRuntime.tick()` 的第一早退（在手势锁之前）；撤销确认调 `abandon()` 静默清场，断连不产 `too_slow` / `hold_short`
- [Phase 4]: 结果用 `Array[Outcome]` 队列 + `pop_outcomes()` 全量 drain + 单调 `seq`；Python 的 `last_outcome` 会吞掉同帧第一条
- [Phase 4]: 逐动作冷却吞掉时静默、全局冷却吞掉时 `suppressed += 1`；两个分支各有一条可达时序（900ms / 1000ms 合成运行时），不互相冒充
- [Phase 4]: 运行时 counters 只从唯一的 `kind == "taps"` ActiveSkill 读；真实配置把绿色搓射排在最后，按 `skills[0]` 取永远是 0
- [Phase 4]: 结构断言必须展开成逐帧 4ms 时间轴；稀疏变化点会让手势锁 / 重新武装的计时器永远等不到阈值
- [Phase 4]: 新增的反向断言都要做一次变异验证（删锁 / 删门 / 改 suppressed），证明它真的会因为缺陷变红，而不是真空绿
- [Phase 4]: `TAP_GOLDEN_RUNTIME cases=6 mismatches=0` 与 `TAP_GOLDEN_DETECTOR` 并列做正向哨兵；第 5 条反例 fixture_missing 用 sha256 证明夹具原样还原
- [Phase 4]: 轴映射的索引与符号分成两个字段：`-1` 既是合法符号又是未映射哨兵，合并成「带符号索引」后无法区分
- [Phase 4]: 校准在原始轴空间测量（`raw_rs` 不乘符号），符号只在 `normalize` 的最后一步施加；顺序是「先减中点 → 再除量程 → 最后乘符号」
- [Phase 4]: 死区逐字移植桌面 `_deadzone`：`scaled = minf(1.0, …)` 让输出长度恒等于 `scaled` ≤ 1.0，斜向 (1,1) 是 (0.7071, 0.7071) 而不是 1.41
- [Phase 4]: 探针的 `rs_y` 只能来自「向下」步，禁止用「向上取反」推导；上下接线反了必须被 `validate_cross` 在探针阶段抓住
- [Phase 4]: `evaluate_step` 返回有符号 `delta`；`validate_cross` 只消费 `axis/sign/separation`，不重算 —— 两边各写一份键名会在 `_check_evaluate_feeds_cross` 立刻变红
- [Phase 4]: `low_separation`（separation < 3.0）是唯一且可达的 warning；`weak_step` 不可达，不写
- [Phase 5]: 手势黄金夹具放 `mobile/tests/fixtures/gesture_golden.json` 而非 ROADMAP 写的 `shared/golden_vectors.json`：唯一消费者是 Godot，`shared/` 在 `res://` 之外读不到
- [Phase 5]: 夹具的 `configs` 注册表存**完整**配置对象，每个用例只认 `configs[case.config]`；回放套件禁止回落到 `res://assets/config/` 的出厂副本，生成器用 `is` 身份比较确认
- [Phase 5]: 检测器一律 `build_detector(skill)` / `DetectorFactory.build(skill)` 按 `skill.kind` 分派；生成器断言类名，套件用 2 arc / 2 sequence / 1 taps 三条点名检查兜底
- [Phase 5]: `direction_name()` 的数字回落分支在参考实现里不可达（八向间隔 45°，最近卡点恒 ≤ 22.5°）；保留为死分支以维持逐行对等，`30°` 的真实结果是「前右」
- [Phase 5]: `_assert_not_rounding_cliff` 在 `update()` 之前预演会被 `%.0f` 格式化的 `swept` / `end_rel`；踩单车语料因此选 0.72°/帧（500ms），避开 4.5° 刀口
- [Phase 5]: 失败码只写数学可达的配置：油炸丸子不写 `too_fast`；`overshoot` / `wrong_direction` 出厂配置不可达，留给变体配置用例
- [Phase 5]: 边界用例的刀口必须放在最后一帧：参考实现「进入终点窗口就成功」，中途满足会提前命中，测到的是窗口入口而不是边界
- [Phase 5]: 时长边界从检测器 `t0`（推过 enter 的那一帧）起算；夹具 `end_ms` = 边界时长 + 100ms 起手延迟
- [Phase 5]: 逆时针 sweep 必须写负的 `angle_to`（线性插值 + `norm_deg`）；写 325 会变成顺时针 271°，这是生成器层面最先暴露的坑
- [Phase 5]: 变体只改一个维度：顶层 `relative_to_ls` 或 `params` 的单个键；反向对照两条用例引用同一个 `segments` 常量与同一份 `ls`
- [Phase 5]: 变异验证用临时目录 `cp` 还原，不用 `git checkout --`；变异 3 的字面目标 `reset()` 在 arc 回放路径不可达，实际机制是回中分支的 rearm 赋值
- [Phase 4]: 复用门只比较实测的四个 index+sign；`calibration.center/scale` 与探针 `rest` 不参与，同名不同映射必须 `can_reuse() == false`
- [Phase 4]: `DeviceProfile.from_dict` 任一字段非法 → null + ConfigError，整份丢弃绝不部分恢复；`profile_id` 固定 "primary" 但字段与序列化必须存在
- [Phase 4]: `suggest_layout` 认不出设备名返回空，调用方必须让用户二选一；绝不预选 Xbox
- [Phase 4]: 不存设备序号 —— `get_connected_joypads()` 的顺序重启后不保证一致
- [Phase 4]: `PadStateBuffer` 是唯一状态写入点：`apply_event` 与 `reconcile` 共用 `_set_button`，状态一致时不产边沿；两条通道写同一份状态因此天然幂等
- [Phase 4]: 轴值只来自 `InputEventJoypadMotion`；`events_motion == 0` 是显式 D0 停止条件，不得在设备层加轮询轴回退（INPUT-05）
- [Phase 4]: `bind_device(同一设备)` 返回 false 且不碰状态/计数器；组合根的初始 emit + 主动播种不得把一次按下变成两次边沿
- [Phase 4]: `ProfileStore` 任一条目 schema 非法即整份丢弃并删文件；`res://` 返回 `ERR_UNAUTHORIZED`；超 1 MiB 用 `ERR_INVALID_DATA` 在分配前拒绝
- [Phase 4]: 本阶段修饰键只有 `RB`；`LT`/`RT` 是轴，`pressed_dict()` 不合成，RT 分支等 Phase 5 扳机归一
- [Phase 4]: lint 的 `outer_layer_dep` 扩到 `src/input/`；轴枚举常量零出现断言排在导入之前，反例 `joy_axis_canary` 证明它在几秒内变红
- [Phase 4]: `OnboardingFlow` 不设 config_error 状态：配置错误发生在状态机构造之前，永远到不了的状态等于假路径；错误屏归 `main.gd`
- [Phase 4]: rest 是四步探针的硬前置：`begin_probe` 只到 `probe_rest`，没有基线时 `submit_probe_step` 直接返回
- [Phase 4]: 探针失败保留已完成步骤，retry 只回退出错那一步；交叉校验失败按 code 指向 RIGHT/DOWN/LEFT/UP
- [Phase 4]: 复用门四项 index+sign 全等才整份采用，失配即整份丢弃；复用成功后 `chosen_layout` 仍清空，必须按键确认布局
- [Phase 4]: 空布局时 `confirm_layout` 与 `accept_layout_anyway` 都留在布局页；绝不静默按 Xbox 进练习
- [Phase 4]: 组合根先 connect 再 add_child，随后主动播种；同一设备的重复列表不重绑、不重放边沿
- [Phase 4]: `Frame.now` 是秒，`PadSampler` 的事件时间戳是毫秒；两类时间量在文件边界分开，组合根不做换算
- [Phase 4]: 字形闭世界：`src/ui` 下任何未登记的 `.gd`/`.tscn` 让 `make_font_subset.py --check` 直接失败（断言挂在 `collect_chars()` 第一句）
- [Phase 4]: 引导屏的 D0 停止条件只在采样窗口仍为空（确实在等推杆）时触发，避免把「设备静止时不发事件」误判成失败
- [Phase 4]: 结果呈现的唯一通路是 `pop_outcomes()` 全量 drain → `result_banner.show_outcome`；去重谓词是静态纯函数 `accepts(shown_seq, seq) = seq > shown_seq`
- [Phase 4]: 进入练习必须同时置 `%Practice` 容器与练习屏节点可见：`practice_screen._process` 第一句 `if not visible: return` 会把其余一切静默挡在屏幕外
- [Phase 4]: 布局三支文案由注入值决定；空布局是错误态（「布局未确认，请返回引导重选」），绝不回退 Xbox 键名
- [Phase 4]: `%DebugPanel` 纯 ASCII 单行，与 `%LiveMs` / `%SuccessCount` 共用 10 Hz 节流且只在变化时赋值；D5/D6 另有 1 Hz `PAD_DIAG` / `PAD_AXIS` / `PAD_DEV`
- [Phase 4]: 字形闭世界两条边：`src/ui` 目录自动枚举 + `RENDER_SOURCES` 点名会渲染的 core 文案；清单 876 → 992 字符
- [Phase 4]: `AppFont.tres` 显式 `variation_opentype wght=400`（UI-SPEC G11）；不改 cmap、不影响 `GLYPH_OK`
- [Phase 4]: `test_green_slice` 用真实配置字节与 60 Hz 合成轴，七段各自新建运行时；不在测试里复刻 `select_taps_skill` 的筛选循环
- [Phase 4]: 真机 D0 失败：探针连续拒绝（两轴同时动了 margin 0.001；上与右落在同一根轴 2/2；上下没有互为反号 上轴2符号-1/下轴3符号1），并在 20:15:50 出现停止屏「没有收到摇杆事件（events_motion = 1931）」；同一时段 `PAD_DIAG ev_m=2633`，停止屏文案与日志自相矛盾，是待修缺陷
- [Phase 4]: release APK 不可调试：`adb shell run-as com.fifaskill.trainer ...` 返回 `run-as: package not debuggable`；D1/D2 的 `controllers.json` 读取与改写通道不存在，后续计划必须换证据出口或出 debuggable 构建
- [Phase 4]: 用户否决多步引导，要求改成单屏输入检测：一屏显示所有按键与摇杆，无状态机、无第一步/第二步顺序依赖，按/推哪个就亮哪个，识别错了由用户指出；这是 Rule 4 架构变更，04-07 未实施，需重新规划与重建
- [Phase 4]: 用户 2026-11-05 最终决定**保留四步探针、只修 UX**（否决单屏检测）；04-08 因此只改引导的可见性与容错，不动判定链
- [Phase 4]: 软重试只对「这一下没推好」的三类原因生效（`ambiguous_axes` / `not_enough_samples` / `not_enough_travel`），上限 2 次，第 3 次硬失败；`_clear_failure()` 同时清失败文案与计数，是唯一的清空点
- [Phase 4]: 交叉校验失败的软重试**不调** `_clear_failure()`：重测的那一步单独是成功的，清掉计数会让交叉失败变成无限重来
- [Phase 4]: 探针屏 `%Hint` 第一行永远是「app 收到了什么」（`你推的是：轴 N 的正/负方向（±x.xx）`），10 Hz 节流；轴序号只能由探针给出，屏幕绝不写「右摇杆 X 轴」（INPUT-02）
- [Phase 4]: 停止屏只报本步增量（`本步开始后新增 N 个摇杆事件（累计 M）`），三个停止判据一字未改；旧文案与 `PAD_DIAG ev_m=2633` 自相矛盾，已写进 ACCEPTANCE 说明替换原因
- [Phase 4]: 诊断覆盖层是 D1/D2 的新证据出口：LB+RB（9+10）0.8 s、十字键左右（13/14）翻页、22 px、每行 ≤100 字符、1 Hz、只经 `screencap`；读原始字节而不调 `ProfileStore.load_all()`（后者会删坏档）
- [Phase 4]: 覆盖层零 Outcome 的三层保证：组合键不含 X → 打开时 `set_layout_confirmed(false)` 静默 abandon → 可见期间组合根 `_process` 早退；`test_onboarding_ui` 有机械断言
- [Phase 4]: 04-07 第二次真机走查（新包 27,046,027 B）D0 仍失败：探针静止基线在扳机轴首次上报前取值（`i=4/i=5` 0.000 → -1.000），57 行 `PROBE_REJECT ambiguous_axes key=up`；用户要求换检测方式或跳过，D1–D6 未执行
- [Phase 4]: **不是用户操作问题**：`PAD_AXIS` 证明两根扳机轴在 21:22:32 都是 0.000、21:22:54 变成 -1.000；静止基线按 0 记后，任何推杆都会被两根「各移动 1.0」的扳机轴淹没。修复方向：等所有轴上报过一次再采基线，或排除从未上报的轴
- [Phase 4]: 04-09 起首启路径是**一页式输入设置**，`OnboardingFlow` / `%Onboarding` 保留但永不 `setup()`、永不可见；页面里没有状态机、没有倒计时、没有自动失败（用户原话「不要有状态改变，我可以反复地测」）
- [Phase 4]: 轴对 = 最近 1 秒内 `min(span_x, span_y)` 最大的一对，并列时取「两轴都更晚变化」的那对；只按峰峰值会在 1 秒窗口里永远判给候选表靠前的一对（用户看到「推了没反应」）
- [Phase 4]: 扳机静止值 = **观测到的最小值**；`i=4/i=5` 从 0.000 一步跳到 -1.000 的「设备基线跳变」按「两轴同值且停住 0.2 秒」识别，只对 (4,5) 不给分（摇杆推 45° 也会同值，不能被压掉）
- [Phase 4]: 复用判据降级为「同 guid key + 结构可用（rs 齐全 + 校准存在 + 有布局）」：没有探针就没有本次观测的四项 index+sign，拿档案自己比自己等于假绿；四项比较仍留在 `DeviceProfile.can_reuse`，等重新引入「探一次」的界面再接回
- [Phase 4]: 设置页写档案时 `scale = 0` 按 1.0 存（未校准直通），并用 `DeviceProfile.from_dict` 往返断言证明这份档案不会被 `load_all()` 整份丢弃；空设备名兜底为「未知手柄」
- [Phase 4]: A 的两个前置（没有手柄 / 还没有轴对）只在 `%Help` 多一行提示，不切屏、不记失败、不清空已采数据 —— 那是「没有可保存的映射」，不是判定失败
- [Phase 4]: 输入事件日志的唯一目的是「事后可回放」：每行都有毫秒时间戳，格式是纯函数（`format_button` / `format_axis`），套件逐字断言；不做实时面板、不做解析器
- [Phase 4]: 日志写 `Android/data/<包名>/files/input_log.txt`（adb 可读，release 包不需要 `run-as`）并镜像 logcat `INPUT_EVT`；非 Android 平台退回 `user://`，避免桌面开发去 `/storage` 撞无关错误
- [Phase 4]: 日志失败只记一次 `INPUT_LOG_ERROR` 并短路本会话写入：按钮边沿永不节流，轴按 `|Δ| < 0.02 且 < 16 ms` 节流；2 MB 轮转只丢最旧的一半
- [Phase 4]: 04-11：X / Y 在设置页**彻底无功能** —— 它们与「按住 RB 连按两下 X」共用同一颗键，真机上还误翻了 X 符号；符号改十字键左右（X）/ 上下（Y），布局改 Start 切换、A 确认
- [Phase 4]: 04-11：保存门写在数据源上 —— `InputSetup.can_save()` 为假时 `build_profile()` 返回 null；量程没推满时 A 只把 `%Help` 换成「量程还没推满…」，不写档案、不切屏
- [Phase 4]: 04-11：`layout_confirmed` 只有一个置真入口 `mark_layout_confirmed()`（由 A 的保存路径调用）；`build_profile()` 自己永远不写 true，只切换布局不算确认
- [Phase 4]: 04-11：旧档案失效靠写入时的事实标记 `quality.range_ready == true`；`DeviceProfile.can_enter_practice()` 把「rs 映射 + 校准半量程 ≥ 0.5 + 中点 ±0.5 + 布局已确认 + 标记」合成一扇门，`can_reuse()` 先过它再比四项
- [Phase 4]: 04-11：默认 `scale=1.0 / center=0` 与「真的推到 ±1.0」在数值上不可区分，所以不能靠校准数值识别默认校准 —— 只能靠保存时量程是否真的推满
- [Phase 4]: 04-11：诊断覆盖层按 Y 调 `ProfileStore.clear()`（只删 `user://profiles/controllers.json`、不存在视为成功、`res://` 返回 ERR_UNAUTHORIZED）并发信号回设置页；覆盖层从「只读」变为「正常渲染只读，唯一例外是 Y 清除」

- [Phase 5]: TapRuntime 只做「一个技能 → 单技能 AppConfig」的参数翻译，tick/_record/status 全部继承 GestureEngine；Phase 4 的 19 套件 / 2044 条断言零改动全绿，是机制替换不改变行为的机械证明
- [Phase 5]: 手势锁的 ±4ms 在 4ms 网格 + 「解锁帧必须回中」下不可直接表示：右摇杆 ≥ RELEASE_STICK 会清零计时，实测边界是 148ms（永不解锁）对 156ms（解锁帧之后再推）
- [Phase 5]: `rt_lock_hold_no_recenter` 在拆掉 `_gesture_locked` 后仍绿（ArcDetector 自己的 armed=false 已挡住第二段弧）；锁的具名红色见证改用 `rt_lock_release_150_minus_4`
- [Phase 5]: `_drain_failures` 必须遍历全部技能取走 pending、只记配置顺序第一个 owner；`rt_failure_owner_config_order` 用同帧的马赛 wrong_start + 磕球 too_slow 钉死没有 break
- [Phase 5]: `measured` 只能随 Hit / Failure 一起产出；删除 Phase 4 的 `ArcDetector.measured()` 事后快照入口（键表与 RESEARCH §D.5 不一致，且一次判定只能有一份度量）
- [Phase 5]: `distance_deg` 用圆周距离（`Geometry.angle_diff`，与 `_end_ok` 同尺）；测试选 50°/90° 让 `angle_diff` 与 `abs(end_rel - nearest)` 同为 40，组 6 仍按同源等式断言
- [Phase 5]: 出厂弧线的终点窗覆盖扫掠中段，200° 成功与 wrong_end 不可达；组 1~6 改用同形状合成弧（只改终点目标/容差/上限），检测器代码零分叉
- [Phase 5]: `_step_t` 存毫秒（`now * 1000.0`），字段名承诺 `t_done_ms`；它只出现在赋值与 measured 构造里，不进任何判定分支

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 4 真机清单 D0 失败（04-07 Task 2，checkpoint:human-verify / blocking-human）— 尝试一（旧包 27,012,856 B）**：手机 Motorola XT2175-2 / Android 12（`ZY22F5FXX9`），D0 在探针重试循环失败：`两轴同时动了：margin 0.001 < 0.25`（20:15:38）/ `上与右落在同一根轴（2/2）`（20:15:46）/ `上下没有互为反号：上 (轴 2, 符号 -1)、下 (轴 3, 符号 1)`（20:18:22）；20:15:50 出现停止屏「没有收到摇杆事件（events_motion = 1931）」。D1–D6 未执行；成功标准 2/3/4/5 均不得勾选。
- **Phase 4 真机清单 D0 仍然失败 — 尝试二（新包 27,046,027 B，04-08 重建）**：干净卸载后安装成功（`versionName=0.1.0`，`lastUpdateTime=2026-11-05 21:19:05`，证书 `e1841a17…32e046` 不变），D0 卡在探针第 1/4 步「上」：`PAD_AXIS i=4/i=5` 在 21:22:32.677 报 `v=0.000`，21:22:54.846 变成 `v=-1.000`（真实静止值）；静止基线按 0 记 → 每窗口 `margin 0.000 < 0.25` → 57 行 `PROBE_REJECT code=ambiguous_axes key=up soft=1`。用户按 B 重来、重新推右摇杆均无效，要求「换一种检测方式或跳过」。D1–D6 未执行；成功标准 2/3/4/5 仍未闭合。**04-09 已修**：整条探针链被单页输入设置替换，`trigger_rest = min`，扳机跳变不再参与轴对识别；新包 27,067,065 B（证书不变），待 04-07 用新包重走。
- **04-11 交付后的待办（04-07，最新包）**：先 `adb uninstall com.fifaskill.trainer` → `adb install -r mobile/build/fifa-trainer.apk`（**27,079,510 B**，证书 `e1841a17…32e046` 不变，`gate-b.sh` 全绿）。D0 按 `ACCEPTANCE.md` §6「D0 操作说明（04-11）」的 11 步走：X/Y **不应**改变符号（改十字键）、量程未满按 A 应停在设置页、布局行必须 `布局：Xbox（按 Start 切换，按 A 确认）`、覆盖层按 Y 应删档回设置页。`INPUT_SETUP` 每秒一行现在带 `layout=` / `confirmed=`。成功标准 2/3/4/5 仍未勾选。
- **04-10 的验收待办（历史，包已被 04-11 取代）**：`InputLog` 写入 `/sdcard/Android/data/com.fifaskill.trainer/files/input_log.txt` 并镜像 logcat `adb logcat -s godot:I | grep INPUT_EVT`；新包仍包含同一套日志，读取命令不变
- **04-09 的验收待办（历史，包已被 04-10 / 04-11 取代）**：单页输入设置 8 步；符号由 X/Y 翻转的说明已过时，04-11 起改十字键
- **D1/D2 的 `run-as` 通道不可用（已绕过，不是已解决）**：release APK 不可调试，`adb shell run-as com.fifaskill.trainer …` 返回 `run-as: package not debuggable`。04-08 增加屏上诊断覆盖层，D1/D2 的证据改为「LB+RB 打开覆盖层 + `adb exec-out screencap`」；但覆盖层**只读**，D2 拒绝面所需的「改写外层 key」仍然做不到
- **用户已决定保留四步探针（2026-11-05，本条关闭）**：用户否决单屏输入检测，改为「保留四步探针、只修 UX」；04-08 按此执行（实时读数 / 两次软重试 / 纯语言文案 / 增量停止屏）。原 blocker 与 04-07 的记录保留为历史
- **D2 缺第二只手柄**：现场只有 Xbox Series X Controller（`getevent -pl` 仅列出 `Xbox Wireless Controller`）；拒绝面（DualSense 或另一只轴映射不同的手柄）未执行，成功标准 3 不得声称完整
- Phase 2 / 4 之前需备齐 **2 台不同 OEM 手机 + Xbox 与 DualSense 手柄**；模拟器不能替代真机验证
- **Phase 2 的人工验收全部未闭合，落点都在 `mobile/ACCEPTANCE.md`**：第 0 节四项前置条件、第 1 节两台 × 四项观察、第 4 节密钥库离线备份、第 5 节第二台干净机器重导出。`adb devices` 当前为空，`device-smoke.sh` 以 `DEVICE_SMOKE_FAIL` 退出（正确行为，不是缺陷）
- 60 Hz 抽稀是否保住 `release_hold_ms = 120` 与 `global_cooldown_ms = 60` 尚未实测，由 Phase 5 的抽稀矩阵回答；在此之前不动任何阈值
- 中文 UI 字体已定案（内嵌 Noto Sans SC 子集 + Noto Sans Symbols 2 fallback），无设备机器上的字形闸门已绿；
  剩余风险是安卓真机是否按 FontVariation 的 fallbacks 渲染 —— 判据已写进 `ACCEPTANCE.md` 第 1 节，等真机
- 干净 clone 的首次 `--import` 观察到 1/5 的段错误（`reimport | NotoSansSC-Subset.ttf`），4 次复跑全绿；**不加重试**，
  若在别的机器上高频率复现，先查 Godot 4.7.2 的字体导入线程崩溃，不要改闸门
- `set_use_accumulated_input(false)` 在安卓上是否真的产生亚帧时间戳未验证（Phase 4 真机记录 `t_ms` 直方图）
- 布局建议与按键确认页已就位（04-03 / 04-05），但 DualSense 的实际确认索引未实测：`INPUT-04` 仍未闭合，不得据此宣布完成
- 引导状态机与组合根已在无头环境证明（04-05：14 套件 / 1175 断言 / main 场景 30 帧启动无错）；真机首启零触摸走完（D0）与断连重探（D2）仍在 04-07
- 帧内反转的事件捕获已在无头层证明（04-04：同帧右→左→右三条 motion 事件全部保留）；真机 `events_motion` / `events_button` / `poll_edges` 的解释与 Δt p95 ≤ 20 ms 仍在 04-07（D5/D6），INPUT-05 不得提前勾选
- `PadSampler._input` 是否在主线程未验证（M3）：`input_thread_id` / `process_thread_id` 已暴露，跨线程时在 `src/input/` 加一把 Mutex 即可

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-11-05T20:21:47.000Z
Stopped at: Completed 05-04-PLAN.md
Resume file: None
