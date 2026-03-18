# smart-sleep 代码审查报告

## 概述

smart-sleep 是一个设计良好的 macOS 合盖模式管理工具，整体结构清晰。以下列出发现的问题和改进建议。

**已修复项**（本次审查中已修复）：
- ✅ 问题 1：pkill 匹配过宽
- ✅ 问题 2：load_config 输入验证
- ✅ 问题 3：display_count 空值处理
- ✅ 问题 9：README 描述更新

---

## 严重问题（已修复）

### 1. ~~`pkill -f "smart-sleep"` 可能杀死正在执行的 uninstall 进程~~ ✅ 已修复

**位置**: `smart-sleep.sh` 第 261 行

**问题**: `cmd_uninstall` 使用 `pkill -f "smart-sleep"` 停止服务。当用户执行 `smart-sleep uninstall` 时，当前进程命令行包含 "smart-sleep"，会被 pkill 匹配并杀死，导致 uninstall 流程中断、无法完成清理。

**对比**: `cmd_install` 正确使用了 `pkill -f "smart-sleep start"`，只匹配 daemon 进程。

**建议修复**:
```bash
pkill -f "smart-sleep start" 2>/dev/null || true
```

---

## 中等问题（已修复）

### 2. ~~配置文件热加载缺少输入验证~~ ✅ 已修复

**位置**: `smart-sleep.sh` 的 `load_config()` 函数

**问题**: 从配置文件读取的 `INTERVAL` 和 `DISPLAY_SLEEP` 未做校验。若用户直接编辑配置文件写入非法值（如 `INTERVAL=0`、`INTERVAL=abc`），可能导致：
- `sleep 0` 造成 CPU 空转
- `sleep abc` 报错
- `displaysleep` 传入非法值影响 pmset

**建议**: 在 `load_config` 中对读取值做范围/类型校验，与 `cmd_set` 保持一致。

### 3. ~~`display_count` 可能为空导致整数比较报错~~ ✅ 已修复

**位置**: `smart-sleep.sh` 的 `has_external_display()` 函数

**问题**: 当 `ioreg` 失败或输出异常时，`display_count` 可能为空。执行 `[ "$display_count" -ge 1 ]` 会触发 "integer expression expected" 并输出到 stderr。

**建议**:
```bash
display_count=$(ioreg -r -c AppleDisplay 2>/dev/null | grep -c '"IODisplayConnectFlags"' || true)
display_count="${display_count:-0}"
```

### 4. 重复的状态恢复逻辑

**位置**: `smart-sleep.sh` 的 `cleanup()`、`cmd_uninstall()`，以及 `uninstall.sh`

**问题**: 从 state 文件读取并恢复 `ORIG_DISABLESLEEP`、`ORIG_DISPLAYSLEEP` 的逻辑在三个地方重复实现，维护成本高且容易不一致。

**建议**: 抽取为共享函数或独立脚本片段，供多处调用。

---

## 轻微问题 / 改进建议

### 5. 主脚本未使用 `set -e`

**位置**: `smart-sleep.sh` 第 12 行

**说明**: 脚本只设置了 `set -o pipefail`，未设置 `set -e`。对 daemon 而言，不因单次命令失败而退出可能是刻意的，但建议在注释中说明设计意图，避免被误认为遗漏。

### 6. PID 文件的竞态条件

**位置**: `cmd_start()` 中 PID 检查与写入逻辑

**问题**: 两个实例几乎同时启动时，可能都通过 `get_pid` 检查，然后先后写入 PID 文件，导致多实例运行。概率较低，但在高并发场景下存在。

**建议**: 使用 `flock` 或先写 PID 再检查是否已有其他进程占用该 PID。

### 7. `uninstall.sh` 与 `cmd_uninstall` 的路径不一致

**说明**: `uninstall.sh` 假设脚本安装在 `~/.local/bin/`，而 Homebrew 安装的 `cmd_uninstall` 不删除脚本（由 brew 负责）。两者针对不同安装方式，逻辑本身合理，但建议在 README 或注释中明确说明：`uninstall.sh` 仅用于手动安装。

### 8. 日志轮转的潜在竞态

**位置**: `log()` 函数

**问题**: 检查 `if [ -f "$LOG_FILE" ]` 和 `mv` 之间，若另一个进程同时执行 log，可能产生竞态。对单 daemon 场景影响较小。

### 9. ~~README 与实现不一致~~ ✅ 已修复

**位置**: README.md 第 18 行

**问题**: README 写的是 "uses `system_profiler` + lid state"，而实际实现使用 `ioreg`（注释中已说明为性能优化）。建议更新 README 以反映当前实现。

---

## 正面评价

- 使用 `ioreg` 替代 `system_profiler` 提升检测速度
- 合盖模式下 display 检测逻辑正确（仅报告外接显示器）
- 配置热加载设计合理
- 日志轮转、Timer、信号处理等实现清晰
- 安装/卸载流程完整，支持 Homebrew 与手动安装
- 使用 `set -o pipefail` 提高管道错误处理可靠性

---

## 建议修复优先级

1. ~~**高**: 修复 `pkill -f "smart-sleep"` 问题（问题 1）~~ ✅
2. ~~**中**: 为 `load_config` 增加输入验证（问题 2）~~ ✅
3. ~~**中**: 处理 `display_count` 为空的情况（问题 3）~~ ✅
4. **低**: 抽取重复的状态恢复逻辑（问题 4）
5. ~~**低**: 更新 README 中关于 `system_profiler` 的描述（问题 9）~~ ✅
