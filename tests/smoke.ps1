<#
.SYNOPSIS
    Smoke test for statusline.ps1. Pipes a mock session JSON into the script
    and asserts that all expected fragments are present in the rendered output.

.DESCRIPTION
    Exits 0 on success with "PASS" on stdout; exits 1 with "FAIL: <reason>"
    on the first missing fragment.

.NOTES
    Run with:
        pwsh -NoProfile -File tests/smoke.ps1
#>

$ErrorActionPreference = 'Stop'
$Script = Join-Path $PSScriptRoot '..\statusline.ps1'
if (-not (Test-Path $Script)) {
    Write-Host "FAIL: statusline.ps1 not found at $Script"
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
    Write-Host "FAIL: script threw an exception: $_"
    exit 1
}

if ($null -eq $output -or $output.Count -eq 0) {
    Write-Host "FAIL: no output from statusline.ps1"
    exit 1
}
$text = ($output | Out-String)

# ponytail: strip ANSI escape sequences before substring match — pwsh's pipeline
# preserves raw ESC bytes; bare -notmatch fails when the bytes around the target fragment
# get split across "lines" by the test runner.
$stripped = [regex]::Replace($text, "`e\[[0-9;]*[A-Za-z]", '')

# Each fragment must appear at least once
$expected = @('in ', 'out ', 'hit ', 'miss ', 'ctx ', 'cache hit', '$', 'EFFORT:')
$missing = @()
foreach ($frag in $expected) {
    if ($stripped.IndexOf($frag) -lt 0) { $missing += $frag }
}

if ($missing.Count -gt 0) {
    Write-Host "FAIL: missing fragments: $($missing -join ', ')"
    Write-Host "--- output ---"
    Write-Host $text
    Write-Host "-------------"
    exit 1
}

Write-Host "PASS"
exit 0