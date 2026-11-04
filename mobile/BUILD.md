# 移动端构建手册

这份文件是**唯一**的重建依据。照着它做，一台从没参与过本项目的机器应当能导出一份
与 `mobile/build/fifa-trainer.apk` 同签名、同包名、同版本的 APK。

这里只写「人和机器各自要做什么」。所有断言都不在本文件里定义第二份：版本前缀、
模板 SHA-512、密钥库默认路径全在 `mobile/tools/doctor.sh`，导出与校验全在
`mobile/tools/gate-b.sh`。文档与脚本冲突时以脚本为准，并请改文档。

> **这条链路只认 macOS。** 引擎是 macOS universal 包，JDK 与 Android SDK 的路径
> 也按 macOS 写。Linux / Windows 上重导需要换掉这三处的安装位置，其余步骤不变。

---

## 一、这套工具链的精确版本

版本号是**钉死的**，不是「当前值」。`mobile/tools/doctor.sh` 会逐项断言，任一项
不符就非零退出并打印实际值与修法。

| 组件 | 精确版本 | 期望输出（可断言的） | 安装位置 | 校验命令 |
|------|----------|----------------------|----------|----------|
| Godot Engine（标准版，非 .NET） | `4.7.2-stable` | `--version` 落在前缀 `4.7.2.stable.` 下；本机完整值为 `4.7.2.stable.official.ed1daf0bf` | `$HOME/Applications/Godot-4.7.2.app`（可用 `GODOT_BIN` 覆盖） | `bash mobile/tools/doctor.sh godot` |
| 导出模板 | `4.7.2.stable` | 目录名恰为 `4.7.2.stable`，且 `version.txt` 内容逐字为 `4.7.2.stable` | `$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable` | `bash mobile/tools/doctor.sh template` |
| JDK | `17`（本机 `17.0.12`） | `java -version` 首行含 `"17.` | `$HOME/.sdkman/candidates/java/17.0.12-oracle` | `bash mobile/tools/doctor.sh jdk` |
| Android SDK build-tools | `36.1.0` | `apksigner`、`zipalign`、`aapt2` 三个可执行文件都在同一目录下 | `$HOME/Library/Android/sdk/build-tools/36.1.0` | `bash mobile/tools/doctor.sh sdk` |
| Android platform | `android-36` | 目录 `platforms/android-36` 存在 | `$HOME/Library/Android/sdk/platforms/android-36` | `bash mobile/tools/doctor.sh sdk` |
| platform-tools（adb） | `36.0.2` | `adb` 可执行（只有真机验收才用到） | `$HOME/Library/Android/sdk/platform-tools/adb` | `bash mobile/tools/doctor.sh sdk` |
| release 密钥库 | 别名 `fifa-trainer` | `keytool` 能打开且别名存在 | `$HOME/.fifa-trainer/release.keystore`（**仓库外**） | `bash mobile/tools/doctor.sh keystore` |

`--version` 那一条**只能前缀匹配**。完整输出带 `.official.<hash>` 后缀，写成等号
比较会永远红 —— 而最容易的「修法」是把断言删掉，那就等于放弃版本锁定。

---

## 二、先设 `JAVA_HOME`，再跑第一次导入

> **顺序不能反。** Godot 第一次 `--import` 会把**当时**的 `JAVA_HOME` 写进
> `editor_settings-4.7.tres` 的 `export/android/java_sdk_path`。顺序反了，这台机器
> 之后每一次导出都用错 JDK，而磁盘上每个文件看起来都「存在」。

系统默认 JDK 是 25。构建只认 17，但我们**不改系统默认值**，只在构建进程里显式选定：

```bash
export JAVA_HOME="$HOME/.sdkman/candidates/java/17.0.12-oracle"
"$JAVA_HOME/bin/java" -version    # 首行应是 java version "17.0.12"
```

设好之后再让 Godot 碰工程：

```bash
"$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot" --headless --path mobile --import
```

**怎么检查写进去的是什么：**

```bash
grep 'java_sdk_path' "$HOME/Library/Application Support/Godot/editor_settings-4.7.tres"
```

值里应当出现 `17.0.12-oracle`。若出现的是 JDK 25 的路径，说明导入时机早于设变量。

**写错了怎么修：** 删掉那份 `editor_settings-4.7.tres`（或者只把 `java_sdk_path`
那一行改成 JDK 17 的路径），然后在**已经设好 `JAVA_HOME` 的同一个 shell** 里重跑
上面那条 `--import`。删掉设置文件是安全的：它是一次性的编辑器偏好，不属于工程。

注意 `mobile/tools/doctor.sh` 的 `jdk` 一项会在 `editor_settings` 已存在时同时校验
这一点 —— 它不只是查路径存在，而是实跑 `java -version` 比对主版本。

---

## 三、下载并校验，校验通过之前不解压

两个下载物都来自官方 GitHub Releases。**先校验，后解压**；校验失败就删掉重下，
不要在「可能是网络抖动」的猜想上继续往下走。

### Godot 引擎

```bash
curl -fL -o /tmp/godot472.zip \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip

echo '38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7ac69ca  /tmp/godot472.zip' | shasum -a 512 -c -

mkdir -p "$HOME/Applications"
unzip -q -o /tmp/godot472.zip -d /tmp/godot472
mv /tmp/godot472/Godot.app "$HOME/Applications/Godot-4.7.2.app"
"$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot" --version   # 4.7.2.stable.official.ed1daf0bf
```

包大小 170,622,178 B。压缩包里只有一个 `Godot.app`，要不要保留 `.zip` 随你 —— 它
不会被任何脚本再读一次。

### 导出模板

```bash
curl -fL -o /tmp/templates.tpz \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz

echo 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079  /tmp/templates.tpz' | shasum -a 512 -c -

DEST="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
mkdir -p "$DEST" && unzip -q -o /tmp/templates.tpz -d /tmp/tpl && cp -R /tmp/tpl/templates/. "$DEST/"
ls "$DEST"/android_release.apk
```

`.tpz` 有 1,281,349,702 B，解压后约 1.9 GB。**解压完立刻删掉 `.tpz` 与 `/tmp/tpl`**：

```bash
rm -rf /tmp/templates.tpz /tmp/tpl
```

为什么不留：模板的**来源**是下载期那一次哈希建立的，事后无法从解压目录反推回来。
这也是为什么 `doctor.sh` 的 `template` 断言只负责抓「装错了版本 / 装漏了」——
装对版本但来源可疑的模板，它看不出来。`doctor` 失败时会把上面整串摘要与那条
`shasum -a 512 -c -` 命令再打一遍，正是为了让重装也从校验开始。

### 从浏览器下载的情况

用浏览器存的包会被 Gatekeeper 打上隔离标记，解压出来的 `Godot.app` 首次运行会被拦。
用上面的 `curl` 就没有这个问题；如果包确实是从浏览器来的：

```bash
xattr -dr com.apple.quarantine "$HOME/Applications/Godot-4.7.2.app"
```

---

## 四、release 密钥库

签名身份是**不可变的**。它一旦发给朋友，就不能再换 —— 换了就是另一个 app，
覆盖安装会变成「必须卸载、`user://` 数据全丢」。

| 事实 | 值 | 可覆盖点 |
|------|-----|----------|
| 位置 | `$HOME/.fifa-trainer/release.keystore`（**仓库外**） | `FIFA_KEYSTORE` |
| 别名 | `fifa-trainer` | `FIFA_KEYSTORE_ALIAS` |
| 口令 | 只在环境变量 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 里 | — |
| 格式 | PKCS12，`-rw-------`，只有本用户可读 | — |

两个覆盖点的默认值必须与 `mobile/tools/doctor.sh` 里的 `KEYSTORE_PATH` /
`KEYSTORE_ALIAS` **逐字相同**。改一处就要改两处，否则会出现「doctor 说密钥库好、
闸门却拿另一把钥匙去签」。

**口令永远不落盘。** 从密码管理器取出后 export 到当前 shell：

```bash
set -a; . "$HOME/.fifa-trainer/credentials.sh"; set +a   # 本机做法：口令在脚本里，脚本在仓库外
```

`keytool` 一律用 `-storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 读口令，
命令行里不出现值：

```bash
keytool -list -v -alias fifa-trainer \
  -keystore "$HOME/.fifa-trainer/release.keystore" \
  -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

**闸门 B 只需要导出这一个变量。** 路径与别名由 `gate-b.sh` 自己从上面那对默认值
解析出来 —— 不需要再设 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` 或
`GODOT_ANDROID_KEYSTORE_RELEASE_USER`，它们由脚本在调用 Godot 时填充。要求调用者
再导两个恒定变量，只会多制造一种「忘了 export」的红，那种红与包打成没打成无关，
迟早会被注释掉。

**备份策略（这是成功标准 5 的人工部分）：**

- 离线介质**至少两处**，两处不同址或不同设备；
- 口令与密钥库文件**分开存放**（一个在密码管理器，一个在离线介质）；
- 恢复演练：从备份拷回一个临时目录，用上面的 `keytool -list` 打开一次，确认别名与
  指纹都对得上，再删掉临时副本。

填表落点在 `mobile/ACCEPTANCE.md` 第 4 节。那里留空，等于成功标准 5 没闭合。

---

## 五、一条命令导出

```bash
export JAVA_HOME="$HOME/.sdkman/candidates/java/17.0.12-oracle"
set -a; . "$HOME/.fifa-trainer/credentials.sh"; set +a
bash mobile/tools/gate-b.sh
```

它内部依次做五段，任何一段失败都非零退出并打印原始输出：

1. **`doctor.sh` 五项** —— 引擎 / 模板 / JDK / SDK / 密钥库。`device` 不在这里：
   导出不需要插手机。
2. **闸门 A** —— 配置单一真源、GDScript 语法、PCK 往返读到 `SKILL_COUNT = 5`、
   字形逐字符覆盖。
3. **删旧产物** —— `rm -f mobile/build/fifa-trainer.apk`。这一行是「文件存在即成功」
   的分界线：Godot 导出器先写包后签名，缺密钥库时它照样留下一个大小正常的未签名
   APK，上一轮的产物会冒充这一轮的成功。
4. **`--export-release Android`** —— 用 release 密钥库签出 `mobile/build/fifa-trainer.apk`。
5. **四段静态校验** —— `apksigner verify`（含 v2）、`zipalign -c -P 16`
   （16 KB 页对齐）、`unzip -l`（双 `assets/assets/config/` 路径、无 x86 库、无
   `.idsig` / 密钥库）、`aapt2 dump badging`（包名 / `versionCode` / `versionName` /
   `arm64-v8a` / `minSdkVersion`）。

末行是 `✓ 闸门 B 通过`。**本文件不复制这些校验命令**：它们在 `gate-b.sh` 里只有
一份定义，这里再抄一份就等于制造第二份会漂移的规范。

---

## 六、同一把钥匙的指纹

Phase 9 的覆盖安装认的是**签名**，不是包名。下面是这把钥匙的证书指纹，
来源是 `apksigner verify --verbose --print-certs` 的输出：

```
Signer #1 certificate DN: CN=FIFA Skill Trainer, OU=Personal, O=fifaskill, C=CN
Signer #1 certificate SHA-256 digest: e1841a17bda43307cdfc8e9e757c672a6a91b7fd60ea86e715afd461ba32e046
Signer #1 certificate SHA-1 digest:   7f20b2f115b55ece5a9120e1a4fde8fc08127988
```

同一个值的冒号分隔写法（`keytool -list -v` 的输出形状）：

```
SHA256: E1:84:1A:17:BD:A4:33:07:CD:FC:8E:9E:75:7C:67:2A:6A:91:B7:FD:60:EA:86:E7:15:AF:D4:61:BA:32:E0:46
```

**Phase 9 覆盖安装前必须先核对这一行。** 两串是同一个摘要的两种写法：连续小写
十六进制来自 `apksigner`，冒号大写来自 `keytool`。核对命令：

```bash
"$HOME/Library/Android/sdk/build-tools/36.1.0/apksigner" verify --verbose --print-certs \
  mobile/build/fifa-trainer.apk | grep 'certificate SHA-256 digest'
```

对不上就是换了钥匙 —— 此时不要装，先弄清楚为什么。

同一节记下另外三个**不可变事实**：包名 `com.fifaskill.trainer`、
`versionCode` 起点 `1`（`versionName 0.1.0`）、keystore 别名 `fifa-trainer`。
它们由 `gate-b.sh` 的 badging 断言与导出参数共同锁定。

---

## 七、故障排查

**导出直接失败，日志里有 `import_etc2_astc`**
`mobile/export_presets.cfg` 的 `gradle_build/use_gradle_build` 与纹理导入格式没对上。

- 工程用 `gl_compatibility` 渲染后端，导出预设必须开 `import_etc2_astc=true`。
- 改完预设要重新导入一次：`--headless --path mobile --import`。
- 检查：`grep -n 'import_etc2_astc' mobile/export_presets.cfg`

**产物落在 `mobile/mobile/build/…`**
Godot 把导出路径按工程目录解析，相对路径于是叠了一层。

- `gate-b.sh` 传的是绝对路径，所以走闸门不会遇到。
- 手跑导出时一律给绝对路径：`--export-release "Android" "$PWD/mobile/build/fifa-trainer.apk"`。
- 已经生成了 `mobile/mobile/` 就整目录删掉，它不是产物的一部分。

**导出成功，但 APK 装不上 / 提示未签名**
缺密钥库或口令错时，Godot 以退出码 1 收场，磁盘上却留下一个大小正常的未签名 APK。

- 先删掉它：`rm -f mobile/build/fifa-trainer.apk`。
- 再确认三件事：密钥库文件在、别名对、口令变量已 export。
- 验签：`…/build-tools/36.1.0/apksigner verify --verbose --print-certs mobile/build/fifa-trainer.apk`

**`doctor.sh jdk` 说 `java_sdk_path` 指向 JDK 25**
第一次 `--import` 发生在设 `JAVA_HOME` 之前，见第二节。

- 删掉 `$HOME/Library/Application Support/Godot/editor_settings-4.7.tres`。
- 在设好 `JAVA_HOME` 的同一个 shell 里重跑 `--import`。
- 复查：`grep 'java_sdk_path' "$HOME/Library/Application Support/Godot/editor_settings-4.7.tres"`

**`doctor.sh godot` 说版本不对，但 `--version` 看着是对的**
断言用的是前缀匹配，人眼容易把它当等号。

- 实际输出是 `4.7.2.stable.official.ed1daf0bf`，末尾还有 `.official.<hash>`。
- 正确的判据是「以 `4.7.2.stable.` 开头」。
- 若真的装了 4.8 之类，用 `GODOT_BIN` 指向正确的那份，或按第三节重装。

**导出末尾刷出 `cannot connect to daemon at tcp:5037`**
这是 Godot 试图 `adb` 找设备装包，属固定噪声，不影响产物。

- 导出不需要手机；这条输出每次都会出现。
- 判据只看退出码与 `gate-b.sh` 之后的四段校验，不要 grep 日志里的 `ERROR`。

**`mobile/build/` 里多出一个 `fifa-trainer.apk.idsig`**
Godot 调 `apksigner` 时生成的 v4 旁文件（增量安装用），不是包的一部分。

- `.gitignore` 已覆盖 `*.idsig`；分发时只拷 `.apk`。
- 想确认它没进包：`unzip -l mobile/build/fifa-trainer.apk | grep idsig` 应当无输出。

**干净 clone 上直接导出报「文件找不到」**
`.godot/` 导入缓存不随仓库走，第一次必须先导入。

- 顺序是 `--import` → `--export-release`，不能跳。
- `bash mobile/tools/gate-a.sh` 会替你做导入；`gate-b.sh` 的第一段就是它。

**干净 clone 跑完 `--import` 后 `git status` 冒出未跟踪的 `*.import` / `*.uid`**
这是 Godot 的**导入边车**（`.import` 钉住导入参数与目标路径，`.uid` 钉住脚本 UID），
它们属于提交物；漏提交才会冒出来。

- 症状是 `?? mobile/assets/fonts/xxx.ttf.import` 或 `?? mobile/tools/xxx.gd.uid`。
- 原因：边车被漏提交，或被误加进 `.gitignore`。忽略它们的代价是每台机器重新抽签
  导入参数与资源 UID，产物随之漂移。
- 修法是**补提交**，不是加忽略规则：`git add mobile/**/*.import mobile/**/*.uid`
- 机械检查：`bash mobile/tools/gate-b.sh` 之后的零漂移断言会以 `??` 指出具体路径；
  `mobile/tools/verify_clean_export.sh` 则在跑闸门之前就逐个点名五个边车。

---

## 八、在另一台干净机器上重导出

前提：那台机器上**没有**本项目的任何构建产物，也**没有**装过 Godot / 模板 / SDK。

1. 装齐第一节表里的每一项。每装一项就跑一次对应的
   `bash mobile/tools/doctor.sh <断言名>`，绿了再装下一项 —— 一次装完再查，
   出错时不知道是哪一步。
2. 按第三节下载引擎与模板，**先校验再解压**，解压后删掉 `.tpz`。
3. 按第二节设 `JAVA_HOME`，然后才允许 Godot 第一次 `--import`。
4. 把 release 密钥库从离线备份拷到 `$HOME/.fifa-trainer/release.keystore`，
   `chmod 600`，并用 `keytool -list` 确认别名 `fifa-trainer` 可读。
5. clone 仓库。
6. `export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`（值从密码管理器取，不写进任何文件）。
7. `bash mobile/tools/gate-b.sh` —— 必须绿，末行 `✓ 闸门 B 通过`。
8. 核对第六节的证书 SHA-256：`apksigner verify --verbose --print-certs` 打出来的
   必须与文档里那串逐字相同。**这一步不通过，就说明那台机器上装的是另一把钥匙。**

第八步是这整节的判据。前七步全绿但指纹不同，等于导出了一个「看起来能装、
装上去会把旧数据锁在外面」的包。

> **`mobile/tools/verify_clean_export.sh` 只能证明仓库状态足够。** 它在 `git clone`
> 出来的临时目录里重跑闸门 B 并断言零漂移，用的是**本机**的 Godot、模板、JDK、SDK
> 与密钥库 —— 那些都是机器状态，不随仓库走。一台全新机器够不够，只有这一节的人
> 能回答。
