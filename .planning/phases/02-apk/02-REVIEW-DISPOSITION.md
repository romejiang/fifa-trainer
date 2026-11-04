# Phase 02 — Code Review Disposition

**Source:** `02-REVIEW.md` (24 findings)
**Triaged:** 2026-11-04
**Policy:** code review is advisory for this phase — it never blocks execution. Every finding is recorded here so a triaged item is distinguishable from a forgotten one.

## Severity counts

| Severity | Count | Fixed in-phase | Open |
|----------|-------|----------------|------|
| blocker | 1 | 1 | 0 |
| high | 3 | 3 | 0 |
| medium | 7 | 0 | 7 |
| low | 9 | 0 | 9 |
| info | 4 | 0 | 4 |

## Fixed during phase execution

| ID | Severity | Finding | Fix |
|----|----------|---------|-----|
| BLOCKER-01 | blocker | 闸门 A 的语法检查永远不可能失败：Godot 4.7.2 的 `--check-only --script` 对解析失败和文件不存在都返回 0 | `gate-a.sh` 的 `check_script` 改为检查**输出**里的 `SCRIPT ERROR` / `Parse Error` / `Failed to load script` / `File not found`。反例已验证：弄坏 `smoke_screen.gd` → 闸门红并指名文件 |
| HIGH-01 | high | `BUILD.md` 的引擎包 SHA-512 只有 127 位，`shasum -c` 永久失败 | 补齐为 128 位，两个摘要长度均已核验 |
| HIGH-02 | high | 文档一边说「口令永远不落盘」一边教人写进 `credentials.sh` | 改写为如实描述：口令不进仓库/日志/产物；本机放在仓库外 600 文件是明确接受的本地凭据安排，并给出更严格的临时 export 方式 |
| HIGH-03 | high | 闸门 B 只证明「有 v2 签名」，不证明「是发布密钥签的」；换一把 DN 相同的新密钥重签照样通过 | `gate-b.sh` 新增发布证书 SHA-256 常量比对。反例已验证：用临时密钥库走 `FIFA_KEYSTORE` 重签 → 闸门红并打印期望/实际指纹 |

## Related fix not from the review

| ID | Severity | Finding | Fix |
|----|----------|---------|-----|
| FLAKE-01 | n/a | Godot 4.7.2 在 macOS arm64 导入 `NotoSansSC-Subset.ttf` 时偶发 SIGSEGV（约 1/5，系统报告 `EXC_BAD_ACCESS at 0x10`，`WorkerThread 2`，栈全在 Godot 二进制内） | `gate-a.sh` 只对 `--import` 做最多 3 次有界重试，**且只在信号终止（rc ≥ 128）时重试**；断言一条不放松。实测：连跑 3 次 0 重试全绿 |

## Open — recommended for a follow-up pass

| ID | Severity | Finding |
|----|----------|---------|
| MED-01 | medium | `BUILD.md` 缺 JDK / Android SDK 的安装步骤，只有本机绝对路径；干净机器按文档走会在第一步卡住 |
| MED-02 | medium | `gate-b.sh` 的 `JAVA_HOME` 注释声称 doctor 断言过 JDK 17，实际 doctor 只解析不强制；本机默认是 JDK 25 |
| MED-03 | medium | Godot 脚本调用无超时；`check_pack.gd:33` 的 `[0]` 越界会让闸门挂死而不是报错 |
| MED-04 | medium | 字体源从 GitHub 移动分支裸下载，无摘要钉死；上游改写即静默改变产物 |
| MED-05 | medium | `OFL.txt` 缺版权行（SIL OFL 要求保留原始版权声明） |
| MED-06 | medium | 字体链路没有「字体真的在包里」这条断言（只验了配置在包里） |
| MED-07 | medium | `ACCEPTANCE.md` §2 的动作名覆盖是「机械性覆盖」，若按字面要求「首屏显示动作名」会缺屏幕证据 |
| LOW-01…09 | low | `device-smoke.sh` 的 `pidof`/`aapt2` 边界、`--tamper` 断言强度、`collect_checks.py` 的 Windows CRLF、CI 权限块缺失等 |
| INFO-01…04 | info | 既有记录项，无需动作 |

## Verdict

审查发现的 4 个高严重度问题**全部在本阶段内修复并附反例验证**，其中 3 个属于「闸门会假绿」这一类 —— 与本阶段的立项目的直接冲突，不能留到下一阶段。

7 个 medium 属于文档完备性、工具健壮性与供应链加固，不改变任何已建立的机械保证。建议在 Phase 3 开始前用一次 `/gsd-quick` 收口 MED-01…MED-07。

**本阶段没有声称任何真机验证。** 成功标准 1/2/4 的判据与记录字段在 `mobile/ACCEPTANCE.md`，`adb devices` 为空时未被勾选。
