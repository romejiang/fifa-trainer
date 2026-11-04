---
gsd_state_version: "1.0"
current_phase: 3
current_phase_name: 纯核心地基 — 几何 / 配置校验 / 无头运行 / 架构 lint
status: executing
stopped_at: Phase 3 plan 06 complete (user:// 稀疏覆盖层 + ConfigStore), 6/6 plans done, ready for verification
last_updated: "2026-11-04T20:03:20.000Z"
last_activity: 2026-11-05
last_activity_desc: Phase 3 plan 06 complete
state_head: 45a164685c173a78808fd7f4329e234a93712f17
progress:
  total_phases: 10
  completed_phases: 2
  total_plans: 16
  completed_plans: 16
  percent: 20
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-04)

**Core value:** 用真手柄、在任何地方都能练，判定准、反馈看得懂。
**Current focus:** Phase 3 — 纯核心地基 — 几何 / 配置校验 / 无头运行 / 架构 lint

## Current Position

Phase: 3 (纯核心地基 — 几何 / 配置校验 / 无头运行 / 架构 lint) — EXECUTING
Plan: 6 of 6
Status: Executing Phase 3 — all plans complete, awaiting verification
Last activity: 2026-11-05 — 03-06 完成：`user://` 稀疏覆盖层 + ConfigStore

Progress: [██░░░░░░░░] 20%

## Performance Metrics

**Velocity:**
- Total plans completed: 16
- Average duration: — min
- Total execution time: 0.9 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 5 | - | - |
| 2 | 5 | - | - |

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

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 2 / 4 之前需备齐 **2 台不同 OEM 手机 + Xbox 与 DualSense 手柄**；模拟器不能替代真机验证
- **Phase 2 的人工验收全部未闭合，落点都在 `mobile/ACCEPTANCE.md`**：第 0 节四项前置条件、第 1 节两台 × 四项观察、第 4 节密钥库离线备份、第 5 节第二台干净机器重导出。`adb devices` 当前为空，`device-smoke.sh` 以 `DEVICE_SMOKE_FAIL` 退出（正确行为，不是缺陷）
- 60 Hz 抽稀是否保住 `release_hold_ms = 120` 与 `global_cooldown_ms = 60` 尚未实测，由 Phase 5 的抽稀矩阵回答；在此之前不动任何阈值
- 中文 UI 字体已定案（内嵌 Noto Sans SC 子集 + Noto Sans Symbols 2 fallback），无设备机器上的字形闸门已绿；
  剩余风险是安卓真机是否按 FontVariation 的 fallbacks 渲染 —— 判据已写进 `ACCEPTANCE.md` 第 1 节，等真机
- 干净 clone 的首次 `--import` 观察到 1/5 的段错误（`reimport | NotoSansSC-Subset.ttf`），4 次复跑全绿；**不加重试**，
  若在别的机器上高频率复现，先查 Godot 4.7.2 的字体导入线程崩溃，不要改闸门
- `set_use_accumulated_input(false)` 在安卓上是否真的产生亚帧时间戳未验证（Phase 4 真机记录 `t_ms` 直方图）

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-11-04T19:56:30.000Z
Stopped at: Phase 3 plan 05 complete (坏配置语料 + 跨语言判定对等), ready for 03-06
Resume file: None
