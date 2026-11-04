---
phase: 02-apk
reviewed: 2026-11-04T15:36:01Z
depth: deep
files_reviewed: 24
files_reviewed_list:
  - mobile/tools/doctor.sh
  - mobile/tools/gate-a.sh
  - mobile/tools/gate-b.sh
  - mobile/tools/gate-b-selftest.sh
  - mobile/tools/verify_clean_export.sh
  - mobile/tools/device-smoke.sh
  - mobile/tools/check_pack.gd
  - mobile/tools/glyph_coverage.gd
  - mobile/src/smoke/smoke_screen.gd
  - mobile/src/smoke/smoke_screen.tscn
  - mobile/project.godot
  - mobile/export_presets.cfg
  - mobile/assets/fonts/AppFont.tres
  - mobile/assets/fonts/NotoSansSC-Subset.ttf.import
  - mobile/assets/fonts/NotoSansSymbols2-Subset.ttf.import
  - mobile/assets/fonts/required_glyphs.txt
  - mobile/assets/fonts/OFL.txt
  - tools/make_font_subset.py
  - mobile/BUILD.md
  - mobile/ACCEPTANCE.md
  - mobile/README.md
  - README.md
  - .gitignore
  - .gitattributes
severity_counts:
  blocker: 1
  high: 3
  medium: 7
  low: 9
  info: 4
  total: 24
---

# Phase 02 代码评审：安卓工具链 + 真机冒烟 APK

**评审范围**：`d6b76b2..HEAD`（19 个提交），重点是六条 `mobile/tools/*.sh`、两个 GDScript 闸门、`tools/make_font_subset.py`、以及 `mobile/BUILD.md` / `ACCEPTANCE.md`。
**方法**：不只读代码。凡是可以机械证伪的断言，都在本机实际跑了一遍（Godot 4.7.2、build-tools 36.1.0、真实 APK 都在）；下文标「实测」的结论都附了复现命令。
**基线**：`bash mobile/tools/gate-a.sh` 当前是绿的（`PACK_OK skills=5`、`GLYPH_OK chars=810`），`bash mobile/tools/doctor.sh godot template jdk sdk` 也是绿的。问题不在「现在能不能过」，在于有几条断言**永远不可能红**。

**没有覆盖到的部分**：闸门 B 未端到端重跑（发布口令不在本会话的环境里，只验证了「缺口令时 rc=1」），但它的四段静态校验都是对磁盘上那份真实 APK 逐条单独执行过的；本阶段没有产生任何真机证据，评审也没有对任何真机行为下判断——`02-05-SUMMARY.md` 在这点上是诚实的（`adb devices` 为空、成功标准 1/2/4 未闭合）。

---

## BLOCKER

### BLOCKER-01：闸门 A 的「GDScript 语法检查」永远不会失败

**File:** `mobile/tools/gate-a.sh:52-65`

**What:** `check_script()` 只用 `--check-only --script` 的**退出码**判定语法。实测 Godot 4.7.2 的 `--check-only` 对**解析失败**和**文件不存在**都返回 0：

```bash
# 把 smoke_screen.gd 复制一份并追加 `func broken(:`，然后：
godot --headless --path <proj> --check-only --script res://src/smoke/broken.gd
# 输出: SCRIPT ERROR: Parse Error: Expected parameter name. ... at: GDScript::reload
# 退出码: 0
godot --headless --path <proj> --check-only --script res://tools/does_not_exist.gd
# 输出: ERROR: Can't load script: ...   退出码: 0
```

顺带实测：带一个解析失败的脚本时，`--import` 返回 **0**、`--export-pack` 也返回 **0** 并照样产出 370 KB 的 PCK。也就是说语法错会**一路绿到 APK**，闸门 A 开头那段「语法错在 10 秒内被抓住，不必等 1.9 GB 模板」的设计目标没有实现。

**Why it matters:** 这是本阶段评审重点里的第一类缺陷——闸门声称证明的东西并不成立，而且它是**唯一**能挡住语法错的一步（`--import`、`--export-pack`、`gate-b` 的静态校验都不看脚本能否解析）。`mobile/BUILD.md:188` 与 `mobile/README.md:25` 都把「语法」写成闸门 A 已证明的事实，`02-02-SUMMARY.md:136` 同样如此。本阶段刚修掉一个同构的假绿（`:?` + EXIT trap），这个却是同一天留下的兄弟。

**Fix:** 判据改成「退出码 0 **且** 输出里没有任何加载/解析错误」，并把漏掉的第三个脚本补上：

```bash
check_script() {
    local script="$1" out
    if ! out="$("$godot" --headless --path "$repo_root/mobile" \
            --check-only --script "$script" 2>&1)"; then
        echo "✗ 脚本语法检查失败：${script}" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    # 实测 4.7.2：--check-only 对解析失败与文件不存在都返回 0，只能看输出。
    # 删掉这段就等于把这条断言变回永远绿（02-REVIEW BLOCKER-01）。
    if printf '%s\n' "$out" | grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Can.t load script'; then
        echo "✗ 脚本语法检查失败：${script}" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    echo "  ✓ ${script}"
}

check_script "res://src/smoke/smoke_screen.gd"
check_script "res://tools/check_pack.gd"
check_script "res://tools/glyph_coverage.gd"   # 现在根本没被检查
```

再补一条**反例自测**（与 `gate-b-selftest.sh` 同构）：在 `$tmp` 里造一个含 `func broken(:` 的脚本，断言 `check_script` 对它非零——否则下次有人「简化」成只看退出码，没有东西会红。

---

## HIGH

### HIGH-01：BUILD.md 里 Godot 引擎包的 SHA-512 只有 127 位，校验命令永远不可能通过

**File:** `mobile/BUILD.md:82`

**What:** 期望摘要是 `38aa16e5…b7ac69ca`，**127 个十六进制字符**。SHA-512 必须是 128 位。实测后果：

```bash
$ echo "<127位摘要>  /tmp/z.txt" | shasum -a 512 -c -
shasum: standard input: no properly formatted SHA checksum lines found
rc=1
```

不是「校验不匹配」，是**格式错误**——一种看起来像「这行命令本身有问题」而不是「包可能被换过」的报错。同一份文档里模板的摘要（`:99`）和 `doctor.sh:32` 的常量都是 128 位，所以只有引擎这一条坏了。

**Why it matters:** 本阶段的收尾主张是「一台从没参与过本项目的机器照着 BUILD.md 能导出同签名 APK」。第三节的「先校验再解压」是这条链路的第二个动作，第八节第 2 步直接引用它。它一开始就失败，等于把「校验」这一步教成「跑不通就删掉」。`02-05-SUMMARY.md` 的机械验证只 grep 了「两个 SHA-512 字面量在不在」，没有验证长度，所以漏了。

**Fix:** 从重新下载的 zip 重新计算（`shasum -a 512 Godot_v4.7.2-stable_macos.universal.zip`）并替换为 128 位；再把判定改成模式校验，让截断当场可见：

```bash
sum='<重新计算出的 128 位摘要>'
test "${#sum}" -eq 128 || { echo "摘要长度不是 128"; exit 1; }
echo "$sum  /tmp/godot472.zip" | shasum -a 512 -c -
```

---

### HIGH-02：BUILD.md 一边写「口令永远不落盘」，一边教人把口令写进 `credentials.sh`

**File:** `mobile/BUILD.md:144-148`（同节 `:137`、`:180`、`:317`）

**What:** 第 144 行是加粗断言「**口令永远不落盘。**」，紧接着的代码块却是：

```bash
set -a; . "$HOME/.fifa-trainer/credentials.sh"; set +a   # 本机做法：口令在脚本里，脚本在仓库外
```

这是一份**明文口令文件**，而且 `set -a` 会把文件里所有变量一并导出。本机实测该文件**已经存在**：

```
-rw-------  1 stephen  staff  98 Nov  4 22:51 credentials.sh
```

即「本机做法」不是假设，是既成事实。**:317**（第八节第 6 步）又写成 `export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`（无值），读者照着做只会得到一个空变量，然后被闸门 B 的守卫挡住。

**Why it matters:** 这是 `T-02-15`（口令不进日志/不进文件/不进提交）在文档层的破口。脚本侧做得很好（`-storepass:env`、`--ks <REDACTED>` 实测确认、`grep` 负向断言 0 命中），但**唯一被推荐的操作路径**把口令落到了磁盘上；一旦这台机器被人拿到文件系统，密钥库的 600 权限就白设了。而且文档自相矛盾，下一个人无法判断该信哪一句。

**Fix:** 把「取出 → 进环境」这一段换成不经文件的写法，并在第八节第 6 步给同一条命令：

```bash
# macOS 钥匙串（口令从不进文件、不进 argv、不进 history）
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(security find-generic-password -s fifa-trainer -a release -w)"

# 或者交互式读取（不回显、不进 history）
read -rs GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD && export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

若确实要保留 `credentials.sh` 这条本机路径，必须把它降级为「已接受的例外」并写清代价（`chmod 600`、不进备份、不进任意同步目录），而不是与「永远不落盘」并列陈述。

---

### HIGH-03：闸门 B 验的是「有 v2 签名」，不是「我这一把钥匙签的」——换钥匙的 APK 照样全绿

**File:** `mobile/tools/gate-b.sh:101-116`

**What:** 签名段只判两件事：`apksigner verify` 退出码 0、输出里有 `Verified using v2 scheme ...: true`。它**不比对签名者身份**，证书摘要只是「打印出来给人看」（`:114`）。实测：拿本阶段产出的 APK，用一把**全新生成、DN 完全相同**的密钥重签后再跑闸门 B 的全部签名判据：

```
verify rc=0
Verified using v2 scheme (APK Signature Scheme v2): true
Signer #1 certificate SHA-256 digest: 7ea633b2…2a1e55     ← 不是 e1841a17…32e046
→ GATE-B v2 CHECK: PASS with the wrong key
zipalign: PASS
package: name='com.fifaskill.trainer' versionCode='1' versionName='0.1.0'
```

**Why it matters:** 这正是 `BUILD.md:204-233` 与 `ACCEPTANCE.md:63-71` 用整节篇幅警告的那个不可逆事故：换了钥匙之后覆盖安装会失败，必须卸载，`user://` 数据全丢。当前把它全部押在「人记得在第八节第 8 步手工核对指纹」上；机器闸门本身对这件事是瞎的，而目录里**已经有**这个指纹的唯一定义（`BUILD.md:211`）可以拿来钉。本阶段的核心卖点「签名是自证的，不是文件存在」因此只成立了一半。

**Fix:** 把期望指纹收进 `doctor.sh`（替身：与 `TEMPLATE_SHA512` 同级的一个 `readonly RELEASE_CERT_SHA256`，BUILD.md 第六节改为引用它，避免两份定义），闸门 B 追加一段：

```bash
if ! grep -qF "Signer #1 certificate SHA-256 digest: ${RELEASE_CERT_SHA256}" "$tmp/sign.txt"; then
    echo "✗ 签名者不是这把发布钥匙（期望 ${RELEASE_CERT_SHA256}）：" >&2
    grep -F 'certificate SHA-256 digest' "$tmp/sign.txt" >&2
    echo "  覆盖安装会变成「必须卸载 + user:// 数据全丢」，不要拿这个包去装。" >&2
    exit 1
fi
```

---

## MEDIUM

### MEDIUM-01：BUILD.md 是「版本表」而不是安装手册 —— JDK 17 与 Android SDK 都没有获取步骤

**File:** `mobile/BUILD.md:20-28`、`mobile/BUILD.md:309-311`

**What:** 第一节的表把 JDK 写成 `$HOME/.sdkman/candidates/java/17.0.12-oracle`、SDK 写成 `$HOME/Library/Android/sdk`，但全文没有 `sdkmanager`、`sdk install`、`brew`、Adoptium/Temurin 或 Android Studio 的任何一处（已 grep 确认为 0 命中）。第八节第 1 步却说「装齐第一节表里的每一项」——对这两项，读者只有一个**本机绝对路径**，没有可执行的动作。另外表里 platform-tools 写成「精确版本 `36.0.2`」，但 `doctor.sh` 的 `sdk` 断言只查 `adb` 可执行，从不比对版本。

**Why it matters:** 评审重点第 4 条要求「BUILD.md 必须让第二台机器复现同一个 APK；凡是机器相关却写成普适的都要点名」。这两个是本阶段唯一没有安装路径的组件，而它们决定了导出的 JDK 与 target SDK。`17.0.12-oracle` 还是 sdkman 的发行版标识，换一台机器用 Temurin 17.0.12 时路径不同、`doctor.sh` 默认值也不同——读者会以为自己装错了。

**Fix:** 补两条可照抄的安装命令，并把「哪些是钉死的、哪些是可替换的实现」写清：

```bash
sdk install java 17.0.12-oracle          # sdkman；其它发行版只要 java -version 首行含 "17. 即可
sdkmanager "build-tools;36.1.0" "platforms;android-36" "platform-tools"
```

platform-tools 二选一：要么在 `doctor.sh` 的 `sdk` 断言里加 `"$adb" version | grep -q '36\.0\.2'`，要么在表里把它标成「不参与判定」。

---

### MEDIUM-02：闸门 B 把 `JAVA_HOME` 交给环境，而注释声称 doctor 已经断言过它是 17 —— 实际没有

**File:** `mobile/tools/gate-b.sh:62-67`

**What:** 注释写「是不是 17 由 doctor.sh 的 jdk 一项断言」。但 `doctor.sh:161-163` 明确**容忍**非 17 的 `JAVA_HOME`（打印一行「已显式改用 …（未修改系统默认值）」然后继续），它验证的是 `editor_settings` 里的 `java_sdk_path`，不是环境变量。于是 `gate-b.sh:64-67` 只在 `JAVA_HOME` 未设置或不可执行时才补默认值；本机现状就是 `JAVA_HOME=/Users/stephen/.sdkman/candidates/java/current`（实跑 `java -version` = **25.0.2**），闸门 B 会原样保留它，`apksigner` 的 wrapper 也就跑在 25 上。

**Why it matters:** 「工具链钉死 JDK 17」是第一节的表头承诺。真跑导出的进程用的 JVM 没有任何断言覆盖，而 `doctor.sh` 那行「已显式改用 17」很容易被读成「整条链路已经用 17 了」。这属于「看起来被断言、其实没被断言」。

**Fix:** 让 doctor 把解析结果交出来（例如 `doctor.sh jdk --print-home` 输出 `jdk_home`），闸门 B 在 doctor 通过后无条件覆盖：

```bash
JDK17="$(bash "$repo_root/mobile/tools/doctor.sh" jdk --print-home)" || exit 1
export JAVA_HOME="$JDK17"
"$JAVA_HOME/bin/java" -version 2>&1 | head -n 1 | grep -q '"17\.' || {
    echo "✗ JAVA_HOME 不是 JDK 17：$JAVA_HOME" >&2; exit 1; }
```

否则就把注释改成事实：这里不保证 17，只保证能执行。

---

### MEDIUM-03：闸门 A 的 Godot 步骤没有超时，脚本异常会把闸门挂死而不是判红

**File:** `mobile/tools/gate-a.sh:44`、`:54`、`:108`；`mobile/tools/check_pack.gd:33`

**What:** `--script` 加载的 `SceneTree` 只有在脚本调用 `quit()` 时才退出。实测一个只有 `func _initialize(): pass` 的脚本：6 秒后进程仍在跑。两个闸门脚本的每条失败路径都 `quit(1)`，除了 `check_pack.gd:33`：

```gdscript
var sidecar := FileAccess.get_file_as_string(SIDECAR_PATH).strip_edges().split(" ", false)[0]
```

sidecar 为 0 字节时 `split` 返回空数组，`[0]` 越界报错 → 函数中断 → 既没 `quit(0)` 也没 `quit(1)` → **闸门 A 无限挂起**，而 `gate-b.sh` 又调 `gate-a.sh`，整条发布链路一起挂。

**Why it matters:** 评审重点第 5 条要求「必须失败得看得见，绝不能静默通过」；挂死是第三种更糟的形态——没有 token、没有退出码、CI 只会超时。当前只是运气好，sidecar 非空。

**Fix:** 两处都补。脚本侧：

```gdscript
var parts := FileAccess.get_file_as_string(SIDECAR_PATH).strip_edges().split(" ", false)
if parts.is_empty():
    failures.append("sha256 文件是空的: " + SIDECAR_PATH)
else:
    var sidecar := parts[0]
    ...
```

闸门侧给每次 Godot 调用加看门狗（macOS 没有 `timeout`）：

```bash
run_godot() {
    local pid wd rc
    "$@" & pid=$!
    ( sleep 180; kill -9 "$pid" 2>/dev/null ) & wd=$!
    wait "$pid"; rc=$?
    kill "$wd" 2>/dev/null || true
    return "$rc"
}
```

---

### MEDIUM-04：BUILD.md 的 `mv` 在目标已存在时会把新引擎塞进旧 bundle 里，而下一行的版本检查照样绿

**File:** `mobile/BUILD.md:86`

**What:** `mv /tmp/godot472/Godot.app "$HOME/Applications/Godot-4.7.2.app"`。当目标目录已存在时，`mv` 的语义是「移进目录」，实测结果是 `Godot-4.7.2.app/Godot.app/Contents/...`；原 bundle 的可执行文件仍在原处，所以 `:87` 的 `--version` 打印的是**旧的**引擎而不是刚解压的那个。

**Why it matters:** 重建手册在「重装」这个最常见场景下静默什么都没做，而验证步骤看不出来。读者会带着一个自己以为换过、其实没换的引擎继续往下走。

**Fix:** 先删再移，并校验产物确实是刚解压的那份：

```bash
rm -rf "$HOME/Applications/Godot-4.7.2.app"
mv /tmp/godot472/Godot.app "$HOME/Applications/Godot-4.7.2.app"
test -x "$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot"
```

---

### MEDIUM-05：字体源文件从移动分支裸下载、无摘要、缓存只查「非空」

**File:** `tools/make_font_subset.py:66-76`、`:136-139`

**What:** `SOURCE_URLS` 指向 `raw.githubusercontent.com/.../main/...`（两个 `main` 分支），`download()` 不做任何哈希校验，`ensure_source()` 只判 `st_size != 0` 就复用缓存。因此：上游改了字体、或上一次下载被截断，`sync` 会安静地产出**不同的子集**，而 `--check` 只比对「清单 vs 源文件」，看不见子集内容变了（只有 `glyph_coverage.gd` 能抓到「少字」，抓不到「多字/字形改了」）。

**Why it matters:** 本阶段的整个论点是「工具链钉死，产物可重建」，字体是唯一一个从网络取原料的环节。文档没说这一点是例外，读起来像和其他 pin 一样确定。

**Fix:** 给三个源文件各加一个 `readonly SOURCE_SHA256`，在 `download()` 写盘后与 `ensure_source()` 命中缓存后都验一次，不符就 `SystemExit`；顺手把 URL 从 `main` 换成带 commit/tag 的固定引用。

---

### MEDIUM-06：`OFL.txt` 没有任何版权声明行，且只来自 Noto CJK 的 LICENSE

**File:** `mobile/assets/fonts/OFL.txt`（生成方：`tools/make_font_subset.py:75`、`:174-181`）

**What:** 仓库里这份 OFL 从第一行就是 "This Font Software is licensed under the SIL Open Font License"，`grep -i copyright` 只命中许可证正文里的定义句，**没有版权持有者行**。而 APK 里同时分发两个字体（`NotoSansSC-Subset.ttf`、`NotoSansSymbols2-Subset.ttf`），后者在 google/fonts 下的 `OFL.txt` 自带自己的版权行，本脚本根本没取。

**Why it matters:** OFL 的分发条件之一是随附版权声明与许可证。当前既没有 Noto CJK 的版权行，也没有 Symbols2 的；这不是运行时缺陷，但它是**分发物**的合规缺陷，而 APK 已经准备侧载给朋友。

**Fix:** 让 `sync_license` 分别取两个字体的 `OFL.txt`（或 `LICENSE`），按字体分段拼成一份，并断言每段都含 `Copyright`：

```python
if "Copyright" not in text or "SIL OPEN FONT LICENSE" not in text:
    raise SystemExit(f"✗ {source} 不含版权行或许可证正文，拒绝写入")
```

---

### MEDIUM-07：`check_pack.gd` 的断言只覆盖「配置在包里」，闸门 A 的字形断言跑的是**工程目录**而不是导出物

**File:** `mobile/tools/gate-a.sh:107-121`（对照 `mobile/tools/check_pack.gd`）

**What:** `glyph_coverage.gd` 带 `--path mobile` 运行，读的是源码目录里的 `res://assets/fonts/AppFont.tres`（以及 `.godot/imported` 缓存）。一旦 `export_presets.cfg` 的 `include_filter` / `exclude_filter` / `export_filter` 变化把字体挡在包外，字形闸门依旧 `GLYPH_OK`，而 `check_pack.gd` 只处理配置（存在性 / JSON 合法性 / SKILL_COUNT / sha256），完全不碰字体——「字体真的进了包」没有任何机械证据（实测当前是进了的：`assets/.godot/imported/*.fontdata` 两个都在）。

**Why it matters:** 成功标准 2 是「屏幕上不是豆腐」。闸门的两个半边分别证明了「清单与源文件一致」「源码字体不缺字」，但没有一条边把字体和**导出物**连起来；而配置那条边恰好是刻意补上的（`T-02-06`）。同一个论证在字体上缺了一块。

**Fix:** 在 `check_pack.gd` 里补三行（它已经跑在 `--main-pack` 上，天然是对的上下文）：

```gdscript
for path in ["res://assets/fonts/AppFont.tres",
             "res://assets/fonts/NotoSansSC-Subset.ttf",
             "res://assets/fonts/NotoSansSymbols2-Subset.ttf"]:
    if not FileAccess.file_exists(path):
        failures.append("字体不在包里: " + path)
```

---

## LOW

### LOW-01：`doctor.sh` 的 godot 断言接受 `.mono.` 构建，也不钉具体 build hash

**File:** `mobile/tools/doctor.sh:77-89`

**What:** 前缀 `4.7.2.stable.` 同时匹配 `4.7.2.stable.mono.official.<hash>` 与 `4.7.2.stable.custom_build`。而 `mobile/BUILD.md:22` 的表头写的是「标准版，非 .NET」，同一格里还给出了本机完整值 `4.7.2.stable.official.ed1daf0bf`。
**Why:** 文档声称的精确度高于断言的实际强度；换成 .NET 版会把整条导出链路换成另一套（需要 dotnet SDK），而闸门不会红。
**Fix:** 断言里再排除 `*.stable.mono.*`，或直接等号比对 `4.7.2.stable.official.ed1daf0bf`（表里已经给出这个值，没有第二份定义的问题）。

### LOW-02：`keytool` 缺失会被报成「keystore 打不开或别名不存在」

**File:** `mobile/tools/doctor.sh:256-262`

**What:** `resolve_jdk17` 失败时 `keytool_home` 退到 `JAVA_HOME`/默认路径，不检查该路径下有没有 `keytool`；随后 `if ! "$keytool_bin" -list ...` 失败，打印的是「keystore 打不开或别名不存在」。
**Why:** 诊断把人指向密钥库（会让人重新生成、甚至换钥匙），真实原因是找不到 keytool。这类误导在「密钥材料不可逆」的项目里代价很高。
**Fix:** 先 `[ -x "$keytool_bin" ]`，缺失时单独报「找不到 keytool：…（先修 jdk 断言）」。

### LOW-03：`java -version | head -n 1` 在 `pipefail` 下有 SIGPIPE 竞态（同文件里已有正确写法）

**File:** `mobile/tools/doctor.sh:133`、`:159`、`:184`

**What:** `first="$(... | head -n 1)" || first=""`。`java -version` 对 stderr 是无缓冲的多行写入，`head` 读完第一行就退出；若 java 之后仍要写，会收到 SIGPIPE（141），`pipefail` 让整条管线非零，`|| first=""` 把已经取到的版本行**清空**，`resolve_jdk17` 误判为「没有 JDK 17」。本机 200 次未复现，属竞态。
**Why:** 这是假红（闸门偶发失败），而假红最终会被「重跑一次」或「删掉断言」消化掉。同一个文件 `assert_godot:74-75` 已经用了正确写法 `version="${version%%$'\n'*}"`。
**Fix:** 三处统一成先整体取回再截首行：`first="$("$cand/bin/java" -version 2>&1)" || first=""; first="${first%%$'\n'*}"`。

### LOW-04：build-tools 版本号在三处各写一份

**File:** `mobile/tools/gate-b.sh:34`、`mobile/tools/device-smoke.sh:30`（定义处 `mobile/tools/doctor.sh:39`）

**What:** `36.1.0` 在 doctor / gate-b / device-smoke 各出现一次，gate-b 的注释自己承认「两边必须相同」。
**Why:** 这正是 `doctor.sh` 头注释反对的模式（「一旦其它脚本各写一份，其中一份就会悄悄漂移」）。当前漂移会以「找不到 apksigner/aapt2」硬失败，代价可控，但规则被自己破了。
**Fix:** 让 doctor 支持 `doctor.sh sdk --print-build-tools-dir`，另两处改读它；或抽一个 `mobile/tools/paths.sh` 被三处 source。

### LOW-05：`device-smoke.sh` 的固定 `/tmp` 日志与「非空即截图」判定

**File:** `mobile/tools/device-smoke.sh:130`、`:138`、`:163-170`

**What:** 两次安装/启动日志写死 `/tmp/device-smoke-*.log`（不清理、并发跑会互相覆盖；macOS 上应优先 `$TMPDIR`/`mktemp`）。截图只判 `-s`（非空），不判它是不是 PNG。
**Why:** 「非空」对截图来说太弱：锁屏、黑屏、系统错误对话框都是非空 PNG；`exec-out` 若把错误写进 stdout 也会被当成成功。评审重点第 5 条要求真机证据不可伪造，这条断言是目前最软的一环。
**Fix:** 日志改 `"$tmp"`（已有 trap），截图补一行 magic 校验：

```bash
head -c 8 "$screenshot" | od -An -tx1 | grep -q '89 50 4e 47 0d 0a 1a 0a' || { echo "DEVICE_SMOKE_FAIL 截图不是 PNG"; exit 1; }
```

### LOW-06：`device-smoke.sh` 不把「装进去的包」绑定到任何一个被验证过的产物

**File:** `mobile/tools/device-smoke.sh:32`、`:176`

**What:** 脚本只要求 `mobile/build/fifa-trainer.apk` 存在。上一轮遗留、或人手拷进来的同名 APK 会被原样安装，`DEVICE_SMOKE_OK` 里也没有任何摘要，验收表因此无法回指「这一格说的是哪一次构建」。
**Why:** 验收表的核心承诺是「不要把上一次的勾当作这一次的证据」；脚本这边却没有给一个可以写进表格的构建标识。
**Fix:** 在 OK token 里加 `apk_sha256=<前 12 位>`（`shasum -a 256`），并在 `ACCEPTANCE.md` 第 2 节加一列抄录它。

### LOW-07：`gate-b-selftest.sh` 的头部说明与实现不符，且探针不在 trap 里

**File:** `mobile/tools/gate-b-selftest.sh:2-14`、`:30-31`、`:106-114`

**What:** 头注释说「两件事」，实际有三个场景（A/B/C）。`$probe` 不在 `trap` 的清理范围内（Ctrl-C 会在 `mobile/build/` 留下 `unsigned-probe.apk`）。场景 B 在日志里没有 `apksigner sign` 时只打印一行说明就通过——如果导出在签名前就失败，canary 断言会**空转通过**。
**Why:** 反例脚本自身的可信度是整条论证的地基；「永远绿的反例比没有反例更危险」这句注释适用于它自己。
**Fix:** 头注释改成「三件事」；`trap 'rm -rf "$tmp"; rm -f "$probe"' EXIT`；场景 B 在 `grep -q 'apksigner sign'` 失败时判 `SELFTEST_FAIL`（场景 A 已经证明同样的输入能走到签名，这里没有理由容忍）。

### LOW-08：`smoke_screen.gd` 在 `skills` 不是数组时抛错，屏幕留白而不是报错

**File:** `mobile/src/smoke/smoke_screen.gd:40-42`

**What:** `(parsed.get("skills", []) as Array).size()`。若 `skills` 是对象或字符串，`as Array` 得到 `null`，`.size()` 运行时报错，`_header.text` 永远不会被赋值。
**Why:** 验收面板的价值在于「出错时屏幕上有字」。这条路径恰好是配置出错时最需要它说话的时刻，结果屏幕一片空白，人只会记「第①项未通过」而不知道原因。
**Fix:** `var skills = parsed.get("skills", []); if not (skills is Array): _header.text = "配置里 skills 不是数组"; return`。

### LOW-09：`.gitattributes` 没有给 `*.uid` / `*.import` 加行尾规则

**File:** `.gitattributes:1-17`

**What:** 全仓 `* text=auto`，但没有 `*.uid` / `*.import` 的显式规则。这两个后缀正是本阶段刚提交、并被 `verify_clean_export.sh` 当作「产物确定性」证据的边车文件；Windows 上 `text=auto` 会按内容嗅探决定 CRLF。
**Why:** 边车被改写行尾就可能让 Godot 重新分配/忽略 UID，而症状（每台机器抽签导入参数）恰恰是这些文件存在的理由。
**Fix:** 加两行 `*.uid text eol=lf`、`*.import text eol=lf`。

---

## INFO

### INFO-01：发布 APK 里带着两个闸门脚本，且申请了用不到的 VIBRATE 权限

**File:** `mobile/export_presets.cfg:11`、`:45`
`export_filter="all_resources"` 把 `res://tools/check_pack.gd` 与 `glyph_coverage.gd` 编译进包（实测：`assets/tools/check_pack.gdc`、`assets/tools/glyph_coverage.gdc`），`permissions/vibrate=true` 在没有一行震动代码时授予 `android.permission.VIBRATE`。二者都不影响正确性，Phase 3 替换首屏时顺手把 `tools/` 排除即可。

### INFO-02：用编辑器导出对话框会把手输的口令写进 `.godot/export_credentials.cfg`

**File:** `mobile/export_presets.cfg:1-3`
注释已经写明这一点，`mobile/.godot/` 也被 `.gitignore` 覆盖，所以没有提交风险。但 BUILD.md 只写了 CLI 路径，没有一句「不要用 GUI 导出对话框」。与 HIGH-02 一起处理时，加一行禁令即可。

### INFO-03：`smoke_screen.tscn` 的 `ext_resource` 没有 `uid=`

**File:** `mobile/src/smoke/smoke_screen.tscn:3`
4.7 保存场景时会补上 `uid="uid://…"`；一旦有人在编辑器里打开并保存，这个已跟踪文件就会产生一处与改动无关的 diff（`verify_clean_export.sh` 会把它报成漂移，但归因不对）。下次保存时让它自然写入即可。

### INFO-04：BUILD.md 第二节的 `--path mobile` 依赖「当前目录是仓库根」

**File:** `mobile/BUILD.md:51`
命令本身没错，但手册通篇没有说要先 `cd` 到仓库根，而第 250 行的排查条目又用了 `$PWD/mobile/build/...`。加一句「以下所有命令都在仓库根执行」可以省掉一次误诊。

---

## Summary

**Verdict: REQUEST CHANGES。** 本阶段的机械部分质量明显高于平均：`set -euo pipefail` 用得到位，`$var` 后接中文的吞变量问题一处都没有（已全量 grep），`VAR=... bash` 与 `env -u` 的用例都实测过，`--ks <REDACTED>` 也确实是 Godot 自己脱敏而非脚本声明。`gate-a`（PCK 往返、字形 810 字、配置真源）、`gate-b` 的四段静态校验（v2、16 KB 对齐、双 assets、badging）都在本机实际跑通并可复现。

但有四点让「闸门已自证」这个结论现在还不能成立：

1. **闸门 A 的语法断言永远不会失败**（BLOCKER-01）。它不只是弱，是恒真：解析错误、文件不存在都返回 0，`--import`/`--export-pack` 也不拦住。这是本阶段要防的那类假绿的直接复现。
2. **重建手册在第一个下载物上就断了**（HIGH-01，127 位的 SHA-512），并且在同一个文件里既说「口令永远不落盘」又教人把口令写进 `credentials.sh`（HIGH-02，本机已有该文件）。
3. **签名只证明「有 v2」，不证明「是我的钥匙」**（HIGH-03，换钥匙的 APK 实测全绿）。这是项目自己定义为不可逆的那个事故。
4. **字体链路缺一条边**（MEDIUM-07）：字形断言跑在工程目录，包外/包内没有任何断言把字体与导出物连起来。

建议修复顺序：BLOCKER-01（十分钟，含一条反例自测）→ HIGH-03（把指纹变成机器判据，顺带让 BUILD.md §8 的人工步骤少一半）→ HIGH-01 → HIGH-02 → MEDIUM-01/02（把「钉死」真正钉到进程上）。其余 low/info 可以并入 Phase 3 的首屏替换一起做。

修复后请重新跑一次 `bash mobile/tools/gate-a.sh`、`bash mobile/tools/gate-b.sh`、`bash mobile/tools/gate-b-selftest.sh`，并为 BLOCKER-01 增加一条「故意写坏语法必红」的反例——否则这次修复本身也无法被证明。

---

_Reviewed: 2026-11-04T15:36:01Z_
_Reviewer: gsd-code-reviewer (deep, adversarial)_
_Scope: `git log --oneline d6b76b2..HEAD` — 19 commits_
