<#
.SYNOPSIS
    Smoke test for statusline.ps1. Pipes a mock session JSON into the script
    and asserts that all expected fragments are present in the rendered output.

.DESCRIPTION
    Writes "PASS" to stdout on success; writes "FAIL: <reason>" and exits 1
    on the first missing fragment.

.NOTES
    Run with:
        pwsh -NoProfile -File tests/smoke.ps1
#>

$ErrorActionPreference = 'Stop'
$Script = Join-Path $PSScriptRoot '..\statusline.ps1'
if (-not (Test-Path $Script)) {
    [Console]::Error.WriteLine("FAIL: statusline.ps1 not found at $Script")
    exit 1
}

# Realistic mid-session numbers
$MockJson = @'
{
  "model": { "id": "claude-opus-4-8", "display_name": "Opus 4.8" },
  "context_window": {
    "context_window_size": 1000000,
    "used_percentage": 42,
    "current_usage": {
      "input_tokens": 312000,
      "output_tokens": 8400,
      "cache_read_input_tokens": 285000,
      "cache_creation_input_tokens": 12000
    }
  },
  "cost": { "total_cost_usd": 0.14 }
}
'@

try {
    $output = $MockJson | pwsh -NoProfile -ExecutionPolicy Bypass -File $Script 2>&1
} catch {
    [Console]::Error.WriteLine("FAIL: script threw an exception: $_")
    exit 1
}

if ($null -eq $output -or $output.Count -eq 0) {
    [Console]::Error.WriteLine("FAIL: no output from statusline.ps1")
    exit 1
}
$text = ($output | Out-String)

# ponytail: strip ANSI escape sequences before substring match — pwsh's pipeline
# preserves raw ESC bytes; bare -notmatch fails when the bytes around the target fragment
# get split across "lines" by the test runner.
$stripped = [regex]::Replace($text, "`e\[[0-9;]*[A-Za-z]", '')

# Core fragments must always appear when the fixture supplies the data.
$expected = @('in ', 'out ', 'hit ', 'miss ', 'ctx ', 'cache hit', '$')
$missing = @()
foreach ($frag in $expected) {
    if ($stripped.IndexOf($frag) -lt 0) { $missing += $frag }
}

# Optional fragments: only assert when the test harness opted in.
# Set $env:SMOKE_EXPECT_EFFORT = 'max' (or any value) to verify the effort badge path.
if ($env:SMOKE_EXPECT_EFFORT) {
    if ($stripped.IndexOf('EFFORT:') -lt 0) { $missing += 'EFFORT:' }
}
# Set $env:SMOKE_EXPECT_PONYTAIL = '1' to verify the ponytail badge path.
if ($env:SMOKE_EXPECT_PONYTAIL) {
    if ($stripped.IndexOf('PONYTAIL') -lt 0) { $missing += 'PONYTAIL' }
}

if ($missing.Count -gt 0) {
    [Console]::Error.WriteLine("FAIL: missing fragments: $($missing -join ', ')")
    [Console]::Error.WriteLine("--- output ---")
    [Console]::Error.WriteLine($text)
    [Console]::Error.WriteLine("-------------")
    exit 1
}

[Console]::WriteLine("PASS")
exit 0