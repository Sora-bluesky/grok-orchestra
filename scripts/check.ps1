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
.PARAMETER SkipToolCheck
  Skip codex presence check (unit tests / offline CI only).
#>
[CmdletBinding()]
param(
  [switch] $Fix,
  [string] $LockDir = '',
  [string] $RepoRoot = '',
  [switch] $SkipToolCheck
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
if ($SkipToolCheck) {
  $results.Add((Write-CheckResult OK 'tool:codex' 'skipped (-SkipToolCheck)')) | Out-Null
}
else {
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

# 5. L2 worktree metadata (active/collected): dir + branch + git worktree registration path match
# Returns hashtable: Path (string|null), ProbeFailed (bool), ProbeMessage (string)
function Get-CheckRegisteredWorktreePath {
  param(
    [string] $ControlRoot,
    [string] $Branch
  )
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $porcelain = & git -C $ControlRoot worktree list --porcelain 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $text = ($porcelain | ForEach-Object { "$_" }) -join [Environment]::NewLine
  if ($code -ne 0) {
    return @{
      Path         = $null
      ProbeFailed  = $true
      ProbeMessage = ("git worktree list failed (exit {0}): {1}" -f $code, $text)
    }
  }
  $currentPath = $null
  $currentBranch = $null
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^worktree (.+)$') {
      if ($currentPath -and $currentBranch -eq $Branch) {
        return @{ Path = $currentPath; ProbeFailed = $false; ProbeMessage = '' }
      }
      $currentPath = $Matches[1]
      $currentBranch = $null
    }
    elseif ($line -match '^branch refs/heads/(.+)$') {
      $currentBranch = $Matches[1]
    }
    elseif ($line -eq '') {
      if ($currentPath -and $currentBranch -eq $Branch) {
        return @{ Path = $currentPath; ProbeFailed = $false; ProbeMessage = '' }
      }
      $currentPath = $null
      $currentBranch = $null
    }
  }
  if ($currentPath -and $currentBranch -eq $Branch) {
    return @{ Path = $currentPath; ProbeFailed = $false; ProbeMessage = '' }
  }
  return @{ Path = $null; ProbeFailed = $false; ProbeMessage = '' }
}

if (Test-Path -LiteralPath $LockDir) {
  foreach ($file in Get-ChildItem -LiteralPath $LockDir -Filter '*.worktree.json' -File -ErrorAction SilentlyContinue) {
    try {
      $wt = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
      $results.Add((Write-CheckResult WARN "worktree:$($file.Name)" "invalid JSON: $($_.Exception.Message)")) | Out-Null
      continue
    }
    $status = [string]$wt.status
    # active/collected: live L2; creating: exclusive new claim (may be mid-flight or crashed)
    if ($status -ne 'active' -and $status -ne 'collected' -and $status -ne 'creating') { continue }
    $jid = [string]$wt.job_id
    $wtPath = [string]$wt.path
    $branch = [string]$wt.branch
    $detail = [System.Collections.Generic.List[string]]::new()
    $dirOk = $wtPath -and (Test-Path -LiteralPath $wtPath)
    if (-not $dirOk) { $detail.Add('directory missing') | Out-Null }

    # Branch probe: distinguish "missing" (exit 1) from git failure (other errors)
    $branchOk = $false
    $branchProbeFailed = $false
    if ($branch) {
      $prevBr = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      $brOut = & git -C $root show-ref --verify --quiet "refs/heads/$branch" 2>&1
      $brCode = $LASTEXITCODE
      $ErrorActionPreference = $prevBr
      if ($brCode -eq 0) {
        $branchOk = $true
      }
      elseif ($brCode -eq 1) {
        $detail.Add('branch missing') | Out-Null
      }
      else {
        $branchProbeFailed = $true
        $detail.Add(("git show-ref probe failed (exit {0})" -f $brCode)) | Out-Null
      }
    }
    else {
      $detail.Add('branch missing') | Out-Null
    }

    # status=creating: exclusive new claim. Never clear a live/recent claim.
    # -Fix may remove claim only when: no dir, no branch, AND created_at older than age gate.
    # Partial (dir and/or branch present) is always WARN for Operator manual cleanup.
    if ($status -eq 'creating') {
      $gitProbeFailedCreating = $branchProbeFailed
      if ($gitProbeFailedCreating) {
        $results.Add((Write-CheckResult WARN "worktree:$jid" "status=creating; git probe failed — not clearing claim")) | Out-Null
        continue
      }
      $provablyEmpty = (-not $dirOk) -and (-not $branchOk)
      $ageMinutes = 15
      $isAged = $false
      $createdRaw = [string]$wt.created_at
      if (-not [string]::IsNullOrWhiteSpace($createdRaw)) {
        try {
          $createdAt = [datetimeoffset]::Parse($createdRaw, [System.Globalization.CultureInfo]::InvariantCulture)
          $isAged = (([datetimeoffset]::UtcNow - $createdAt.ToUniversalTime()).TotalMinutes -ge $ageMinutes)
        }
        catch {
          # Unparseable created_at: treat as not aged (do not auto-clear)
          $isAged = $false
        }
      }
      if ($provablyEmpty -and $isAged) {
        if ($Fix) {
          Remove-Item -LiteralPath $file.FullName -Force
          $results.Add((Write-CheckResult WARN "worktree:$jid" ("status=creating aged >={0}m with no dir/branch; claim file removed (-Fix)" -f $ageMinutes))) | Out-Null
        }
        else {
          $results.Add((Write-CheckResult WARN "worktree:$jid" ("status=creating aged >={0}m with no dir/branch (stale claim); re-run with -Fix to clear" -f $ageMinutes))) | Out-Null
        }
      }
      elseif ($provablyEmpty -and -not $isAged) {
        $results.Add((Write-CheckResult WARN "worktree:$jid" 'status=creating recent (no dir/branch yet); not auto-cleared')) | Out-Null
      }
      else {
        $results.Add((Write-CheckResult WARN "worktree:$jid" 'status=creating (in progress or partial); not auto-cleared — Operator cleans manually')) | Out-Null
      }
      continue
    }

    $regPath = $null
    $regProbeFailed = $false
    if ($branchOk) {
      $regInfo = Get-CheckRegisteredWorktreePath -ControlRoot $root -Branch $branch
      if ($regInfo.ProbeFailed) {
        $regProbeFailed = $true
        $detail.Add($regInfo.ProbeMessage) | Out-Null
      }
      else {
        $regPath = $regInfo.Path
      }
    }
    $regOk = $false
    if ($regPath -and $dirOk) {
      try {
        $regOk = ((Resolve-Path -LiteralPath $regPath).Path -eq (Resolve-Path -LiteralPath $wtPath).Path)
      }
      catch {
        $regOk = $false
      }
    }
    if (-not $regOk -and -not $regProbeFailed -and $branchOk) {
      $detail.Add('not registered as worktree or path mismatch') | Out-Null
    }

    $gitProbeFailed = $branchProbeFailed -or $regProbeFailed
    if ($dirOk -and $branchOk -and $regOk) {
      $results.Add((Write-CheckResult OK "worktree:$jid" "status=$status dir+branch+registration OK")) | Out-Null
      continue
    }
    $msg = ($detail -join '; ')
    # Do not destructively rewrite metadata when a git probe itself failed
    if ($gitProbeFailed) {
      $results.Add((Write-CheckResult WARN "worktree:$jid" "$msg; git probe failed — not marking stale")) | Out-Null
      continue
    }
    if ($Fix) {
      $wt.status = 'stale'
      $wt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file.FullName -Encoding UTF8
      $results.Add((Write-CheckResult WARN "worktree:$jid" "$msg; marked status=stale (-Fix)")) | Out-Null
    }
    else {
      $results.Add((Write-CheckResult WARN "worktree:$jid" "$msg; re-run with -Fix to mark stale")) | Out-Null
    }
  }
}

# 6. gitignore alignment
$gitignorePath = Join-Path $root '.gitignore'
if (-not (Test-Path -LiteralPath $gitignorePath)) {
  $results.Add((Write-CheckResult WARN 'gitignore' '.gitignore missing')) | Out-Null
}
else {
  $gi = Get-Content -LiteralPath $gitignorePath -Raw -Encoding UTF8
  $need = @('.agents/locks/*.lease.json', '.agents/locks/*.worktree.json', '.agents/logs/codex/*.last.txt')
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
