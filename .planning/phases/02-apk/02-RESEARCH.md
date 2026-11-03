# Phase 2: 安卓工具链 + 真机冒烟 APK - Research

**Researched:** 2026-11-04
**Domain:** Godot 4.7.2-stable → 签名 arm64 APK（macOS 宿主）· CJK 字体 · `res://` 配置入包 · 安卓手柄原始轴
**Confidence:** **HIGH 对工具链与导出链路**（全部在本机用 4.7.2-stable 实际跑通：导入、打包、签名、校验 16 KB 对齐、字体覆盖探针）；**LOW/MEDIUM 对真机**（本机无手机、无手柄、无模拟器，所有"手机上看起来对不对"的结论仍需真机验收）

---

## Summary

这一阶段的研究结论是**「链路已经跑通，风险不在能不能做，而在文档与闸门能不能防止下一次做错」**。我用官方 4.7.2-stable macOS 包 + 官方导出模板 + 本机已有 JDK 17 + 本机已有 build-tools 36.1.0，在一台原本**没有装过 Godot**的机器上，从零走完了 `--import → --export-release → apksigner → zipalign -c -P 16` 全链路，产出一个 26.5 MB、仅含 `arm64-v8a`、v2+v3 签名、16 KB 对齐通过的 release APK。也就是说：**成功标准 1/5 的技术前提已被证明成立**，剩下的是把这条链路固化成脚本 + 文档，并把三条真机判据（中文不豆腐、`SKILL_COUNT=5`、手柄原始轴）在真实设备上验一遍。

研究中出现了**六个会直接改变计划写法的发现**，都不是文档能直接读到的：

1. **`*.json` 在 4.7.2 里已经算「资源」，不加 `include_filter` 也会进包。** 官方 troubleshooting 页那句"JSON 不是资源，必须加过滤"对 4.7.2 已经过期（`ResourceLoader.get_recognized_extensions_for_type("JSON")` 返回 `["tres","res","json"]`，实测无过滤器仍入包）。**但 `.sha256` 不是资源，不加过滤就丢**。所以"记得加 `*.json` 过滤"不能当验收，验收必须是"从包里读出来"。
2. **可以在没有导出模板的情况下先做一次 `--export-pack` 闸门。** `--export-pack` 不需要 Android 模板、不需要签名、几秒内出 PCK；配合 `--main-pack` 跑一个读配置的脚本，就能在 CI 里证明「配置真的进包且能读」。这把成功标准 3 的自动化成本从 1.9 GB 模板降到零。
3. **Noto Sans SC 没有 `✗`（U+2717）。** `° ± → ✓` 都有，唯独 `✗` 缺。要满足成功标准 2 里写死的 `✓ ✗`，必须再挂一个符号 fallback 字体（Noto Sans Symbols 2 子集 6.6 KB）。这不是"可选优化"，是判据能不能过的硬条件。
4. **导出失败会在磁盘上留下一个未签名 APK。** 缺 keystore 时 Godot 打印"找不到发布密钥库"，退出码 1，但 `nokey.apk`（26.5 MB）照样躺在 `build/` 里。任何"文件存在即成功"的判据都是假的，必须 `apksigner verify`。
5. **编辑器设置可以被 headless 首次运行自举。** 删掉 `editor_settings-4.7.tres` 后，只要 `JAVA_HOME` 指向 JDK 17，`godot --headless --path mobile --import` 会自动写出 `export/android/java_sdk_path = $JAVA_HOME` 与 `android_sdk_path = ~/Library/Android/sdk`。这直接决定了成功标准 5（另一台干净机器能重导出）的可行路径：**不需要开编辑器 GUI**。
6. **Phase 1 生成的 `.sha256` 是 shasum 格式（`摘要 + 两个空格 + 文件名`），不是裸摘要。** 移动端如果照"字符串相等"去校验，永远失败。已经在 `check_pack.gd` 示例里改成取第一个空白字段 [VERIFIED: tools/sync_config.py:98-99]。

**Primary recommendation:** 分三段交付，每段都有独立的机械闸门：**(a) 工具链自举 + `doctor` 脚本**（版本、模板、JDK 17、SDK、keystore 五项断言）→ **(b) 最小工程 + 字体 + 首屏 smoke 场景 + 无模板 PCK 闸门**（证明配置与字形，完全不碰手机）→ **(c) 导出预设 + release keystore + APK 静态闸门 + 真机验收 + BUILD.md**。前两段可以在没有手机的情况下全部做完并全部自动化；只有最后的"两台 OEM 手机 + 蓝牙手柄"必须人来做，且这部分不许用模拟器冒充。

---

## 前置约束（本阶段没有 CONTEXT.md）

`.planning/phases/02-apk/` 下没有 `CONTEXT.md`（Phase 2 未走 discuss）。以下约束来自 `PROJECT.md`、`ROADMAP.md`、`STATE.md` 与 Phase 1 的 D-10 决策，效力等同锁定决策，研究不得与之冲突：

| 编号 | 约束 | 来源 |
|------|------|------|
| P-01 | **版本锁死 Godot `4.7.2-stable`**，导出模板必须是 `4.7.2.stable`（含 `.stable`）。禁止用 4.8 打开工程（会静默升级工程格式） | `research/STACK.md`；ROADMAP 成功标准 5 |
| P-02 | `project.godot` **由本阶段创建**，Phase 1 明确不做（D-10） | `mobile/README.md`；Phase 1 D-10 |
| P-03 | 渲染后端 **Compatibility (GL Compatibility)**，把 minSdk 压回 24 | `research/STACK.md` |
| P-04 | `shared/skills_config.json` 是唯一真源；`mobile/assets/config/` 下的 `.json` 与 `.sha256` 是**生成物，不可手改** | Phase 1 D-04 / `tools/sync_config.py` |
| P-05 | 本阶段**不做设备输入层**（轴探针、扳机校准、热插拔归 Phase 4）。这里只要能看见原始轴在动 | ROADMAP Phase 2 排序理由 |
| P-06 | **真机是退出条件**，模拟器只能做布局截图，不能替代任何一条成功标准 | ROADMAP「真机是退出条件」 |
| P-07 | 标识符/配置键英文 ASCII；文档、注释、错误、用户可见文案中文 | `AGENTS.md` 项目约定 |
| P-08 | 包名 / keystore / versionCode **现在就要定死**，因为 Phase 9 的 v1→v2 覆盖安装依赖它们不变 | ROADMAP Phase 9 成功标准 2 |

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-04 | 真机冒烟 APK：能安装、能启动、能读到原始轴值 | §Standard Stack（工具链精确版本与安装路径）、§Architecture Patterns 模式 1/2（三段式闸门 + headless 自举）、§Code Examples 1–3（已验证的 `project.godot` / `export_presets.cfg` / 导出脚本）、§Validation Architecture（A/B/C 三层，A 层完全无设备） |

**映射到成功标准：**

| 成功标准 | 本研究中被证明的部分 | 仍需真机 |
|----------|----------------------|----------|
| 1. 签名 APK 装机启动、不经编辑器 | 签名 release APK 已产出并 `apksigner` 验证；全程 `--headless`，无 GUI | 装机、启动、首屏 |
| 2. 两台 OEM 无豆腐块 | 139 字字形覆盖集合已确定；`✗` 缺失已定位；双字体方案已在 headless 通过 `has_char` 断言 | 两台真机截图 |
| 3. `res://assets/config/` 读到且 `SKILL_COUNT=5` | 已从导出的 PCK 里用 `FileAccess` 读出 9117 字节、解析出 5 条 skills | 手机上屏幕上显示 5 |
| 4. 蓝牙手柄推动右摇杆，原始轴实时变化 | 脚本形状已 `--check-only` 通过；`Input.get_joy_axis` / `joy_connection_changed` 签名已核对 | 真手柄 + 真手机 |
| 5. BUILD.md 精确版本 + keystore 备份 + 另一台机器能重导出 | 干净设置状态下的 headless 自举已实测；keystore 生成与 env 注入已实测 | 第二台物理机器实操一遍 |
</phase_requirements>

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| 引擎与导出工具链版本 | **宿主 / 构建机** | — | 版本错配是本项目最高频的"卡三天"问题，必须在机器层钉死，不能靠人记 |
| `project.godot` / `export_presets.cfg` | **仓库（`mobile/`）** | — | 工程配置是源码，必须可 review、可 diff、可复现 |
| 编辑器设置（SDK/JDK 路径） | **宿主 / 构建机** | 仓库文档（BUILD.md） | 属于"机器状态"，不进仓库；但必须有一份文档 + `doctor` 把它变成可检查的断言 |
| 字体与字形覆盖 | **仓库（`mobile/assets/fonts/`）** | — | 内嵌子集 + fallback 是唯一跨 OEM 确定的行为；系统字体只作兜底，不可作主路径 |
| 技能配置 | **仓库（`shared/` 生成到 `mobile/assets/config/`）** | 运行期只读 `res://` | 单一真源在 Phase 1 已定，这里只负责"真的进包" |
| 首屏 smoke UI | **移动端应用（`mobile/`）** | — | 成功标准 2/3/4 全部靠这一屏一次性证明，不分散到多个界面 |
| 手柄原始轴读数 | **引擎 `Input`（平台层）** | 应用层只做显示 | 轴序号是 Android 平台事实，应用层不解释、不映射、不猜（映射归 Phase 4） |
| 签名与版本号 | **构建机 + keystore 离线备份** | 仓库只存非密配置 | 密钥不能进仓库；版本号必须单一来源 |

---

## Standard Stack

### Core

| 组件 | 版本 | 用途 | 为什么是它 |
|------|------|------|-----------|
| Godot Engine（标准版，非 .NET） | **4.7.2-stable**（发布 2026-08-18T16:12:28Z） | 引擎 / 导出 | 当前 stable 分支最新补丁；4.8 仍是 beta2 [VERIFIED: GitHub Releases API] |
| macOS 包 | `Godot_v4.7.2-stable_macos.universal.zip`，170,622,178 B | 宿主可执行文件 | 官方只提供 universal（arm64+x86_64）一种 macOS 包，无独立 arm64 资产 [VERIFIED: 4.7.2-stable release assets] |
| SHA-512 | `38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca` | 下载校验 | 来自官方 `SHA512-SUMS.txt` [VERIFIED: 该文件内容] |
| 导出模板 | `Godot_v4.7.2-stable_export_templates.tpz`，1,281,349,702 B，解压后 **~1.9 GB** | 打 APK 必需 | 内含 `templates/android_debug.apk` + `android_release.apk` + `version.txt`（内容 = `4.7.2.stable`）[VERIFIED: 解压实测] |
| 模板 SHA-512 | `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079` | 下载校验 | 同上 [VERIFIED] |
| JDK | **17**（本机已有 `~/.sdkman/candidates/java/17.0.12-oracle`） | keystore / apksigner | 官方："Higher versions of the JDK are also supported, but we recommend using JDK 17" [CITED: docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html] |
| Android SDK | `~/Library/Android/sdk`，**build-tools 36.1.0**、platform-tools 36.0.2 | `apksigner` / `zipalign` / `aapt2` / `adb` | 本机已装；`zipalign`/`apksigner`/`aapt2` 均存在于 `build-tools/36.1.0/` [VERIFIED: 目录列举] |
| 渲染后端 | `gl_compatibility` | 2D | minSdk 24（Vulkan 路径强制 29）[CITED: research/STACK.md 源码核实] |

### Supporting

| 组件 | 版本 | 用途 | 何时用 |
|------|------|------|--------|
| Noto Sans SC（可变字体，SC 子集） | 17,356.6 KB 源文件 → **子集 66.3 KB** | 中文主字体 | 必用。覆盖 109 个 CJK 字形 + `° ± → ✓ ×` |
| Noto Sans Symbols 2 | 1,204.2 KB 源文件 → **子集 6.6 KB** | 符号 fallback | 必用。补 `✗`（SC 没有） |
| SIL OFL 1.1 许可证文本 | — | 合规 | 随字体一起进包/进仓库。OFL 要求保留版权声明与许可证 [CITED: noto-cjk/Sans/LICENSE] |
| `fonttools` 4.60.2（PyPI） | 仅一次性开发工具 | 生成字体子集 | **不进入构建链路**：子集产物提交进仓库后，构建不再需要 fonttools |
| `uv` 0.9.5 | 已有 | 跑一次性字体脚本 / 现有 Python 工具 | 复用，不新增工具链 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 官方 zip + 固定路径 | `brew install --cask godot` | cask 今天恰好是 4.7.2 [VERIFIED: `brew info --cask godot`]，但 `brew upgrade` 会把它推到 4.8 —— 与 P-01 直接冲突。**不写进 BUILD.md 的主路径**，最多作为"想先看一眼"的旁路 |
| 官方 zip | Godot 官方 `.dmg` | 4.7.2 的 macOS 资产只有 `.zip`，没有 dmg [VERIFIED: release assets] |
| 内嵌子集 + 符号 fallback | 纯 `SystemFont` | 官方明说安卓系统字体加载**不可靠**（无官方 API，靠解析厂商可改的配置文件）[CITED: gui_using_fonts.html]；本项目的 UI 全是中文，赌不起 |
| 内嵌子集 + 符号 fallback | 只嵌 Noto Sans SC，把 `✗` 换成 `×` | 少一个字体、少一次 fallback；但成功标准 2 写死了 `✓ ✗`，换字符等于改验收标准，需要用户确认 |
| `--export-pack` 做无设备闸门 | 直接上模板打 APK | 打 APK 需要 1.9 GB 模板 + JDK + SDK + keystore；PCK 闸门 7 秒、零依赖，应作为第一道闸 |

**Installation:**

```bash
# 1) Godot 4.7.2-stable（不覆盖系统里任何东西；路径固定、版本可断言）
mkdir -p "$HOME/Applications"
curl -L -o /tmp/godot472.zip \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip
echo "38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca  /tmp/godot472.zip" | shasum -a 512 -c -
unzip -q -o /tmp/godot472.zip -d /tmp/godot472 && mv /tmp/godot472/Godot.app "$HOME/Applications/Godot-4.7.2.app"
"$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot" --version   # 4.7.2.stable.official.ed1daf0bf

# 2) 导出模板（目录名必须是 4.7.2.stable，取自 tpz 内 version.txt）
curl -L -o /tmp/templates.tpz \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
echo "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079  /tmp/templates.tpz" | shasum -a 512 -c -
DEST="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
mkdir -p "$DEST" && unzip -q -o /tmp/templates.tpz -d /tmp/tpl && cp -R /tmp/tpl/templates/. "$DEST/"
ls "$DEST"/android_release.apk

# 3) 字体子集（一次性；产物提交，之后构建不再需要 fonttools）
uv run --with fonttools pyftsubset NotoSansSC-VF.ttf \
  --text-file=subset_text.txt --output-file=NotoSansSC-Subset.ttf \
  --layout-features='*' --drop-tables+=DSIG
uv run --with fonttools pyftsubset NotoSansSymbols2-Regular.ttf \
  --text-file=sym_text.txt --output-file=NotoSansSymbols2-Subset.ttf \
  --layout-features='*' --drop-tables+=DSIG
```

**Version verification（本机已实测）:**

```bash
"$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot" --version
# 期望前缀：4.7.2.stable.  （完整输出是 4.7.2.stable.official.ed1daf0bf —— 不是等号比较，是前缀匹配）
cat "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/version.txt"   # 4.7.2.stable
"$HOME/.sdkman/candidates/java/17.0.12-oracle/bin/java" -version 2>&1 | head -1           # 17.0.12
ls "$HOME/Library/Android/sdk/build-tools/36.1.0/apksigner"
```

> **注意**：`--version` 输出带 `.official.<hash>` 后缀。STACK.md 里"输出必须等于 `4.7.2.stable`"这句话按字面理解会误红，必须是前缀/正则匹配。

---

## Package Legitimacy Audit

本阶段**不通过 npm/PyPI 安装任何运行时依赖**。唯一新增的可执行物是 Godot 编辑器压缩包（GitHub Releases，SHA-512 钉死）与两套 OFL 字体（源文件 + 子集产物都落仓库）。`fonttools` 只用于**一次性**生成字体子集，产物提交后构建链路不再需要它。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `fonttools` | PyPI | 项目极老（4.x 系列发布史可追溯到多年），但 `package-legitimacy` 按"最新版本发布时间 2026-10-27"判为 too-new | 未取得 | github.com/fonttools/fonttools | **SUS**（`too-new`, `unknown-downloads`） | **保留但降级为一次性工具**：不在构建/CI 链路里依赖；若要装，planner 加一个 `checkpoint:human-verify` |
| `Noto Sans SC` | 非包管理器（notofonts/noto-cjk 仓库） | 长期维护 | — | github.com/notofonts/noto-cjk | 非 npm/PyPI，不走本闸门 | 提交**子集产物** + OFL 许可证全文 |
| `Noto Sans Symbols 2` | 非包管理器（google/fonts） | 长期维护 | — | github.com/google/fonts | 同上 | 同上 |
| Godot 4.7.2-stable | GitHub Releases | 2026-08-18 | — | github.com/godotengine/godot | 非包管理器 | SHA-512 + `--version` 双重钉死 |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** `fonttools` —— 只作为一次性字体子集工具，**不得**进入 `pyproject.toml` 的运行期依赖；若执行阶段需要联网安装，先做人工确认。

*说明：`package-legitimacy` 对 `fonttools` 的 `too-new` 判定来自"最新 release 时间"，对这样一个长期存在的项目属于启发式误报；但按协议仍记为 SUS 并给出处置。规避方式很简单——**不要把 fonttools 放进构建链**。*

---

## Architecture Patterns

### System Architecture Diagram

```
                     ┌──────────────────────────── 宿主机器状态（不进仓库） ────────────────────────────┐
                     │ Godot 4.7.2.app   export_templates/4.7.2.stable/   JDK17   Android SDK 36.1.0   │
                     │        │                    │                        │              │          │
                     │        └── editor_settings-4.7.tres（java_sdk_path / android_sdk_path）──────────┤
                     └────────┼────────────────────┼────────────────────────┼──────────────┼──────────┘
                              │                    │                        │              │
  ┌───────────────────────────▼────────────────────▼────────────────────────▼──────────────▼─────────┐
  │ tools/android_doctor.sh —— 五项断言（版本 / 模板 / JDK17 / SDK 组件 / keystore）                      │
  │   任一不满足 → 非零退出 + 指名人话修复建议；全满足 → 打印解析后的实际路径                              │
  └───────────────────────────┬──────────────────────────────────────────────────────────────────────┘
                              │
  ┌───────────────────────────▼───────────┐      ┌──────────────────────────────────────────────────┐
  │ shared/skills_config.json（唯一真源）   │─────▶│ tools/sync_config.py → mobile/assets/config/      │
  └───────────────────────────────────────┘      │   *.json + *.sha256（生成物，禁止手改）             │
                                                 └───────────────────┬──────────────────────────────┘
                                                                     │
  ┌──────────────────────────────────────────────────────────────────▼───────────────────────────────┐
  │ mobile/ 工程（进仓库）                                                                             │
  │   project.godot   export_presets.cfg   assets/config/*   assets/fonts/*.ttf + AppFont.tres        │
  │   src/ 首屏 smoke 场景（SKILL_COUNT / 最长中文串 / ° ± → ✓ ✗ / 轴读数）                            │
  └───────────────┬──────────────────────────────────┬───────────────────────────────────────────────┘
                  │                                  │
   ┌──────────────▼───────────────┐     ┌────────────▼──────────────────────────────────────────────┐
   │ 闸门 A：无模板 / 无设备        │     │ 闸门 B：需要模板 + JDK + SDK（仍无设备）                     │
   │  --import                     │     │  --export-release Android → build/*.apk                    │
   │  --check-only *.gd            │     │  apksigner verify（v2/v3）                                 │
   │  --export-pack → *.pck        │     │  zipalign -c -P 16 -v 4                                    │
   │  --main-pack + 读配置脚本      │     │  unzip -l（assets/config、只有 arm64、无 .idsig/keystore）   │
   │  glyph_coverage.gd（字体字形）  │     │  aapt2 dump badging（包名 / versionCode / minSdk / ABI）     │
   └──────────────┬───────────────┘     └────────────┬──────────────────────────────────────────────┘
                  │                                  │
                  └──────────────┬───────────────────┘
                                 │ 两道闸全绿
                    ┌────────────▼──────────────────────────────────────────┐
                    │ 闸门 C：真机（人 + 2 台不同 OEM 手机 + 真手柄）        │
                    │  安装 → 启动到首屏 → 中文无豆腐块（截图）              │
                    │  SKILL_COUNT=5 → 推右摇杆看轴值实时变化                │
                    └────────────┬──────────────────────────────────────────┘
                                 │
                    ┌────────────▼────────────────────┐
                    │ BUILD.md + keystore 离线备份     │
                    │ 第二台干净机器按文档重导出        │
                    └─────────────────────────────────┘
```

### Recommended Project Structure

```text
mobile/
├── project.godot                 # 唯一工程定义；config_version=5
├── export_presets.cfg            # 提交；不含任何密钥（4.7.2 起 keystore/* 是 SECRET，落 .godot/）
├── icon.svg                      # 可选；不提供会打印一条无害 ERROR
├── assets/
│   ├── config/                   # 由 tools/sync_config.py 生成，禁止手改
│   │   ├── skills_config.json
│   │   └── skills_config.json.sha256
│   └── fonts/
│       ├── NotoSansSC-Subset.ttf
│       ├── NotoSansSymbols2-Subset.ttf
│       ├── AppFont.tres          # FontVariation: base + fallbacks
│       └── OFL.txt               # 许可证全文
├── src/
│   └── smoke/
│       ├── smoke_screen.tscn     # 首屏：SKILL_COUNT / 最长中文 / 符号 / 轴读数
│       └── smoke_screen.gd
├── tools/
│   ├── glyph_coverage.gd         # headless 字形闸门（--script）
│   └── check_pack.gd             # 从 PCK 里读配置并断言 SKILL_COUNT
└── build/                        # gitignored（.gitignore 已有 mobile/build/）

tools/
├── android_doctor.sh             # 环境断言，非零退出
├── export_android.sh             # doctor → import → export → 静态校验
└── make_font_subset.py           # 一次性；产物提交后可删/可留
```

### Pattern 1: 三段式闸门（A 无模板 → B 无设备 → C 真机）

**What:** 把"能导出"拆成三个成本递增、依赖递增的闸门。A 层 7 秒、零外部依赖；B 层需要 1.9 GB 模板但不需要手机；C 层只有人能过。
**When to use:** 任何"构建产物 + 真机行为"混合的阶段。
**Why:** 本项目最大的浪费模式是"用真机调试构建脚本"。A 层把 90% 的配置错误（JSON 没进包、字体缺字、脚本语法、工程配置缺键）挡在真机之前。

```bash
# 闸门 A（无模板、无签名、无设备）
"$GODOT" --headless --path mobile --import
"$GODOT" --headless --path mobile --check-only --script res://src/smoke/smoke_screen.gd
"$GODOT" --headless --path mobile --export-pack "Android" "$PWD/mobile/build/verify.pck"
"$GODOT" --headless --main-pack "$PWD/mobile/build/verify.pck" --script res://tools/check_pack.gd
"$GODOT" --headless --path mobile --script res://tools/glyph_coverage.gd
```

### Pattern 2: 编辑器设置即环境（headless 自举）

**What:** Godot 的 Android 导出只认 `EditorSettings` 里的 `export/android/java_sdk_path` 与 `export/android/android_sdk_path`，**没有**专属环境变量覆盖这两项（源码里是 `EDITOR_GET(...)`，`ANDROID_HOME` 只是被**写出**给子进程，不被读入）[VERIFIED: platform/android/export/export_plugin.cpp:2691-2722, 3782-3791, 3858-3862]。
**Why it matters:** 这决定了"干净机器"能不能纯 CLI 复现。
**实测结论:** 删掉 `~/Library/Application Support/Godot/editor_settings-4.7.tres` 后，只要 `JAVA_HOME` 指向 JDK 17，`--headless --path <proj> --import` 会自动生成该文件并写入：

```ini
export/android/debug_keystore = "/Users/<user>/Library/Application Support/Godot/keystores/debug.keystore"
export/android/debug_keystore_pass = "android"
export/android/java_sdk_path = "/Users/<user>/.sdkman/candidates/java/17.0.12-oracle"
export/android/android_sdk_path = "/Users/<user>/Library/Android/sdk"
```

[VERIFIED: 删除设置文件 → 以 JAVA_HOME=JDK17 跑 `--import` → grep 生成结果]

**推论（直接写进 BUILD.md）：** 干净机器的正确顺序是 **先设 `JAVA_HOME`，再跑第一次 `--import`**；顺序反了会得到指向错误 JDK 的 `java_sdk_path`（本机首次就是这样被写成 `.sdkman/candidates/java/current`，即 JDK 25）。`doctor` 必须把这两个值打印出来并校验 `java_sdk_path` 里的 `java -version` 是 17。

### Pattern 3: 字体双链路（CJK 主字体 + 符号 fallback）

**What:** `FontVariation`（`base_font` = SC 子集，`fallbacks = [Symbols2 子集]`）挂到项目设置 `gui/theme/custom_font`。全部是纯文本 `.tres` + `project.godot` 一行键，**不需要打开编辑器**配置导入选项。
**Why:** 一条链路覆盖 CJK，另一条只补 SC 缺的 Dingbats（`✗`）。两者都 `allow_system_fallback` 保持默认 true 时，仍未覆盖的字形还有系统兜底；但**验收断言必须在关掉系统兜底的前提下做**，否则在 macOS 上测得过、在手机上豆腐。

```gdscript
# 验证（headless 可跑）：ThemeDB.fallback_font 必须是 AppFont.tres，且两个字符都在
print(ThemeDB.fallback_font.resource_path)          # res://assets/fonts/AppFont.tres
print(ThemeDB.fallback_font.has_char("马".unicode_at(0)))  # true
print(ThemeDB.fallback_font.has_char("✗".unicode_at(0)))  # true（只挂 SC 子集时是 false）
```

[VERIFIED: 4.7.2-stable headless 实测，`has_char('马')=true`、`has_char('✗')=true`；去掉 fallback 后 `✗` 为 false]

### Anti-Patterns to Avoid

- **用"文件存在"判断导出成功**：签名失败仍会留下未签名 APK（实测 26.5 MB，`apksigner` 报 `DOES NOT VERIFY`）。
- **用 `grep ERROR` 判断导出失败**：成功的导出日志里也有 `ERROR: No project icon specified`（无害）；失败的导出可能只打 WARNING。唯一判据是退出码 + 产物校验。
- **把 keystore 写进 `export_presets.cfg` 然后提交**：4.7.2 里 `keystore/*` 六个选项全部是 `PROPERTY_USAGE_SECRET`，编辑器一保存就会把它们搬进 `res://.godot/export_credentials.cfg`；写进去也会被静默搬走，且下一次提交可能带上旧值。
- **用 Homebrew cask 当规范安装路径**：今天恰好 4.7.2，`brew upgrade` 之后就未必。
- **在真机上排查"配置没进包"**：先跑 `--export-pack`，7 秒就有答案。

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 16 KB 页对齐 | 手写 zip 对齐脚本 / 依赖 `zipalign` 事后修 | Godot 内置对齐（`.so` 按 16×1024 对齐，其余按 4 字节） | 导出器已经做了，且必须在签名**之前**做；`zipalign` 只用来**校验**（`-c -P 16`）[VERIFIED: export_plugin.cpp:4378-4435] |
| 版本号注入 | 手改 `project.godot` / 手改多处 | 单一 `version.txt` + 脚本 patch `export_presets.cfg` 的 `version/code`、`version/name` | Phase 9 明确要求"版本号来自唯一来源"；现在就把接口留出来 |
| 字体子集 | 在 GDScript 里运行时裁字形 | `fonttools subset` 离线裁一次，产物提交 | 运行期裁字形会让包体积不变（源字体仍在包里），且首次渲染卡顿 |
| 字形覆盖检查 | 人眼看截图（唯一手段） | `FontFile.has_char()` headless 断言 + 真机截图 | 人眼只能证明"这台手机这一刻没事"；`has_char` 能进 CI |
| PCK 内容检查 | 解析 PCK 二进制格式 | `--main-pack` 跑一个 `FileAccess` 脚本 | PCK 格式随引擎版本变；`FileAccess` 是稳定 API |
| APK 内容检查 | 自己解 zip 找 `classes.dex` | `unzip -l` + `aapt2 dump badging` + `apksigner verify` | 三个官方工具各管一段，别再造 |
| CJK 字体 | 手写 TTF 解析 / 从系统字体拷 | Noto Sans SC 子集 + Noto Sans Symbols 2 子集 | 见 §Common Pitfalls P6 |

**Key insight:** 这个阶段所有"手写"的诱惑都来自"想绕过 1.9 GB 模板下载"。正确答案不是手写打包器，而是**先跑不需要模板的 `--export-pack` 闸门**。

---

## Common Pitfalls

### P1: `import_etc2_astc` 没开 → 导出直接失败
**What goes wrong:** `ERROR: 导出 Android 版本需要 ETC2/ASTC 纹理压缩格式`，退出码 1，APK 不生成。
**Why:** 安卓导出要求 `rendering/textures/vram_compression/import_etc2_astc=true`，这个键默认是 false。
**How to avoid:** 写进 `project.godot` 的 `[rendering]` 段（见 §Code Examples 1）。
**Warning signs:** 导出日志第一屏就报错，且 `build/` 为空。
[VERIFIED: 本机先失败后加上该键成功]

### P2: 相对导出路径被解析成 `proj/proj/build/x.apk`
**What goes wrong:** `--path proj --export-release Android proj/build/app.apk` → 报"无法以写入模式打开路径 proj/build/app.pck"。
**Why:** 帮助文档写的是"absolute or relative to the project directory"——`--path` 之后，相对路径的锚点是**工程目录**，不是 cwd。
**How to avoid:** 导出脚本里一律用绝对路径（`"$ROOT/mobile/build/app.apk"`）。
[VERIFIED: 同一条命令用绝对路径即成功]

### P3: 缺 keystore 时留下未签名 APK
**What goes wrong:** 导出打印 `WARNING: 代码签名: 找不到发布密钥库，无法导出。`，退出码 1，但 `build/app.apk` 已存在且大小正常。
**Why:** 导出器先写包、后签名。
**How to avoid:** 闸门必须 `apksigner verify`（并检查 `Verified using v2 scheme: true`），不能只 `test -f`。
**Warning signs:** `apksigner verify` → `DOES NOT VERIFY / Missing META-INF/MANIFEST.MF`。
[VERIFIED]

### P4: 日志里的 ERROR 不代表失败
**What goes wrong:** 成功的导出日志里也有 `ERROR: No project icon specified.`；不同步 grep `ERROR` 会把成功判成失败，或反过来被真正的失败淹没。
**How to avoid:** 判据 = 退出码（成功 0 / 失败 1）+ 产物校验。日志只用于**报告**，不用于**判定**。
[VERIFIED: 成功导出含该 ERROR 行]

### P5: `.sha256` 不会自动进包（而 `.json` 会）
**What goes wrong:** 只想着 `*.json`，结果运行期 `FileAccess.file_exists("res://assets/config/skills_config.json.sha256")` 为 false，启动校验直接失败。
**Why:** 4.7.2 里 `.json` 是**已注册资源扩展名**（`ResourceLoader.get_recognized_extensions_for_type("JSON") == ["tres","res","json"]`），`all_resources` 会带上；`.sha256` 不是资源，必须靠 `include_filter`。
**How to avoid:** `include_filter="assets/config/*.json,assets/config/*.sha256"`，并在闸门 A 里断言两个文件都能从包里读出来。
**Warning signs:** 空的 `include_filter` 下，PCK 里能找到 `skills_config.json` 但找不到 `skills_config.json.sha256`。
[VERIFIED: 两次 `--export-pack` 对照实测]

### P6: Noto Sans SC 没有 `✗`
**What goes wrong:** 只嵌 SC 子集，`✓` 正常、`✗` 是豆腐；而这一条恰好写在成功标准 2 里。
**Why:** SC 覆盖 `° ± → ✓ × ← ↑ ↓`，但 U+2717/2718/2715/2716 全缺；Noto Sans Symbols 2 有 `✓ ✗ ✘ ✖ ✕ ×`，却没有 `° ± →`。**没有任何一个字体单独覆盖这五个符号**。
**How to avoid:** 双字体（Pattern 3）+ headless 字形闸门。若用户接受把 `✗` 改成 `×`，单字体即可——这是需要显式确认的取舍。
[VERIFIED: fontTools 4.60.2 逐码点查表]

### P7: Godot 首次运行会把 `java_sdk_path` 写成当时的 `JAVA_HOME`
**What goes wrong:** 机器上有 8/19/21/25，`JAVA_HOME` 指向 25，于是 `java_sdk_path` 被写成 JDK 25；此后所有导出都用 25。
**Why:** 首次创建 `editor_settings-4.7.tres` 时的自举行为。
**How to avoid:** BUILD.md 写死顺序（先 `export JAVA_HOME=<JDK17>`，再第一次 `--import`）；`doctor` 校验解析出的路径且实跑 `java -version`。
**Warning signs:** `grep java_sdk_path editor_settings-4.7.tres` 指向 `.sdkman/candidates/java/current`。
[VERIFIED: 本机首次即为 JDK 25，重置后为 17]

### P8: `--version` 不等于 `4.7.2.stable`
**What goes wrong:** CI 断言写成 `[ "$(godot --version)" = "4.7.2.stable" ]`，永远红。
**Why:** 实际输出 `4.7.2.stable.official.ed1daf0bf`。
**How to avoid:** `case "$(godot --version)" in 4.7.2.stable.*) ;; *) exit 1;; esac`。
[VERIFIED]

### P9: `--script` 里的 `quit()` 可能给出非预期退出码
**What goes wrong:** 一个"通过"的探针脚本让 CI 变红，或反之。
**Why:** `quit()` 不带参数时依赖上下文；实测同一个 `_initialize()` 里 `quit()` 曾返回 1。
**How to avoid:** 闸门脚本一律 `quit(0)` / `quit(1)` 显式传值。
[VERIFIED: `quit(0)→0`，`quit(1)→1`]

### P10: 导出结束时的 `adb` 噪声
**What goes wrong:** 日志尾部固定出现 `cannot connect to daemon at tcp:5037: Connection refused`，看起来像失败。
**Why:** 安卓导出平台在收尾时会尝试探测设备。
**How to avoid:** 忽略；判据仍看退出码。
[VERIFIED: 每次导出都有，成功时也有]

### P11: `.idsig` 与 debug keystore 混进产物
**What goes wrong:** `build/` 里除了 APK 还有一个 `app.apk.idsig`（v4 签名旁文件）；直接打包分发会带上它。
**Why:** Godot 4.7.2 调用 apksigner 时生成 v4 旁文件（但 `apksigner verify` 报 `Verified using v4 scheme: false`）。
**How to avoid:** `.gitignore` 已有 `mobile/build/`、`*.apk`；分发脚本只拷 `.apk`。Phase 9 的 `unzip -l` 检查再兜一层。
[VERIFIED: 产物目录实测]

### P12: 用模拟器证明"手柄能用"
**What goes wrong:** 模拟器里一切正常，真机上轴序号、配对、字体全不一样。
**Why:** 本项目每个真实风险（蓝牙配对、OEM 字体栈、轴映射、息屏）在模拟器里都不存在。
**How to avoid:** 闸门 C 明确标注"只有人能过"；模拟器只允许用于布局截图。
[CITED: ROADMAP「真机是退出条件」；research/SUMMARY.md C15]

### P13: 首次运行镜像里 `.godot/` 不存在 → 任何 headless 命令都炸
**What goes wrong:** 干净 clone 直接 `--export-release`，报文件找不到。
**Why:** 导入缓存没生成。
**How to avoid:** 脚本第一步永远 `--import`；`.godot/` 必须 gitignore（`.gitignore` 已有 `mobile/.godot/`）。
[CITED: docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html（`.godot/` 应忽略）]

### P14: 安卓蓝牙手柄在第一次按键前可能不出现在设备列表
**What goes wrong:** 用户打开 app 看到"没有手柄"，以为坏了。
**Why:** Android 输入设备的注册时机受厂商与 HID 状态影响，社区长期反馈"先按一下键才出现"。
**How to avoid:** 首屏永远显示提示文案「先按手柄上任意键唤醒」；`joy_connection_changed` + 低频兜底刷新。
[ASSUMED —— 需真机验证；但提示文案无论真假都该有]

### P15: `.sha256` 是 sha256sum 格式，不是裸摘要
**What goes wrong:** 运行期做 `FileAccess.get_file_as_string(".sha256").strip_edges() == FileAccess.get_sha256(json)`，永远不相等，启动校验直接失败（或被人"修"成跳过校验）。
**Why:** Phase 1 的生成器写的是「摘要 + 两个空格 + 文件名 + LF」，即 `shasum -a 256` 的格式：
`bccf123a06efc61c7f05bc430e488a0f596bdc1e5c7eade4c18a3660f9d0eee9  skills_config.json` [VERIFIED: tools/sync_config.py:98-99 与实测 sidecar 内容]
**How to avoid:** 取第一个空白分隔字段再比：`split(" ", false)[0]`。桌面侧的 `check()` 用的是同一格式，不要在移动端另造一种解析。
**Warning signs:** 自动闸门报"sha256 不匹配"，但 `shasum -a 256 -c` 在仓库里是 OK 的。

---

## Code Examples

以下每一段都在本机 4.7.2-stable 上跑过（除明确标注"仅语法检查"者）。

### 1. 最小可导出工程：`mobile/project.godot`

```ini
; Source: 本机实测（4.7.2-stable），--import 后引擎未改写本文件
config_version=5

[application]

config/name="FIFA 花式动作练习器"
run/main_scene="res://src/smoke/smoke_screen.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true

[gui]

theme/custom_font="res://assets/fonts/AppFont.tres"
```

要点：
- `config_version=5` 是 4.7.2 的当前值 [VERIFIED: `core/config/project_settings.h:161` 为 `static const int CONFIG_VERSION = 5;`]。
- `config/features` 里写 `"4.7"` 而不是 `"4.7.2"`——引擎按 major.minor 匹配；这里也应作为"禁止 4.8 打开"的哨兵（4.8 打开会改写它）。
- 不写 `application/config/icon` 只会打印一条无害 ERROR，不影响导出。

### 2. 最小导出预设：`mobile/export_presets.cfg`

```ini
; Source: 键名取自 4.7.2 源码 editor/export/editor_export.cpp:40-121；
;         选项名取自 EditorExportPlatformAndroid 类文档；本文件实测可导出签名的 arm64 release APK
[preset.0]

name="Android"
platform="Android"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="assets/config/*.json,assets/config/*.sha256"
exclude_filter=""
export_path="build/fifa-trainer.apk"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
gradle_build/min_sdk=""
gradle_build/target_sdk=""
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
package/unique_name="com.fifaskill.trainer"
package/name="FIFA 花式动作练习器"
package/signed=true
version/code=1
version/name="0.1.0"
permissions/vibrate=true
```

**为什么这里**看不到 **keystore**：4.7.2 里 `keystore/debug`、`keystore/debug_user`、`keystore/debug_password`、`keystore/release`、`keystore/release_user`、`keystore/release_password` 全部带 `PROPERTY_USAGE_SECRET` [VERIFIED: platform/android/export/export_plugin.cpp:2227-2232]，编辑器保存时会被搬进 `res://.godot/export_credentials.cfg` [VERIFIED: editor/export/editor_export.cpp:107-120]。官方文档亦说明 4.1+ 不再在 `export_presets.cfg` 里存凭据 [CITED: version_control_systems.html]。**结论：密钥只走环境变量，仓库里一个字都不留。**

`package/unique_name` 建议沿用桌面版已有的 bundle id `com.fifaskill.trainer`（`desktop/build/build_macos.sh:22` 的 `--osx-bundle-identifier com.fifaskill.trainer`），保持两个平台同一身份；**这个值一旦发给朋友就不能改**（改了 = 另一个 app + 数据全丢）。

### 3. 字体资源：`mobile/assets/fonts/AppFont.tres`

```ini
; Source: 本机 4.7.2-stable 实测，ThemeDB.fallback_font.has_char('✗') == true
[gd_resource type="FontVariation" format=3]

[ext_resource type="FontFile" path="res://assets/fonts/NotoSansSC-Subset.ttf" id="1_sc"]
[ext_resource type="FontFile" path="res://assets/fonts/NotoSansSymbols2-Subset.ttf" id="2_sym"]

[resource]
base_font = ExtResource("1_sc")
fallbacks = Array[Font]([ExtResource("2_sym")])
```

### 4. 字形闸门：`mobile/tools/glyph_coverage.gd`（headless，可进 CI）

```gdscript
# Source: 本机实测；只挂 SC 子集时 MISSING=1 -> ✗，加 fallback 后 MISSING=0
extends SceneTree

## 必须覆盖的字符：UI 里真实出现过的全部中文字 + 五个符号。
## 文本文件 res://assets/fonts/required_glyphs.txt 由 tools/make_font_subset.py 生成，
## 与字体子集用的是**同一份**字符清单——这是"子集不漏字"的唯一保证。
const REQUIRED_PATH := "res://assets/fonts/required_glyphs.txt"

func _initialize() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		printerr("FAIL: 没有 fallback font")
		quit(1)
		return
	# 关掉系统兜底：否则在 macOS 上测得过，在手机上仍可能豆腐
	if font is FontFile:
		(font as FontFile).allow_system_fallback = false

	var text := FileAccess.get_file_as_string(REQUIRED_PATH)
	var missing: Array[String] = []
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 10 or c == 13 or c == 32:
			continue
		if not font.has_char(c):
			var s := String.chr(c)
			if not missing.has(s):
				missing.append(s)
	if missing.is_empty():
		print("GLYPH_OK total=%d" % text.length())
		quit(0)
	else:
		printerr("GLYPH_MISSING %d: %s" % [missing.size(), "".join(missing)])
		quit(1)
```

### 5. PCK 内容闸门：`mobile/tools/check_pack.gd`

```gdscript
# Source: 本机实测（--main-pack 无 --path 运行，读到 9117 字节、SKILL_COUNT=5）
extends SceneTree

const CONFIG_PATH := "res://assets/config/skills_config.json"
const SIDECAR_PATH := "res://assets/config/skills_config.json.sha256"
const EXPECTED_SKILLS := 5

func _initialize() -> void:
	var failures: Array[String] = []
	if not FileAccess.file_exists(CONFIG_PATH):
		failures.append("配置不在包里: " + CONFIG_PATH)
	if not FileAccess.file_exists(SIDECAR_PATH):
		failures.append("sha256 不在包里: " + SIDECAR_PATH)
	if failures.is_empty():
		var text := FileAccess.get_file_as_string(CONFIG_PATH)
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			failures.append("配置不是合法 JSON")
		else:
			var skills = parsed.get("skills", [])
			if not (skills is Array) or skills.size() != EXPECTED_SKILLS:
				failures.append("SKILL_COUNT != %d" % EXPECTED_SKILLS)
			# 注意：.sha256 是 sha256sum 兼容格式「摘要 + 两个空格 + 文件名 + LF」，
			# 不是裸摘要。见 tools/sync_config.py:98-99。必须取第一个空白分隔字段。
			var sidecar := FileAccess.get_file_as_string(SIDECAR_PATH).strip_edges().split(" ", false)[0]
			var digest := FileAccess.get_sha256(CONFIG_PATH)
			if sidecar != digest:
				failures.append("sha256 不匹配: %s != %s" % [sidecar, digest])
	if failures.is_empty():
		print("PACK_OK skills=%d" % EXPECTED_SKILLS)
		quit(0)
	else:
		for f in failures:
			printerr("PACK_FAIL " + f)
		quit(1)
```

> `FileAccess.get_sha256(path)` 是 Godot 4 内置的静态方法（读文件算 SHA-256），正好对上 Phase 1 生成的 `.sha256` 文本格式（hex + 换行）。

### 6. 首屏 smoke 场景（证明成功标准 2/3/4 的那一屏）

```gdscript
# Source: 仅 --check-only 语法通过；运行时行为需真机
extends Control

## 这一屏要一次性证明三件事：
##   1) 最长中文串 + ° ± → ✓ ✗ 都能显示（成功标准 2）
##   2) 从 res://assets/config/ 读到配置并显示 SKILL_COUNT（成功标准 3）
##   3) 手柄原始轴在动（成功标准 4）
## Phase 3 之后这一屏会被真正的首屏替换；在此之前它是唯一的"验收面板"。

const LONGEST := "起点错了：注意从左摇杆朝向的哪个方位起手。"
const SYMBOLS := "° ± → ✓ ✗   0°  45°  −1.000"

@onready var _header: Label = %Header
@onready var _axes: Label = %Axes

var _skill_count := -1
var _device_ids: Array[int] = []

func _ready() -> void:
	Input.use_accumulated_input = false          # 采样时钟归 Phase 4，这里先关掉便于观察
	Input.joy_connection_changed.connect(_on_joy_changed)
	_load_config()
	_refresh_axes()

func _load_config() -> void:
	var path := "res://assets/config/skills_config.json"
	if not FileAccess.file_exists(path):
		_header.text = "配置缺失: " + path
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_skill_count = (parsed.get("skills", []) as Array).size()
	_header.text = "SKILL_COUNT = %d\n%s\n%s" % [_skill_count, LONGEST, SYMBOLS]

func _on_joy_changed(_device: int, _connected: bool) -> void:
	_device_ids = Input.get_connected_joypads()
	_refresh_axes()

func _process(_delta: float) -> void:
	_refresh_axes()

func _refresh_axes() -> void:
	_device_ids = Input.get_connected_joypads()
	if _device_ids.is_empty():
		_axes.text = "没有检测到手柄：先按手柄上任意键唤醒"
		return
	var out: PackedStringArray = []
	for d in _device_ids:
		out.append("#%d  %s" % [d, Input.get_joy_name(d)])
		for axis in range(8):
			out.append("  axis %d = %+.3f" % [axis, Input.get_joy_axis(d, axis as JoyAxis)])
	_axes.text = "\n".join(out)
```

对应 `smoke_screen.tscn`（手写、不需要编辑器）：

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/smoke/smoke_screen.gd" id="1"]

[node name="Smoke" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Header" type="Label" parent="."]
unique_name_in_owner = true
offset_left = 32.0
offset_top = 32.0
offset_right = 1200.0
offset_bottom = 260.0
theme_override_font_sizes/font_size = 28

[node name="Axes" type="Label" parent="."]
unique_name_in_owner = true
offset_left = 32.0
offset_top = 280.0
offset_right = 1200.0
offset_bottom = 700.0
theme_override_font_sizes/font_size = 22
```

> 轴读数用 `Input.get_joy_axis()`（每帧快照）是**故意**的：成功标准 4 只要求"看得见在动"。事件驱动的采样契约归 Phase 4（INPUT-05），此处不建立任何"这就是判定的输入源"的错觉。

### 7. 导出 + 静态校验脚本骨架：`tools/export_android.sh`

```bash
#!/usr/bin/env bash
# Source: 本机全链路实测（退出码、路径、校验命令均来自实际运行）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
BT="$SDK/build-tools/36.1.0"
OUT="$ROOT/mobile/build/fifa-trainer.apk"
PCK="$ROOT/mobile/build/verify.pck"

bash "$ROOT/tools/android_doctor.sh"

"$GODOT" --headless --path "$ROOT/mobile" --import
"$GODOT" --headless --path "$ROOT/mobile" --export-pack "Android" "$PCK"
"$GODOT" --headless --main-pack "$PCK" --script res://tools/check_pack.gd
"$GODOT" --headless --path "$ROOT/mobile" --script res://tools/glyph_coverage.gd

rm -f "$OUT"
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?缺 keystore 路径}" \
GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?缺 alias}" \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?缺密码}" \
  "$GODOT" --headless --path "$ROOT/mobile" --export-release "Android" "$OUT"

# 退出码 0 还不够：失败时会留下未签名 APK
"$BT/apksigner" verify --print-certs "$OUT" > /dev/null
"$BT/zipalign" -c -P 16 -v 4 "$OUT" > /dev/null
unzip -l "$OUT" | grep -q "assets/assets/config/skills_config.json"
unzip -l "$OUT" | grep -q "assets/assets/config/skills_config.json.sha256"
if unzip -l "$OUT" | grep -q "lib/x86_64/"; then echo "FAIL: 混入 x86_64"; exit 1; fi

"$BT/aapt2" dump badging "$OUT" | head -1
echo "OK: $OUT"
```

> **注意两处容易写错的地方**：(a) APK 里 `res://assets/...` 的实际路径是 `assets/assets/...`（PCK 整体挂在 `assets/` 下）——`unzip -l` 输出实测如此；(b) `apksigner verify` 通过管道接 `grep` 时 `$?` 是 `grep` 的，脚本里必须直接判断命令本身（`set -e` 或 `&&`）。

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `export_presets.cfg` 里存 keystore 与密码 | 4.1+ 凭据移到 `.godot/export_credentials.cfg`；4.7.2 六个 keystore 选项全是 SECRET | Godot 4.1 | 仓库里可以安全提交 `export_presets.cfg`；密钥走 env |
| `*.json` 必须手动加非资源过滤 | 4.7 里 `.json` 已是注册资源扩展名，默认入包 | 至少在 4.7.2 实测如此（官方 troubleshooting 文案未更新） | "记得加过滤"不再是可靠检查点；必须靠"从包里读" |
| 导出后手动 `zipalign -P 16` | 导出器内置 16 KB 对齐 `.so` | 4.7.2 源码可见 `PAGE_SIZE_KB = 16 * 1024` | `zipalign -c -P 16` 只作校验 |
| 电脑上装 Godot 用 dmg/安装器 | 官方只发 `.zip`（macOS universal） | 4.7.2 | 安装脚本 = 下载 + 解压 + 固定路径 |
| 靠 SystemFont 显示 CJK | 内嵌子集 + 显式 fallback（官方明说安卓系统字体不可靠） | 长期 | 字体是仓库资产，不是运行时假设 |

**Deprecated/outdated:**
- 官方《Exporting for Android》页里列的工具链版本（build-tools 35.0.1 / platform 35 / NDK 28.1）落后于 4.7.2 源码的 `config.gradle`（36.1.0 / 36）。**以源码与实测为准**；本阶段不启用 Gradle build，因此 NDK/CMake 完全不参与。
- "Judge by log output" 在本阶段彻底失效（见 P3/P4）。

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 安卓蓝牙手柄在第一次按键前可能不出现在 `Input.get_connected_joypads()` | P14 / Code Example 6 | 若实际是"连上即出现"，提示文案略保守，无功能损失；若真是"按键才出现"而没写提示，用户会以为坏了 |
| A2 | `permissions/vibrate=true` 现在勾上不会有害 | Code Example 2 | 只是多一个权限声明；Phase 10 之前不调用 `vibrate_handheld()`。若 Play 侧载审核在意可去掉 |
| A3 | `package/name`（应用显示名）用中文没有问题 | Code Example 2 | 极老设备/极少数启动器可能显示异常；可在真机上确认，退路是英文名 + 中文 `name_localized` |
| A4 | 两个 Noto 子集在真机上渲染质量足够（对比度、字重） | §Standard Stack | 若视觉偏细，可改子集源为 Medium/SemiBold 字重后重新子集（体积变化很小） |
| A5 | `xattr -dr com.apple.quarantine` 在浏览器下载的 Godot.app 上是必要的 | §Environment Availability | 用 curl 下载不会有隔离属性；用 Safari 下载会被 Gatekeeper 拦，BUILD.md 需两条路径 |
| A6 | Android 覆盖安装（同包名 + 同签名 + 更高 versionCode）保留 `user://` 数据 | §Pattern/§Pitfalls | 这是 Android 平台标准行为，但本项目要到 Phase 9 才真正验证；本阶段只需保证 keystore 与包名现在定死 |
| A7 | 两台 OEM 手机与两只手柄能按时备齐 | §Environment Availability | 这是本阶段唯一的**外部**阻塞项（STATE.md 已记为 Blocker）；没有它，成功标准 1/2/4 无法关闭 |

---

## Open Questions

1. **`✗` 保留还是换成 `×`？**
   - 已知：Noto Sans SC 无 U+2717；Symbols2 有；双字体方案已实测可行，代价 +6.6 KB 与一个 `.tres`。
   - 不清楚：用户是否介意多一个字体文件（几乎不占体积）。
   - 建议：**保留 `✗`，走双字体**（成功标准 2 原文写的就是 `✓ ✗`；改字符等于改验收标准）。

2. **首屏 smoke 屏是"一次性脚手架"还是"未来首屏的雏形"？**
   - 已知：Phase 3 之后会有真正的核心与 UI；Phase 6/7 才是真正的首屏。
   - 不清楚：是否值得现在就把布局做好看。
   - 建议：**明确写成"验收面板，可整体删除"**，用最少的节点（两个 Label + 一个 Timer），不做样式。避免 Phase 6 之前先背上一个假 UI。

3. **Godot 装到哪里、是否随仓库？**
   - 已知：官方 zip 170 MB；装到 `~/Applications/Godot-4.7.2.app` 或仓库外任意固定路径都行。
   - 建议：**装到仓库外**（`$HOME/Applications/`），用 `GODOT_BIN` 环境变量覆盖；绝不把 170 MB 二进制放进 git。

4. **CI 要不要跑闸门 B（打 APK）？**
   - 已知：闸门 A 只需 Linux 版 Godot（77 MB），可在 GitHub Actions 跑；闸门 B 需要 1.9 GB 模板 + JDK + Android SDK。
   - 建议：**Phase 2 只把闸门 A 进 CI（可选）**，闸门 B 留在本机脚本。Phase 9 再决定是否上 CI 打发布包。

5. **keystore 备份怎么算"已备份"？**
   - 建议：BUILD.md 写清"离线介质 + 至少两处 + 密码与文件分开存放"，并在 `doctor` 里校验 keystore 能被 `keytool -list` 打开（能打开 = 密码对、文件没坏），但**不**把 keystore 放进任何自动化路径。

---

## Environment Availability

> 本阶段重度依赖宿主工具链，故不跳过本节。下列状态是**研究时实测**，不是假设。

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Godot 编辑器 | 导入 / 导出 | ✗（未安装到系统路径） | 研究时已下载并验证 4.7.2-stable；`which godot` 为空、`/Applications` 无 Godot | 按 §Installation 安装；`GODOT_BIN` 可覆盖 |
| 导出模板 4.7.2.stable | 打 APK | ✓（研究时已放入 `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`，1.9 GB） | `version.txt` = `4.7.2.stable` | 重新下载 .tpz + 解压（约 1.28 GB 下载） |
| JDK 17 | keystore / apksigner | ✓（SDKMAN 已装，路径 `~/.sdkman/candidates/java/17.0.12-oracle`） | 17.0.12 | 若丢失：`sdk install java 17.0.x-tem` 或 Temurin cask |
| 系统默认 JDK | — | ✓ 但是 **25.0.2**（`JAVA_HOME=~/.sdkman/candidates/java/current`） | 25.0.2 | **不要用它**；显式设 `JAVA_HOME` 到 17 |
| Android SDK | apksigner / zipalign / aapt2 / adb | ✓ `~/Library/Android/sdk` | build-tools 34/35/**36.1.0**，platform-tools 36.0.2，platforms 27–36 | — |
| `adb` | 装机 / logcat | ✓ | 1.0.41 (36.0.2) | — |
| Android 模拟器 | 布局截图（可选） | ✗ | — | 不装也行；装也不许当验收 |
| 真 Android 手机 × 2（不同 OEM） | 成功标准 1/2/4 | ✗（`adb devices` 为空） | — | **无替代**。这是阶段级阻塞 |
| 蓝牙手柄（Xbox + DualSense） | 成功标准 4 | ✗（本机无连接） | — | **无替代** |
| `fonttools` | 一次性字体子集 | ✗（venv 未装） | 4.60.2（PyPI） | `uv run --with fonttools`；产物提交后不再需要 |
| `uv` | 一次性脚本 | ✓ | 0.9.5 | — |
| 磁盘空间 | 模板 + 产物 | — | 模板 ~1.9 GB + Godot ~0.4 GB + 产物 ~30 MB | 至少预留 3 GB |

**Missing dependencies with no fallback:**
- **两台不同 OEM 的真机 + 至少一只蓝牙手柄** —— 直接阻塞成功标准 1、2、4。建议计划把"设备到位"写成 Wave 0 的显式前置检查（`adb devices` + 人工确认），而不是等到最后一波才发现没有手机。
- Godot 编辑器本体（可由脚本安装，非外部阻塞）。

**Missing dependencies with fallback:**
- `fonttools`：可用 `uv run --with fonttools` 临时获取；或直接提交已生成好的子集（研究阶段已产出并验证过尺寸与覆盖）。
- 模拟器：可跳过。

---

## Validation Architecture

> `workflow.nyquist_validation = true`（`.planning/config.json`），故本节必填。
> 本阶段的特殊性：**几乎全部真值都在设备上**。本节的目标不是"用自动化替代真机"，而是把**能自动化的部分切干净**，让真机时间只花在真机上才能回答的问题上。

### Test Framework

| Property | Value |
|----------|-------|
| Framework | 无第三方框架。沿用仓库既有风格：shell 闸门 + Godot `extends SceneTree` 脚本（`quit(0)` / `quit(1)` 控制退出码） |
| Config file | none — 由 `tools/export_android.sh` 串起来 |
| Quick run command | `bash tools/android_gate_a.sh`（导入 + 语法 + PCK + 字形，约 10–20 s，无需模板/设备） |
| Full suite command | `bash tools/export_android.sh`（含真实 APK 导出与静态校验，约 1–2 min，需模板/JDK/SDK/keystore） |

### Phase Requirements → Test Map

| Req ID / 成功标准 | Behavior | Test Type | Automated Command | File Exists? |
|-------------------|----------|-----------|-------------------|--------------|
| SC-5（版本） | Godot 版本 = 4.7.2.stable.* | 环境断言 | `"$GODOT" --version \| grep -q '^4.7\.2\.stable\.'` | ❌ Wave 0（`android_doctor.sh`） |
| SC-5（版本） | 模板目录 = `4.7.2.stable` 且含 android_release.apk | 环境断言 | `test -f "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/android_release.apk"` | ❌ Wave 0 |
| SC-5（JDK） | `JAVA_HOME` 的 java 是 17，且 `editor_settings` 指向它 | 环境断言 | `"$JAVA_HOME/bin/java" -version 2>&1 \| grep -q '"17\.'` + grep 设置文件 | ❌ Wave 0 |
| SC-3 | 配置与 `.sha256` 进包且 SKILL_COUNT=5 | 集成（无模板） | `--export-pack` + `--main-pack --script res://tools/check_pack.gd` | ❌ Wave 1 |
| SC-2 | 139 个必需字形全部可渲染 | 单元（headless） | `--script res://tools/glyph_coverage.gd`（`allow_system_fallback=false`） | ❌ Wave 1 |
| — | 所有 `.gd` 语法通过 | 静态 | `--check-only --script <each>.gd` | ❌ Wave 1 |
| SC-1 | 签名 APK 产出且签名有效 | 集成（需模板） | `--export-release` → `apksigner verify --print-certs` | ❌ Wave 2 |
| SC-1 | 16 KB 对齐 | 集成 | `zipalign -c -P 16 -v 4 app.apk` | ❌ Wave 2 |
| SC-1 | 只有 arm64、无 x86、无 keystore/.idsig 混入 | 集成 | `unzip -l` + grep | ❌ Wave 2 |
| SC-5 | 包名 / versionCode / versionName / minSdk 正确 | 集成 | `aapt2 dump badging` | ❌ Wave 2 |
| SC-5 | 干净 clone 能重导出 | 端到端 | 复用 Phase 1 的 `tools/verify_clean_clone.sh` 思路（导出脚本 + doctor） | ❌ Wave 3 |
| **SC-1** | 真机安装并启动到首屏 | **manual-only** | `adb install -r app.apk`，然后**拔掉 USB** 从桌面图标启动一次 | — |
| **SC-2** | 两台 OEM 无豆腐块 | **manual-only** | 两台手机截图，人工比对 21 字长串 + `° ± → ✓ ✗` | — |
| **SC-3** | 屏幕上显示 SKILL_COUNT = 5 | manual-only（弱自动） | 截图 + 与 `check_pack.gd` 的自动结论交叉验证 | — |
| **SC-4** | 蓝牙手柄推右摇杆，轴值实时变化 | **manual-only** | 真手柄；观察 axis 值随推动变化，换一个轴再推 | — |

**为什么 SC-1/2/4 必须 manual-only（不是懒，是真的没有替代）：**
- 模拟器没有蓝牙手柄通道、没有 OEM 字体栈、没有真实 GPU 驱动与厂商 ROM 的字形回退行为。
- `has_char()` 只能证明"字体里有这个字形"，不能证明"这台手机的渲染管线把它画出来了"（emoji 字体、字形合成、厂商替换都可能出问题）。
- 成功标准原文就写着"两台不同 OEM 手机"，这条本身就是人工判据。

### Sampling Rate

- **Per task commit:** `bash tools/android_gate_a.sh`（闸门 A，< 30 s；任何 `project.godot` / 字体 / 场景改动都跑）
- **Per wave merge:** `bash tools/export_android.sh`（闸门 B，含真 APK）
- **Phase gate:** 闸门 A + B 全绿 **且** 闸门 C 的人工验收表（2 台手机 × 每台 4 条观察项）全部打勾，才允许 `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tools/android_doctor.sh` —— 五项环境断言（Godot 版本 / 模板版本 / JDK17 / SDK 组件 / keystore 可解析），失败必须指名"改哪一行"
- [ ] `tools/export_android.sh` —— 闸门 B 的唯一入口
- [ ] `tools/make_font_subset.py` —— 从 `shared/skills_config.json` + `desktop/padskills/{detectors,gui}.py` 抽取字符清单 → 生成 `required_glyphs.txt` 与两个子集（**清单与子集必须同源**，否则字形闸门会假绿）
- [ ] `mobile/tools/glyph_coverage.gd`
- [ ] `mobile/tools/check_pack.gd`
- [ ] `mobile/src/smoke/smoke_screen.{tscn,gd}`
- [ ] 真机验收清单模板（4 条 × 2 台，带截图位）

*(框架安装：不需要。退出码约定 = `quit(0)` / `quit(1)`，shell 层 `set -euo pipefail`。)*

---

## Security Domain

> `workflow.security_enforcement = true`，`security_asvs_level = 1`。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | 无账号、无登录 |
| V3 Session Management | no | 无会话 |
| V4 Access Control | no | 单用户本地应用 |
| V5 Input Validation | **yes（有限）** | 本阶段只校验"配置文件存在 + 可解析 + sha256 匹配"；完整的配置校验（BOM / 字符串布尔 / null 数值 / `start_angle` 数组）归 Phase 3 RESIL-02 |
| V6 Cryptography | **yes（仅签名密钥管理）** | 不手写加密；keystore 用 `keytool` 生成 RSA-2048、SHA256withRSA；签名由 `apksigner` 完成。**绝不自己实现签名** |
| V7 Error Handling & Logging | yes | 导出/校验失败必须非零退出并指名文件；不得静默回退 |
| V14 Configuration | yes | 密钥不进仓库；`export_presets.cfg` 中不得出现 `storepass`/`password`/`keystore` 路径 |

### Known Threat Patterns for {Godot + Android sideload}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| keystore 或其密码进入 git | Information disclosure | 4.7.2 的 SECRET 机制 + 只用环境变量注入；提交前 `grep -rn "storepass\|keystore_password\|GODOT_ANDROID_KEYSTORE" mobile/ export_presets.cfg` 必须为空 |
| 用错 key 签名导致用户必须卸载（丢 `user://` 数据） | Tampering / DoS | 包名 + keystore 现在定死；`apksigner --print-certs` 的证书 SHA-256 写进 BUILD.md 作为"同一把钥匙"的指纹 |
| 产物里混入 `.idsig` / debug keystore / `.DS_Store` | Information disclosure | `unzip -l` 断言；`.gitignore` 已忽略 `*.apk` 与 `mobile/build/` |
| 从不可信来源下载 Godot / 模板 | Tampering | SHA-512（官方 `SHA512-SUMS.txt`）+ `--version` 断言 |
| 导出脚本把密码打到 stdout | Information disclosure | 导出日志里 Godot 会自己打 `--ks <REDACTED>`（实测已脱敏）；脚本禁止 `set -x` |
| 侧载 APK 被替换 | Tampering | APK 的 v2/v3 签名 + 发布时公布 SHA-256（Phase 9）；本阶段先在 BUILD.md 记录 `--print-certs` 输出 |

**本阶段安全结论：** 没有运行时攻击面（无网络、无账号、无外部输入）。真正需要纪律的只有一件——**密钥管理**。`security_block_on = high` 在本阶段不会触发。

---

## Sources

### Primary (HIGH confidence — 本次会话实际执行/阅读)
- **Godot `4.7.2-stable` 二进制实测**（官方 macOS universal zip，SHA-512 校验通过）：`--version`、`--import`、`--export-pack`、`--main-pack`、`--export-release`、`--check-only`、`--script`、`quit(0/1)`、字体 `has_char` 探针、apksigner/zipalign/aapt2 校验
- **Godot 源码 `4.7.2-stable`**：`editor/export/editor_export.cpp`（预设键、SECRET 分流、加载顺序）、`platform/android/export/export_plugin.cpp`（keystore 选项、`PAGE_SIZE_KB = 16*1024` 对齐、`EDITOR_GET("export/android/*")`）、`core/config/project_settings.h:161`（`CONFIG_VERSION = 5`）
- **`https://api.github.com/repos/godotengine/godot/releases/tags/4.7.2-stable`** + `SHA512-SUMS.txt`：版本日期、资产名与大小、校验值
- **本机环境实测**：`/usr/libexec/java_home -V`、`sdkmanager --list_installed`、`adb devices`、`brew info --cask godot`、`du -sh` 模板目录
- **fontTools 4.60.2 实测**：139 个必需字符的逐码点覆盖查表、子集产物体积（66.3 KB / 6.6 KB）

### Secondary (MEDIUM confidence — 官方文档)
- `https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html` —— JDK 17 推荐语、keytool 命令、keystore 三项填写、"同包名不同 key 必须先卸载"、6 个 keystore 环境变量
- `https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformandroid.html` —— `architectures/arm64-v8a`、`package/*`、`version/code|name`、`permissions/vibrate`、`keystore/*` 可被 env 覆盖
- `https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html` —— `--headless`、`--import`、`--export-release`、路径相对工程目录
- `https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html` + `troubleshooting.html` —— 资源/非资源过滤的**官方表述**（对 4.7.2 的 `.json` 已过期，见 P5）
- `https://docs.godotengine.org/en/4.7/tutorials/ui/gui_using_fonts.html` —— 系统字体在安卓**不可靠**的原文、安卓字体别名表、`allow_system_fallback`
- `https://docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html` —— `.godot/` 应忽略；4.1+ 不再在 `export_presets.cfg` 存凭据
- `https://developer.android.com/studio/publish/versioning` —— versionCode 单调递增、系统阻止降级、2100000000 上限
- `research/STACK.md`（本项目既有研究，源码级）—— 安卓输入走自研 `InputDevice` 路径、无映射库、轴序号排序规则、`set_use_accumulated_input(false)`

### Tertiary (LOW confidence — 需真机/后续验证)
- 安卓蓝牙手柄"先按键才出现"（A1）
- 两台 OEM 上双字体子集的实际观感（A4）
- 覆盖安装保留 `user://`（A6，Phase 9 验证）

---

## Metadata

**Confidence breakdown:**
- **Standard Stack: HIGH** —— 版本、下载物、SHA-512、模板目录名、JDK/SDK 路径全部本机实测。
- **Architecture / 闸门设计: HIGH** —— 每一层闸门都真的跑过（PCK 闸门、字形闸门、APK 导出、签名、对齐、badging）。
- **Pitfalls: HIGH** —— P1–P11 全部由本机失败/成功对照得出；P14 标 ASSUMED。
- **字体: HIGH（覆盖与体积）/ LOW（真机观感）** —— 字形覆盖是查表结果，渲染质量只能靠眼睛。
- **真机行为: LOW** —— 本阶段所有"手机上会不会"的结论一律未验证。

**Research date:** 2026-11-04
**Valid until:** 工具链事实 30 天（Godot 4.7.2 是已发布补丁版，短期不变）；字体覆盖与 APK 结构不随时间变；真机结论在第一次实测后立即取代本文对应条目。

**研究过程中在宿主机上留下的状态（供执行阶段复用，不构成承诺）：**
- `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`（1.9 GB，已解压）
- `~/Library/Application Support/Godot/editor_settings-4.7.tres`（`java_sdk_path` 指向 JDK 17，`android_sdk_path` 指向 `~/Library/Android/sdk`）
- `~/Library/Application Support/Godot/keystores/debug.keystore`（Godot 自动生成的调试密钥，口令 `android`）
- Godot 4.7.2 本体验证时位于 `/private/var/folders/n2/41xggy1s0m70w7d4dbzm9nph0000gp/T/gsd_research/Godot.app`（临时目录，随时可能被系统清理），**未**安装到 `~/Applications`；执行阶段仍须按 BUILD.md 正式安装
- 未生成任何 release keystore、未改动仓库任何文件
