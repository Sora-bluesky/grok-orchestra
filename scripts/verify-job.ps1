#requires -Version 5.1
<#
.SYNOPSIS
  Mechanical verification gate (judge only — never commit/merge/fix).
.PARAMETER JobId
  Job id used for Codex log path .agents/logs/codex/{JobId}.last.txt
.PARAMETER OwnedPaths
  Optional repo-relative path prefixes; all changed files must fall under one.
.PARAMETER BaseRef
  Optional git ref for comparison (includes worktree vs ref). Empty = worktree+index+untracked.
.PARAMETER SkipLog
  Skip Codex log non-empty check (Grok-direct implement).
.PARAMETER AcceptTestChanges
  Explicit override for F07 test-weakening FAIL (still reports WARN-style note as PASS with accept).
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

function Invoke-Git {
  param([string[]] $GitArgs)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = & git @GitArgs 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return [pscustomobject]@{
    ExitCode = $code
    Lines    = @($out | ForEach-Object { "$_" })
  }
}

function Get-ChangedPaths {
  param([string] $BaseRefValue)
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

  if ([string]::IsNullOrWhiteSpace($BaseRefValue)) {
    foreach ($line in (Invoke-Git @('diff', '--name-only')).Lines) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
    foreach ($line in (Invoke-Git @('diff', '--cached', '--name-only')).Lines) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
    foreach ($line in (Invoke-Git @('status', '--porcelain')).Lines) {
      if ($line.Length -lt 4) { continue }
      $code = $line.Substring(0, 2)
      if ($code -eq '??' -or $code.Trim() -eq '??') {
        $path = $line.Substring(3).Trim().Trim('"').Replace('\', '/')
        if ($path) { [void]$set.Add($path) }
      }
    }
  }
  else {
    foreach ($line in (Invoke-Git @('diff', '--name-only', $BaseRefValue)).Lines) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
    foreach ($line in (Invoke-Git @('diff', '--name-only', '--cached', $BaseRefValue)).Lines) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
  }

  return @($set)
}

function Get-AddedDiffLines {
  param([string] $BaseRefValue)
  $chunks = @()
  if ([string]::IsNullOrWhiteSpace($BaseRefValue)) {
    $chunks += (Invoke-Git @('diff', '-U0')).Lines
    $chunks += (Invoke-Git @('diff', '--cached', '-U0')).Lines
  }
  else {
    $chunks += (Invoke-Git @('diff', '-U0', $BaseRefValue)).Lines
    $chunks += (Invoke-Git @('diff', '--cached', '-U0', $BaseRefValue)).Lines
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
  param([string] $BaseRefValue)
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $nameStatusArgs = if ([string]::IsNullOrWhiteSpace($BaseRefValue)) {
    @(@('diff', '--name-status'), @('diff', '--cached', '--name-status'))
  }
  else {
    @(@('diff', '--name-status', $BaseRefValue), @('diff', '--cached', '--name-status', $BaseRefValue))
  }
  foreach ($args in $nameStatusArgs) {
    foreach ($line in (Invoke-Git $args).Lines) {
      if ($line -match '^[D]\s+(.+)$') {
        [void]$set.Add($Matches[1].Trim().Replace('\', '/'))
      }
      elseif ($line -match '^[R][0-9]*\s+\S+\s+(.+)$') {
        # renames are not pure deletes
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

# 2. Diff scope (worktree + index + untracked)
$changed = @(Get-ChangedPaths -BaseRefValue $BaseRef)
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

# 3. Stub detection (WARN only)
$addedLines = @(Get-AddedDiffLines -BaseRefValue $BaseRef)
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
$deleted = @(Get-DeletedPaths -BaseRefValue $BaseRef)
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

# 5. Summary
if ($fail) {
  Write-Host 'verify-job: FAIL'
  exit 1
}
Write-Host 'verify-job: PASS'
exit 0
