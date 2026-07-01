# Claude Code Statusline

用于 [Claude Code](https://docs.claude.com/en/docs/claude-code) 的 PowerShell 状态栏脚本：每回合输出 token 用量、费用、缓存命中率与上下文窗口占用。

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/OWNER/REPO.svg" alt="License"></a>
  <a href="releases"><img src="https://img.shields.io/github/v/release/OWNER/REPO?label=Release" alt="Release"></a>
  <a href="actions"><img src="https://img.shields.io/github/actions/workflow/status/OWNER/REPO/test.yml?branch=main" alt="Build"></a>
  <a href="#环境要求"><img src="https://img.shields.io/badge/pwsh-%E2%89%A57.0-blue" alt="PowerShell"></a>
  <a href="#跨平台说明"><img src="https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-lightgrey" alt="Platform"></a>
</p>

## 显示内容

每个回合输出一行状态。

默认：

```
in 312k | out 8.4k | hit 285k | miss 12k • 96% cache hit • $0.14 • ctx 42% [████░░░░░░]
```

启用 ponytail 徽标后（见 [可选扩展](#可选扩展)）：

```
PONYTAIL • in 312k | out 8.4k | hit 285k | miss 12k • 96% cache hit • $0.14 • ctx 42% [████░░░░░░]
```

启用 effort 徽标（等级来自标志文件或 `settings.json`）：

```
PONYTAIL • EFFORT:MAX • in 312k | out 8.4k | hit 285k | miss 12k • 96% cache hit • $0.14 • ctx 42% [████░░░░░░]
```

### 字段含义

| 标签 | 来源 | 颜色 |
|---|---|---|
| `in` | `current_usage.input_tokens`，本次提示中按全价计费的部分 | 蓝 |
| `out` | `current_usage.output_tokens`，模型生成的输出 | 紫 |
| `hit` | `current_usage.cache_read_input_tokens`，命中缓存复用 | 青 |
| `miss` | `current_usage.cache_creation_input_tokens`，写入新缓存 | 橙 |
| `% cache hit` | `hit / (hit + miss)` | ≥80% 绿，≥50% 青，更低黄 |
| `$X.XX` | `cost.total_cost_usd`，会话累计费用 | 灰 |
| `ctx X% [bar]` | `context_window.used_percentage`，10 格条形图 | <70% 绿，70-89% 黄，≥90% 红 |

未提供数据的字段静默省略。

## 特性

- 按类别拆分 token，附带缓存命中率。
- 上下文窗口同时以百分比和 10 格条形图呈现。
- 会话累计费用。
- ponytail 与 effort 徽标由标志文件触发，缺失时脚本保持纯 Claude Code 状态栏行为。
- ANSI 256 色输出。除 `pwsh` 7 之外无任何外部依赖。

## 环境要求

- `pwsh` 7.0 或更高版本。Windows PowerShell 5.1 可以执行，但不会渲染 ANSI 颜色。
- Claude Code 2.0 或更高版本；更早版本不会通过 stdin 推送状态栏 JSON。

## 安装

### 1. 放置脚本

将 `statusline.ps1` 复制到稳定路径：

```bash
mkdir -p ~/.claude
cp statusline.ps1 ~/.claude/statusline.ps1
```

### 2. 接入 Claude Code

在 `~/.claude/settings.json` 中加入 `statusLine` 字段：

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh ~/.claude/statusline.ps1"
  }
}
```

若脚本放在其他路径，请调整 `command`。Windows 平台应使用 `pwsh.exe`。

## 配置

- `CLAUDE_CONFIG_DIR`：覆盖 Claude Code 读取设置的目录，状态栏自动识别。
- `.ponytail-active`：位于 `CLAUDE_CONFIG_DIR`（默认 `~/.claude`）的标志文件。存在则启用 `PONYTAIL` 徽标；首行内容（`full` | `lite` | `ultra`）决定徽标文本。
- `.effort-active`：同目录的标志文件。首行内容（`low` | `medium` | `high` | `xhigh` | `max`）显示为 `EFFORT:<LEVEL>`。文件不存在时回退到 `settings.json` 中的 `effortLevel`；两者皆缺则不显示 effort 徽标。

## 可选扩展

无需修改脚本，放置标志文件即可启用对应徽标：

```bash
echo full > ~/.claude/.ponytail-active
```

显示 effort 等级：

```bash
echo max > ~/.claude/.effort-active
```

删除文件即可关闭徽标。每次调用都会重新检查，下一回合立即生效。

## 开发

仓库内置 smoke test，将固定 fixture 送入状态栏并断言输出包含预期片段：

```bash
pwsh ./tests/smoke.ps1
```

通过则退出码 0，失败则 1。

## 跨平台说明

- **Linux**：在 `pwsh` 7 下运行，无原生依赖。
- **macOS**：与 Linux 相同。
- **Windows**：直接在 `pwsh` 7 下运行，无需 WSL 或外部工具。

## 许可证

MIT。详见 [LICENSE](LICENSE)。

## 致谢

灵感来自 [stormzhang/token-tracker](https://github.com/stormzhang/token-tracker)，改造为读取 Claude Code 的 stdin JSON 并渲染为单行状态栏。