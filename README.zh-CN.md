# smart-sleep

macOS 智能合盖模式管理器。轻量级、零依赖的 Shell 脚本。

**[English](./README.md)**

## 问题背景

macOS 在合盖模式（合上盖子连接外接显示器）下需要连接电源适配器。未接电源时，合上盖子会立即让 Mac 进入睡眠，导致外接显示器信号中断。

直接运行 `pmset disablesleep 1` 可以解决显示问题，但会带来新问题：你的 Mac **永远不会睡眠**，即使拔掉显示器、把电脑塞进包里也是如此。

## 解决方案

**smart-sleep** 作为后台守护进程运行，实现：

1. **检测外接显示器** — 使用 `system_profiler` 结合盖子状态进行准确检测
2. **连接外接显示器时禁用睡眠** — 无论是否接电源均可工作
3. **显示器断开且盖子关闭时强制睡眠**
4. **管理显示器超时** — 闲置后显示器仍会正常熄屏

全部由一个 Shell 脚本实现。无需编译、无额外依赖、无需 App Store。

## 功能特性

- 盖子感知的显示器检测 — 正确处理合盖模式下 macOS 仅报告外接显示器的情况
- 自动睡眠/唤醒管理 — 根据显示器与盖子状态智能切换
- 断开时强制睡眠 — 显示器拔掉且盖子关闭时 Mac 自动睡眠
- 计时器模式 — 临时禁用睡眠指定时长
- 日志轮转 — 自动管理日志
- 可配置 — 通过环境变量设置轮询间隔、显示器睡眠超时
- 简洁安装/卸载 — 一键安装、一键移除
- LaunchAgent 集成 — 登录后自动启动
- Shell 脚本，零依赖 — 无需编译、无需 App Store
- 兼容 macOS Tahoe
- CLI 命令 — 查看状态、计时器、配置
- 支持 Homebrew 安装

## 安装

### Homebrew

```bash
brew tap lbb00/smart-sleep https://github.com/lbb00/smart-sleep
brew install smart-sleep
```

### 手动安装

```bash
git clone https://github.com/lbb00/smart-sleep.git
cd smart-sleep
bash install.sh
```

安装程序将：

- 将 `smart-sleep.sh` 复制到 `~/.local/bin/`
- 仅为 `pmset` 配置免密 sudo
- 安装并启动 LaunchAgent（登录后自动运行）

## 使用方法

```bash
# 查看状态
smart-sleep.sh status

# 禁用睡眠 1 小时（不受显示器状态影响）
smart-sleep.sh timer

# 取消计时器
smart-sleep.sh timer-off

# 停止守护进程
smart-sleep.sh stop

# 查看日志
cat /tmp/smart-sleep.log
```

> **提示：** Homebrew 安装后命令已在 PATH 中。手动安装需将 `~/.local/bin` 加入 PATH 或使用完整路径。

## 配置

无需重启守护进程即可修改配置：

```bash
# 设置轮询间隔为 3 秒
smart-sleep.sh set interval 3

# 设置显示器睡眠超时为 5 分钟
smart-sleep.sh set displaysleep 5
```

配置保存在 `~/.config/smart-sleep/config`，会自动生效。

### 环境变量

安装前可设置初始默认值：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SMART_SLEEP_INTERVAL` | `5` | 轮询间隔（秒） |
| `SMART_SLEEP_DISPLAY_SLEEP` | `10` | 显示器睡眠超时（分钟） |
| `SMART_SLEEP_LOG` | `/tmp/smart-sleep.log` | 日志文件路径 |

## 工作原理

```
┌──────────────────────────────────────┐
│           每 N 秒执行一次             │
│                                      │
│  ┌─ 有外接显示器？                    │
│  │   是 → disablesleep 1（保持唤醒）  │
│  │   否 → 盖子是否关闭？              │
│  │          是 → pmset sleepnow      │
│  │          否 → 保持唤醒             │
│  │                                   │
│  └─ 计时器激活？ → 覆盖：保持唤醒     │
└──────────────────────────────────────┘
```

**核心逻辑：** 盖子关闭时，macOS 不会在 `system_profiler` 中报告内置显示器。因此盖子关闭且 `display_count=1` 时，表示外接显示器已连接。脚本结合盖子状态与显示器数量实现准确检测。

## 行为矩阵

| 场景 | 行为 |
|------|------|
| 盖子关闭 + 外接显示器（任意电源状态） | ✅ 显示器正常，Mac 保持唤醒 |
| 锁屏 + 闲置 10 分钟 | ✅ 显示器熄屏 |
| 盖子关闭 + 显示器断开 | ✅ 约 5 秒内 Mac 进入睡眠 |
| 盖子打开 + 无外接显示器 | ✅ 正常使用 |
| 手动 Apple → 睡眠 | ✅ 正常工作 |
| 睡眠后重新连接显示器 | ⚠️ 需按外接键盘/鼠标唤醒 |

## 卸载

**Homebrew：**
```bash
brew uninstall smart-sleep
```

**手动安装：**
```bash
bash uninstall.sh
```

将停止守护进程、删除所有文件、清理 sudoers 配置并恢复默认睡眠设置。

## 许可证

Unlicense（公有领域）— <https://unlicense.org>
