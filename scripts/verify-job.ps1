#requires -Version 5.1
<#
.SYNOPSIS
  Mechanical verification gate (judge only — never commit/merge/fix).
.PARAMETER JobId
  Job id used for Codex log path .agents/logs/codex/{JobId}.last.txt
.PARAMETER OwnedPaths
  Optional repo-relative path prefixes; all changed files must fall under one.
.PARAMETER BaseRef
  Optional git ref for comparison. Resolved to a commit SHA first; values starting
  with '-' are rejected (prevents git option injection such as --output=...).
.PARAMETER SkipLog
  Skip Codex log non-empty check (Grok-direct implement).
.PARAMETER AcceptTestChanges
  Explicit override for F07 test-weakening FAIL.
.PARAMETER RepoRoot
  Override repository root.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $JobId,

  [string[]] $OwnedPaths = @(),

  [string] $BaseRef = '',

  [switch] $SkipLog,

  [switch] $AcceptTestChanges,

  [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$script:GitFailed = $false
$script:GitFailMessages = [System.Collections.Generic.List[string]]::new()

function Get-RepoRoot {
  if ($RepoRoot) { return (Resolve-Path -LiteralPath $RepoRoot).Path }
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Write-Item {
  param(
    [ValidateSet('PASS', 'WARN', 'FAIL')]
    [string] $Level,
    [string] $Name,
    [string] $Message
  )
  Write-Host ("[{0}] {1}: {2}" -f $Level, $Name, $Message)
  [pscustomobject]@{ Level = $Level; Name = $Name; Message = $Message }
}

function Invoke-GitChecked {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $GitArgs
  )
  # Defense in depth: never pass a bare option-looking token after subcommand without allowlist.
  foreach ($a in $GitArgs) {
    if ($a -match '^--output(=|$)') {
      throw "Refusing git argument that can write files: $a"
    }
  }
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = & git @GitArgs 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $lines = @($out | ForEach-Object { "$_" })
  if ($code -ne 0) {
    $script:GitFailed = $true
    $msg = "git $($GitArgs -join ' ') exit=$code :: $(($lines | Select-Object -First 3) -join ' | ')"
    $script:GitFailMessages.Add($msg) | Out-Null
    return @()
  }
  return $lines
}

function Resolve-BaseRefSha {
  param([string] $Ref)
  if ([string]::IsNullOrWhiteSpace($Ref)) { return '' }
  $trimmed = $Ref.Trim()
  # Reject option-shaped input (F10: BaseRef must not inject git flags).
  if ($trimmed.StartsWith('-')) {
    throw "BaseRef must be a ref/SHA, not a git option: $trimmed"
  }
  if ($trimmed -match '[\s"''`]|--') {
    throw "BaseRef contains forbidden characters: $trimmed"
  }
  $shaLines = Invoke-GitChecked @('rev-parse', '--verify', "$trimmed^{commit}")
  if ($script:GitFailed -or $shaLines.Count -eq 0) {
    throw "BaseRef could not be resolved to a commit: $trimmed"
  }
  return $shaLines[0].Trim()
}

function Add-UntrackedPaths {
  param([System.Collections.Generic.HashSet[string]] $Set)
  foreach ($line in (Invoke-GitChecked @('status', '--porcelain', '-uall'))) {
    if ($line.Length -lt 4) { continue }
    $xy = $line.Substring(0, 2)
    if ($xy -eq '??') {
      $path = $line.Substring(3).Trim().Trim('"').Replace('\', '/')
      if ($path) { [void]$Set.Add($path) }
    }
  }
}

function Get-ChangedPaths {
  param([string] $BaseSha)
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

  if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    foreach ($line in (Invoke-GitChecked @('diff', '--name-only'))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
    foreach ($line in (Invoke-GitChecked @('diff', '--cached', '--name-only'))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
  }
  else {
    foreach ($line in (Invoke-GitChecked @('diff', '--name-only', $BaseSha))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
    foreach ($line in (Invoke-GitChecked @('diff', '--cached', '--name-only', $BaseSha))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
  }
  # Always include untracked (owned_paths can escape via new files under any BaseRef mode).
  Add-UntrackedPaths -Set $set
  return @($set)
}

function Get-AddedDiffLines {
  param([string] $BaseSha)
  $chunks = @()
  if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    $chunks += Invoke-GitChecked @('diff', '-U0')
    $chunks += Invoke-GitChecked @('diff', '--cached', '-U0')
  }
  else {
    $chunks += Invoke-GitChecked @('diff', '-U0', $BaseSha)
    $chunks += Invoke-GitChecked @('diff', '--cached', '-U0', $BaseSha)
  }
  $added = @()
  foreach ($line in $chunks) {
    if ($line.StartsWith('+') -and -not $line.StartsWith('+++')) {
      $added += $line.Substring(1)
    }
  }
  return $added
}

function Get-DeletedPaths {
  param([string] $BaseSha)
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $argSets = if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    @(@('diff', '--name-status'), @('diff', '--cached', '--name-status'))
  }
  else {
    @(@('diff', '--name-status', $BaseSha), @('diff', '--cached', '--name-status', $BaseSha))
  }
  foreach ($args in $argSets) {
    foreach ($line in (Invoke-GitChecked $args)) {
      if ($line -match '^[D]\s+(.+)$') {
        [void]$set.Add($Matches[1].Trim().Replace('\', '/'))
      }
    }
  }
  return @($set)
}

function Test-UnderOwnedPaths {
  param(
    [string] $Path,
    [string[]] $Owned
  )
  $p = $Path.Replace('\', '/').TrimStart('./').ToLowerInvariant()
  foreach ($o in $Owned) {
    $own = $o.Replace('\', '/').Trim().TrimStart('./').TrimEnd('/').ToLowerInvariant()
    if (-not $own) { continue }
    if ($p -eq $own -or $p.StartsWith($own + '/')) { return $true }
  }
  return $false
}

$root = Get-RepoRoot
Set-Location $root
$items = [System.Collections.Generic.List[object]]::new()
$fail = $false

# 1. Status / log
if ($SkipLog) {
  $items.Add((Write-Item PASS 'status:log' 'skipped (-SkipLog)')) | Out-Null
}
else {
  $logPath = Join-Path $root ".agents\logs\codex\$JobId.last.txt"
  if (-not (Test-Path -LiteralPath $logPath)) {
    $items.Add((Write-Item FAIL 'status:log' "missing: $logPath")) | Out-Null
    $fail = $true
  }
  elseif ((Get-Item -LiteralPath $logPath).Length -eq 0) {
    $items.Add((Write-Item FAIL 'status:log' "empty: $logPath")) | Out-Null
    $fail = $true
  }
  else {
    $items.Add((Write-Item PASS 'status:log' "non-empty: $logPath")) | Out-Null
  }
}

# Resolve BaseRef early (fail closed)
$baseSha = ''
try {
  if (-not [string]::IsNullOrWhiteSpace($BaseRef)) {
    $baseSha = Resolve-BaseRefSha -Ref $BaseRef
    $items.Add((Write-Item PASS 'git:baseref' "resolved to $baseSha")) | Out-Null
  }
}
catch {
  $items.Add((Write-Item FAIL 'git:baseref' $_.Exception.Message)) | Out-Null
  $fail = $true
}

# 2. Diff scope (worktree + index + untracked; BaseRef uses resolved SHA only)
$changed = @()
if (-not $fail) {
  $changed = @(Get-ChangedPaths -BaseSha $baseSha)
}
if ($script:GitFailed) {
  $items.Add((Write-Item FAIL 'git' (($script:GitFailMessages | Select-Object -First 3) -join '; '))) | Out-Null
  $fail = $true
}

if (-not $fail) {
  if ($OwnedPaths.Count -gt 0) {
    $escapes = @()
    foreach ($path in $changed) {
      if (-not (Test-UnderOwnedPaths -Path $path -Owned $OwnedPaths)) {
        $escapes += $path
      }
    }
    if ($escapes.Count -gt 0) {
      $items.Add((Write-Item FAIL 'diff:scope' ("outside owned_paths: {0}" -f ($escapes -join ', ')))) | Out-Null
      $fail = $true
    }
    else {
      $items.Add((Write-Item PASS 'diff:scope' ("{0} path(s) within owned_paths" -f $changed.Count))) | Out-Null
    }
  }
  else {
    $items.Add((Write-Item PASS 'diff:scope' ("owned_paths not set; {0} changed path(s) observed" -f $changed.Count))) | Out-Null
  }
}

# 3. Stub detection (WARN only)
$addedLines = @()
$deleted = @()
if (-not $fail) {
  $addedLines = @(Get-AddedDiffLines -BaseSha $baseSha)
  $deleted = @(Get-DeletedPaths -BaseSha $baseSha)
  if ($script:GitFailed) {
    $items.Add((Write-Item FAIL 'git' (($script:GitFailMessages | Select-Object -First 3) -join '; '))) | Out-Null
    $fail = $true
  }
}

if (-not $fail) {
  $stubHits = @()
  foreach ($line in $addedLines) {
    if ($line -match 'NotImplementedError' -or $line -match 'TODO:' -or $line -match "throw new Error\('not implemented'\)") {
      $stubHits += $line.Trim()
    }
  }
  if ($stubHits.Count -gt 0) {
    $sample = ($stubHits | Select-Object -First 3) -join ' | '
    $items.Add((Write-Item WARN 'stub' "possible stub markers in added lines: $sample")) | Out-Null
  }
  else {
    $items.Add((Write-Item PASS 'stub' 'no stub markers in added lines')) | Out-Null
  }

  # 4. Test weakening (F07) — staged + unstaged
  $testDeleteHits = @($deleted | Where-Object { $_ -match '(?i)(test|spec|Tests)' })
  $skipHits = @()
  foreach ($line in $addedLines) {
    if ($line -match 'Skip\s*=\s*\$true' -or $line -match 'it\.skip' -or $line -match 'describe\.skip' -or $line -match '@pytest\.mark\.skip') {
      $skipHits += $line.Trim()
    }
  }

  if ($testDeleteHits.Count -gt 0 -or $skipHits.Count -gt 0) {
    $msgParts = @()
    if ($testDeleteHits.Count -gt 0) { $msgParts += "deleted test-like paths: $($testDeleteHits -join ', ')" }
    if ($skipHits.Count -gt 0) { $msgParts += "skip markers: $(($skipHits | Select-Object -First 3) -join ' | ')" }
    $msg = $msgParts -join '; '
    if ($AcceptTestChanges) {
      $items.Add((Write-Item PASS 'f07:tests' "accepted via -AcceptTestChanges: $msg")) | Out-Null
    }
    else {
      $items.Add((Write-Item FAIL 'f07:tests' "$msg (use -AcceptTestChanges to override)")) | Out-Null
      $fail = $true
    }
  }
  else {
    $items.Add((Write-Item PASS 'f07:tests' 'no test deletion or skip markers detected')) | Out-Null
  }
}

# 5. Summary
if ($fail) {
  Write-Host 'verify-job: FAIL'
  exit 1
}
Write-Host 'verify-job: PASS'
exit 0
