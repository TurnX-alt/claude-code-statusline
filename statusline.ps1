<#
.SYNOPSIS
    High-signal statusline script for Claude Code.

.DESCRIPTION
    Reads a JSON object from stdin describing the current Claude Code session,
    and writes a compact one-line status string to stdout. The format is:

        EFFORT:MAX • in 312k | out 8.4k | hit 285k | miss 12k • 96% cache hit • $0.14 • ctx 42% [████░░░░░░]

    Sections with no data are silently omitted. ANSI 256-color output is emitted
    via raw escape sequences; rendering requires a terminal that interprets them
    (most modern terminals, including Claude Code's own TUI).

.REQUIREMENTS
    - PowerShell 7.0 or later (Windows PowerShell 5.1 does NOT render ANSI escapes).
      Use `pwsh.exe`, not `powershell.exe`.
    - Claude Code 2.0 or later (older versions do not send the statusline JSON).

.STDIN CONTRACT
    A single JSON object. Fields read:
      context_window.context_window_size   [int]    window size in tokens
      context_window.used_percentage        [double] 0-100
      context_window.current_usage.input_tokens                [int]
      context_window.current_usage.output_tokens               [int]
      context_window.current_usage.cache_read_input_tokens     [int]
      context_window.current_usage.cache_creation_input_tokens [int]
      cost.total_cost_usd                  [double]

.ENVIRONMENT
    CLAUDE_CONFIG_DIR
        Override path to the Claude config directory. Defaults to ~/.claude.
        Both the optional ponytail badge and the effort-level fallback read this.

.EXTENSION POINTS
    OPTIONAL — ponytail badge (lazy-mode plugin):
        If $CLAUDE_CONFIG_DIR/.ponytail-active exists and contains a mode name
        (full | lite | ultra), a [PONYTAIL[:MODE]] badge is prepended. This script
        ships with the extension wired in but inert when the file is absent.

    EFFORT LEVEL:
        Reads $CLAUDE_CONFIG_DIR/.effort-active if present; otherwise falls back
        to settings.json's effortLevel. Recognized values: low, medium, high,
        xhigh, max. No flag and no settings.json value: no badge emitted.

.NOTES
    Behavior is unchanged from the personal-use script in ~/.claude/hooks/.
    This is the distribution copy; the personal copy continues to work.
#>

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }

# --- 256-color palette ---
$DIM = "$([char]27)[38;5;245m"
$RST = "$([char]27)[0m"
$GRN = "$([char]27)[38;5;108m"
$YEL = "$([char]27)[38;5;221m"
$RED = "$([char]27)[38;5;203m"
$CYN = "$([char]27)[38;5;81m"
$BLU = "$([char]27)[38;5;111m"
$MAG = "$([char]27)[38;5;141m"
$ORA = "$([char]27)[38;5;215m"

# --- OPTIONAL: ponytail badge (inert when flag file is absent) ---
$Badge = ""
$Flag = Join-Path $ClaudeDir ".ponytail-active"
if (Test-Path $Flag) {
    try { $Mode = (Get-Content $Flag -ErrorAction Stop | Select-Object -First 1).Trim() }
    catch { $Mode = "" }   # ponytail: missing/unreadable flag = no badge, never error
    if (-not [string]::IsNullOrEmpty($Mode)) {
        $Tag = if ($Mode -eq "full") { "PONYTAIL" } else { "PONYTAIL:$($Mode.ToUpperInvariant())" }
        $Badge = "$GRN$Tag$RST"
    }
}

# --- effort level (flag file, else settings.json fallback) ---
$EffortBadge = ""
$EffortLevel = ""
$EffortFlag = Join-Path $ClaudeDir ".effort-active"
if (Test-Path $EffortFlag) {
    try { $EffortLevel = (Get-Content $EffortFlag -ErrorAction Stop | Select-Object -First 1).Trim().ToLowerInvariant() }
    catch { $EffortLevel = "" }   # ponytail: missing/unreadable flag = fall through to settings.json
}
if ([string]::IsNullOrEmpty($EffortLevel)) {
    $SettingsPath = Join-Path $ClaudeDir "settings.json"
    if (Test-Path $SettingsPath) {
        try {
            $s = Get-Content $SettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($s.effortLevel) { $EffortLevel = ([string]$s.effortLevel).Trim().ToLowerInvariant() }
        }
        catch { $EffortLevel = "" }   # ponytail: malformed settings.json = no effort badge
    }
}
if (-not [string]::IsNullOrEmpty($EffortLevel)) {
    $effortColor = $DIM
    switch ($EffortLevel) {
        'max'   { $effortColor = $RED }
        'xhigh' { $effortColor = $ORA }
        'high'  { $effortColor = $YEL }
        'medium'{ $effortColor = $CYN }
        'low'   { $effortColor = $DIM }
    }
    $EffortBadge = "$effortColor" + "EFFORT:" + "$($EffortLevel.ToUpperInvariant())" + "$RST"
}

# --- stdin JSON ---
# Bind stdin to $raw directly; do NOT pipe through `$raw | ConvertFrom-Json`.
# Piping a [String] through PowerShell's pipeline echos it to stdout AND splits
# it into line-shaped tokens, which makes ConvertFrom-Json silently fail when
# the JSON spans the whole stdin blob. Using -InputObject keeps it as one value.
$state = $null
$raw = [Console]::In.ReadToEnd()
if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try { $state = ConvertFrom-Json -InputObject $raw -ErrorAction Stop } catch { $state = $null }
}

# ponytail: avoid '-f' format strings — PS parses '0.1f' as width/precision/grouping and eats the suffix
function Format-TokenCount([int64]$n) {
    if ($n -ge 1000000) { return ([math]::Round($n / 1000000.0, 1)).ToString() + 'M' }
    if ($n -ge 1000)    { return ([math]::Round($n / 1000.0, 1)).ToString() + 'k' }
    return "$n"
}

# ponytail: 10-block bar; returns "" if Width <= 0
function Format-Bar([double]$pct, [int]$Width) {
    if ($Width -le 0) { return "" }
    $filled = [math]::Floor(($pct / 100.0) * $Width)
    if ($filled -gt $Width) { $filled = $Width }
    if ($filled -lt 0) { $filled = 0 }
    return ('█' * $filled) + ('░' * ($Width - $filled))
}

# --- context window + per-turn usage ---
$ctxPct = $null
$ctxIn = 0; $ctxOut = 0; $ctxCacheRead = 0; $ctxCacheCreate = 0
if ($state -and $state.context_window) {
    $ctx = $state.context_window
    if ($null -ne $ctx.used_percentage) { $ctxPct = [double]$ctx.used_percentage }
    if ($ctx.current_usage) {
        $u = $ctx.current_usage
        if ($u.input_tokens)               { $ctxIn          = [int64]$u.input_tokens }
        if ($u.output_tokens)              { $ctxOut         = [int64]$u.output_tokens }
        if ($u.cache_read_input_tokens)    { $ctxCacheRead   = [int64]$u.cache_read_input_tokens }
        if ($u.cache_creation_input_tokens){ $ctxCacheCreate = [int64]$u.cache_creation_input_tokens }
    }
}

$cost = 0.0
if ($state -and $state.cost -and $state.cost.total_cost_usd) { $cost = [double]$state.cost.total_cost_usd }

# --- tokens: in (paid fresh) / out (generated) / hit (cache served) / miss (cache written) ---
$tokParts = @()
if ($ctxIn -gt 0)          { $tokParts += "${DIM}in${RST} ${BLU}$(Format-TokenCount $ctxIn)${RST}" }
if ($ctxOut -gt 0)         { $tokParts += "${DIM}out${RST} ${MAG}$(Format-TokenCount $ctxOut)${RST}" }
if ($ctxCacheRead -gt 0)   { $tokParts += "${DIM}hit${RST} ${CYN}$(Format-TokenCount $ctxCacheRead)${RST}" }
if ($ctxCacheCreate -gt 0) { $tokParts += "${DIM}miss${RST} ${ORA}$(Format-TokenCount $ctxCacheCreate)${RST}" }
$tokStr = if ($tokParts.Count -gt 0) { $tokParts -join " ${DIM}|${RST} " } else { "" }

# --- cache hit % (cache_read / (cache_read + cache_creation)) ---
$cacheHitStr = ""
$cacheTotal = $ctxCacheRead + $ctxCacheCreate
if ($cacheTotal -gt 0) {
    $hitPct = [math]::Round(($ctxCacheRead * 100.0) / $cacheTotal, 0)
    $hitColor = if ($hitPct -ge 80) { $GRN } elseif ($hitPct -ge 50) { $CYN } else { $YEL }
    $cacheHitStr = "$hitColor" + "$hitPct%" + "$RST" + "${DIM} cache hit${RST}"
}

# --- cost ---
$costStr = ""
if ($cost -gt 0) { $costStr = $DIM + '$' + ('{0:0.00}' -f $cost) + $RST }

# --- ctx% with bar ---
$ctxStr = ""
if ($ctxPct -ne $null) {
    $used = [math]::Round($ctxPct, 0)
    $color = $GRN
    if ($used -ge 70) { $color = $YEL }
    if ($used -ge 90) { $color = $RED }
    $bar = Format-Bar $used 10
    $ctxStr = "$color" + "ctx $used%" + "$RST" + "$DIM [$bar]$RST"
}

# --- assemble ---
$SEP = " $DIM•$RST "
$parts = @($Badge, $EffortBadge, $tokStr, $cacheHitStr, $costStr, $ctxStr) | Where-Object { $_ }
[Console]::Write(($parts -join $SEP))