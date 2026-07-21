#requires -Version 5.1
<#
.SYNOPSIS
  Doctor for grok-orchestra: tool presence, SSOT layout, stale locks/leases, gitignore.
.PARAMETER Fix
  Remove dead write-job.lock (missing process) and mark orphan running leases as stale.
.PARAMETER LockDir
  Override locks directory (default: <repo>/.agents/locks). Tests inject $TestDrive here.
.PARAMETER RepoRoot
  Override repository root (default: parent of scripts/).
#>
[CmdletBinding()]
param(
  [switch] $Fix,
  [string] $LockDir = '',
  [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  if ($RepoRoot) { return (Resolve-Path -LiteralPath $RepoRoot).Path }
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Write-CheckResult {
  param(
    [ValidateSet('OK', 'WARN', 'FAIL')]
    [string] $Level,
    [string] $Name,
    [string] $Message
  )
  Write-Host ("[{0}] {1}: {2}" -f $Level, $Name, $Message)
  [pscustomobject]@{ Level = $Level; Name = $Name; Message = $Message }
}

$root = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($LockDir)) {
  $LockDir = Join-Path $root '.agents\locks'
}
$results = [System.Collections.Generic.List[object]]::new()

# 1. Tool presence (same priority as delegate-codex Resolve-CodexNodeInvocation)
$npmCodex = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\bin\codex.js'
$codexCmd = Get-Command codex -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $npmCodex) {
  $results.Add((Write-CheckResult OK 'tool:codex' "npm codex.js present: $npmCodex")) | Out-Null
}
elseif ($codexCmd) {
  $results.Add((Write-CheckResult OK 'tool:codex' "codex on PATH: $($codexCmd.Source)")) | Out-Null
}
else {
  $results.Add((Write-CheckResult FAIL 'tool:codex' 'Neither npm codex.js nor codex on PATH found')) | Out-Null
}

# 2. SSOT layout
$required = @(
  'AGENTS.md',
  '.agents\INDEX.md',
  '.agents\docs\failure-modes.md',
  'scripts\delegate-codex.ps1',
  'scripts\lease-paths.ps1'
)
foreach ($rel in $required) {
  $full = Join-Path $root $rel
  $name = "ssot:$($rel.Replace('\', '/'))"
  if (Test-Path -LiteralPath $full) {
    $results.Add((Write-CheckResult OK $name 'present')) | Out-Null
  }
  else {
    $results.Add((Write-CheckResult FAIL $name "missing: $full")) | Out-Null
  }
}

# 3. Stale write-job.lock
$writeLock = Join-Path $LockDir 'write-job.lock'
if (Test-Path -LiteralPath $writeLock) {
  $lockText = Get-Content -LiteralPath $writeLock -Raw -Encoding UTF8
  $pidMatch = [regex]::Match($lockText, '(?m)^pid=(\d+)\s*$')
  if (-not $pidMatch.Success) {
    $results.Add((Write-CheckResult WARN 'lock:write-job' 'legacy lock without pid=; not auto-removed — confirm manually')) | Out-Null
  }
  else {
    $lockPid = [int]$pidMatch.Groups[1].Value
    $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
    if ($proc) {
      $results.Add((Write-CheckResult OK 'lock:write-job' "held by live pid=$lockPid")) | Out-Null
    }
    else {
      if ($Fix) {
        Remove-Item -LiteralPath $writeLock -Force
        $results.Add((Write-CheckResult WARN 'lock:write-job' "stale pid=$lockPid removed (-Fix)")) | Out-Null
      }
      else {
        $results.Add((Write-CheckResult WARN 'lock:write-job' "stale pid=$lockPid (process not found); re-run with -Fix to remove")) | Out-Null
      }
    }
  }
}
else {
  $results.Add((Write-CheckResult OK 'lock:write-job' 'absent')) | Out-Null
}

# 4. Stale leases (running without matching write lock)
$lockJobId = $null
if (Test-Path -LiteralPath $writeLock) {
  $lockText2 = Get-Content -LiteralPath $writeLock -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
  if (-not $lockText2) { $lockText2 = '' }
  $jm = [regex]::Match($lockText2, '(?m)^job_id=(.+?)\s*$')
  if ($jm.Success) { $lockJobId = $jm.Groups[1].Value.Trim() }
}

if (Test-Path -LiteralPath $LockDir) {
  foreach ($file in Get-ChildItem -LiteralPath $LockDir -Filter '*.lease.json' -File -ErrorAction SilentlyContinue) {
    try {
      $lease = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
      $results.Add((Write-CheckResult WARN "lease:$($file.Name)" "invalid JSON: $($_.Exception.Message)")) | Out-Null
      continue
    }
    if ($lease.status -ne 'running') { continue }
    $jid = [string]$lease.job_id
    $orphan = (-not (Test-Path -LiteralPath $writeLock)) -or ($null -eq $lockJobId) -or ($lockJobId -ne $jid)
    if (-not $orphan) {
      $results.Add((Write-CheckResult OK "lease:$jid" 'running and matches write-job.lock')) | Out-Null
      continue
    }
    if ($Fix) {
      $lease.status = 'stale'
      $lease | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file.FullName -Encoding UTF8
      $results.Add((Write-CheckResult WARN "lease:$jid" 'orphan running lease marked status=stale (-Fix)')) | Out-Null
    }
    else {
      $results.Add((Write-CheckResult WARN "lease:$jid" 'orphan running lease (no matching write-job.lock); re-run with -Fix to mark stale')) | Out-Null
    }
  }
}

# 5. gitignore alignment
$gitignorePath = Join-Path $root '.gitignore'
if (-not (Test-Path -LiteralPath $gitignorePath)) {
  $results.Add((Write-CheckResult WARN 'gitignore' '.gitignore missing')) | Out-Null
}
else {
  $gi = Get-Content -LiteralPath $gitignorePath -Raw -Encoding UTF8
  $need = @('.agents/locks/*.lease.json', '.agents/logs/codex/*.last.txt')
  foreach ($pat in $need) {
    if ($gi -notlike "*$pat*") {
      $results.Add((Write-CheckResult WARN 'gitignore' "missing pattern: $pat")) | Out-Null
    }
    else {
      $results.Add((Write-CheckResult OK 'gitignore' "has $pat")) | Out-Null
    }
  }
}

$failCount = @($results | Where-Object { $_.Level -eq 'FAIL' }).Count
$warnCount = @($results | Where-Object { $_.Level -eq 'WARN' }).Count
Write-Host ("check.ps1 summary: FAIL={0} WARN={1} OK={2}" -f $failCount, $warnCount, (@($results | Where-Object { $_.Level -eq 'OK' }).Count))
if ($failCount -gt 0) { exit 1 }
exit 0
