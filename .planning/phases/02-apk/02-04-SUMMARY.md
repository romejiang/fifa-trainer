---
phase: 02-apk
plan: 04
subsystem: infra

tags: [android, apk, apksigner, zipalign, aapt2, keystore, signing, gate, selftest, canary]

# Dependency graph
requires:
  - phase: 02-apk
    plan: 01
    provides: "mobile/tools/doctor.sh 五项构建断言（含 keystore 可读性与 FIFA_KEYSTORE / FIFA_KEYSTORE_ALIAS 默认值）"
  - phase: 02-apk
    plan: 02
    provides: "mobile/tools/gate-a.sh 七步闸门（配置真源 → 语法 → PCK → 字形）+ 可导出工程"
  - phase: 02-apk
    plan: 03
    provides: "810 字形清单与双字体子集：闸门 A 的 GLYPH_OK 分支"
provides:
  - "mobile/tools/gate-b.sh：doctor 五项 → 闸门 A → 先删旧产物 → release 导出 → 验签 / 对齐 / 包内容 / badging 四段静态校验"
  - "mobile/tools/gate-b-selftest.sh：反例证明「未签名残留必被 apksigner 拒绝」与「口令不进导出日志」"
  - ".gitignore：*.keystore / *.jks / *.idsig 三类永不进仓库"
  - "mobile/build/fifa-trainer.apk（26,793,210 B，gitignored）：v2+v3 签名、16 KB 对齐、仅 arm64-v8a、minSdk 24"
  - "签名身份指纹：证书 SHA-256 = E1:84:1A:17:BD:A4:33:07:CD:FC:8E:9E:75:7C:67:2A:6A:91:B7:FD:60:EA:86:E7:15:AF:D4:61:BA:32:E0:46"
affects: [02-05, "09"]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 4237
  tasks: 3
  commits: 3
  plan_head_before: 7a05170762f79a3cca4c1e79aaa2b378669a969c
  plan_head_after: 8e7c6e65dc59e2d491821dd61d11471f58b098d5

tech-stack:
  added:
    - "apksigner 0.9 / zipalign / aapt2（build-tools 36.1.0 已有，未新增任何依赖；本计划零包管理器安装）"
  patterns:
    - "先删后建：`rm -f` 放在导出之前，让「上一轮的产物冒充这一轮」在物理上不可能（T-02-11）"
    - "外部命令的判定直接取退出码，输出先落临时文件再比对内容 —— 管道里 `$?` 是后一个命令的"
    - "反例自测不复制闸门逻辑：只造反例、判期望失败、清理现场，完整验证一律回调 gate-b.sh"
    - "canary 生成必须是「上游一次产出固定字节 + 下游读到底」，任何「无限产出 + 按字节截断」的管道在 pipefail 下都会让反例脚本自己死于 SIGPIPE"
    - "环境输入契约：唯一必填是口令（`${VAR:?}` + export），路径与别名由脚本解析出与 doctor.sh 逐字相同的默认值"

key-files:
  created:
    - mobile/tools/gate-b.sh
    - mobile/tools/gate-b-selftest.sh
  modified:
    - .gitignore
    - mobile/tools/doctor.sh

key-decisions:
  - "密钥库沿用仓库外已存在的 $HOME/.fifa-trainer/release.keystore（alias=fifa-trainer），不重新生成：重新生成等于换身份，Phase 9 的覆盖安装会变成「必须卸载、数据全丢」"
  - "口令守卫放在 doctor 之前而不是第 4 步：doctor 的 keystore 断言读的是同一个变量，守卫放后面时最先撞到的是 doctor 的报错，读者会误以为密钥库坏了"
  - "Task 1 的验签与 gate-b.sh 都用 `apksigner verify --verbose --print-certs`：只加 --print-certs 时 apksigner 0.9 不输出 Verified using 行，计划里那条断言会永远红"
  - "gate-b.sh 里 build-tools 路径写死 36.1.0（与 doctor.sh 的 BUILD_TOOLS 同一枚 pin），但引擎/模板版本断言仍只在 doctor 里定义一次"
  - "minSdk 只要求存在并打印实际值（24），不钉死：它由模板与 gl_compatibility 共同决定，钉死一个会随模板变化的数字只会制造噪音"
  - "INFRA-04 仍不标记完成：本计划只做到「签名 APK 自证」，能装 / 能启动 / 能读到原始轴必须由 02-05 的真机冒烟收口"

patterns-established:
  - "闸门 B 的单向调用图：gate-b → doctor（五项）/ gate-a → sync_config / Godot / check_pack / glyph_coverage；gate-b-selftest → gate-b。没有任何检查逻辑的第二份定义"
  - "「文件存在 ≠ 导出成功」的机械化落点：rm -f → 导出 → apksigner 退出码 → 内容断言，四步缺一不可"
  - "反例输出语汇：`  ✓ 未签名产物被 apksigner 拒绝` / `  ✓ 导出日志不含口令 canary` / `SELFTEST_OK` / `SELFTEST_FAIL`，与 verify_clean_clone.sh 的 if 包期望失败同构"

requirements-completed: []

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "一条命令产出并自证一个 v2 签名有效、16 KB 页对齐、只含 arm64-v8a 的 release APK"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "bash mobile/tools/gate-b.sh（连跑两次均退出 0，末行为 `✓ 闸门 B 通过`）"
        status: pass
      - kind: other
        ref: "apksigner verify --verbose --print-certs → Verified using v2 scheme: true；zipalign -c -P 16 -v 4 → Verification successful"
        status: pass
    human_judgment: false
  - id: D2
    description: "导出失败后残留的未签名 APK 必被 apksigner 拒绝（「文件存在」永远不等于「导出成功」）"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "bash mobile/tools/gate-b-selftest.sh → 场景 A 留下 26,777,137 B 的未签名探针，apksigner verify 拒绝"
        status: pass
    human_judgment: false
  - id: D3
    description: "口令从不出现在导出日志 / stdout / stderr / 仓库文件中"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "bash mobile/tools/gate-b-selftest.sh → 场景 B canary 未出现在导出日志，签名命令行里密钥库参数已脱敏"
        status: pass
    human_judgment: false
  - id: D4
    description: "密钥库与签名旁文件永不进仓库；APK 内无 x86 库、无 .idsig、无密钥库"
    verification:
      - kind: other
        ref: "git ls-files | grep -Ec '\\.keystore$|\\.jks$' = 0；unzip -l 只含 lib/arm64-v8a/"
        status: pass
    human_judgment: false

# Metrics
duration: 13min
completed: 2026-11-04
status: complete
---

# Phase 02 Plan 04: release keystore + 签名 APK + 闸门 B Summary

**一条命令从「这台机器对不对」走到「这个 APK 能自证」：闸门 B 产出 26.8 MB 的 v2+v3 签名 arm64 APK，并用一个 26.8 MB 的未签名残留证明「文件存在 ≠ 导出成功」**

## Performance

- **Duration:** 13 min
- **Started:** 2026-11-04T14:51:00Z
- **Completed:** 2026-11-04T15:05:00Z
- **Tasks:** 3
- **Files modified:** 4（2 新建 / 2 修改）

## Accomplishments

- `mobile/tools/gate-b.sh`：doctor 五项 → 闸门 A → `rm -f` 旧产物 → release 导出 → apksigner / zipalign / unzip / aapt2 四段校验，连跑两次都退出 0 且末行为 `✓ 闸门 B 通过`
- `mobile/tools/gate-b-selftest.sh`：场景 A 实测让 Godot 在「口令写错」时留下 26,777,137 B 的未签名 APK，`apksigner verify` 拒绝它；场景 B 用 24 位随机 canary 当口令，导出日志里一个字都没出现
- 环境输入契约收成「一个必填 + 两个有默认值」：`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 是唯一必填项（`:?` 守卫 + export），`FIFA_KEYSTORE` / `FIFA_KEYSTORE_ALIAS` 由脚本解析出与 doctor 逐字相同的默认值 —— 干净 shell 不设这两个变量也能跑
- 签名身份定死并可核对：包名 `com.fifaskill.trainer`、别名 `fifa-trainer`、`versionCode=1` / `versionName=0.1.0`；证书 SHA-256 = `E1:84:1A:17:BD:A4:33:07:CD:FC:8E:9E:75:7C:67:2A:6A:91:B7:FD:60:EA:86:E7:15:AF:D4:61:BA:32:E0:46`（与 `keytool -list` 输出逐位一致，且与 orchestrator 给出的期望值一致）
- 回归红线未动：`bash tools/check_desktop.sh` 仍是 230 项全绿，`bash mobile/tools/gate-a.sh` 仍 `PACK_OK skills=5` + `GLYPH_OK chars=810`

## Task Commits

Each task was committed atomically:

1. **Task 1: 生成 release 密钥库，签出第一个能自证的 APK** - `1ef3e02` (feat)
2. **Task 2: 闸门 B —— 一条命令导出并自证** - `bac9b8f` (feat)
3. **Task 3: 反例证明 —— 未签名残留必被拒绝，口令不进日志** - `8e7c6e6` (feat)

**Plan metadata:** _(docs commit follows this file)_

## Files Created/Modified

- `mobile/tools/gate-b.sh`（新建，181 行）— 闸门 B 唯一入口；四段静态校验全部直接判退出码，输出落 `mktemp -d` 下的临时文件再比对内容
- `mobile/tools/gate-b-selftest.sh`（新建，116 行）— 两个反例；不复制任何闸门逻辑，期望失败一律用 `if` 包住
- `.gitignore`（修改，+6）— 在既有「移动端产物」组内追加 `*.idsig` / `*.keystore` / `*.jks`，各带一行中文注释
- `mobile/tools/doctor.sh`（修改，1 行）— 口令修法措辞去掉赋值形状（见偏差 3）
- `mobile/build/fifa-trainer.apk`（产物，gitignored）— 26,793,210 B；`fifa-trainer.apk.idsig` 同在 `build/`，`.gitignore` 已覆盖

## 产物实测数据（供 02-05 的 BUILD.md 直接抄）

```
apksigner verify --verbose --print-certs
  Verified using v2 scheme (APK Signature Scheme v2): true
  Verified using v3 scheme (APK Signature Scheme v3): true
  Signer #1 certificate DN: CN=FIFA Skill Trainer, OU=Personal, O=fifaskill, C=CN
  Signer #1 certificate SHA-256 digest: e1841a17bda43307cdfc8e9e757c672a6a91b7fd60ea86e715afd461ba32e046
  Signer #1 certificate SHA-1 digest:   7f20b2f115b55ece5a9120e1a4fde8fc08127988

zipalign -c -P 16 -v 4  → Verification successful
aapt2 dump badging
  package: name='com.fifaskill.trainer' versionCode='1' versionName='0.1.0'
  minSdkVersion:'24'   targetSdkVersion:'36'
  native-code: 'arm64-v8a'
unzip -l
  lib/arm64-v8a/  （唯一 lib 目录）
  assets/assets/config/skills_config.json         9117 B
  assets/assets/config/skills_config.json.sha256    85 B
```

导出日志里密钥库参数是脱敏的（Godot 自己打 `--ks <REDACTED> --ks-pass pass:<REDACTED> --ks-key-alias <REDACTED>`），末尾的 `cannot connect to daemon at tcp:5037` 与 `No project icon specified` 都是固定噪声（RESEARCH P4 / P10）。

## Decisions Made

- **沿用已有密钥库，不重新生成**：`$HOME/.fifa-trainer/release.keystore`（`-rw-------`，仓库外）已由人托管，重新生成等于换签名身份 —— 那会让 Phase 9 的覆盖安装变成「必须卸载、`user://` 数据全丢」。
- **口令守卫前置到 doctor 之前**：doctor 的 `keystore` 断言读同一个变量，守卫放在第 4 步时最先打出的是 doctor 的报错，读者会误以为是密钥库坏了。
- **验签统一加 `--verbose`**：apksigner 0.9 只加 `--print-certs` 时不输出 `Verified using …` 行，计划里那条「验 v2 为 true」的断言会永远红。
- **minSdk 只打印不钉死**：由模板与 `gl_compatibility` 共同决定，钉一个会随模板飘的数字只是噪音；实际值 24 已记录在上表。
- **INFRA-04 不标记完成**：本计划只证明「签名 APK 自证」，能装 / 能启动 / 中文不豆腐 / 读到原始轴必须由 02-05 的真机冒烟收口。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `apksigner verify --print-certs` 不输出 `Verified using v2 scheme`**
- **Found during:** Task 1（首次验签）
- **Issue:** 计划附录的命令与 Task 1 的 `<automated>` 都是 `apksigner verify --print-certs`，但 apksigner 0.9 只在 `--verbose` 下才打印 `Verified using …` 行 —— 照抄会让断言永远红，而最容易的「修法」是删掉这条断言。
- **Fix:** Task 1 验签与 `gate-b.sh` 第 5 步统一改成 `apksigner verify --verbose --print-certs`，断言写成 `grep -qF 'Verified using v2 scheme (APK Signature Scheme v2): true'`。
- **Files modified:** `mobile/tools/gate-b.sh`
- **Verification:** `grep 'Verified using'` 输出 v2=true / v3=true；gate-b 连跑两次退出 0。
- **Committed in:** `1ef3e02`（Task 1 验签口径）、`bac9b8f`（gate-b.sh）

**2. [Rule 2 - Missing Critical] `doctor.sh` 里存在赋值形状的口令占位串，让「口令零字面值」不变量不成立**
- **Found during:** Task 1（跑计划自己的验收 grep）
- **Issue:** `grep -rnE 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=[^"$]' mobile/tools/` 命中 1 条：`doctor.sh:242` 的帮助文案里写着 `export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<口令>`。它是占位符不是真口令，但它让「整个 `mobile/tools/` 不存在赋值形状的口令」这条安全不变量出现一个永远红的例外 —— 例外一出现，下一个人就会把整条 grep 放宽。
- **Fix:** 改写那一句为「先 export 变量 GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD（口令只留在环境里，不要写进任何文件）」，保留变量名与可操作性，去掉 `=` 的形状。**这是 `files_modified` 之外的一处改动**，只改措辞、零行为变化。
- **Files modified:** `mobile/tools/doctor.sh`
- **Verification:** `grep -rnE 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=[^"$]' mobile/tools/ | wc -l` → 0；`bash mobile/tools/doctor.sh keystore` 仍退出 0。
- **Committed in:** `1ef3e02`

**3. [Rule 1 - Bug] `minSdkVersion` 的大小写：写成 `sdkVersion:'` 永远不匹配**
- **Found during:** Task 2（gate-b.sh 第一次实跑，末行 `✗ badging 里没有 minSdkVersion 行`）
- **Issue:** aapt2 打的是 `minSdkVersion:'24'`（大写的 `Sdk`），我的模式是小写 `sdkVersion` —— 大小写敏感下永远匹配不到。讽刺的是这条断言「失败得很正确」：它确实报了红，只是红的原因是我自己写错了模式。
- **Fix:** 模式改为 `minSdkVersion:'`，并在注释里写死「注意大小写」。
- **Files modified:** `mobile/tools/gate-b.sh`
- **Verification:** `· 最小 SDK: minSdkVersion:'24'`；gate-b 退出 0。
- **Committed in:** `bac9b8f`

**4. [Rule 1 - Bug] `$out（` 把中文全角括号吞进了变量名**
- **Found during:** Task 2（gate-b.sh 第二次实跑，末行 `out?: unbound variable`）
- **Issue:** `echo "· APK: $out（…）"` 在 UTF-8 locale 下 bash 把紧跟其后的全角括号字节当成变量名的一部分，于是 `set -u` 报 `out: unbound variable`。这类错误只在含中文的 echo 里出现，`shellcheck` 之前的肉眼审查看不出来。
- **Fix:** 变量紧邻多字节字符时一律写 `${out}`；并用一段脚本扫描全文件，确认没有其它 `$var` 后直接跟非 ASCII 字符的位置。
- **Files modified:** `mobile/tools/gate-b.sh`
- **Verification:** 全文件扫描 0 处；gate-b 退出 0。
- **Committed in:** `bac9b8f`

**5. [Rule 3 - Blocking] 密钥库已在仓库外存在，跳过 `keytool -genkeypair`**
- **Found during:** Task 1（precondition 检查）
- **Issue:** 计划 Task 1 的 action 要求生成密钥库，但 `$HOME/.fifa-trainer/release.keystore` 已由人托管（`-rw-------`，2,708 B），且 orchestrator 明确要求「不要生成新的、不要问口令」。
- **Fix:** 跳过生成步骤，只做后续的导出与验签；用 `keytool -list` 确认 alias=`fifa-trainer` 可读、证书 SHA-256 与期望值逐位一致。
- **Files modified:** 无（仓库外文件，不入 git）
- **Verification:** `keytool -list -alias fifa-trainer -storepass:env …` 输出 `E1:84:1A:…:E0:46`，与 `apksigner --print-certs` 的 `e1841a17…32e046` 同源。
- **Committed in:** n/a

---

**Total deviations:** 5（3 修复 bug / 1 补安全不变量 / 1 沿用既有凭据）
**Impact on plan:** 四条代码改动全部是「让断言真的成立」而不是「让断言变绿」：没有放宽任何一条校验。唯一越出 `files_modified` 的是 `doctor.sh` 的一句帮助文案（偏差 2）。

## Issues Encountered

- Task 1 的导出是手跑一次 Godot（`gate-b.sh` 当时还不存在），Task 2 完成后改由闸门复跑，两次产物大小一致（26,793,210 B）—— 说明导出可复现。
- `mobile/build/` 里除 APK 还躺着 `fifa-trainer.apk.idsig`（Godot 调 apksigner 时生成的 v4 旁文件）。它被 `*.idsig` 覆盖，且 `unzip -l` 证明它没进包内；分发时只拷 `.apk`。

## User Setup Required

- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 必须由人在当前 shell 里 export（从密码管理器取），不要写进任何文件。当前已通过 `$HOME/.fifa-trainer/credentials.sh` 加载。
- 密钥库与口令的离线备份（离线介质 + 至少两处 + 密码与文件分开存放）仍需人完成 —— 这是成功标准 5 的人工部分，02-05 的 BUILD.md 会写指引。

## Known Stubs

None.

## Threat Flags

None — 本计划新增的是构建期脚本，没有引入运行期网络 / 认证 / 数据访问面。威胁登记 T-02-10…T-02-13 的缓解措施全部落地并有反例证明。

## Next Phase Readiness

- 02-05 可以直接引用本文件里的实测数据写 `mobile/BUILD.md`（版本表、证书指纹、minSdk/targetSdk、双 `assets` 路径）。
- `mobile/BUILD.md` 必须把三件不可变事实写成「不可变」而不是「当前值」：包名 `com.fifaskill.trainer`、keystore 别名 `fifa-trainer`、`versionCode` 起点 1。
- 真机侧仍全空：能装 / 能启动 / 中文不豆腐 / 读到原始轴只有 02-05 的真机冒烟能证明（闸门 C）。

---
*Phase: 02-apk*
*Completed: 2026-11-04*

## Self-Check: PASSED
