---
status: testing
phase: 02-安卓工具链 + 真机冒烟 APK
source: [02-VERIFICATION.md]
started: 2026-11-04T16:20:00Z
updated: 2026-11-04T16:20:00Z
---

## Current Test

number: 3
name: 蓝牙手柄原始轴实时变化
expected: |
  安装成功、启动到验收屏；Header 第一行显示 SKILL_COUNT = 5（不是 0 / -1 / 配置缺失）
awaiting: user response

## Tests

### 1. 两台不同 OEM 手机装机并启动到首屏
expected: 安装成功、启动到验收屏；Header 第一行显示 `SKILL_COUNT = 5`（不是 0 / -1 / 配置缺失）
how: |
  连上手机后执行：
    bash mobile/tools/device-smoke.sh
  或手工：
    adb install -r mobile/build/fifa-trainer.apk
    adb shell monkey -p com.fifaskill.trainer -c android.intent.category.LAUNCHER 1
result: partial — Motorola XT2175-2 (ZY22F5FXX9) 通过：DEVICE_SMOKE_OK、SKILL_COUNT=5、进程存活；第二台不同 OEM 待测

### 2. 中文与符号不豆腐
expected: 「起点错了：注意从左摇杆朝向的哪个方位起手。」完整无豆腐；`° ± → ✓ ✗` 全部为字形；负号为 ASCII 短横
how: 在**两台不同品牌**手机上逐字比对首屏第二、三行
result: partial — Motorola XT2175-2 截图逐字确认：中文完整、`° ± → ✓ ✗` 全部为字形、负号为 ASCII `-`（截图 mobile/build/device-smoke-ZY22F5FXX9.png）；第二台不同 OEM 待测

### 3. 蓝牙手柄原始轴实时变化
expected: 配对并唤醒手柄后，推动右摇杆至少有两个 axis 数值实时变化
how: 系统蓝牙里配对 Xbox 或 DualSense → 打开 App → 推右摇杆
result: [pending]

### 4. 密钥库离线备份与恢复演练
expected: `mobile/ACCEPTANCE.md` §4 的四行字段全部有可核对内容；两处备份不同址/不同设备；口令与 keystore 分开存放
how: 按 `~/.fifa-trainer/README-请备份.md` 操作，然后填 `mobile/ACCEPTANCE.md` §4
result: [pending]

### 5. 第二台干净机器重导出
expected: `bash mobile/tools/gate-b.sh` 退出 0，证书指纹与 `BUILD.md` §6 逐字相同
how: 在一台未配置过的机器上按 `BUILD.md` §1–§8 执行，填 `mobile/ACCEPTANCE.md` §5
result: [pending]

### 6. 真机跑 device-smoke.sh 并检查截图
expected: 末行 `DEVICE_SMOKE_OK serial=… package=com.fifaskill.trainer pid=… screenshot=…`；截图非空且确为验收屏
how: 接一台设备执行 `bash mobile/tools/device-smoke.sh`
result: [pending]

## Summary

total: 6
passed: 0
partial: 2
issues: 0
pending: 4
skipped: 0
blocked: 0

**已有真机证据：** Motorola XT2175-2（Android，序列号 ZY22F5FXX9）—— 安装、启动、`SKILL_COUNT=5`、中文与 `° ± → ✓ ✗` 均通过。缺第二台不同 OEM 手机以闭合 SC2 的「两台」要求。

## Gaps

（暂无 —— 机械证明 0 缺口；以上 6 项是「只有人能证明」的部分）
