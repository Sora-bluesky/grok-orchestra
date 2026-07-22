#requires -Version 5.1
<#
.SYNOPSIS
  Delegate a job to Codex CLI (headless) with L0 single-writer guard.

.PARAMETER JobId
  Stable id used for log/result filenames.

.PARAMETER Type
  review|design|investigate|implement|fix

.PARAMETER PromptFile
  Path to Prompt Contract body (required fields checked lightly).

.PARAMETER RepoRoot
  Control-plane repository root (default: parent of scripts/).
  With -Worktree, codex -C uses the worktree path; L2 metadata stays under RepoRoot.

.PARAMETER Worktree
  L2 mode for implement/fix: create a job worktree, run codex -C there, skip L0 lock and L1 lease.
  For read-only types: no-op + warning.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $JobId,

  [Parameter(Mandatory = $true)]
  [ValidateSet('review', 'design', 'investigate', 'implement', 'fix')]
  [string] $Type,

  [Parameter(Mandatory = $true)]
  [string] $PromptFile,

  [string] $RepoRoot = '',

  [string[]] $OwnedPaths = @(),

  [switch] $Worktree
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  if ($RepoRoot) { return (Resolve-Path $RepoRoot).Path }
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Test-PromptContract {
  param([string] $Text)
  $required = @('## Objective', '## Constraints', '## Relevant files', '## Acceptance checks', '## Output format')
  $missing = @()
  foreach ($h in $required) {
    if ($Text -notmatch [regex]::Escape($h)) { $missing += $h }
  }
  return $missing
}

function Resolve-CodexNodeInvocation {
  # Prefer direct node + codex.js (avoids npm shim stderr quirks).
  $npmCodex = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\bin\codex.js'
  if (Test-Path -LiteralPath $npmCodex) {
    return @{ Exe = 'node'; ArgsPrefix = @($npmCodex) }
  }
  return @{ Exe = 'codex'; ArgsPrefix = @() }
}

$root = Get-RepoRoot
Set-Location $root

$promptPath = if ([System.IO.Path]::IsPathRooted($PromptFile)) { $PromptFile } else { Join-Path $root $PromptFile }
if (-not (Test-Path -LiteralPath $promptPath)) {
  Write-Error "Prompt file not found: $promptPath"
}

$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$missing = Test-PromptContract -Text $promptText
if ($missing.Count -gt 0) {
  Write-Error ("Prompt Contract incomplete. Missing: {0}" -f ($missing -join ', '))
}

$lockDir = Join-Path $root '.agents\locks'
New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
$writeLock = Join-Path $lockDir 'write-job.lock'
$isWrite = $Type -in @('implement', 'fix')
$leaseAcquired = $false
$useL2 = $false
$execRoot = $root
$leaseScript = Join-Path $root 'scripts\lease-paths.ps1'
$worktreeScript = Join-Path $root 'scripts\worktree-job.ps1'
# Prefer scripts next to this file when RepoRoot is a temp test tree without a full scripts copy
if (-not (Test-Path -LiteralPath $worktreeScript)) {
  $worktreeScript = Join-Path $PSScriptRoot 'worktree-job.ps1'
}
if (-not (Test-Path -LiteralPath $leaseScript)) {
  $leaseScript = Join-Path $PSScriptRoot 'lease-paths.ps1'
}

if ($Worktree) {
  if (-not $isWrite) {
    Write-Warning "delegate-codex: -Worktree is a no-op for read-only type='$Type' (L2 is for implement/fix only)."
  }
  else {
    $useL2 = $true
    if (-not (Test-Path -LiteralPath $worktreeScript)) {
      Write-Error "worktree-job.ps1 not found (expected next to delegate or under RepoRoot/scripts)."
    }
    $wtArgs = @{
      Action   = 'new'
      JobId    = $JobId
      RepoRoot = $root
      LockDir  = $lockDir
    }
    if ($OwnedPaths.Count -gt 0) { $wtArgs['OwnedPaths'] = $OwnedPaths }
    $wtOut = & $worktreeScript @wtArgs
    if ($LASTEXITCODE -ne 0) {
      Write-Error "worktree-job new failed for JobId=$JobId"
    }
    $wtLine = ($wtOut | ForEach-Object { "$_" } | Where-Object { $_ -match '^path=' } | Select-Object -Last 1)
    if (-not $wtLine -or $wtLine -notmatch 'path=([^;]+)') {
      Write-Error "worktree-job new did not emit path=... line. Output: $wtOut"
    }
    $execRoot = $Matches[1]
    if (-not (Test-Path -LiteralPath $execRoot)) {
      Write-Error "L2 worktree path missing after new: $execRoot"
    }
    Write-Host "delegate-codex: L2 worktree mode - skip L0 write-job.lock and L1 lease; exec -C $execRoot"
  }
}

# L0 single-writer lock: main-tree only (never in L2 worktree mode)
if ($isWrite -and -not $useL2) {
  if (Test-Path -LiteralPath $writeLock) {
    $existing = Get-Content -LiteralPath $writeLock -Raw -ErrorAction SilentlyContinue
    Write-Error "L0 single-writer: another write job is running.`n$existing`nRemove $writeLock only if stale."
  }
  @"
job_id=$JobId
type=$Type
started=$(Get-Date -Format o)
pid=$PID
"@ | Set-Content -LiteralPath $writeLock -Encoding UTF8
}

$sandbox = if ($isWrite) { 'workspace-write' } else { 'read-only' }

# Logs: execution root (worktree when L2, else control root)
$logDir = Join-Path $execRoot '.agents\logs\codex'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$outLast = Join-Path $logDir "$JobId.last.txt"
$outErr = Join-Path $logDir "$JobId.stderr.log"
$outCombined = Join-Path $logDir "$JobId.combined.log"

Write-Host "delegate-codex: job=$JobId type=$Type sandbox=$sandbox cwd=$execRoot l2=$useL2"

$inv = Resolve-CodexNodeInvocation
$argList = @()
$argList += $inv.ArgsPrefix
$argList += 'exec'
$argList += @('-C', $execRoot, '-s', $sandbox, '-o', $outLast)

try {
  # L1 leases only for main-tree write jobs (L2 stores owned_paths in worktree.json)
  if ($isWrite -and -not $useL2 -and $OwnedPaths.Count -gt 0) {
    & $leaseScript -Action acquire -JobId $JobId -OwnedPaths $OwnedPaths -Type $Type
    if ($LASTEXITCODE -ne 0) { throw "L1 lease acquire failed for job: $JobId" }
    $leaseAcquired = $true
  }

  $env:NO_COLOR = '1'
  # Capture all streams; do not use 2> file redirect with ErrorAction Stop
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = $promptText | & $inv.Exe @argList 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prevEap

  $text = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
  Set-Content -LiteralPath $outCombined -Value $text -Encoding UTF8

  if ($code -ne 0) {
    Set-Content -LiteralPath $outErr -Value $text -Encoding UTF8
    Write-Error "codex exec failed with exit $code. See $outCombined"
  }

  if (-not (Test-Path -LiteralPath $outLast) -or ((Get-Item -LiteralPath $outLast).Length -eq 0)) {
    # Fall back: write combined output as last message if -o empty
    if ($text.Trim().Length -gt 0) {
      Set-Content -LiteralPath $outLast -Value $text -Encoding UTF8
    } else {
      Write-Error "codex exec exit 0 but empty last message: $outLast"
    }
  }

  Write-Host "OK: wrote $outLast"
  exit 0
}
finally {
  if ($leaseAcquired) {
    try { & $leaseScript -Action release -JobId $JobId | Out-Host }
    catch { Write-Warning "L1 lease release failed for job '$JobId': $($_.Exception.Message)" }
  }
  if ($isWrite -and -not $useL2 -and (Test-Path -LiteralPath $writeLock)) {
    $lockContent = Get-Content -LiteralPath $writeLock -Raw -ErrorAction SilentlyContinue
    if ($lockContent -match [regex]::Escape("job_id=$JobId")) {
      Remove-Item -LiteralPath $writeLock -Force -ErrorAction SilentlyContinue
    }
  }
}
