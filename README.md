# Claude Code Statusline

A PowerShell statusline script for [Claude Code](https://docs.claude.com/en/docs/claude-code) that prints token usage, cost, cache hit rate, and context window consumption after each turn.

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/OWNER/REPO.svg" alt="License"></a>
  <a href="releases"><img src="https://img.shields.io/github/v/release/OWNER/REPO?label=Release" alt="Release"></a>
  <a href="actions"><img src="https://img.shields.io/github/actions/workflow/status/OWNER/REPO/test.yml?branch=main" alt="Build"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/pwsh-%E2%89%A57.0-blue" alt="PowerShell"></a>
  <a href="#cross-platform-notes"><img src="https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-lightgrey" alt="Platform"></a>
</p>

## What it shows

One line per Claude Code turn.

Default:

```
in 312k | out 8.4k | hit 285k | miss 12k • 96% cache hit • $0.14 • ctx 42% [████░░░░░░]
```

With the optional ponytail badge enabled (see [Optional extensions](#optional-extensions)):

```
PONYTAIL • in 312k | out 8.4k | hit 285k | miss 12k • 96% cache hit • $0.14 • ctx 42% [████░░░░░░]
```

With the optional effort badge (the level comes from a flag file or `settings.json`):

```
PONYTAIL • EFFORT:MAX • in 312k | out 8.4k | hit 285k | miss 12k • 96% cache hit • $0.14 • ctx 42% [████░░░░░░]
```

### Field meanings

| Label | Source | Color |
|---|---|---|
| `in` | `current_usage.input_tokens` — paid fresh prompt content | blue |
| `out` | `current_usage.output_tokens` — model output | magenta |
| `hit` | `current_usage.cache_read_input_tokens` — cache reused | cyan |
| `miss` | `current_usage.cache_creation_input_tokens` — cache written | orange |
| `% cache hit` | `hit / (hit + miss)` | green ≥80%, cyan ≥50%, yellow below |
| `$X.XX` | `cost.total_cost_usd` (cumulative session cost) | dim |
| `ctx X% [bar]` | `context_window.used_percentage`, 10-cell bar | green <70%, yellow 70-89%, red ≥90% |

Sections with no data (no API call yet, no cost accumulated, no flag file) are silently omitted.

## Features

- Token breakdown by category, with cache hit rate.
- Context window as both a percentage and a 10-cell bar.
- Session-cumulative cost.
- Optional ponytail and effort badges, driven by flag files. The script stays inert without them.
- ANSI 256-color output. No external dependencies beyond `pwsh` 7.

## Requirements

- `pwsh` 7.0 or newer. Windows PowerShell 5.1 will run the script but will not render the ANSI colors.
- Claude Code 2.0 or newer. Older versions do not feed the statusline JSON on stdin.

## Installation

### 1. Place the script

Copy `statusline.ps1` to a stable location:

```bash
mkdir -p ~/.claude
cp statusline.ps1 ~/.claude/statusline.ps1
```

### 2. Wire it into Claude Code

Add a `statusLine` block to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh ~/.claude/statusline.ps1"
  }
}
```

Adjust the path if you placed the script elsewhere. On Windows, the command is `pwsh.exe`.

## Configuration

- `CLAUDE_CONFIG_DIR` — overrides the directory Claude Code reads settings from. The statusline picks this up automatically.
- `.ponytail-active` — flag file in `CLAUDE_CONFIG_DIR` (default `~/.claude`). Presence enables the `PONYTAIL` badge. First-line content (`full` | `lite` | `ultra`) controls the badge label.
- `.effort-active` — flag file in the same directory. First-line content (`low` | `medium` | `high` | `xhigh` | `max`) is shown as `EFFORT:<LEVEL>`. Falls back to `effortLevel` in `settings.json` when the file is absent. Absent everywhere: no effort badge.

## Optional extensions

To enable the ponytail badge without editing the script:

```bash
echo full > ~/.claude/.ponytail-active
```

To display an effort level:

```bash
echo max > ~/.claude/.effort-active
```

Delete the file to disable the badge. Both checks happen on each invocation, so toggling takes effect on the next turn.

## Development

A smoke test ships with the repo. It pipes a fixed fixture through the statusline and asserts the rendered output contains the expected fragments:

```bash
pwsh ./tests/smoke.ps1
```

Exit 0 on pass, 1 on failure.

## Cross-platform notes

- **Linux** — runs under `pwsh` 7. No native dependencies.
- **macOS** — same as Linux.
- **Windows** — runs under `pwsh` 7 directly; no WSL or external tools.

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgments

Inspired by [stormzhang/token-tracker](https://github.com/stormzhang/token-tracker), adapted to consume Claude Code's stdin JSON and render as a single-line statusline.